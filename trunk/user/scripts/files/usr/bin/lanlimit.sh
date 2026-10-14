#!/bin/sh
#
# lanlimit.sh —— Padavan 按 IP / MAC 给单台 LAN 设备限速
#
# 依赖：/bin/tc（iproute2，固件已内置）、ifb 内核模块（CONFIG_FIRMWARE_INCLUDE_IFB=y）
# 配置：/etc/storage/lanlimit.conf，格式见该文件头部注释
# 用法：lanlimit.sh start | stop | reload | show
#
# 限速的两个方向分别落在哪里：
#   · 下行（外网 -> 客户端）：在 LAN 网桥的 egress 上整形。网桥出口方向就是
#     「发给客户端」，所以匹配 dst。
#   · 上行（客户端 -> 外网）：网桥的 ingress 方向没有队列，必须先 mirred 镜像
#     到一个 ifb 虚拟设备，再在 ifb 上整形。镜像时包头不变，所以匹配 src。
#   未被限速的设备走 default 类，速率取一个远高于实际带宽的值，等价于不限。
#
# ⚠️ 硬件 NAT 加速（hw_nat_mode）与 SFE 会绕过内核协议栈，被加速的长连接
#    （下载、在线视频）不经过 qdisc，限速对它们无效。要稳定生效需：
#      nvram set hw_nat_mode=0 && nvram set sfe_enable=0 && nvram commit && reboot
#    代价是转发性能下降，自行权衡。

LAN_IF="$(nvram get lan_ifname 2>/dev/null)"
[ -n "$LAN_IF" ] || LAN_IF="br0"
IFB_DEV="ifb0"
CONF="/etc/storage/lanlimit.conf"
# 未单独限速的设备走这个速率，取得足够高即等价于不限
FREE_RATE="1000mbit"

log() {
	logger -t lanlimit "$1"
	echo "$1"
}

# MAC -> IP。先查 dnsmasq 当前租约，再用 ARP 表补
mac2ip() {
	local mac ip
	mac="$(echo "$1" | tr 'A-Z' 'a-z')"
	# 租约表格式：过期时间 MAC IP 主机名 客户端ID
	ip="$(awk -v m="$mac" 'tolower($2)==m {print $3; exit}' /tmp/dnsmasq.leases 2>/dev/null)"
	if [ -z "$ip" ]; then
		# ARP 表格式：IP 类型 标志 MAC 掩码 设备
		# 标志 0x0 是未完成表项，MAC 全 0 是无效表项，都必须跳过
		ip="$(awk -v m="$mac" '$3!="0x0" && tolower($4)==m {print $1; exit}' /proc/net/arp 2>/dev/null)"
	fi
	echo "$ip"
}

# 目标字段可能是 IP 也可能是 MAC，冒号是判据
resolve() {
	case "$1" in
		*:*) mac2ip "$1" ;;
		*)   echo "$1" ;;
	esac
}

# 从配置里读出「有没有人要限下行 / 限上行」。没有就不建对应的 qdisc，
# 免得凭空给网桥挂一层无用的整形
scan_conf() {
	DL=0
	UL=0
	while read -r tgt dl ul _; do
		case "$tgt" in ""|\#*) continue ;; esac
		[ "${dl:-0}" -gt 0 ] 2>/dev/null && DL=1
		[ "${ul:-0}" -gt 0 ] 2>/dev/null && UL=1
	done < "$CONF"
}

do_stop() {
	tc qdisc del dev "$LAN_IF" root 2>/dev/null
	tc qdisc del dev "$LAN_IF" ingress 2>/dev/null
	tc qdisc del dev "$IFB_DEV" root 2>/dev/null
	ip link set "$IFB_DEV" down 2>/dev/null
	log "已清除全部限速规则"
}

# 建两个方向各自的「骨架」：根 qdisc + 不限速的 default 类
build_skeleton() {
	if [ "$DL" = "1" ]; then
		tc qdisc add dev "$LAN_IF" root handle 1: htb default 99
		tc class add dev "$LAN_IF" parent 1: classid 1:99 htb rate "$FREE_RATE"
	fi
	if [ "$UL" = "1" ]; then
		modprobe ifb 2>/dev/null
		ip link set "$IFB_DEV" up 2>/dev/null
		tc qdisc add dev "$LAN_IF" handle ffff: ingress
		tc qdisc add dev "$IFB_DEV" root handle 2: htb default 99
		tc class add dev "$IFB_DEV" parent 2: classid 2:99 htb rate "$FREE_RATE"
	fi
}

# 给一台设备挂上类与过滤器。n 是类号，从 1 开始，避开 default 的 99
limit_one() {
	local tgt dl ul ip n
	tgt="$1"
	dl="$2"
	ul="$3"
	ip="$(resolve "$tgt")"
	if [ -z "$ip" ]; then
		# 设备当前不在线就解析不到 IP。这不是错误，下次 reload 再试即可
		log "跳过 $tgt：不在线，解析不到 IP（设备上线后 reload 生效）"
		return 0
	fi
	n="$4"
	if [ "${dl:-0}" -gt 0 ] 2>/dev/null; then
		tc class add dev "$LAN_IF" parent 1: classid "1:$n" \
			htb rate "${dl}kbit" ceil "${dl}kbit" burst 15k
		tc filter add dev "$LAN_IF" parent 1: protocol ip prio 1 \
			u32 match ip dst "$ip"/32 flowid "1:$n"
	fi
	if [ "${ul:-0}" -gt 0 ] 2>/dev/null; then
		# 只有被限上行的设备才需要从 ingress 镜像出来
		tc filter add dev "$LAN_IF" parent ffff: protocol ip prio 1 \
			u32 match ip src "$ip"/32 action mirred egress redirect dev "$IFB_DEV"
		tc class add dev "$IFB_DEV" parent 2: classid "2:$n" \
			htb rate "${ul}kbit" ceil "${ul}kbit" burst 15k
		tc filter add dev "$IFB_DEV" parent 2: protocol ip prio 1 \
			u32 match ip src "$ip"/32 flowid "2:$n"
	fi
	log "已限速 $tgt ($ip)：下行 ${dl}kbit / 上行 ${ul}kbit"
}

do_start() {
	if [ ! -f "$CONF" ]; then
		log "配置不存在：$CONF"
		return 1
	fi
	# 网桥还没起来的场景（开机脚本里调）等一小会儿
	w=0
	while [ ! -d "/sys/class/net/$LAN_IF" ] && [ "$w" -lt 20 ]; do
		sleep 1
		w=$((w + 1))
	done
	if [ ! -d "/sys/class/net/$LAN_IF" ]; then
		log "接口 $LAN_IF 不存在，放弃"
		return 1
	fi

	scan_conf
	if [ "$DL" = "0" ] && [ "$UL" = "0" ]; then
		log "配置里没有任何限速项"
		return 0
	fi
	do_stop
	build_skeleton

	n=0
	cnt=0
	while read -r tgt dl ul _; do
		case "$tgt" in ""|\#*) continue ;; esac
		n=$((n + 1))
		limit_one "$tgt" "${dl:-0}" "${ul:-0}" "$n"
		cnt=$((cnt + 1))
	done < "$CONF"
	log "共处理 $cnt 条限速条目"
}

do_show() {
	echo "--- $LAN_IF 出口（下行）---"
	tc -s class show dev "$LAN_IF" 2>/dev/null
	echo "--- $IFB_DEV 出口（上行）---"
	tc -s class show dev "$IFB_DEV" 2>/dev/null
}

case "$1" in
	start|reload) do_start ;;
	stop)         do_stop ;;
	show)         do_show ;;
	*)            echo "用法: $0 start|stop|reload|show" ; exit 1 ;;
esac
