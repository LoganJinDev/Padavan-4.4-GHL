#!/bin/sh
#
# WireGuard 客户端启停脚本
#
# 关键点：WireGuard 的 allowed-ips 只是「加密路由」（决定出站哪些目标交给该
# peer 加密），它 **不会** 往内核路由表插任何条目 —— 那是 wg-quick 的活。
# 本脚本走手写 ip/ifconfig 路线，没有 wg-quick，所以必须自己补 ip route，
# 否则隧道能建起来、握手也可能成功，但流量永远走原默认路由出去，隧道形同虚设。

WG_IF="wg0"
WG_KEY="/tmp/privatekey"
DEF_ROUTE_FILE="/tmp/wg0_default_route"

# 读取允许走隧道的目标网段；留空回落 0.0.0.0/0（全量）
get_allowed_ips() {
	local a="$(nvram get wireguard_allowedips)"
	[ -n "$a" ] || a="0.0.0.0/0"
	echo "$a"
}

# 规范化成 wg 认识的逗号分隔形式（用户可能用空格或逗号分隔）
normalize_allowed_ips() {
	local net out=""
	for net in $(echo "$1" | tr ',' ' '); do
		[ -n "$net" ] || continue
		out="${out:+$out,}$net"
	done
	echo "$out"
}

# 保存「原始默认路由」（隧道外的真网关），stop 时还回去。
# 必须排除 dev wg0 的条目 —— 上次若没走 stop 就被重入，路由表里的默认路由
# 已经是隧道自己那条，存下来会让 stop 后把默认路由又指回隧道（自环断网）。
save_default_route() {
	[ -f "$DEF_ROUTE_FILE" ] && return 0
	local line="$(ip route show default | awk -v wg="$WG_IF" \
		'/^default/ && $0 !~ ("dev " wg) {print $3" "$5; exit}')"
	[ -n "$line" ] && echo "$line" > "$DEF_ROUTE_FILE"
	return 0
}

# 还回原始默认路由。指向 wg0 的路由会随接口被内核清掉，但原始那条不会自动
# 回来（它是被 replace 覆盖掉的）—— 不还就是「关掉 VPN 后彻底断网」。
restore_default_route() {
	[ -f "$DEF_ROUTE_FILE" ] || return 0
	local gw dev
	read gw dev < "$DEF_ROUTE_FILE"
	[ -n "$gw" ] && [ -n "$dev" ] && ip route replace default via "$gw" dev "$dev"
	rm -f "$DEF_ROUTE_FILE"
	return 0
}

# 按 allowed-ips 逐条铺内核路由 + 给 endpoint 开例外
setup_route() {
	local allowed="$(normalize_allowed_ips "$(get_allowed_ips)")"
	local orig_gw orig_dev ep_ip net old_ifs

	# 真网关：优先用 save_default_route 存下的那份 —— 重入场景下路由表里的
	# 默认路由可能已经被隧道自己占了，直接查表会取到 wg0（自环）。
	if [ -f "$DEF_ROUTE_FILE" ]; then
		read orig_gw orig_dev < "$DEF_ROUTE_FILE"
	fi
	[ -n "$orig_gw" ] || orig_gw="$(ip route show default | awk '/^default/{print $3; exit}')"
	[ -n "$orig_dev" ] || orig_dev="$(ip route show default | awk '/^default/{print $5; exit}')"

	# endpoint 例外：去对端的 UDP 包必须走物理网卡，否则会被下面那条
	# 0.0.0.0/0 卷进隧道 → 自己绕自己 → 永远握手不上。
	# /32 比 0.0.0.0/0 更具体，最长前缀匹配保证它优先命中。
	ep_ip="$1"
	case "$ep_ip" in
		*[!0-9.]*) ep_ip="" ;;	# 含非数字/点的字符 → 是域名，解析不到具体 IP，跳过
	esac
	if [ -n "$ep_ip" ] && [ -n "$orig_gw" ] && [ -n "$orig_dev" ]; then
		ip route replace "$ep_ip/32" via "$orig_gw" dev "$orig_dev"
	else
		logger -t "WIREGUARD" "未能确定对端 IP 或物理网关，未添加 endpoint 例外路由（若 endpoint 用域名且全量分流，可能握手不上）"
	fi

	old_ifs="$IFS"
	IFS=','
	for net in $allowed; do
		[ -n "$net" ] || continue
		ip route replace "$net" dev "$WG_IF"
	done
	IFS="$old_ifs"
}

start_wg() {
	local localip="$(nvram get wireguard_localip)"
	local privatekey="$(nvram get wireguard_localkey)"
	local peerkey="$(nvram get wireguard_peerkey)"
	local peerip="$(nvram get wireguard_peerip)"
	local allowed

	if [ -z "$localip" ] || [ -z "$privatekey" ] || [ -z "$peerkey" ] || [ -z "$peerip" ]; then
		logger -t "WIREGUARD" "配置不完整（本机IP/本机密钥/对端密钥/对端地址需全部填写），未启动"
		return 1
	fi

	logger -t "WIREGUARD" "正在启动wireguard"

	# 先留一份真网关，供 stop 时还原默认路由
	save_default_route

	# 首次启动时 wg0 不存在，静默忽略；删接口会连带清掉指向它的旧路由
	ip link del dev "$WG_IF" 2>/dev/null

	ip link add dev "$WG_IF" type wireguard
	ip link set dev "$WG_IF" mtu 1420
	ip addr add "$localip" dev "$WG_IF"

	# 私钥落盘：收紧权限，别让同机其他进程读到
	umask 077
	echo "$privatekey" > "$WG_KEY"

	allowed="$(normalize_allowed_ips "$(get_allowed_ips)")"

	wg set "$WG_IF" private-key "$WG_KEY"
	wg set "$WG_IF" peer "$peerkey" persistent-keepalive 25 \
		allowed-ips "$allowed" endpoint "$peerip"

	ifconfig "$WG_IF" up

	# ---- 路由：这一步不做，隧道等于白建 ----
	setup_route "${peerip%%:*}"

	iptables -t nat -C POSTROUTING -o "$WG_IF" -j MASQUERADE 2>/dev/null || \
		iptables -t nat -A POSTROUTING -o "$WG_IF" -j MASQUERADE

	logger -t "WIREGUARD" "wireguard 已启动，分流网段：$allowed"
	return 0
}

stop_wg() {
	local peerip="$(nvram get wireguard_peerip)"
	local ep_ip="${peerip%%:*}"

	# endpoint 例外那条指向物理网卡，不随 wg0 消失，必须显式撤
	[ -n "$ep_ip" ] && ip route del "$ep_ip/32" 2>/dev/null

	ip link del dev "$WG_IF" 2>/dev/null

	# 还回原始默认路由，否则关掉 VPN 就彻底没网了
	restore_default_route

	iptables -t nat -D POSTROUTING -o "$WG_IF" -j MASQUERADE 2>/dev/null
	rm -f "$WG_KEY"
	logger -t "WIREGUARD" "正在关闭wireguard"
	return 0
}

case $1 in
start) start_wg ;;
stop)  stop_wg ;;
*)     echo "check" ;;
esac
