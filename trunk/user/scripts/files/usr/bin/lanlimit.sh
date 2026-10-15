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
#    （下载、在线视频）不经过 qdisc，限速对它们无效。
#    因此只要配置里存在生效的限速条目，本脚本会仿 sqm/run.sh 的做法自动把
#    两者关掉并卸载 hw_nat 模块，代价是转发性能下降。
#    该行为由 nvram 变量 lanlimit_autohwnat 控制（界面上的「限速时自动关闭
#    硬件加速」开关），默认开。关掉开关、清空规则或执行 stop 都会把原值还回去。
#    原值连同「接管那一刻 SQM 是否开着」一起记下：若期间 SQM 被开关过，说明
#    hw_nat 已经易主，这时不硬写回，交给 SQM 自己定，只还 SFE（SQM 从不碰它）。
#    SQM 开着但一直没动过时照常还原 —— 包括还原成 SQM 要的 hw_nat_mode=2
#    （runmode_2/4 会加载 hw_nat 模块，此时不还原就等于让限速静默失效）。
#
# ⚠️ 总开关门控：按设备限速是 QOS 流控（SQM）的子功能，sqm_enable 不为 1 时
#    本脚本一律不接管，并且会顺手撤掉之前留下的 tc 规则与硬件加速改动。
#    门控特意放在脚本里而不是界面或后端，因为 reload 有三个入口：
#      ① 界面点「应用」—— web_ex.c 里对 scripts.lanlimit.conf 的写盘分支会
#         无条件 fork 一次 `lanlimit.sh reload`，它根本不看 sqm_enable；
#      ② 开机脚本；
#      ③ 手工执行。
#    只在界面加限制的话，①③ 仍然会绕过。

LAN_IF="$(nvram get lan_ifname 2>/dev/null)"
[ -n "$LAN_IF" ] || LAN_IF="br0"
IFB_DEV="ifb0"
CONF="/etc/storage/lanlimit.conf"
# 未单独限速的设备走这个速率，取得足够高即等价于不限
FREE_RATE="1000mbit"
# 有规则时是否自动关闭硬件加速；变量不存在时按「开」处理
AUTOHWNAT="$(nvram get lanlimit_autohwnat 2>/dev/null)"
[ -n "$AUTOHWNAT" ] || AUTOHWNAT=1

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

# 关掉硬件加速，让流量回到内核协议栈，qdisc 才管得到。
# 关之前把原值记进 lanlimit_prev_*，规则清空 / 执行 stop 时还回去
hwnat_off() {
	[ "$AUTOHWNAT" = "1" ] || return 0

	local hw se
	hw="$(nvram get hw_nat_mode)"
	se="$(nvram get sfe_enable)"

	# 两个都已经关着就什么都不做。顺带保住已记录的原值，
	# 免得重复 reload 时把「0」误记成用户的原始设置
	if [ "${hw:-0}" = "0" ] && [ "${se:-0}" = "0" ]; then
		return 0
	fi

	# 只在第一次真正改动时记录原值。连当时的 SQM 状态一起记下来，
	# 还原时靠它判断这段时间里 hw_nat 有没有易主
	if [ -z "$(nvram get lanlimit_prev_hwnat)" ]; then
		nvram set lanlimit_prev_hwnat "${hw:-0}"
		nvram set lanlimit_prev_sfe "${se:-0}"
		nvram set lanlimit_prev_sqm "$(nvram get sqm_enable 2>/dev/null)"
	fi

	nvram set hw_nat_mode=0
	nvram set sfe_enable=0
	nvram commit
	# 卸载模块即立刻停止硬件直通，与 sqm/run.sh 的处理一致
	rmmod hw_nat 2>/dev/null
	log "为限速生效已关闭硬件加速（hw_nat_mode=0 / sfe_enable=0）"
}

# 还原硬件加速。不猜 SQM 想要什么，只把「我接管时看到的值」原样还回去；
# 唯一例外是接管之后 SQM 被开关过 —— 那说明 hw_nat 已归 SQM 管，硬写回
# 会和它抢，此时只还 SFE。重新加载 hw_nat 交给 /sbin/restart_firewall，
# 它会带上正确的 VLAN 参数，比自己 modprobe 可靠
hwnat_restore() {
	local ph ps psm sqm
	ph="$(nvram get lanlimit_prev_hwnat)"
	# 没记录过原值说明从没关过，无需还原
	[ -n "$ph" ] || return 0

	ps="$(nvram get lanlimit_prev_sfe)"
	# psm 为空的只可能是升级前留下的旧记录，按「已易主」处理，保守
	psm="$(nvram get lanlimit_prev_sqm)"
	sqm="$(nvram get sqm_enable)"

	if [ "${sqm:-0}" = "1" ] && [ "${psm:-0}" != "1" ]; then
		[ -n "$ps" ] && nvram set sfe_enable="$ps"
		nvram unset lanlimit_prev_hwnat
		nvram unset lanlimit_prev_sfe
		nvram unset lanlimit_prev_sqm
		nvram commit
		log "SQM 已接管硬件加速，跳过 hw_nat 还原，仅还原 SFE=${ps:-未记录}"
		return 0
	fi

	nvram set hw_nat_mode="$ph"
	[ -n "$ps" ] && nvram set sfe_enable="$ps"
	nvram unset lanlimit_prev_hwnat
	nvram unset lanlimit_prev_sfe
	nvram unset lanlimit_prev_sqm
	nvram commit
	log "已还原硬件加速（hw_nat_mode=$ph）"
	# 原本是开着的，要把 hw_nat 模块重新加载起来
	if [ "$ph" != "0" ]; then
		restart_firewall >/dev/null 2>&1 &
	fi
	return 0
}

do_start() {
	# 按设备限速挂在 QOS 流控（SQM）总开关下面：关着就不该生效。
	# 这里同时承担「撤销」职责 —— 之前生效过、现在总开关被关掉的情况下，
	# 光不新建规则不够，旧的 tc 规则和硬件加速改动都得还回去。
	#
	# 清理动作是无条件做的，不去先探测「有没有残留」：探测要么多一个持久标记、
	# 要么去 tc show 里 grep "htb 1:"，而后者会误判 —— SQM 自己在 br0 上也挂
	# 同样是 htb 1: 的 qdisc，grep 到就会把它删掉。无条件清扫反而安全，因为
	# SQM 关着时它的 qdisc 已由 stop-sqm 撤掉，此时删除只会命中我们自己挂的东西
	# （没有就什么都不删）。代价是每次点「应用」多一条日志和几条空转的 tc 调用
	if [ "$(nvram get sqm_enable 2>/dev/null)" != "1" ]; then
		do_stop
		hwnat_restore
		log "QOS 流控（SQM）总开关未开启，按设备限速不生效"
		return 0
	fi

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
		# 规则被清空了，之前挂上去的 tc 类与过滤器必须一起撤掉，
		# 否则旧限速会一直生效到重启
		do_stop
		hwnat_restore
		log "配置里没有任何限速项"
		return 0
	fi

	# 有限速规则才动硬件加速；关掉开关则走还原分支，
	# 免得之前自动关过、用户又在这里关掉开关后一直关着
	if [ "$AUTOHWNAT" = "1" ]; then
		hwnat_off
	else
		hwnat_restore
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
	# 停用限速时把硬件加速还回去，否则会一直关着影响转发性能
	stop)         do_stop; hwnat_restore ;;
	show)         do_show ;;
	*)            echo "用法: $0 start|stop|reload|show" ; exit 1 ;;
esac
