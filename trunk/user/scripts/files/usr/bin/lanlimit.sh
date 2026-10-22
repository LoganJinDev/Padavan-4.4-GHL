#!/bin/sh
#
# lanlimit.sh —— Padavan 按 IP / MAC 给单台 LAN 设备限速
#
# 依赖：/bin/tc（iproute2，固件已内置）、ifb 内核模块（CONFIG_FIRMWARE_INCLUDE_IFB=y）
# 配置：/etc/storage/lanlimit.conf，格式见该文件头部注释
# 用法：lanlimit.sh start | stop | reload | show
#
# 限速的两个方向分别落在哪里：
#
#   · 下行（外网 -> 客户端）挂在 LAN 网桥的**每个从属口**（eth2 / ra0 / rai0 ...）
#     的 egress 上。从属口的出口方向就是「发给客户端」，所以匹配 dst。
#     为什么不挂网桥主设备 br0：SQM 在 runmode_2/3 下把整形树挂在 br0 的 root
#     上，而 root 一个设备只有一个。两边都抢，谁后执行谁把对方连根删掉
#     （旧实现的 do_stop 无条件 `del dev br0 root`，正是「开了 SQM 再点应用就
#     失效」的根因）。改挂从属口之后，下行与 SQM 各占各的设备，彼此删不到。
#
#   · 上行（客户端 -> 外网）只能挂在网桥主设备 br0 的 ingress 上。
#     这不是选择而是唯一可行点，两条实测结论支撑：
#       ① 从属口的 ingress 拦不到上行包 —— bridge 在 br_pass_frame_up() 里会
#          嵌套再调一次 netif_receive_skb，此时 skb->dev 已经换成 br0，于是
#          handle_ing() 读的是 br0 的 ingress 链，从属口上挂多少都是 Sent 0；
#       ② WAN 口（eth3）的 ingress 虽然生效，但它位于 DNAT 之前，进来的下行包
#          dst 仍是公网地址，认不出是哪台内网设备。
#     ingress 本身没有队列，必须 mirred 到一个 ifb 虚拟设备再整形。镜像时包头
#     不变，所以匹配 src。
#
#   未被限速的设备走 default 类，速率取一个远高于实际带宽的值，等价于不限。
#
# ⚠️ 与 SQM 共用 br0 ingress 的后果：SQM 每次启动都会 `del` 再 `add` 这个 qdisc
#    （各 .qos 脚本的 ingress() 函数），本脚本挂上去的过滤器会被一并清掉，需要
#    再触发一次 reload 才能恢复；界面点「应用」时会连带重载本脚本，所以正常操作
#    路径上会自动重建。为把两边的干扰降到最低：
#      · 本脚本过滤器一律用 prio 1，SQM 用 prio 10，删除时按 prio 精确切分；
#      · do_stop 只在过滤器链**空了**才删 ingress qdisc，SQM 在跑时永远不空，
#        因此绝不会误删它的 qdisc；
#      · 建 ingress 只发裸 add 并吞掉失败 —— 已存在说明 SQM 建好了，直接共用。
#        这里刻意不用 `qdisc replace`：sch_ingress 没有 change 回调，replace 会
#        走销毁重建，连 SQM 的过滤器一起清掉。
#
# ⚠️ 另一种残余耦合：SQM 的 runmode_1 整形的就是 eth2，runmode_4 整的是
#    sqm_active 指定的那个接口，两者都可能是网桥的从属口。一个设备只容得下
#    一个 root qdisc，所以那种模式下下行限速本就挂不上去（build_skeleton 的
#    add 会失败）。此时代本脚本不去抢，do_stop 也认得出那不是自己的树、不会删
#    （见 port_is_ours）。要同时用，把 SQM 的模式选成 2 或 3（整形 br0）即可。
#
# ⚠️ 硬件 NAT 加速（hw_nat_mode）会把已建立的长连接（下载、在线视频）交给
#    MT7621 的 PPE 硬件直通转发，包不进内核协议栈，也就不经过 qdisc，限速对
#    它们无效。因此只要配置里存在生效的限速条目，本脚本会仿 sqm/run.sh 的
#    做法自动关掉它并卸载 hw_nat 模块，代价是转发性能下降。
#    SFE（sfe_enable / shortcut_fe）也一并置 0，但那是保守起见 —— SFE 挂的是
#    内核的 POST_ROUTING 钩子，省掉的是路由查找与 FORWARD 链，而 qdisc 在它
#    之前（网卡入口）和之后（网卡出口），所以 SFE 从不绕过限速，也不需要、
#    不应该去卸载它的模块（2026-10-22 设备实测：限速生效期间 shortcut_fe /
#    fast_classifier 仍在内存里，限速照常工作）。
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
#      ② 开机脚本（autostart.sh，排在 SQM 启动之后）；
#      ③ 手工执行。
#    只在界面加限制的话，①③ 仍然会绕过。

LAN_IF="br0"
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

# 列出网桥当前的全部从属口，一行一个；没有则输出为空。
# ⚠️ 判据必须是「brif 目录里有条目」而不是「br0 存在」：br0 会先于成员口出现，
# 此时若退回 br0 本身，规则就会挂到网桥主设备上，正好撞上 SQM 的整形树。
# 目录不存在、或存在但为空，一律返回空 —— 调用方据此直接跳过。
lan_ports() {
	local p
	for p in /sys/class/net/"$LAN_IF"/brif/*; do
		[ -e "$p" ] || continue
		basename "$p"
	done
}

# 判断某个从属口 root 上的整形树是不是本脚本建的。
# htb 的 dump 会把自己的 default 类号一并打出来，本脚本恒用 99，SQM 的 htb 用 10，
# cake / tbf 的 root 压根不是 htb。靠这个标记就能精确区分归属，不必去复刻 SQM 的
# 「runmode -> 接口」映射（那份映射在上游一改就会失配，反而变成新的隐患）
#
# ⚠️ default 类号必须按十六进制比，不能按十进制字面量比。
# tc 解析 default/classid 用的是 16 进制：写 `default 99` 实得 0x99（=153），
# dump 回来也是 `default 0x99`。早年这里直接比字符串 "default 99" 永远 NOMATCH，
# 后果是 do_stop 认不出自己的树 -> 不删 -> reload 时 add 全部 File exists ->
# 旧速率（如 2048Kbit）一直残留，改限速值永不生效（2026-10-19 设备实测）。
# 剥掉 0x/0X 前缀后 "0x99" 与 "99" 归一；153 是同类的十进制写法，一并认。
port_is_ours() {
	local p q d
	p="$1"
	q="$(tc qdisc show dev "$p" root 2>/dev/null)"
	case "$q" in *"htb 1:"*) ;; *) return 1 ;; esac
	d="${q##*default }"
	d="${d%% *}"
	d="${d#0x}"
	d="${d#0X}"
	case "$d" in 99|153) return 0 ;; esac
	return 1
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
# 免得凭空给网口挂一层无用的整形
scan_conf() {
	DL=0
	UL=0
	while read -r tgt dl ul _; do
		case "$tgt" in ""|\#*) continue ;; esac
		[ "${dl:-0}" -gt 0 ] 2>/dev/null && DL=1
		[ "${ul:-0}" -gt 0 ] 2>/dev/null && UL=1
	done < "$CONF"
}

# 只拆自己挂的东西。br0 与从属口上分别可能立着 SQM 的整形树，处置方式不同：
#   · br0 root    —— SQM 在 runmode_2/3 下的落脚点，一个 qdisc 都不碰
#   · br0 ingress —— 上行唯一可行的落点，必须与 SQM 共用同一个 qdisc，
#                    所以只删自己的过滤器（prio 1，SQM 是 prio 10），
#                    并且确认链上再没有别人才回收 qdisc
#   · 从属口 root —— 按 port_is_ours 认领，不是自己的一律不动
do_stop() {
	local p
	for p in $(lan_ports); do
		port_is_ours "$p" || continue
		tc qdisc del dev "$p" root 2>/dev/null
	done
	tc filter del dev "$LAN_IF" parent ffff: protocol ip prio 1 2>/dev/null
	if [ -z "$(tc filter show dev "$LAN_IF" parent ffff: 2>/dev/null)" ]; then
		tc qdisc del dev "$LAN_IF" ingress 2>/dev/null
	fi
	tc qdisc del dev "$IFB_DEV" root 2>/dev/null
	ip link set "$IFB_DEV" down 2>/dev/null
	log "已清除全部限速规则"
}

# 建两个方向各自的「骨架」：根 qdisc + 不限速的 default 类
build_skeleton() {
	local p
	if [ "$DL" = "1" ]; then
		for p in $(lan_ports); do
			tc qdisc add dev "$p" root handle 1: htb default 99
			tc class add dev "$p" parent 1: classid 1:99 htb rate "$FREE_RATE"
		done
	fi
	if [ "$UL" = "1" ]; then
		modprobe ifb 2>/dev/null
		ip link set "$IFB_DEV" up 2>/dev/null
		# 与 SQM 共用 br0 的 ingress。已存在时 add 会失败，这里就是要它失败 ——
		# 说明 SQM 已经建好，直接拿来用即可。刻意不用 replace：见文件头注释
		tc qdisc add dev "$LAN_IF" handle ffff: ingress 2>/dev/null
		tc qdisc add dev "$IFB_DEV" root handle 2: htb default 99
		tc class add dev "$IFB_DEV" parent 2: classid 2:99 htb rate "$FREE_RATE"
	fi
}

# 给一台设备挂上类与过滤器。n 是类号，从 1 开始，避开 default 的 99
limit_one() {
	local tgt dl ul ip n p
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
		# 每个从属口都要挂：设备接 2.4G 走 ra0、接 5G 走 rai0、走网线走 eth2，
		# 事先不知道它会从哪个口出去，全部挂上一份，代价只是几条规则
		for p in $(lan_ports); do
			tc class add dev "$p" parent 1: classid "1:$n" \
				htb rate "${dl}kbit" ceil "${dl}kbit" burst 15k
			tc filter add dev "$p" parent 1: protocol ip prio 1 \
				u32 match ip dst "$ip"/32 flowid "1:$n"
		done
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
		# ⚠️ 下面三行必须写成 name=value。Padavan 的 nvram applet 只认等号形式，
		# 写成 `nvram set name value` 会被静默当成 `nvram unset name` ——
		# 原值存不下、已有的值还会被一起抹掉，而退出码依然是 0，
		# 从外部完全看不出异常。2026-10-19 设备实测根因：关掉 SQM 后
		# 硬件加速再也回不来（hwnat_restore 读到空值直接 return），就是这三行。
		nvram set lanlimit_prev_hwnat="${hw:-0}"
		nvram set lanlimit_prev_sfe="${se:-0}"
		nvram set lanlimit_prev_sqm="$(nvram get sqm_enable 2>/dev/null)"
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
# 会和它抢，此时只还 SFE。重新加载 hw_nat 交给 rc（会带上正确的 VLAN 参数，
# 比自己 modprobe 可靠），但必须走通知那条路径 —— 见下面的说明
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
	# 原本是开着的，要把 hw_nat 模块重新加载起来。
	#
	# ⚠️ 必须走 rc 的**通知**机制，不能执行 /sbin/restart_firewall。
	# 那个文件是 rc 的 symlink，但 shell 执行它走的是 main() 的 argv[0] 派发
	# （rc.c:1705），只调 restart_firewall()；带 reload_nat_modules() 的是
	# 通知派发那条（rc.c:1333 的 RCN_RESTART_FIREWALL 分支）。
	# 走错路径的症状很隐蔽：nvram 值全对、命令也没报错，但模块根本没加载，
	# 硬件加速静默不回来（2026-10-19 设备实测：lsmod 里查不到 hw_nat）。
	if [ "$ph" != "0" ]; then
		if [ -d /tmp/rc_notification ]; then
			: >/tmp/rc_notification/restart_firewall
			kill -USR1 1 2>/dev/null
		else
			# 兜底：通知目录还不存在（rc 未就绪）时退回直接调用，
			# 至少让 nvram 值生效，模块等下次防火墙重启再加载
			restart_firewall >/dev/null 2>&1 &
		fi
	fi
	return 0
}

do_start() {
	# 按设备限速挂在 QOS 流控（SQM）总开关下面：关着就不该生效。
	# 这里同时承担「撤销」职责 —— 之前生效过、现在总开关被关掉的情况下，
	# 光不新建规则不够，旧的下行队列与上行过滤器都得还回去。
	#
	# 清理动作是无条件做的，不去先探测「有没有残留」：探测要么多一个持久标记、
	# 要么去 tc show 里比对，而后者容易误判。无条件清扫在这里是安全的，因为
	# do_stop 已经改成只碰自己的东西 —— 从属口的 root 按 port_is_ours 认领，
	# br0 只删自己的 prio 1 过滤器、链非空时不动 qdisc，所以 SQM 正开着也删不到
	# 它头上。代价是每次点「应用」多一条日志和几条空转的 tc 调用
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
	# 网桥还没起来的场景（开机脚本里调）等一小会儿。判据取「有没有从属口」
	# 而不是「br0 在不在」：br0 会先于成员口出现，此时挂规则等于挂到空网桥上
	w=0
	while [ -z "$(lan_ports)" ] && [ "$w" -lt 20 ]; do
		sleep 1
		w=$((w + 1))
	done
	if [ -z "$(lan_ports)" ]; then
		log "网桥 $LAN_IF 下没有从属口，放弃"
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
	local p
	for p in $(lan_ports); do
		echo "--- $p 出口（下行）---"
		tc -s class show dev "$p" 2>/dev/null
	done
	echo "--- $LAN_IF 入口（上行，镜像到 $IFB_DEV）---"
	tc -s filter show dev "$LAN_IF" parent ffff: 2>/dev/null
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
