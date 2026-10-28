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
		# 本机已有该网段的直连路由（= 自己的 LAN / WAN）→ 跳过。
		# 否则下面那条 replace 会顶掉 br0 的 proto kernel 直连路由，把发往
		# 本网段的包全送进隧道 ⇒ 管理页与 SSH 立刻失联（单向断连）。
		#
		# 判定用【精确前缀】而不是包含关系：ip route replace 只在前缀完全
		# 相同时才覆盖，超网（用户填 192.168.0.0/16 而本机是 /24）会被更长
		# 前缀的直连路由压住、本来就无害。反过来若用包含判断，会误伤
		# 0.0.0.0/0 —— 那是全量分流的正常默认值，必须照常铺进隧道。
		if ip route show "$net" 2>/dev/null | grep -q 'proto kernel'; then
			logger -t "WIREGUARD" "跳过 $net：与本机直连网段冲突，保留原路由"
			continue
		fi
		ip route replace "$net" dev "$WG_IF"
	done
	IFS="$old_ifs"
}

# ---- 一键互联：放行从隧道进来的流量 ----
#
# Padavan 的防火墙不认识 wg0：INPUT 只放行 br0 / lo / ESTABLISHED，FORWARD 只
# 放行 br0 与 ESTABLISHED。于是【对端主动发起】的连接（ping / SSH / 管理页）
# 首包不匹配任何 ACCEPT ⇒ 被 DROP；而本机主动发起的连接，回包能命中
# ESTABLISHED,RELATED ⇒ 通。这就是「GHL 能访问对端、对端访问不到 GHL」。
#
# 两条规则补上缺口：
#   INPUT   -i wg0 -j ACCEPT          → 对端能访问本机（管理页 / SSH / ping）
#   FORWARD -i wg0 -o br0 -j ACCEPT   → 对端能访问 LAN 内所有设备
# 回程无需额外规则：FORWARD 已有「-i br0 -j ACCEPT」，OUTPUT 策略是 ACCEPT。
# 安全性由 WireGuard 自己兜底：源地址不在 AllowedIPs 里的包根本进不了 wg0。
#
# ★ 规则本体不在这里，由 firewall_ex.c 的 ipt_filter_rules() 按 nvram 开关
#   直接 fprintf 进 /tmp/ipt_filter.rules 生成。理由：filter 表会被
#   iptables-restore 整表重建（改任何防火墙设置都触发），重建后必须由 C 侧
#   重新生成；而若改由本脚本写一个 /tmp 下的脚本文件让 C 侧去执行，就等于
#   让 root 执行世界可写目录（/tmp 是 1777 tmpfs）里的文件 —— 本地提权面。
#   本脚本只负责「立刻生效」这一半。
#
# 为什么脚本这边还要自己执行一遍 —— 开机时防火墙与 WireGuard 谁先跑不确定：
#   防火墙先跑 → 那时 nvram 开关已是 1 → 规则已被写进规则集，这里是幂等重放
#   WireGuard 先跑 → 规则集里还没有 → 这里补上，随后防火墙重建时再生成一次
# 两条都用「-C 探测，没有才 -A」⇒ 不堆叠。
enable_lan_access() {
	iptables -C INPUT -i "$WG_IF" -j ACCEPT 2>/dev/null || \
		iptables -A INPUT -i "$WG_IF" -j ACCEPT
	iptables -C FORWARD -i "$WG_IF" -o br0 -j ACCEPT 2>/dev/null || \
		iptables -A FORWARD -i "$WG_IF" -o br0 -j ACCEPT
	logger -t "WIREGUARD" "已放行隧道入站：对端可访问本机与 LAN 设备"
}

# 关闭：撤规则。规则本体由 C 侧按 nvram 开关决定是否生成，这里无需删文件。
disable_lan_access() {
	iptables -D INPUT -i "$WG_IF" -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i "$WG_IF" -o br0 -j ACCEPT 2>/dev/null
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

	# ---- 一键互联（默认关）：放行隧道入站 ----
	# 关掉开关时也要走 disable —— 否则上一轮留下的放行规则会一直在，
	# 用户以为关了其实没关。
	if [ "$(nvram get wireguard_lan_access)" = "1" ]; then
		enable_lan_access
	else
		disable_lan_access
	fi

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

	# 撤掉一键互联的入站放行规则
	disable_lan_access

	rm -f "$WG_KEY"
	logger -t "WIREGUARD" "正在关闭wireguard"
	return 0
}

case $1 in
start) start_wg ;;
stop)  stop_wg ;;
*)     echo "check" ;;
esac
