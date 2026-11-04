#!/bin/sh
#
# EasyTier 客户端控制脚本（Padavan 移植版）
#
# 用法： easytier.sh start|stop|restart|firewall|dl|state|C|info|link|log|logclear|bininfo
#   start    —— 启动 easytier-core（本体转后台运行）
#   stop     —— 停止进程并清理运行态
#   restart  —— 先 stop 再 start
#   firewall —— 只重建防火墙规则（由 start_firewall_ex() 钩子调用）
#   C        —— 保活检查，供 cron 每分钟调用：进程掉了就拉起、日志超限就轮转
#   dl       —— 后台下载二进制（界面按钮调用，立刻返回、不等下载完）
#   state    —— 单行回显二进制与隧道状态（界面按钮调用，只读、同步）
#   info     —— 只读查询连接信息（peer/route/node/conn），界面按钮调用
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
# P2 通断检测的运行态标记（/tmp 是 tmpfs，重启即清）。
# ★ 不复用 ET_TSFILE：那个是「进程启动时刻」，语义不同，混用会让宽限期算错。
ET_CHKTS=/tmp/easytier_check_ts
ET_CHKFAIL=/tmp/easytier_check_fail

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

# 供界面「日志」区块调用：把日志尾部若干行原样打到 stdout。
# ★ 刻意【不做】ANSI 去色：busybox sed 自己只认 \n \t \r 三种反斜杠转义
#   （sed.c 的 copy_parsing_escapes 那个 for 循环），\x1b 能不能生效取决于
#   libc 的 regex，而那部分源码没随 busybox 进本仓库 ⇒ 在仓库内无法证实。
#   去色改在前端用 JS 正则做（确定且可测）。就算前端也没去掉，ESC 字节留在
#   文本里同样无害 —— 前端用 .val() 赋值，永不解析 HTML。
# ★ 行数走白名单：非数字 / 前导零 / 越界一律回落到 300。
#   前导零必须单独挡：busybox test 的 -ge 可能按 base 0 解析，"08" 会直接报错。
#   注意 0*[0-9]* 命中 "08"/"010" 但【不】命中 "0"，所以 0 会落到下面的范围判断被拒。
et_log_view() {
	_lo_n="$2"
	case "$_lo_n" in
		''|*[!0-9]*|0*[0-9]*) _lo_n=300 ;;
	esac
	if [ "$_lo_n" -lt 1 ] || [ "$_lo_n" -gt 2000 ]; then
		_lo_n=300
	fi
	[ -f "$ET_LOG" ] || { echo "日志文件不存在（$ET_LOG）"; return 0; }
	tail -n "$_lo_n" "$ET_LOG"
	return 0
}

# 供界面「清空日志」按钮调用。
# ★ 顺序要紧：先截断、再写审计行。反过来的话那句「日志已被手动清空」
#   会被自己清掉，界面表现成「点了清空，文件是空的但没有任何痕迹」。
# ★ 只清文件，不碰运行中的隧道进程。
et_log_clear() {
	: > "$ET_LOG" 2>/dev/null || { echo "无法清空日志（$ET_LOG）"; return 1; }
	et_log "日志已被手动清空"
	echo "日志已清空"
	return 0
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

# ---------------------------------------------------------------------------
# 下载锁
# ---------------------------------------------------------------------------
# ★ 为什么需要：cron 保活每分钟起一个新进程，busybox crond 不做互斥；
#   而 easytier_download.sh 会无条件 `rm -rf` 暂存目录 ⇒ 两个实例并发会互相
#   踩掉对方的暂存目录，双双失败。锁把并发收敛成一个。
# ★ 锁是【目录】：同一文件系统上 mkdir 原子，比「先判断再创建」可靠。
#   目录内不写任何文件 ⇒ 释放用 rmdir；/tmp 是 tmpfs，重启即清。
# ★ ET_DL_LOCK 还有第三个读者：easytier_state() 见到锁目录就报「下载中…」
#   ⇒ 残锁不清理会让 Web UI 永远卡在这个状态。

# 残锁清理：持锁进程被 kill（或掉电）会留下没人摘的锁目录。
# 下载 8.94 MiB 正常不超过 10 分钟 ⇒ 锁目录 mtime 超 10 分钟即视为死锁。
# ★ 已真机成对对照验证 busybox find 的 -maxdepth / -mmin 有判别力
#   （造旧 mtime 要用 touch -t，busybox 的 touch 不支持 -d）。
# ★ 故意不写 2>/dev/null：开机窗口内 /dev/null 可能尚不存在，
#   那会让整条命令【不执行】而不是只吞掉报错。前置 [ -d ] 已足够。
et_dl_lock_stale_clean() {
	[ -d "$ET_DL_LOCK" ] || return 0
	[ -n "$(find "$ET_DL_LOCK" -maxdepth 0 -mmin +10)" ] && rmdir "$ET_DL_LOCK"
	return 0
}

# 抢锁。成功返回 0，已被占用返回 1。
et_dl_lock_acquire() {
	et_dl_lock_stale_clean
	mkdir "$ET_DL_LOCK" 2>/dev/null
}

# 放锁。
et_dl_lock_release() {
	rmdir "$ET_DL_LOCK" 2>/dev/null
}

# IPv4 合法性校验。
# ★ 为什么必须校验：检测目标 IP 是本脚本里唯一会进 ping 命令行的用户输入。
#   直接拼进去等于把命令注入面开到 nvram 上，所以读配置时就逐个过筛，
#   只保留合法的（不是「发现非法就整体拒绝」——那样一个笔误就让整个功能失效）。
# ★ 用 IFS=. + set -- 拆 4 段逐段校验，不依赖外部命令。
#   函数内的 set -- 只改本函数自己的 $@，不影响调用方。
et_valid_ip4() {
	case "$1" in
		*[!0-9.]*) return 1 ;;
	esac
	_vi_save=$IFS
	IFS=.
	set -- $1
	IFS=$_vi_save
	[ $# -eq 4 ] || return 1
	for _vi_o in "$@"; do
		# 空段（"1..2"）与前导零（"010"）一并拒掉 —— busybox 的 test
		# 可能按 base 0 解析，"010" 会变成 8。
		case "$_vi_o" in ''|*[!0-9]*|0*[0-9]*) return 1 ;; esac
		[ "$_vi_o" -le 255 ] || return 1
	done
	return 0
}

# P2 通断检测的配置读取与白名单校验。
# ★ 单独成函数而不是内联进 et_load_cfg：那段有 case + for + 两处分支，
#   内联会把 et_load_cfg 的 CCN 顶到阈值上限（实测 11 -> 15）。
et_load_check_cfg() {
	ET_CHKEN=$(nvram get easytier_check_enable)

	# 检测周期（分钟，1-1440）。前导零一并拒掉 —— busybox 的 test 可能按
	#   base 0 解析，"08" 会解析失败、"010" 会变成 8。
	ET_CHKTIME=$(nvram get easytier_check_time)
	case "$ET_CHKTIME" in
		''|*[!0-9]*|0*[0-9]*) ET_CHKTIME=2 ;;
		*) [ "$ET_CHKTIME" -ge 1 ] && [ "$ET_CHKTIME" -le 1440 ] || ET_CHKTIME=2 ;;
	esac

	# 检测目标 IP 列表：★ 这是唯一会进 ping 命令行的用户输入 ⇒ 逐个按 IPv4 校验，
	#   只保留合法的；一个都不合法就等于没配。分隔符接受空格 / 逗号 / 分号
	#   （与 ET_PEERS 一样宽进）。
	ET_CHKIP=""
	for _vip in $(printf '%s' "$(nvram get easytier_check_ip)" | tr ',;' '  '); do
		et_valid_ip4 "$_vip" || continue
		# ★ 这里刻意【不】用「去掉首个空格」的参数展开写法：lizard 的 shell 词法器
		#   会把参数展开内部出现的井号当成注释起点，连带吃掉同一行行尾的右花括号
		#   ⇒ 函数大括号永不闭合 ⇒ 整个函数被静默丢弃、复杂度统计归零。
		#   改成「非空才补分隔空格」，效果等价且对分析器透明。
		[ -n "$ET_CHKIP" ] && ET_CHKIP="$ET_CHKIP "
		ET_CHKIP="$ET_CHKIP$_vip"
	done
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

	# ---- P1 常用高级项 ----
	# 布尔项一律只读原值，白名单校验放在 argv 拼装处（那里才知道要不要发 flag）。
	ET_DHCP=$(nvram get easytier_dhcp)
	ET_LATFIRST=$(nvram get easytier_latency_first)
	ET_NOIPV6=$(nvram get easytier_disable_ipv6)
	ET_NOUPNP=$(nvram get easytier_disable_upnp)
	ET_EXITNODE=$(nvram get easytier_enable_exit_node)
	ET_NOENCRYPT=$(nvram get easytier_disable_encryption)
	ET_PRIVATE=$(nvram get easytier_private_mode)

	# 多线程：★ easytier-core 2.6.4 自己的默认值是 true（不是 false）。
	#   所以这里【不能】用「勾了才发」——那样「界面不勾」等于「实际开启」，
	#   语义正好反了。改成：nvram 默认 "1" + 恒发显式值，
	#   界面勾选就是唯一事实来源，完全不依赖二进制默认值。
	case "$(nvram get easytier_multi_thread)" in
		0) ET_MT=0 ;;
		*) ET_MT=1 ;;
	esac

	# 线程数：clap 侧是 u32，非数字会让 easytier-core 当场退出 ⇒ 只放纯数字。
	ET_MTCOUNT=$(nvram get easytier_multi_thread_count)
	case "$ET_MTCOUNT" in
		''|*[!0-9]*) ET_MTCOUNT="" ;;
	esac

	# 默认协议：只影响「优先尝试哪种监听协议」，非法值不崩，但会让优先级提示失效。
	#   "-" 是上游 LuCI 的「未指定」哨兵 ⇒ 与空串一样不传。
	ET_DEFPROTO=$(nvram get easytier_default_protocol)
	case "$ET_DEFPROTO" in
		tcp|udp|ws|wss) ;;
		*) ET_DEFPROTO="" ;;
	esac

	# 压缩：★ 非法值在 easytier-core 里是 panic!（core.rs:1117），不是优雅报错
	#   ⇒ 白名单是硬要求，不是「顺手校验」。none 是二进制默认值 ⇒ 不传。
	ET_COMP=$(nvram get easytier_compression)
	case "$ET_COMP" in
		zstd) ;;
		*) ET_COMP="" ;;
	esac

	# 加密算法：★ v2.6.4 只有这 4 个合法值。上游 LuCI 还列了 3 个 openssl-*，
	#   那是 2.7.0 才有的枚举项，在我们这个二进制上必然报错。
	#   aes-gcm 是二进制默认值 ⇒ 与空串一样不传。
	ET_ENCA=$(nvram get easytier_encryption_algorithm)
	case "$ET_ENCA" in
		xor|aes-256-gcm|chacha20) ;;
		*) ET_ENCA="" ;;
	esac

	# SOCKS5 端口：1-65535 纯数字。前导零一并拒掉 —— busybox 的 test 可能按
	#   八进制解析（base 0 自动识别），"08" 会解析失败，"01080" 会变成 576。
	ET_SOCKS=$(nvram get easytier_socks5)
	case "$ET_SOCKS" in
		''|*[!0-9]*|0*[0-9]*) ET_SOCKS="" ;;
		*) [ "$ET_SOCKS" -ge 1 ] && [ "$ET_SOCKS" -le 65535 ] || ET_SOCKS="" ;;
	esac

	# ---- P2 通断检测（读侧与校验见 et_load_check_cfg）----
	et_load_check_cfg
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

# 通断检测（P2）：隧道健康时周期性 ping 用户指定的目标 IP，全不通则重启隧道。
#
# ★ 与上游 LuCI 插件的三处刻意差异：
#   1. 上游用 procd 起一个常驻 while 循环；Padavan 没有 procd，本脚本复用已有的
#      cron 每分钟一跳（easytier_check），不额外起进程、不额外占内存。
#   2. 上游「本轮全不通就立刻重启」—— 目标 IP 自己挂掉就会变成重启循环。
#      这里要求【连续两轮】全不通才重启：误判代价从「断一次」降到「多等一轮」。
#   3. 上游每轮都写一行日志（每 checktime 分钟一条）。这里只在【状态翻转】和
#      【触发重启】时写 —— 每轮都写会同时灌 syslog 和 $ET_LOG。
#
# 返回 0 = 健康 / 未启用 / 未到检测时刻（调用方继续）
# 返回 1 = 判定不通且已达重启阈值（调用方负责 stop）
et_check_link() {
	[ "$ET_CHKEN" = "1" ] || return 0
	[ -n "$ET_CHKIP" ] || return 0

	# 时间闸门：cron 每分钟一跳，而检测周期是分钟级 ⇒ 自己记上次检测时刻。
	# /tmp 是 tmpfs，重启后标记消失 ⇒ 开机第一跳就会检测一次（期望行为）。
	_ck_now=$(date +%s)
	_ck_last=$(cat "$ET_CHKTS" 2>/dev/null)
	case "$_ck_last" in ''|*[!0-9]*) _ck_last=0 ;; esac
	[ $((_ck_now - _ck_last)) -ge $((ET_CHKTIME * 60)) ] || return 0
	echo "$_ck_now" > "$ET_CHKTS"

	# ★ 外网本身不通就直接跳过 —— 这正是上游那个 223.5.5.5 预检的作用。
	#   没有它，宽带掉线会被误判成「隧道故障」，变成无限重启。
	et_check_net || return 0

	_ck_ok=""
	_ck_ms=""
	for _ck_ip in $ET_CHKIP; do
		_ck_out=$(/bin/ping -c 2 -w 4 "$_ck_ip" 2>/dev/null)
		if [ $? -eq 0 ]; then
			_ck_ok="$_ck_ip"
			# ★ 用 sed 取平均延迟，而不是上游（以及本仓库 sh_ezscript.sh）的
			#   awk -F/ '{print $4}' —— 带 mdev 的输出
			#   （min/avg/max/mdev = a/b/c/d）里 $4 是 mdev，不是 avg。
			#   sed 只认「= 后面的前两个数」，两种格式都对。
			_ck_ms=$(printf '%s\n' "$_ck_out" | sed -n 's/.*= *[0-9.]*\/\([0-9.]*\).*/\1/p')
			break
		fi
	done

	if [ -n "$_ck_ok" ]; then
		# 只有「上一轮判定为不通」时才记恢复，否则每轮都会刷日志。
		if [ -f "$ET_CHKFAIL" ]; then
			_ck_msg="通断检测：已恢复（$_ck_ok 可达"
			[ -n "$_ck_ms" ] && _ck_msg="$_ck_msg，平均 ${_ck_ms}ms"
			et_log "$_ck_msg）"
		fi
		rm -f "$ET_CHKFAIL"
		return 0
	fi

	# 全不通：累加失败轮次
	_ck_n=$(cat "$ET_CHKFAIL" 2>/dev/null)
	case "$_ck_n" in ''|*[!0-9]*) _ck_n=0 ;; esac
	_ck_n=$((_ck_n + 1))
	echo "$_ck_n" > "$ET_CHKFAIL"

	if [ "$_ck_n" -lt 2 ]; then
		et_log "通断检测：$ET_CHKIP 全部不可达（第 $_ck_n 轮，未达重启阈值）"
		return 0
	fi

	et_log "通断检测：$ET_CHKIP 连续 $_ck_n 轮全部不可达，重启 easytier-core"
	rm -f "$ET_CHKFAIL"
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
# ★★ 这里【不能】加 `[ -f "$_cron" ] || return 0` 守卫。
#   本机型（CONFIG_FIRMWARE_INCLUDE_SCUTCLIENT=n）开机路径上没有任何东西
#   会创建 crontab 文件（check_crontab.sh 被 #if APP_SCUT 条件编译吃掉），
#   而 `>>` 本来就会自建文件 —— 加守卫等于把「首次使用」这个必经场景
#   变成静默 return 0（成功），cron 永远装不上。对齐 frp.sh / adbyby.sh 的写法。
et_install_cron() {
	_cron=$(et_cron_file)
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
# P1 常用高级项 -> 追加给 easytier-core 的额外参数
# ---------------------------------------------------------------------------
# ★ 为什么返回 token 流、由调用方词分割追加，而不是在函数里 set -- "$@"：
#   函数内的 set -- 只改那个函数自己的 $@，参数出了函数就没了。
#   这里输出的都是【已白名单校验过】的纯 token（数字 / 固定枚举 / true|false），
#   不含空格；本脚本第 33 行又开着 set -f（无通配）⇒ 调用方词分割是安全的。
# ★ 用 printf 而不是 echo：echo 对 `--latency-first` 这类以 - 开头的参数
#   行为依 busybox 版本而异，可能吞掉前导 `--`。
et_p1_flags() {
	[ "$ET_DHCP" = "1" ] && printf '%s\n' -d
	[ "$ET_LATFIRST" = "1" ] && printf '%s\n' --latency-first
	[ "$ET_NOIPV6" = "1" ] && printf '%s\n' --disable-ipv6
	[ "$ET_NOUPNP" = "1" ] && printf '%s\n' --disable-upnp
	[ "$ET_EXITNODE" = "1" ] && printf '%s\n' --enable-exit-node
	[ "$ET_NOENCRYPT" = "1" ] && printf '%s\n' -u

	# ★★ 本批唯一必须【带值】的布尔项。
	#   --private-mode 的 clap 定义没有 num_args / default_missing_value
	#   ⇒ 裸写 `--private-mode` 会让 clap 解析失败、easytier-core 当场退出，
	#   症状是「页面保存正常、隧道却起不来」，极难排查。必须显式给 true。
	[ "$ET_PRIVATE" = "1" ] && printf '%s\n' --private-mode true

	# ★ multi-thread 恒发显式值（对齐上游 initd.sh 的做法），理由见 et_load_cfg。
	if [ "$ET_MT" = "0" ]; then
		printf '%s\n' --multi-thread false
	else
		printf '%s\n' --multi-thread true
	fi

	[ -n "$ET_MTCOUNT" ] && printf '%s\n' --multi-thread-count "$ET_MTCOUNT"
	[ -n "$ET_DEFPROTO" ] && printf '%s\n' --default-protocol "$ET_DEFPROTO"
	[ -n "$ET_COMP" ] && printf '%s\n' --compression "$ET_COMP"
	[ -n "$ET_ENCA" ] && printf '%s\n' --encryption-algorithm "$ET_ENCA"
	[ -n "$ET_SOCKS" ] && printf '%s\n' --socks5 "$ET_SOCKS"

	# ★ SOCKS5 是【无认证】代理，且 easytier-core 固定绑 0.0.0.0（所有接口，
	#   core.rs:1011 / launcher.rs:669）—— 官方明确不再自动放行该端口到 WAN。
	#   本脚本同样只在 LAN 可达（et_setup_firewall 只放行监听端口），
	#   需要公网访问请自行在防火墙页加规则。
	# ★ 这条日志放函数内而不是调用方：et_log 的 stdout 是干净的
	#   （logger 走 syslog、echo 已重定向到 $ET_LOG）⇒ 不污染 token 流。
	[ -n "$ET_SOCKS" ] && et_log "提示：SOCKS5 代理已监听 0.0.0.0:$ET_SOCKS（无认证，仅 LAN 可达）"
	return 0
}

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
			# ★ 必须抢锁：cron 每分钟起一个新进程，而下载会 rm -rf 暂存目录，
			#   两个实例并发会互相踩掉、双双失败。抢不到就等下一分钟再试。
			if et_dl_lock_acquire; then
				et_log "未找到 $ET_CORE，尝试下载"
				"$ET_DL" download
				et_dl_lock_release
			else
				et_log "已有下载任务在进行，本轮跳过启动"
				return 1
			fi
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

	# ---- P1 常用高级项 ----
	# ★ 参数拼装全部在 et_p1_flags（返回 token 流）：输出的都是白名单校验过的
	#   纯 token（数字 / 固定枚举 / true|false），不含空格与 glob 字符；
	#   本脚本第 33 行已 set -f ⇒ 这里的词分割不做路径展开。
	set -- "$@" $(et_p1_flags)

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
	# 通断检测的运行态一并清掉：stop 之后重新 start 等于「重新开始计数」，
	# 否则手动重启后残留的失败计数会让下一轮直接触发重启。
	rm -f "$ET_CHKTS" "$ET_CHKFAIL"

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
			# 进程在、接口在 ⇒ 隧道本身健康；再跑一次 P2 通断检测。
			# et_check_link 返回 1 = 判定「不通且已达重启阈值」，
			# 落到下面的 easytier_stop 统一重启。
			et_check_link && return 0
			et_log "通断检测：隧道不通，重启 easytier-core"
		else
			et_log "easytier-core 在运行但接口 $ET_DEV 不存在，判定为异常并重启"
		fi
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

	if ! et_dl_lock_acquire; then
		et_state_echo "已有下载任务在进行，完成后点「刷新状态」"
		return 0
	fi

	( "$ET_DL" download >/dev/null 2>&1; et_dl_lock_release ) &

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

# 供界面「连接信息」按钮调用：把 easytier-cli 的一张表原样打到 stdout。
#
# ★ 只读、同步。走 SystemCmd 通道 ⇒ httpd 是单进程 select 循环、doSystem 阻塞，
#   这次请求会一直等到命令跑完才返回 ⇒ 界面不需要轮询。也正因为会阻塞 httpd，
#   这里只能放「毫秒级」的本地 RPC 查询，绝不能放下载这类长任务。
# ★ 白名单派发：$2 只允许下面四个词，绝不把它拼进命令串（无 eval、无字符串拼接）。
# ★ 命令串总长必须 < 127 字节（httpd 的 static SystemCmd[128]）。
#   实测 "easytier.sh info connector" 也只有 27 字节，余量充足。
# ★ node 用【默认 table 输出】而不是 -o json：json 里的 config 字段内嵌
#   network_secret 明文，原样回显到网页 = 泄漏网络准入凭据。
# ★ connector 的 table 输出是 Rust Debug 格式（不是对齐表格），能看但排版不同。
# ★ 这里【不判 easytier_enable】：隧道关着时也允许查看，此时 RPC 连不上，
#   回显的就是 cli 的原始报错，正好是排障需要的证据。
et_info() {
	et_load_cfg		# 内含 et_resolve_bins，顺带把 ET_RPC 读出来
	[ -x "$ET_CLI" ] || { echo "easytier-cli 不存在，请先点「下载 / 校验二进制」"; return 1; }
	case "$2" in
		peer)  "$ET_CLI" -p "$ET_RPC" peer ;;
		route) "$ET_CLI" -p "$ET_RPC" route ;;
		node)  "$ET_CLI" -p "$ET_RPC" node ;;
		conn)  "$ET_CLI" -p "$ET_RPC" connector ;;
		stun)       "$ET_CLI" -p "$ET_RPC" stun ;;
		peercenter) "$ET_CLI" -p "$ET_RPC" peer-center ;;
		vpnportal)  "$ET_CLI" -p "$ET_RPC" vpn-portal ;;
		proxy)      "$ET_CLI" -p "$ET_RPC" proxy ;;
		acl)        "$ET_CLI" -p "$ET_RPC" acl stats ;;
		mapped)     "$ET_CLI" -p "$ET_RPC" mapped-listener ;;
		stats)      "$ET_CLI" -p "$ET_RPC" stats ;;
		*)     echo "用法: $0 info {peer|route|node|conn|stun|peercenter|vpnportal|proxy|acl|mapped|stats}" ; return 1 ;;
	esac
}

# 供 et_bininfo 用：打一行「标签: 路径（大小）」。文件不在就报「不存在」。
# ★ 用 du -h 而不是 ls -lh：du 的输出只有一列、也不受 TTY 影响。
#   （本仓库的 ls 开了 FEATURE_LS_COLOR，管道下虽不染色，但少一个变量少一个坑。）
et_bin_line() {
	if [ -f "$2" ]; then
		_bi_sz=$(du -h "$2" 2>/dev/null | awk '{print $1}')
		echo "  $1: $2（${_bi_sz:-?}）"
	else
		echo "  $1: $2（不存在）"
	fi
	return 0
}

# 供界面「二进制详情」按钮调用：把二进制的【环境事实】打成多行。
#
# ★ 与 easytier_state 刻意分工：state 给【单行结论】并做 sha256 校验
#   （设备上 1~3 秒）；bininfo 只读路径 / 大小 / 分区剩余空间，不哈希、秒回。
#   两者不重叠，免得同一个哈希被算两遍。
# ★ 与 et_info 的其它子命令不同，这里【不检查 cli 是否存在】——
#   二进制缺失时恰恰最需要看这个。所以它挂在顶层子命令上，
#   不放在 et_info 那个 `[ -x "$ET_CLI" ]` 前置检查之后。
# ★ 只读本地文件与 df，不碰 RPC、不碰隧道。
et_bininfo() {
	et_resolve_bins

	_bi_src="下载到 $ET_DIR"
	if [ "$ET_CORE" = "$ET_SYS_CORE" ]; then
		_bi_src="固件内置"
	elif [ ! -f "$ET_CORE" ] && [ ! -f "$ET_CLI" ]; then
		# 两个都不在时【不能】报「下载到」—— 那会让人以为已经下好了。
		_bi_src="未就绪（两个二进制都不在）"
	fi

	echo "easytier 二进制信息"
	echo "  来源      : $_bi_src"
	et_bin_line "核心程序  " "$ET_CORE"
	et_bin_line "命令行工具" "$ET_CLI"

	# ${ET_CORE%/*} 是纯参数展开，不含井号 ⇒ 不触发 lizard 的 shell 盲区。
	_bi_dir="${ET_CORE%/*}"
	if [ -d "$_bi_dir" ]; then
		# df -h 第 2 行是数据行：$2=Size $4=Available（见 df.c 的表头）。
		_bi_space=$(df -h "$_bi_dir" 2>/dev/null | awk 'NR==2{print "剩余 "$4" / 共 "$2}')
		echo "  所在分区  : $_bi_dir（${_bi_space:-?}）"
	fi
	return 0
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
	link)
		# 手动触发一次通断检测（排障用，只读探测、不重启任何东西）。
		# ★ 把周期置 0 绕过时间闸门 —— 否则刚跑过一轮的话这里什么都不做，
		#   看起来像「命令没生效」，排障时最容易误判。
		et_load_cfg
		ET_CHKTIME=0
		if [ "$ET_CHKEN" != "1" ]; then
			echo "通断检测未启用（easytier_check_enable=$ET_CHKEN）"
		elif et_check_link; then
			echo "通断检测：正常"
		else
			echo "通断检测：$ET_CHKIP 全部不可达，判定不通"
		fi
		;;
	info)
		et_info "$@"
		;;
	log)
		# 只读命令：拉日志尾部。行数由 et_log_view 自己白名单。
		et_log_view "$@"
		;;
	logclear)
		# 清空日志（只清文件，不动隧道）。
		et_log_clear
		;;
	bininfo)
		# 只读命令：二进制路径 / 来源 / 大小 / 分区剩余空间。不哈希、不碰隧道。
		et_bininfo
		;;
	*)
echo "用法: $0 {start|stop|restart|firewall|dl|state|C|info|link|log|logclear|bininfo}"
		;;
esac
