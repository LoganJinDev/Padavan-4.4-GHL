#!/bin/sh
#
# urltest.sh —— 真实 URL 测节点延迟
#
# 与 ping.sh 的区别：ping.sh 量的是「到节点服务器的 ICMP/TCP 可达性」，
# 本脚本量的是「经这个节点自己的 socks 出口，跑一次完整 HTTP 请求要多久」——
# 后者才是用户真正感知到的「打开网页快不快」，也是 OpenWrt passwall2 里
# ping / URL 测试两套方案并存的原因。
#
# 调用方：httpd/src/web_ex.c 的 applydb_store()
#     doSystem("/etc_ro/ss/urltest.sh %s", dbvar)
#   dbvar 是 POST 的【键】= 裸数字节点号，与 ping 完全同构（见 Shadowsocks.asp
#   的 urltest_dlink()）。
#   ★ 探测 URL 绝不能走 argv：SystemCmd 只有 128 字节（web_ex.c:80 + :3547 的
#     MIN(sizeof-1, ...)），一条 URL 就吃掉大半，会被静默截断。
#     URL 由本脚本自己 dbus get urltest_url。
#
# ★★ 为什么必须【后台脱离】—— 这是硬要求，不是优化，也不是可以照抄现成代码的地方
#
#   本仓库既有的两个长任务（ping.sh / allping.sh）都是【同步】的：httpd fork 后
#   一直等到脚本退出才回 HTTP 响应（allping.sh:5-6 的注释明写了这一点），面板靠
#   「AJAX 请求一直挂着 + success 回调里停表」表现进度。
#
#   这条路对 URL 测速走不通：一次探测要经代理跑完整的 DNS+TCP+TLS+HTTP，单节点
#   2~10 秒，41 个节点即使 4 路并发也要 1~2 分钟。而 httpd 是【单进程 select 循环】、
#   doSystem 又是同步阻塞的 ⇒ 不脱离的话这段时间里一个 HTTP 请求都进不来，连前端
#   要发的 /dbconf?p=urltest 轮询都被堵住 —— 用户看到的就是界面卡死。
#
#   所以：真正的测试循环整体放进子 shell 并脱离，本脚本立刻 exit 0。
#   三个 fd 都要重定向，</dev/null 不能省：后台子进程默认继承 httpd 已 accept 的
#   socket fd，不重定向则客户端等不到 EOF、面板一直转圈（同 allping.sh:34 给子进程
#   加 >/dev/null 2>&1 < /dev/null 的理由）。
#
#   连带后果：前端的 success 回调会在【毫秒级】触发，所以前端绝不能用 ctime()/dtime()
#   那对客户端计时器（它们会在测试刚开跑时就打出「脚本运行完成!」），改为轮询
#   dbus 的 urltest_run / urltest_status。
#
# 结果写回：每个节点的 JSON 里加两个字段
#     urltest      成功 = 数字毫秒；失败 = 字符串 "failed"（与 ping 字段同形）
#     urltest_ts   本次测量的 unix 时间戳，用来区分「这轮的结果」和「上轮的残留」
#   订阅更新不会抹掉它们：dlink.lua:666 的 `if not vv._ignore` 会跳过已有节点。
#
# 状态键（供前端轮询）：
#     urltest_run     1 = 正在测，0 = 空闲
#     urltest_status  人类可读的单行结果
#     urltest_url     探测用的 URL（前端下拉框写，本脚本读；空则用内置默认）
#   ★ 必须用 urltest_ 前缀，不能用 ss 前缀：/dbconf?p=X 是前缀匹配，任何以 ss 开头的
#     键都会落进 window.db_ss，而面板对 db_ss 里每个键【无保护地】JSON.parse
#     ⇒ 节点下拉框多一个垃圾项、主表多一行垃圾。
#
# 用法：urltest.sh <节点号> [节点号 ...]
#

PORT_BASE=1089
PORT_SCAN=200
SLOTS=4
PIDFILE=/tmp/urltest.pids
LOCKFILE=/tmp/urltest.lock
# 锁的最长寿命（秒）。超过就当上一轮已经死透，接管。
LOCK_STALE=600
UT_TMP=/tmp/urltest
DEFAULT_URL="http://www.gstatic.com/generate_204"
SS_MAIN=/usr/bin/shadowsocks.sh

# dbus 的值会被 web_ex.c 的 db_print 原样塞进 JS 单引号串（o["k"]='v';），
# 值里一个单引号就能破页。与 xrayctl.sh 的 sanitize() 同一处理。
sanitize() {
	tr '\n\r\t' '   ' | tr -d "'\\\\" | tr -s ' '
}

dbus_set_status() {
	dbus set "urltest_status=$(printf '%s' "$1" | sanitize)"
}

# ---------------------------------------------------------------------------
# 端口探测
# ---------------------------------------------------------------------------

# 把当前所有 LISTEN 的本地端口读进 LISTEN_PORTS（空格分隔的十六进制端口串）。
#
# 读 /proc/net/tcp 而不是 netstat：内核格式固定（$2 = 十六进制IP:十六进制端口，
# $4 = 0A 表示 LISTEN），不受 busybox netstat 的输出格式与列宽影响。
#
# 先整体读一次、再在 shell 里比对，而不是每个端口起一次 awk：find_free_ports 要
# 连扫 200 个端口，每个都起一次 awk 的话光解释器启动就是秒级开销（MT7621 上
# busybox awk 的成本实测教训）。
#
# ★ 必须用 printf 而不是 print：awk 的 print 是换行分隔，而 port_listening 用
#   「空格分隔」的 case 模式匹配（见下），换行≠空格 ⇒ 只要设备上有两个以上监听
#   端口（真机上永远有 5 个：dnsmasq/sshd/httpd/…），匹配就永远失败。后果不是
#   「偶尔测不出」，而是 port_listening 恒假：run_one 的等待循环跑满 10 轮上界、
#   probe_once 一次都不执行（实测 ps 全程看不到 curl、nat 计数器零增量），
#   最终每个节点都记 failed；同时 find_free_ports 会把 200 个端口全判为空闲，
#   端口占用检测一起失效。台架当时只有单个监听端口才漏过这个缺陷。
refresh_listen_ports() {
	LISTEN_PORTS=$(awk '$4 == "0A" { split($2, a, ":"); printf "%s ", a[2] }' /proc/net/tcp 2>/dev/null)
}

port_listening() {
	_h=$(printf '%04X' "$1" 2>/dev/null)
	[ -n "$_h" ] || return 1
	case " $LISTEN_PORTS " in
	*" $_h "*) return 0 ;;
	esac
	return 1
}

# 从 PORT_BASE 起扫出 SLOTS 个空闲端口，空格分隔打印。扫不到则返回 1。
find_free_ports() {
	refresh_listen_ports
	_n=0
	_p=$PORT_BASE
	_out=""
	while [ "$_n" -lt "$SLOTS" ] && [ "$_p" -lt "$((PORT_BASE + PORT_SCAN))" ]; do
		if ! port_listening "$_p"; then
			_out="$_out $_p"
			_n=$((_n + 1))
		fi
		_p=$((_p + 1))
	done
	[ "$_n" -eq "$SLOTS" ] || return 1
	printf '%s' "$_out"
}

# 取端口清单里第 $1 个（从 1 数起）
port_at() {
	_i=1
	for _x in $PORTS; do
		if [ "$_i" = "$1" ]; then
			printf '%s' "$_x"
			return 0
		fi
		_i=$((_i + 1))
	done
	return 1
}

# ---------------------------------------------------------------------------
# 探测 URL
# ---------------------------------------------------------------------------

# 读 dbus 的 urltest_url，为空或形态不合法则回落内置默认。结果放 PROBE_URL。
#
# ★ 形态守卫：这个值来自网页输入，最终会进 curl 的参数列表。加了引号也仍要挡空白 ——
#   挡的是「参数内容里混进分隔用的空白」这类形态问题，与「订阅内容 = 未受信输入」
#   同一教训：形态守卫必须自己写，不能指望下游。
read_probe_url() {
	_u=$(dbus get urltest_url 2>/dev/null)
	case "$_u" in
	http://* | https://*) ;;
	*) _u="" ;;
	esac
	if [ -z "$_u" ] || printf '%s' "$_u" | grep -q '[[:space:]]'; then
		_u="$DEFAULT_URL"
	fi
	PROBE_URL="$_u"
}

# ---------------------------------------------------------------------------
# 起 / 收 临时 socks 实例
# ---------------------------------------------------------------------------

# 生成临时配置并起一个只监听 127.0.0.1:<port> 的本地 socks 实例。
# 成功时把 PID 放进 CHILD_PID。
#
# ★ 不用 shadowsocks.sh 的 gen_config_file()：它按 nvram 的 d_type / ud_type /
#   s5_type 分派，测的是「主服务的类型」而不是「这个节点的类型」—— 拿它去测别的
#   节点会生成错误的配置。
# ★ 不用 run_bin()：它把命令包进 ( ... ) & 且带 cgroup 注入 ⇒ $! 是子 shell 的 PID，
#   真正的二进制是孙进程，kill $! 只会杀掉子 shell，实例变孤儿继续占着端口。
#   这里直接 & 起二进制，$! 就是它自己。
#
# 各生成器的端口参数位（逐个读过源码，这是最容易写错的点）：
#   genssconfig.lua      <n> <port>                → arg[2]
#   genssrconfig.lua     <n> <port>                → arg[2]
#   gentrojanconfig.lua  <n> client <port>         → arg[3]
#   genxrayconfig.lua    <n> tcp <local> <socks>   → arg[4]
#     （genxrayconfig.lua:36-38 的 arg[2]=proto / arg[3]=local_port / arg[4]=socks_port，
#       且 :387 要求 proto=="tcp" 且 socks_port~="0" 才会加 socks 入站
#       ⇒ 测 socks 出口必须传 `tcp 0 <port>`，把 local_port 让给 socks 用）
#
# 产物要过 sed -i 's/\\//g'：与 shadowsocks.sh 的 gen_config_file() 一致。
# cjson 的转义表（lua_cjson.c:161）把 / 编成 "\/"，四个生成器的输出里都带反斜杠转义，
# 生产路径一律剥掉。
#
# ★ 只在这里剥【不够】：下面 fixbind 会重新编码，而 cjson.encode() 又会把 / 写回 "\/"
#   ⇒ 归一化必须由【最后一个写文件的人】负责。fixbind 自己也做了一遍同样的剥离，
#   这里保留是为了与 gen_config_file() 形态一致，不是为了它单独生效。
#
# 为什么非要对齐生产形态、而不是"反正 JSON 合法就行"：生产剥反斜杠这条规则说明有人
# 认定过目标程序不认带反斜杠的配置，但本机没有 ARM 的目标二进制可跑，这假设无法验证。
# 让两条路径产出同一形态，假设就整个消失了。
start_proxy() {
	_n="$1"
	_port="$2"
	_cfg="$UT_TMP/$_n.json"
	_type=$(lua /etc_ro/ss/urltest_node.lua "$_n" 2>/dev/null)

	# 分派只负责「生成配置 + 定下二进制与配置参数名」，启动统一放在 case 之后：
	# 四个分支原本各自重复一遍 sed + 启动，绑定地址加固就得跟着抄四遍 ——
	# 抄漏一个分支，那一路就在局域网上留个开放代理，而且不会有任何报错。
	_bin=""
	_flag=""
	case "$_type" in
	ss)
		lua /etc_ro/ss/genssconfig.lua "$_n" "$_port" >"$_cfg" 2>/dev/null || return 1
		_bin=$(find_bin ss-local)
		_flag="-c"
		;;
	ssr)
		lua /etc_ro/ss/genssrconfig.lua "$_n" "$_port" >"$_cfg" 2>/dev/null || return 1
		_bin=$(find_bin ssr-local)
		_flag="-c"
		;;
	trojan)
		lua /etc_ro/ss/gentrojanconfig.lua "$_n" client "$_port" >"$_cfg" 2>/dev/null || return 1
		_bin=$(find_bin trojan)
		_flag="--config"
		;;
	v2ray | xray)
		lua /etc_ro/ss/genxrayconfig.lua "$_n" tcp 0 "$_port" >"$_cfg" 2>/dev/null || return 1
		# ★ 必须走 find_bin()：本机 xray 在、v2ray 不在（GHL.config 里 v2ray = n），
		#   硬编码 /usr/bin/v2ray 会让所有 vmess 节点报失败。
		#   find_bin 内部对 v2ray|xray 有「缺哪个就用另一个」的回退。
		_bin=$(find_bin "$_type")
		_flag="-config"
		;;
	*)
		return 1
		;;
	esac

	[ -x "$_bin" ] || return 1

	# 与 shadowsocks.sh 的 gen_config_file() 一致：产物里的反斜杠全部剥掉。
	# ★ 真正兜底的是下面 fixbind（它会重编码、必须自己再剥一遍），这里是为了形态一致。
	sed -i 's/\\//g' "$_cfg"

	# ★ 把监听地址从 0.0.0.0 改成 127.0.0.1。
	#   生成器写的都是 0.0.0.0（xray 的 socks 入站甚至不写 listen，默认同样是
	#   0.0.0.0）⇒ 不改的话每次测速都在局域网上多出 4 个开放代理，其中 xray 那路
	#   是 auth="noauth" —— 同一局域网里任何人都能拿用户自己买的节点上网。
	#   改不动就当失败（脚本自己判「一个字段都没改到」也返回非 0），绝不放行 0.0.0.0。
	lua /etc_ro/ss/urltest_fixbind.lua "$_cfg" >/dev/null 2>&1 || return 1

	# 直接 & 起二进制，$! 就是它自己 —— 不用 -f 让它 daemonize（那样 $! 是 fork 后
	# 立刻退出的父进程，kill 它杀不到真正的实例）。
	"$_bin" "$_flag" "$_cfg" >/dev/null 2>&1 &
	CHILD_PID=$!
	# 记进 PID 文件：脚本被 SIGKILL 时 trap 来不及跑，子实例会留在后台占着端口，
	# 下一轮开头按这个文件兜底清理。
	echo "$CHILD_PID" >>"$PIDFILE" 2>/dev/null
	return 0
}

# 收实例：先 SIGTERM，再等端口关闭（最多 5 秒），最后 SIGKILL 兜底。
#
# ★ 轮询用「端口还听着吗」而不是 kill -0：进程退出后到 wait 回收前是僵尸态，
#   kill -0 对僵尸仍返回成功 ⇒ 用 kill -0 轮询会每次都白等到上界。
# ★ 只杀自己 $! 记下的 PID —— 绝不 killall：shadowsocks.sh:576 的 kill_process()
#   按进程名杀，会连用户正在用的主代理一起杀掉。
stop_proxy() {
	_p="$1"
	_port="$2"
	[ -n "$_p" ] || return 0
	kill "$_p" 2>/dev/null
	_i=0
	while [ "$_i" -lt 5 ]; do
		refresh_listen_ports
		port_listening "$_port" || break
		sleep 1
		_i=$((_i + 1))
	done
	kill -9 "$_p" 2>/dev/null
	wait "$_p" 2>/dev/null
	return 0
}

# ---------------------------------------------------------------------------
# 单节点探测
# ---------------------------------------------------------------------------

# 探测一次。成功时把毫秒数放进 PROBE_MS 并返回 0，失败返回 1。
#
# 判据用 %{http_code} 非 000，不能只看耗时 —— 沿用节点探活的教训：time_connect
# 单独用会假活（TCP 能连上但拿不到 HTTP 响应）。
# 任何非 000 都算成功，包括 404：404 说明请求确实经代理到达了目标，那就是一次
# 有效的延迟测量。socks5-hostname 让 DNS 也在代理侧解析，测的是节点自己的解析能力。
probe_once() {
	_port="$1"
	_r=$(curl -s -o /dev/null -w '%{http_code}:%{time_total}' \
		--socks5-hostname "127.0.0.1:$_port" \
		--connect-timeout 3 --max-time 8 \
		"$PROBE_URL" 2>/dev/null)
	_code=${_r%%:*}
	_sec=${_r##*:}
	case "$_code" in
	000 | "") PROBE_MS=""; return 1 ;;
	esac
	PROBE_MS=$(awk -v s="$_sec" 'BEGIN { printf "%d", s * 1000 }')
	[ -n "$PROBE_MS" ] || PROBE_MS=0
	return 0
}

# 测一个节点：起实例 → 等端口 LISTEN → 探测 → 收实例 → 写回结果 → 记成败。
#
# 等端口用轮询而不是盲 sleep：条件一满足就立刻继续（ss-local 通常不到 1 秒就绪），
# 条件不满足也有上界（xray 加载配置 + 解析域名可能慢）。盲 sleep 要么白等要么不够。
run_one() {
	_n="$1"
	_port="$2"
	_ms=""

	if start_proxy "$_n" "$_port"; then
		_w=0
		while [ "$_w" -lt 10 ]; do
			refresh_listen_ports
			port_listening "$_port" && break
			# 实例已经死了就别再等了（配置错 / 端口被占 / 二进制缺失）
			kill -0 "$CHILD_PID" 2>/dev/null || break
			sleep 1
			_w=$((_w + 1))
		done
		refresh_listen_ports
		if port_listening "$_port"; then
			probe_once "$_port" && _ms="$PROBE_MS"
		fi
		stop_proxy "$CHILD_PID" "$_port"
	fi

	# 空串传给写回脚本会被判成 "failed"，与探测失败同一条路径
	lua /etc_ro/ss/urltest_write.lua "$_n" "$_ms" >/dev/null 2>&1
	rm -f "$UT_TMP/$_n.json"

	if [ -n "$_ms" ]; then
		echo ok >>"$UT_TMP/res"
	else
		echo fail >>"$UT_TMP/res"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 并发闸门
# ---------------------------------------------------------------------------

# 取锁成功返回 0，已被别人占着返回 1。
#
# 为什么必须有：两轮测试共用 $PIDFILE 与 $UT_TMP/res。后一轮开头的 reap_stale
# 只看「PID 文件里有没有号」，不问号是谁的 ⇒ 它会把前一轮【正在跑】的实例全杀掉，
# 而前一轮的 run_one 还在等端口、接着把「失败」写进自己的 res ⇒ 用户看到的是一份
# 一半被杀出来的假结果。前端的按钮 disable 只能挡住「同一个页面」的重复点击，
# 刷新页面按钮就重新可用了，所以必须在脚本里兜。
#
# ★ 为什么是时间戳锁而不是 PID 锁：真正的测试循环跑在 ( ) 子 shell 里，而 busybox
#   ash 的 $$ 在子 shell 里仍然是【父进程】的 PID —— 拿不到 worker 自己的号。
#   记错人的 PID 锁会永远解不开（记的那个人早退出了）。
# ★ 一切异常一律【放行】：时间取不到、锁文件内容是垃圾、算出来的年龄为负
#   （时钟往回跳），都当过期锁接管。宁可偶发一次并发，也不能让一次异常把
#   「URL测试」永久锁死 —— 那种故障用户除了重启路由器没有任何自救手段。
lock_acquire() {
	_now=$(date +%s 2>/dev/null)
	case "$_now" in
	"" | *[!0-9]*) return 0 ;;
	esac
	if [ -f "$LOCKFILE" ]; then
		_old=$(cat "$LOCKFILE" 2>/dev/null)
		case "$_old" in
		"" | *[!0-9]*) ;;
		*)
			_age=$((_now - _old))
			if [ "$_age" -ge 0 ] && [ "$_age" -lt "$LOCK_STALE" ]; then
				return 1
			fi
			;;
		esac
	fi
	printf '%s' "$_now" >"$LOCKFILE" 2>/dev/null
	return 0
}

lock_release() {
	rm -f "$LOCKFILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 残留清理
# ---------------------------------------------------------------------------

# 清理上一轮残留的实例。脚本被 SIGKILL 时 trap 来不及跑，子实例会留在后台。
# 只杀 PID 文件里记下的那些 —— 绝不 killall（会连用户的主代理一起杀）。
reap_stale() {
	[ -f "$PIDFILE" ] || return 0
	for _p in $(cat "$PIDFILE" 2>/dev/null); do
		case "$_p" in
		"" | *[!0-9]*) continue ;;
		esac
		kill -9 "$_p" 2>/dev/null
	done
	rm -f "$PIDFILE"
	return 0
}

ut_cleanup() {
	# 本轮起过的实例 PID 全在 $PIDFILE 里（start_proxy 每起一个追加一行），
	# 退出时统一收掉，只杀自己记下的 PID。
	if [ -f "$PIDFILE" ]; then
		for _p in $(cat "$PIDFILE" 2>/dev/null); do
			case "$_p" in
			"" | *[!0-9]*) continue ;;
			esac
			kill -9 "$_p" 2>/dev/null
		done
		rm -f "$PIDFILE"
	fi
	rm -rf "$UT_TMP"
	# 锁在【最后】才放：本函数是 worker 的 EXIT trap，跑到这里时主循环已经 wait
	# 过、所有子实例都已收掉、最终状态也已落库 ⇒ 此刻放锁，下一轮拿到的就是一个
	# 干净的世界。放早了则下一轮可能与本轮的收尾动作交叠。
	lock_release
}

# ---------------------------------------------------------------------------
# 主循环（跑在已脱离的子 shell 里）
# ---------------------------------------------------------------------------

urltest_worker() {
	# ★ 先清空位置参数再 source：shadowsocks.sh 尾部有 `case $1 in` 派发，
	#   不清空的话节点号会被当成动作名送进去。
	#   只需要它的 find_bin()（v2ray→xray 的回退）与 log()，不需要它的全局状态。
	set --
	. "$SS_MAIN" >/dev/null 2>&1 </dev/null
	# 万一 source 失败（文件被裁过 / 路径变了），log 退化成只写 syslog，
	# 而不是让每个调用点都报 command not found。
	#
	# ★ 这里必须用 `type`，不能用 `command -v`：
	#   本设备的 busybox 没编 ENABLE_ASH_CMDCMD ⇒ `command` 根本不是内建，
	#   `command -v X` 退化成「找一个叫 command 的外部程序」并恒失败
	#   （真机实测：`command -v ls` → rc=127，stderr `sh: command: not found`，
	#    对存在与不存在的命令结果完全一样）。
	#   用 `command -v` 会让这个守卫【永远触发】，无条件把 source 进来的好 log
	#   覆盖成只写 syslog 的桩 ⇒ worker 日志全丢、logread 为空，而功能看不出异常。
	type log >/dev/null 2>&1 || log() { logger -t shadowsocksr "$@"; }

	trap 'ut_cleanup' EXIT INT TERM

	read_probe_url
	reap_stale
	rm -rf "$UT_TMP"
	mkdir -p "$UT_TMP"
	: >"$UT_TMP/res"

	PORTS=$(find_free_ports)
	if [ -z "$PORTS" ]; then
		dbus_set_status "失败：找不到空闲端口"
		dbus set urltest_run=0
		return 0
	fi

	_total=0
	for _n in $NODES; do
		_total=$((_total + 1))
	done
	log "开始 URL 测速，共 $_total 个节点，探测地址 $PROBE_URL"

	# 分批：每 SLOTS 个节点一批，批内并发、批间 wait。
	# 槽位由主循环静态分配（第 i 个节点用第 (i-1)%SLOTS+1 个端口），不用抢锁 ——
	# 批间 wait 天然是屏障，上一批的实例一定已经收掉，同一个端口可以复用。
	_i=0
	for _n in $NODES; do
		_i=$((_i + 1))
		run_one "$_n" "$(port_at "$(((_i - 1) % SLOTS + 1))")" &
		if [ $((_i % SLOTS)) -eq 0 ]; then
			wait
		fi
	done
	wait

	_ok=$(grep -c '^ok$' "$UT_TMP/res" 2>/dev/null)
	_fail=$(grep -c '^fail$' "$UT_TMP/res" 2>/dev/null)
	[ -n "$_ok" ] || _ok=0
	[ -n "$_fail" ] || _fail=0

	# ★ 先落最终状态，再清运行位 —— 顺序不能反，否则页面可能在状态还是旧值时就看到
	#   「已结束」（与 xrayctl.sh:70-77 的 begin_run/end_run 同一条）。
	dbus_set_status "完成：$_ok 成功 / $_fail 失败"
	dbus set urltest_run=0
	log "URL 测速完成：$_ok 成功 / $_fail 失败"
}

# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

NODES="$*"

# 节点号会被拼进 dbus 变量名与生成器的 argv，必须是纯数字。
# 与 ping.sh / ssping.lua 的入参守卫同一理由：拼进命令的变量不校验，
# 等于把命令拼接权交出去。
case "$NODES" in
"") exit 0 ;;
esac
for _n in $NODES; do
	case "$_n" in
	*[!0-9]*) exit 0 ;;
	esac
done

# ★ 拿不到锁就【什么都不改】直接退出 —— 尤其不能置 urltest_run=1：
#   置了的话前端会一直转圈，而实际上什么都没跑，用户还会把上一轮的结果
#   当成这一轮的。只留一句状态说明，不动运行位。
if ! lock_acquire; then
	dbus_set_status "已有测速在跑，请稍后再试"
	exit 0
fi

# 运行位在脱离【之前】置起：否则前端可能先轮询到 run=0、再看到 status 变化，
# 表现为「点了按钮但进度条闪一下就没了」。
dbus set urltest_run=1
dbus_set_status "测试中..."

# ★ 整体脱离，立刻返回。详见文件头「为什么必须后台脱离」。
( urltest_worker ) >/dev/null 2>&1 </dev/null &
exit 0
