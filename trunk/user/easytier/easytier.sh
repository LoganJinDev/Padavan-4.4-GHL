#!/bin/sh
#
# EasyTier 客户端控制脚本（Padavan 移植版）
#
# 用法： easytier.sh start|stop|restart|firewall|dl|state|C
#   start    —— 启动 easytier-core（本体转后台运行）
#   stop     —— 停止进程并清理运行态
#   restart  —— 先 stop 再 start
#   firewall —— 只重建防火墙规则（由 start_firewall_ex() 钩子调用）
#   C        —— 保活检查，供 cron 每分钟调用：进程掉了就拉起、日志超限就轮转
#   dl       —— 后台下载二进制（界面按钮调用，立刻返回、不等下载完）
#   state    —— 单行回显二进制与隧道状态（界面按钮调用，只读、同步）
#
# 与官方 OpenWrt easytier.init 的差异（移植时必须做的等价替换）：
#   * Padavan 没有 procd        ⇒ 用「后台启动 + cron 保活」替代 respawn（照 frp.sh）
#   * Padavan 没有 UCI          ⇒ 配置改从 nvram 读
#   * Padavan 没有 /overlay     ⇒ 空间探测改用 df /tmp
#   * Padavan 没有 /var/lock    ⇒ 不再需要锁（cron 每分钟一次，本身不并发）
#   * 官方 start_web() 整段丢弃 ⇒ webconsole 在 mipsel 上不存在（上游
#     depends on !(mips||mipsel)，发布 zip 内也确实没有 web 二进制）
#   * 官方 utils.sh 的 safe_exec() 用 eval 执行拼接出来的命令 ⇒ 本脚本一律用
#     位置参数 set -- 拼装 argv，绝不 eval，避免命令注入
#
# 安全约定：
#   * --network-secret 绝不写进日志（ps 输出里无法避免，但日志可以）
#   * 二进制只从 $ET_DIR 下执行，且必须是 700 权限（由 easytier_download.sh 保证）
#

# 禁止 glob 展开：本脚本所有清理动作都用显式列表，不依赖通配符。
# 好处是文件名里带特殊字符也不会误伤，坏处是忘记写全就漏删 —— 故 RPC 缓存
# 列表集中在下面一处定义。
set -f

ET_DIR=/tmp/easytier
ET_CORE=$ET_DIR/easytier-core
ET_CLI=$ET_DIR/easytier-cli

# 大闪存机型把二进制编进固件，落在 /usr/bin；小闪存机型下载到 /tmp/easytier。
# ET_CORE / ET_CLI 由 et_resolve_bins() 按实际存在情况改写。
ET_SYS_CORE=/usr/bin/easytier-core
ET_SYS_CLI=/usr/bin/easytier-cli

ET_LOG=/tmp/easytier.log
ET_TSFILE=/tmp/easytier_time
ET_DL=/usr/bin/easytier_download.sh
ET_SELF=/usr/bin/easytier.sh

# 下载互斥锁（目录）。★ 别和 easytier_download.sh 的暂存目录/tmp/easytier_dl 撞名。
ET_DL_LOCK=/tmp/easytier_dl.lock

# easytier-cli 的 RPC 结果缓存。
# ★ 必须逐个列出，不能用 /tmp/easytier-cli_* 通配 —— 上面 set -f 已禁 glob。
# 残留后果：stop 后 easytier-cli 仍能读到上一次的 peer 列表，界面显示假数据。
ET_RPC_CACHES="easytier-cli_peer easytier-cli_connector easytier-cli_stun
easytier-cli_route easytier-cli_acl easytier-cli_peer-center
easytier-cli_vpn-portal easytier-cli_node easytier-cli_mapped_listener
easytier_cmd"

# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------

et_log() {
	logger -t easytier "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$ET_LOG"
}

# 日志轮转：超过 5120 KiB 就只留最后 500 行（阈值与官方一致）
et_rotate_log() {
	[ -f "$ET_LOG" ] || return 0
	_sz=$(ls -l "$ET_LOG" 2>/dev/null | awk '{print int($5/1024)}')
	[ -z "$_sz" ] && return 0
	if [ "$_sz" -gt 5120 ]; then
		tail -n 500 "$ET_LOG" > "$ET_LOG.tmp" 2>/dev/null && mv "$ET_LOG.tmp" "$ET_LOG"
		et_log "日志超过 5120KB，已截断保留最后 500 行"
	fi
}

# ---------------------------------------------------------------------------
# 配置读取
# ---------------------------------------------------------------------------

# 决定用哪一份二进制：/tmp 下载的优先，其次固件内置的。
#
# ★ 为什么不统一复制到 /tmp：8.94 MiB 复制进 tmpfs 是纯浪费 —— 占内存，
#   而且每次重启都要重来。内置机型直接原地执行。
# ★ 两份都不在时不报错：后面 easytier_start 会走下载路径，
#   下载失败才由那里报「不存在或不可执行」。
et_resolve_bins() {
	if [ -x "$ET_DIR/easytier-core" ]; then
		ET_CORE=$ET_DIR/easytier-core
		ET_CLI=$ET_DIR/easytier-cli
	elif [ -x "$ET_SYS_CORE" ]; then
		ET_CORE=$ET_SYS_CORE
		ET_CLI=$ET_SYS_CLI
	fi
}

# 一次性把 nvram 读进变量，避免后面反复调用 nvram
et_load_cfg() {
	et_resolve_bins
	ET_ENABLE=$(nvram get easytier_enable)
	ET_NETNAME=$(nvram get easytier_network_name)
	ET_NETSECRET=$(nvram get easytier_network_secret)
	ET_IPV4=$(nvram get easytier_ipv4)
	ET_PEERS=$(nvram get easytier_peers)
	ET_PROXY=$(nvram get easytier_proxy_networks)
	ET_EXITS=$(nvram get easytier_exit_nodes)
	ET_HOSTNAME=$(nvram get easytier_hostname)
	ET_MTU=$(nvram get easytier_mtu)
	ET_NOP2P=$(nvram get easytier_disable_p2p)
	ET_MASQ=$(nvram get easytier_masq)

	ET_RPC=$(nvram get easytier_rpc_port)
	[ -z "$ET_RPC" ] && ET_RPC="127.0.0.1:15888"

	ET_LISTEN=$(nvram get easytier_listen_port)
	[ -z "$ET_LISTEN" ] && ET_LISTEN="11010"

	# 端口白名单：必须是纯数字。这个值会被拼进 iptables 规则，不能让任意字符过关。
	case "$ET_LISTEN" in
		''|*[!0-9]*) ET_LISTEN=11010 ;;
	esac

	# 设备名白名单：只允许字母数字下划线连字符，非法值回落 et0。
	ET_DEV=$(nvram get easytier_dev_name)
	case "$ET_DEV" in
		''|*[!a-zA-Z0-9_-]*) ET_DEV=et0 ;;
	esac

	# 日志级别白名单
	case "$(nvram get easytier_log_level)" in
		error|warn|info|debug|trace) ET_LOGLEVEL=$(nvram get easytier_log_level) ;;
		*) ET_LOGLEVEL=info ;;
	esac
}

# ---------------------------------------------------------------------------
# 网络可达性
# ---------------------------------------------------------------------------

# 返回 0 = 外网通。★ 语义与 frp.sh 的 check_net 相反（那个是 ping 通返回 1），
# 这里刻意用常规语义，避免后续维护者踩同一个坑。
et_check_net() {
	/bin/ping -c 2 -w 5 223.5.5.5 >/dev/null 2>&1 && return 0
	/bin/ping -c 2 -w 5 114.114.114.114 >/dev/null 2>&1 && return 0
	return 1
}

# ---------------------------------------------------------------------------
# cron 保活
# ---------------------------------------------------------------------------

et_cron_file() {
	echo "/etc/storage/cron/crontabs/$(nvram get http_username)"
}

# 安装保活 cron。先删自己的行再加，保证幂等。
# ★ 匹配关键字用 easytier，与 frp.sh 的 '/frp/d' 互不误删。
et_install_cron() {
	_cron=$(et_cron_file)
	[ -f "$_cron" ] || return 0
	sed -i '/easytier/d' "$_cron"
	echo "*/1 * * * * /bin/sh $ET_SELF C >/dev/null 2>&1" >> "$_cron"
}

et_remove_cron() {
	_cron=$(et_cron_file)
	[ -f "$_cron" ] || return 0
	sed -i '/easytier/d' "$_cron"
}

# ---------------------------------------------------------------------------
# 防火墙
# ---------------------------------------------------------------------------

# 幂等加一条规则：已存在则跳过
et_ipt_add() {
	iptables -C "$@" >/dev/null 2>&1 || iptables -A "$@"
}

et_ipt_add_nat() {
	iptables -t nat -C "$@" >/dev/null 2>&1 || iptables -t nat -A "$@"
}

# 建立隧道接口的放行规则。
#
# 对应官方 OpenWrt 的 firewall.easytierzone（input/output/forward=ACCEPT +
# masq=1 + mtu_fix=1）—— 那一套已经涵盖了官方 setup_forwarding_rules() 的四方向
# 转发（etfwlan/etfwwan/lanfwet/wanfwet），所以这里只需 5 条：
#   INPUT   -i et0  ACCEPT   允许对端访问本机（ping 隧道 IP、访问路由器服务）
#   FORWARD -i et0  ACCEPT   允许对端访问 LAN 设备
#   FORWARD -o et0  ACCEPT   允许 LAN 设备回程
#   nat     -o et0  MASQUERADE  源地址伪装（官方 masq=1）
#   MSS clamp                官方 mtu_fix=1，防大包被隧道 MTU 卡住
#
# ★ 接口不存在时 iptables 也会接受规则（只是永远不匹配），所以本函数不依赖
#   easytier-core 已经启动 —— 与 firewall_ex.c 的调用顺序解耦。
et_setup_firewall() {
	[ -n "$ET_DEV" ] || return 0

	# WAN 侧放行监听端口（官方 add_firewall_rule 的 src=wan ACCEPT）
	if [ -n "$ET_LISTEN" ]; then
		et_ipt_add INPUT -p tcp --dport "$ET_LISTEN" -j ACCEPT
		et_ipt_add INPUT -p udp --dport "$ET_LISTEN" -j ACCEPT
	fi

	et_ipt_add INPUT -i "$ET_DEV" -j ACCEPT
	et_ipt_add FORWARD -i "$ET_DEV" -j ACCEPT
	et_ipt_add FORWARD -o "$ET_DEV" -j ACCEPT

	if [ "$ET_MASQ" != "0" ]; then
		et_ipt_add_nat POSTROUTING -o "$ET_DEV" -j MASQUERADE
	fi

	# MSS 钳制：隧道 MTU 小于物理口时，PMTU 黑洞会让大包静默丢失
	et_ipt_add FORWARD -o "$ET_DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

	et_log "防火墙规则已就绪（设备 $ET_DEV，监听端口 $ET_LISTEN）"
}

et_clean_firewall() {
	[ -n "$ET_DEV" ] || return 0

	if [ -n "$ET_LISTEN" ]; then
		iptables -D INPUT -p tcp --dport "$ET_LISTEN" -j ACCEPT 2>/dev/null
		iptables -D INPUT -p udp --dport "$ET_LISTEN" -j ACCEPT 2>/dev/null
	fi
	iptables -D INPUT -i "$ET_DEV" -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i "$ET_DEV" -j ACCEPT 2>/dev/null
	iptables -D FORWARD -o "$ET_DEV" -j ACCEPT 2>/dev/null
	iptables -t nat -D POSTROUTING -o "$ET_DEV" -j MASQUERADE 2>/dev/null
	iptables -D FORWARD -o "$ET_DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
}

# ---------------------------------------------------------------------------
# 启动 / 停止
# ---------------------------------------------------------------------------

easytier_start() {
	et_load_cfg

	if [ "$ET_ENABLE" != "1" ]; then
		et_log "未启用（easytier_enable=$ET_ENABLE），跳过启动"
		return 0
	fi

	if [ -n "$(pidof easytier-core)" ]; then
		et_log "easytier-core 已在运行，跳过启动"
		return 0
	fi

	# 二进制不存在就尝试下载（固件内未编译二进制时走这条路）
	if [ ! -x "$ET_CORE" ]; then
		if [ -x "$ET_DL" ]; then
			et_log "未找到 $ET_CORE，尝试下载"
			"$ET_DL" download
		fi
	fi
	if [ ! -x "$ET_CORE" ]; then
		et_log "错误：$ET_CORE 不存在或不可执行，放弃启动"
		return 1
	fi

	# 必填项：网络名。没有它 easytier 会落到公共网络，不符合预期。
	if [ -z "$ET_NETNAME" ]; then
		et_log "错误：easytier_network_name 未配置，放弃启动"
		return 1
	fi

	# ---- 拼装 argv ----
	# ★ 全程用位置参数 set --，绝不把命令拼成字符串再 eval。
	#   下面每个 set -- 都作用在 easytier_start 自己的 $@ 上，不影响脚本尾部的 case。
	set -- "$ET_CORE"
	set -- "$@" --network-name "$ET_NETNAME"
	[ -n "$ET_NETSECRET" ] && set -- "$@" --network-secret "$ET_NETSECRET"
	[ -n "$ET_IPV4" ] && set -- "$@" -i "$ET_IPV4"
	[ -n "$ET_HOSTNAME" ] && set -- "$@" --hostname "$ET_HOSTNAME"
	set -- "$@" --dev-name "$ET_DEV"
	[ -n "$ET_MTU" ] && set -- "$@" --mtu "$ET_MTU"
	set -- "$@" -r "$ET_RPC"
	set -- "$@" --console-log-level "$ET_LOGLEVEL"
	set -- "$@" -l "tcp://0.0.0.0:$ET_LISTEN"
	[ "$ET_NOP2P" = "1" ] && set -- "$@" --disable-p2p

	# ★ 多值字段必须内联在这里展开，不能抽成函数：
	#   抽成函数的话 set -- 只改那个函数自己的 $@，加进去的参数全丢；
	#   写成 `printf ... | while read` 则管道开子 shell，同样丢。
	#   for 循环体在当前位置执行，改的就是本函数的 $@，这才有效。
	for _p in $(printf '%s' "$ET_PEERS" | tr ',;' '  '); do
		[ -n "$_p" ] && set -- "$@" -p "$_p"
	done

	# -n 宣告本机 LAN 网段给全网 —— 这就是「LAN 内所有设备与其他客户端双向互通」
	for _n in $(printf '%s' "$ET_PROXY" | tr ',;' '  '); do
		[ -n "$_n" ] && set -- "$@" -n "$_n"
	done

	for _e in $(printf '%s' "$ET_EXITS" | tr ',;' '  '); do
		[ -n "$_e" ] && set -- "$@" --exit-nodes "$_e"
	done

	# ★ 日志脱敏：network-secret 是网络准入凭据，绝不能落盘
	et_log "启动：$(printf '%s' "$*" | sed 's/--network-secret [^ ][^ ]*/--network-secret ***/')"

	# 三个 fd 全部重定向，进程才能脱离控制终端独立存活
	cd /tmp || return 1
	"$@" </dev/null >>"$ET_LOG" 2>&1 &

	# 记录启动时刻，供保活检查判断宽限期
	date +%s > "$ET_TSFILE"

	et_setup_firewall

	# 开启 IPv4 转发（官方在 start_et 尾部做同一件事）
	echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

	# 不立刻判活：easytier-core 建 TUN、跑握手都需要时间，
	# 这里只确认进程没当场退出，真正的健康判断交给 cron 的 C 路径。
	sleep 2
	if [ -n "$(pidof easytier-core)" ]; then
		et_log "easytier-core 启动成功"
	else
		et_log "警告：easytier-core 启动后立即退出，请查看 $ET_LOG"
	fi
}

easytier_stop() {
	et_load_cfg

	# 先干掉可能正在执行的保活检查（官方 stop_service 同款做法），
	# 否则 cron 可能在 stop 中途把进程又拉起来
	for _pid in $(pidof easytier_check); do
		kill -9 "$_pid" 2>/dev/null
	done

	if [ -n "$(pidof easytier-core)" ]; then
		killall -9 easytier-core 2>/dev/null
		sleep 1
		[ -z "$(pidof easytier-core)" ] && et_log "easytier-core 已停止"
	fi

	et_clean_firewall

	# 清理 RPC 结果缓存 —— 不清的话 easytier-cli 会读到陈旧数据
	for _c in $ET_RPC_CACHES; do
		rm -f "/tmp/$_c"
	done
	rm -f "$ET_TSFILE"

	# ★ 刻意不删 $ET_LOG：日志是排障依据，留在 /tmp 由轮转机制管理
}

# ---------------------------------------------------------------------------
# 保活检查（cron 每分钟一次）
# ---------------------------------------------------------------------------

easytier_check() {
	et_load_cfg
	et_rotate_log

	[ "$ET_ENABLE" = "1" ] || return 0

	if [ -n "$(pidof easytier-core)" ]; then
		# 宽限期：刚启动 120 秒内 TUN 可能还没建好，不能据此判死。
		# 没有这个宽限期，慢启动会被误判成故障，陷入「起来就被杀」的死循环。
		_now=$(date +%s)
		_start=$(cat "$ET_TSFILE" 2>/dev/null)
		[ -z "$_start" ] && _start=$_now
		if [ $((_now - _start)) -lt 120 ]; then
			return 0
		fi

		if ifconfig "$ET_DEV" >/dev/null 2>&1; then
			return 0	# 进程在、接口在 ⇒ 健康
		fi

		et_log "easytier-core 在运行但接口 $ET_DEV 不存在，判定为异常并重启"
		easytier_stop
	fi

	if et_check_net; then
		easytier_start
	else
		et_log "外网不通，本轮不启动"
	fi
}

# ---------------------------------------------------------------------------
# 界面按钮入口
# ---------------------------------------------------------------------------

# 状态回显：既打到 stdout（SystemCmd 通道会把它送回界面），也写进 nvram
# 的 easytier_bin_state —— 这样点完「保存」整页重载后状态格不是空的。
# ★ nvram set 只认【等号】形式：写成 `nvram set key value` 会被静默当成
#   unset（删掉这个变量，还返回 0）。整个 `key=value` 必须是一个参数。
# ★ 只 set 不 commit：状态是易失信息，不值得为它写一次 flash；
#   下次任何一次正常 commit 会顺带把它带上。
et_state_echo() {
	echo "$1"
	nvram set "easytier_bin_state=$1"
}

# 供界面「下载 / 校验二进制」按钮调用。
# ★ 必须【立刻返回】把下载丢到后台：这条命令走 httpd 的 SystemCmd 通道，
#   而整条命令被包成 `sh -c '<cmd> >/tmp/syscmd.log 2>&1'` —— 同步等一个
#   8.94 MiB 的下载（慢的时候好几分钟）会把 httpd 卡死在那里。
# ★ 互斥用 mkdir：同一文件系统上 mkdir 是原子的，比「先判断再创建」可靠。
#   锁由后台子 shell 在下载器退出后摘掉；/tmp 是 tmpfs，重启即清。
easytier_dl() {
	et_resolve_bins

	# 固件已内置 ⇒ 没什么可下的。说清楚，别让用户等一个永远不来的下载。
	if [ -x "$ET_SYS_CORE" ]; then
		et_state_echo "固件已内置二进制，无需下载"
		return 0
	fi

	if ! mkdir "$ET_DL_LOCK" 2>/dev/null; then
		et_state_echo "已有下载任务在进行，完成后点「刷新状态」"
		return 0
	fi

	( "$ET_DL" download >/dev/null 2>&1; rmdir "$ET_DL_LOCK" 2>/dev/null ) &

	et_state_echo "已开始后台下载（约 8.9 MiB），完成后点「刷新状态」"
}

# 供界面「刷新状态」按钮调用：算一遍二进制完整性，回显【单行】。
# ★ 单行是硬要求 —— 界面把它塞进行内 <span>，多行会被压成一行很难看。
# ★ 同步执行：只读 + 两次 sha256（约 8.94 MiB），设备上 1~3 秒，可接受；
#   异步的是 dl，不是它。
easytier_state() {
	et_resolve_bins

	_where="下载到 /tmp"
	[ "$ET_CORE" = "$ET_SYS_CORE" ] && _where="固件内置"

	# 下载进行中就直接报这个：此刻 /tmp 里的文件本来就不完整，
	# 算哈希只会得到一个吓人的「校验不通过」。
	if [ -d "$ET_DL_LOCK" ]; then
		et_state_echo "下载中… 完成后点「刷新状态」"
		return 0
	fi

	# 二进制就绪判定。★ 哈希常量只在 easytier_download.sh 里有一份，
	#   这里用 check 的显式路径参数复用，绝不把 sha256 抄第二遍。
	#   ★ 必须传路径：download.sh 自己只认 /tmp，不传会把固件内置的
	#   大闪存机型判成校验失败。
	if [ ! -f "$ET_CORE" ] && [ ! -f "$ET_CLI" ]; then
		_bin="二进制缺失，点「下载 / 校验二进制」"
	elif [ -x "$ET_DL" ] && "$ET_DL" check "$ET_CORE" "$ET_CLI" >/dev/null 2>&1; then
		_bin="二进制就绪（$_where）"
	else
		_bin="二进制校验不通过，可能下载不完整，请重新下载"
	fi

	if [ -n "$(pidof easytier-core)" ]; then
		et_state_echo "运行中 · $_bin"
	else
		et_state_echo "已停止 · $_bin"
	fi
}

# ---------------------------------------------------------------------------
# 子命令派发
# ---------------------------------------------------------------------------

case "$1" in
	start)
		et_install_cron
		easytier_start
		;;
	stop)
		easytier_stop
		et_remove_cron
		;;
	restart)
		easytier_stop
		et_install_cron
		easytier_start
		;;
	firewall)
		et_load_cfg
		[ "$ET_ENABLE" = "1" ] && et_setup_firewall
		;;
	dl)
		easytier_dl
		;;
	state)
		easytier_state
		;;
	C)
		easytier_check
		;;
	*)
		echo "用法: $0 {start|stop|restart|firewall|dl|state|C}"
		;;
esac
