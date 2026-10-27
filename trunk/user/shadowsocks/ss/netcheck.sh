#!/bin/sh
#
# netcheck.sh —— 路由器侧的网络出口检测（国内IP / 国外IP / 站点延迟）
#
# 调用方（两处，都在 web_ex.c）：
#   1) applydb_store()      —— 前端点「检测」时的 POST 派发
#   2) netcheck_ip_hook()   —— 页面渲染时自动跑一次 IP 检测
# 用法：netcheck.sh ip   |   netcheck.sh lat
#
# ★ 参数只有两种取值，用 case 白名单校验。不校验的话任何字符串都能成为 $MODE
#   的一部分并拼进 dbus 键名。
#
# ★★ 为什么必须【后台脱离】—— 这是硬要求，不是优化。
#   httpd 是单进程 select 循环，doSystem 是同步 system()，会一直等到 shell 退出。
#   不脱离的话这段时间里一个 HTTP 请求都进不来 —— 连前端要发的
#   /dbconf?p=netchk 轮询都被堵住，用户看到的就是界面卡死。
#   三个 fd 都要重定向：</dev/null 不能省，否则后台子进程可能抢 httpd 的
#   标准输入（那是 socket），表现为「检测跑完之后页面再也点不动」。
#
# ★ 前端的 success 回调会在【毫秒级】触发（脚本立刻 return），所以前端绝不能用
#   ctime()/dtime() 计时，必须轮询 dbus 的 netchk_ip_run / netchk_lat_run。
#
# ★ 键名一律 netchk_ 前缀，绝不能用 ss 前缀：
#   /dbconf?p=X 是【前缀匹配】，任何 ss 开头的键都会落进 window.db_ss，
#   而 Shadowsocks.asp 对 db_ss 每个键无保护地 JSON.parse ⇒ 节点下拉框多一个
#   垃圾项、主表多一行垃圾。netchk_ 不属于任何既有前缀。
#
# ★ 本脚本写出的值会被 web_ex.c 的 db_print 原样塞进 JS 单引号串（o["k"]='v';），
#   值里一个单引号就能破页。所以三处取值都有形态守卫：
#     - IP 值只允许 [0-9.] 且长度 ≤15          （见 netchk_get_ip）
#     - 延迟值只可能是 awk 打印的 "N.NN" / failed / nourl
#     - 自定义 URL 走【白名单】字符集 + 必须 http(s):// 开头
#   这不是「加个引号」能替代的：对无引号裸拼接点，一个空格就能另起一个选项。
#
# ★ 探测 URL 绝不能走 argv：SystemCmd 只有 128 字节。
#   本脚本的 URL 全部硬编码在脚本里，只有自定义站点从 dbus 读。
#
# ★ 不用 set -e：中间任何一步失败就无声退出，日志一个字都不打印。
#   （见 gfwlist/chnroute 那次的教训：失败分支「存在」≠「可达」）

# ── 常量 ────────────────────────────────────────────────────────────────
IP_MAXTIME=5			# 单个 IP 探测端点的最长耗时（秒）
LAT_MAXTIME=5			# 单个站点延迟探测的最长耗时（秒）
LOCK_STALE=120			# 锁的最长寿命：超过就当上一轮已死透，接管
NETCHK_LOG=/tmp/netchk.log

# ── 日志（仅用于真机验收取证，不参与任何逻辑判断）─────────────────────
netchk_log() {
	printf '%s netcheck[%s] %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$MODE" "$*" >> "$NETCHK_LOG" 2>/dev/null
}

# ── 值净化：dbus 的值会被 db_print 原样塞进 JS 单引号串，一个单引号就能破页 ──
# 与 urltest.sh / xrayctl.sh 的 sanitize() 同一处理。
sanitize() {
	tr '\n\r\t' '   ' | tr -d "'\\\\" | tr -s ' '
}

# ── 写 dbus ────────────────────────────────────────────────────────────
# ★ 必须 "k=v" 形式：`dbus set k v` 会被静默当成 `unset k`（同 nvram 的坑）。
netchk_dbus_set() {
	dbus set "$1=$(printf '%s' "$2" | sanitize)"
}

# ── 锁 ─────────────────────────────────────────────────────────────────
# 只用时间戳判过期，【不】依赖 trap 清理：`( ) &` 起的子壳在 ash 里会重置
# trap，谁清理谁不清理不确定。清理动作放在 worker 末尾显式做（见 netchk_worker）。
netchk_lock() {
	_lf="$1"
	if [ -f "$_lf" ]; then
		_now=$(date +%s 2>/dev/null)
		_old=$(cat "$_lf" 2>/dev/null)
		case "$_old" in ''|*[!0-9]*) _old=0 ;; esac
		case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
		if [ "$_now" -gt 0 ] && [ "$_old" -gt 0 ] && [ $((_now - _old)) -lt "$LOCK_STALE" ]; then
			return 1
		fi
		netchk_log "接管过期锁 $_lf (age=$((_now - _old))s)"
	fi
	date +%s > "$_lf" 2>/dev/null
	return 0
}

# ── IPv4 形态守卫 ──────────────────────────────────────────────────────
# 只允许数字与点，且长度 ≤15，且至少三个点。
# ★ 这不是「防注入的保险」，而是唯一的安全边界 —— 值会经 dbus 落进
#   /etc/storage/db/0.udbData，再被 db_print 塞进 JS 单引号串。
#   数字+点+长度≤15 的集合里没有任何可破页字符。
#   完整的八位组范围校验故意不做：边际价值≈0，安全性质由字符集承载。
netchk_valid_ip() {
	case "$1" in
		'') return 1 ;;
		*[!0-9.]*) return 1 ;;
	esac
	[ "${#1}" -le 15 ] || return 1
	case "$1" in
		*.*.*.*) return 0 ;;
	esac
	return 1
}

# ── 从端点取 IP ────────────────────────────────────────────────────────
# $1=URL  $2=解析方式：raw=整段就是 IP；trace=从 key=value 行里取 ip=
# 成功 ⇒ stdout 打印 IPv4 并 return 0；失败 ⇒ return 1
netchk_get_ip() {
	_raw=$(curl -s --connect-timeout 3 -m "$IP_MAXTIME" -- "$1" 2>/dev/null)
	[ -n "$_raw" ] || return 1
	if [ "$2" = "trace" ]; then
		_val=$(printf '%s\n' "$_raw" | grep '^ip=' | head -n 1 | cut -d= -f2 | tr -d '\r\t ')
	else
		_val=$(printf '%s\n' "$_raw" | head -n 1 | tr -d '\r\t ')
	fi
	netchk_valid_ip "$_val" || return 1
	printf '%s' "$_val"
	return 0
}

# 依次试一个端点；成功就把 IP 打到 stdout，失败返回 1（并记日志）
netchk_try_one() {
	_v=$(netchk_get_ip "$2" "$1") || { netchk_log "探测失败[$1] $2"; return 1; }
	printf '%s' "$_v"
	return 0
}

# ── 国内出口 ───────────────────────────────────────────────────────────
# 路由器自己 curl 国内主机 ⇒ 命中 ss-rules 的 chnroute RETURN ⇒ 直连
# ⇒ 拿到的是【直连出口 IP】。
# ★ http://ip.3322.org 实测 rc=000 已死，不要用。
netchk_ip_domestic() {
	netchk_try_one raw "http://ip.3322.net" && return 0
	netchk_try_one raw "http://members.3322.org/dyndns/getip" && return 0
	return 1
}

# ── 国外出口 ───────────────────────────────────────────────────────────
# 路由器自己 curl 国外主机 ⇒ 被 OUTPUT 链 REDIRECT 进透明代理 ⇒ 拿到的是
# 【代理出口 IP】。第三个端点用 IP 字面量，完全绕开 DNS 污染。
netchk_ip_foreign() {
	netchk_try_one raw   "https://ifconfig.me/ip" && return 0
	netchk_try_one raw   "https://api.ipify.org" && return 0
	netchk_try_one trace "https://1.1.1.1/cdn-cgi/trace" && return 0
	return 1
}

# ── 站点延迟 ───────────────────────────────────────────────────────────
# $1=URL；成功 ⇒ stdout 打印 "123.45"（毫秒，两位小数）；失败 ⇒ return 1
netchk_lat_one() {
	_r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --connect-timeout 3 -m "$LAT_MAXTIME" -- "$1" 2>/dev/null)
	_code=$(printf '%s' "$_r" | cut -d' ' -f1)
	_tot=$(printf '%s' "$_r" | cut -d' ' -f2)
	# ★ 判据是 %{http_code} 非 000：000 表示连 TCP 都没建起来（或 TLS 失败），
	#   此时 time_total 仍有值，单看它会把「连不上」当成「很快」。
	case "$_code" in ''|000) return 1 ;; esac
	case "$_tot" in ''|0|0.000000) return 1 ;; esac
	printf '%s' "$_tot" | awk '{printf "%.2f", $1 * 1000}'
	return 0
}

netchk_lat_store() {
	# $1=站点键后缀（硬编码常量）  $2=URL
	_t=$(netchk_lat_one "$2") || _t="failed"
	netchk_dbus_set "netchk_lat_$1" "$_t"
	netchk_log "延迟 $1 ($2) = $_t"
}

# 自定义站点 URL 的形态守卫（与前端 urltest_url_save 的白名单同构，且更严）
#   1) 必须 http:// 或 https:// 开头 —— 这一条同时挡住「值以 - 开头」：
#      curl 会把 "-O/etc/x" 当选项，加引号也挡不住（引号只解决 shell 分词，
#      不解决 getopt 的选项解析）。脚本里另外还用了 `curl ... -- "$url"` 兜底。
#   2) 字符集白名单 —— 不含 ' " ` $ \ < > 空格 ; | ( ) , # ! * 等
#
# ★★ 第 2 步必须用【单引号 grep 模式】，不能写成 case 的中括号表达式：
#   同一个字符类写成 `case "$1" in *[!A-Za-z0-9:/?&=._%~+@-]*) ...` 时，
#   模式里的裸 `&` 会被 shell 先当成控制操作符解析 ⇒ 直接语法错、
#   `sh -n` 就红（实测 line 175: syntax error near unexpected token '&'）。
#   单引号包起来后 shell 一个字都不解析，`&` 才真正只是字符类的一员。
netchk_url_ok() {
	case "$1" in
		'') return 1 ;;
	esac
	case "$1" in
		http://*|https://*) : ;;
		*) return 1 ;;
	esac
	printf '%s' "$1" | grep -q '[^A-Za-z0-9:/?&=._%~+@-]' && return 1
	return 0
}

netchk_lat_custom() {
	_cu=$(dbus get netchk_custom_url 2>/dev/null)
	if [ -z "$_cu" ]; then
		netchk_dbus_set netchk_lat_custom "nourl"
		netchk_log "自定义：未设置"
		return 0
	fi
	if ! netchk_url_ok "$_cu"; then
		netchk_log "自定义 URL 形态非法，已清空：$_cu"
		netchk_dbus_set netchk_custom_url ""
		netchk_dbus_set netchk_lat_custom "nourl"
		return 0
	fi
	netchk_lat_store custom "$_cu"
}

# ── 两个 worker ────────────────────────────────────────────────────────
netchk_worker_ip() {
	# 国内 / 国外【并行】：最坏 ≈ max(国内 2×5s, 国外 3×5s) 而不是两者相加。
	# ★ 两个子壳各自写各自的键，互不覆盖；dbus 守护进程本身串行化写入
	#   （urltest.sh 的 SLOTS=4 已经是同样的并发写先例）。
	( _v=$(netchk_ip_domestic); netchk_dbus_set netchk_ip_domestic "${_v:-failed}"; netchk_log "国内 = ${_v:-failed}" ) &
	( _v=$(netchk_ip_foreign);  netchk_dbus_set netchk_ip_foreign  "${_v:-failed}"; netchk_log "国外 = ${_v:-failed}" ) &
	wait
}

netchk_worker_lat() {
	# 四个站点【串行】：并行 curl 会互相抬高 time_total（抢 CPU/带宽），
	# 而这一行的全部意义就是给出可横向比较的延迟数字。
	netchk_lat_store baidu  "http://www.baidu.com"
	netchk_lat_store google "http://www.gstatic.com/generate_204"
	netchk_lat_store github "https://github.com"
	netchk_lat_custom
}

netchk_worker() {
	netchk_log "开始"
	case "$MODE" in
		ip) netchk_worker_ip ;;
		lat) netchk_worker_lat ;;
	esac
	# 显式收尾，不靠 trap（子壳的 trap 语义在 ash 里不确定，见 netchk_lock 注释）
	rm -f "$NETCHK_LOCK"
	dbus set "netchk_${MODE}_run=0"
	netchk_log "结束"
}

# ── 入口 ───────────────────────────────────────────────────────────────
MODE="$1"
case "$MODE" in
	ip|lat) : ;;
	*) exit 2 ;;
esac
NETCHK_LOCK="/tmp/netchk_${MODE}.lock"

if ! netchk_lock "$NETCHK_LOCK"; then
	netchk_log "已有检测在跑，忽略本次"
	exit 0
fi

dbus set "netchk_${MODE}_run=1"
( netchk_worker ) >/dev/null 2>&1 </dev/null &
exit 0
