#!/bin/sh
#
# xrayctl.sh —— 分流/访问控制/Geo查询 三个页面的唯一 shell 入口（短命令网关）
#
# 为什么必须有这个文件：
#   httpd 里 SystemCmd 是 `static char SystemCmd[128]`（web_ex.c:80），赋值处
#   cmd_len = MIN(sizeof(SystemCmd)-1, strlen(cmd_str)) 会把命令静默截断到 127 字节
#   （web_ex.c:3528-3542）。页面因此不能内联长命令，只能调这个短网关：
#       /etc_ro/ss/xrayctl.sh rules update      <- 36 字节，留足余量
#   所有复杂逻辑在这里展开。
#
# 结果怎么回传给页面：
#   不走 /tmp/syscmd.log。sys_script()（web_ex.c:153）在 SystemCmd 为空时会执行
#   `echo -n > /tmp/syscmd.log` 把日志清空，所以 console_response.asp 那条读回链路
#   自己会把内容冲掉，不可靠。改为把结果写进 dbus，页面用 /dbconf?p=xray 读回，
#   与规则列表走同一条通道。
#
# dbus 值约束（与面板规则字段同源）：
#   必须单行、不含单引号、不含反斜杠 —— web_ex.c 的 db_print 把值原样塞进 JS
#   单引号字符串（o["k"]='v';），带这些字符会破页。见 sanitize()。
#
# dbus 键：
#   xray_action_run     1=正在执行 0=空闲
#   xray_action_status  人类可读的单行结果
#
# 用法（页面只会发这几种）：
#   xrayctl.sh rules update [geosite:x geoip:y ...]   更新分类（异步，立即返回）
#   xrayctl.sh rules list                             列出已装分类
#   xrayctl.sh lookup <域名|IP|CIDR>                  查该目标命中哪些分类
#   xrayctl.sh extract <geosite:x|geoip:y|x>          打印某个分类的条目
#   xrayctl.sh restart                                重启 xray（等价面板「应用」）
#

RULES_DIR="/tmp/ss_rules"
UPDATER="/etc_ro/ss/ssrules_update.sh"
RUN_LOG="/tmp/ssrules.run.log"
LOCK_DIR="/tmp/xrayctl.lock"
LOCK_TIMEOUT=900

# ---------------------------------------------------------------------------
# dbus 写入
# ---------------------------------------------------------------------------

# 单行化 + 去掉会破页的字符。
# tr 的字符集：第一段把 换行/回车/制表 换成空格，第二段删掉 单引号 与 反斜杠。
sanitize() {
	tr '\n\r\t' '   ' | tr -d "'\\\\" | tr -s ' '
}

# 写一个 dbus 键。值经过 sanitize 后，用双引号包住传给 dbus：
# shell 不会对展开结果做二次解析，所以值里残留的 $ 或反引号不会被当命令执行。
dbus_set() {
	dbus set "$1=$(printf '%s' "$2" | sanitize)"
}

# 标记「正在执行」并给出进行中的提示
begin_run() {
	dbus set xray_action_run=1
	dbus_set xray_action_status "$1"
}

# 先落最终状态再清运行位 —— 顺序不能反，否则页面可能在状态还是旧值时就看到「已结束」
end_run() {
	dbus_set xray_action_status "$1"
	dbus set xray_action_run=0
}

# ---------------------------------------------------------------------------
# 分类统计（状态文本里用）
# ---------------------------------------------------------------------------

# 输出「N 个分类 / M KB」
summarize() {
	_c=0
	_t=0
	for _f in "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt; do
		[ -f "$_f" ] || continue
		_c=$((_c + 1))
		_t=$((_t + $(wc -c <"$_f")))
	done
	printf '%d 个分类 / %d KB' "$_c" "$((_t / 1024))"
}

# ---------------------------------------------------------------------------
# rules update —— 更新分类小文本（异步）
# ---------------------------------------------------------------------------

# 真正干活的函数，在后台子 shell 里跑，三个流都已被调用方重定向走
do_update() {
	"$UPDATER" "$@" >"$RUN_LOG" 2>&1
	_rc=$?
	_s=$(summarize)
	if [ $_rc -eq 0 ]; then
		end_run "更新完成：$_s"
	else
		end_run "更新失败(退出码 $_rc)：$_s，详见 /tmp/ssrules.log"
	fi
	rm -rf "$LOCK_DIR"
}

# 陈旧锁检查：上次异常退出（断电、被 kill）会留下锁目录，让按钮永久卡在
# 「已在更新中」。用锁目录里的时间戳判断，超过 LOCK_TIMEOUT 秒就当作失效清掉。
cmd_rules_update() {
	if [ -d "$LOCK_DIR" ]; then
		if [ -f "$LOCK_DIR/ts" ]; then
			_now=$(date +%s)
			_st=$(cat "$LOCK_DIR/ts" 2>/dev/null)
			if [ -n "$_st" ] && [ $((_now - _st)) -gt $LOCK_TIMEOUT ]; then
				rm -rf "$LOCK_DIR"
			fi
		fi
	fi

	if [ -d "$LOCK_DIR" ]; then
		end_run "已在更新中，请稍候…"
		return 0
	fi

	mkdir -p "$LOCK_DIR" 2>/dev/null || {
		end_run "无法创建锁目录 $LOCK_DIR"
		return 0
	}
	date +%s >"$LOCK_DIR/ts"

	begin_run "正在更新分类…"
	# 三个流全部重定向并丢给 /dev/null：后台任务不能握着 httpd 的
	# /tmp/syscmd.log 文件描述符不放，否则响应结束后还往已复用的文件里写
	( do_update "$@" ) >/dev/null 2>&1 </dev/null &
}

# ---------------------------------------------------------------------------
# rules list —— 列出已装分类
# ---------------------------------------------------------------------------

cmd_rules_list() {
	if [ ! -d "$RULES_DIR" ]; then
		end_run "分类目录不存在，请先执行「更新分类」"
		return 0
	fi
	_out=""
	_c=0
	_t=0
	for _f in "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt; do
		[ -f "$_f" ] || continue
		_n=$(basename "$_f" .txt)
		_b=$(wc -c <"$_f")
		_c=$((_c + 1))
		_t=$((_t + _b))
		_out="$_out $_n($((_b / 1024))K)"
	done
	if [ $_c -eq 0 ]; then
		end_run "未安装任何分类"
	else
		end_run "已装 $_c 个分类 / $((_t / 1024)) KB：$_out"
	fi
}

# ---------------------------------------------------------------------------
# lookup / extract —— Geo 查询
# ---------------------------------------------------------------------------

# 只允许出现在分类名、域名、IP 里的字符。
# 这个值最终会被拼进 shell 命令（页面侧的 SystemCmd 是裸 shell 执行），
# 所以客户端与这里各校验一遍，这里是最后一道。
valid_target() {
	printf '%s' "$1" | grep -qE '^[A-Za-z0-9._:@!/-]+$'
}

# lookup <域名|IP|CIDR>
cmd_lookup() {
	_t="$1"
	if [ -z "$_t" ]; then
		end_run "请输入域名或 IP"
		return 0
	fi
	if ! valid_target "$_t"; then
		end_run "非法字符：只允许 字母 数字 . _ : @ ! / -"
		return 0
	fi

	_kind="domain"
	if printf '%s' "$_t" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$'; then
		_kind="ip"
	fi

	_res=$(awk -v t="$_t" -v kind="$_kind" '
		function ip2n(s,  a) {
			split(s, a, ".")
			return ((a[1] * 256 + a[2]) * 256 + a[3]) * 256 + a[4]
		}
		# CIDR 归属：把基址和被测地址各自右移到同一个网段粒度上比整数。
		# 不能用 and() —— 那是 gawk 扩展，固件里是 busybox awk。
		# 2^32 以内的整数在双精度里是精确的，所以除法取整不会出错。
		function inm(n, cidr,  p, bits, base, sh) {
			split(cidr, p, "/")
			bits = (p[2] == "" ? 32 : p[2] + 0)
			base = ip2n(p[1])
			sh = 2 ^ (32 - bits)
			return int(base / sh) == int(n / sh)
		}
		function cat(path,  a, n, s) {
			n = split(path, a, "/")
			s = a[n]
			sub(/\.txt$/, "", s)
			if (s ~ /^geosite_/) return "geosite:" substr(s, 9)
			if (s ~ /^geoip_/)   return "geoip:" substr(s, 7)
			return s
		}
		BEGIN { n = ip2n(t) }
		{
			line = $0
			sub(/\r$/, "", line)
			if (line == "" || substr(line, 1, 1) == "#") next
			# 剥属性：先处理 "domain:x:@cn"，再处理 "domain:x @cn"
			while (match(line, /:@[A-Za-z0-9_!-]+$/)) line = substr(line, 1, RSTART - 1)
			sub(/[ \t]+@[A-Za-z0-9_!-]+$/, "", line)
			p = ""
			v = line
			if (match(line, /^[A-Za-z]+:/)) {
				p = substr(line, 1, RLENGTH - 1)
				v = substr(line, RLENGTH + 1)
			}
			if (v == "") next
			ok = 0
			if (kind == "domain") {
				# regexp 在生成期就被丢弃，查询这里同样不报命中，保持两边一致
				if (p == "regexp")      ok = 0
				else if (p == "full")   ok = (t == v)
				else if (p == "keyword") ok = (index(t, v) > 0)
				else ok = (t == v || (length(t) > length(v) && substr(t, length(t) - length(v)) == "." v))
			} else if (kind == "ip") {
				if (index(v, ":") > 0) next        # IPv6 条目本方案不处理
				if (index(t, "/") > 0) ok = (v == t)   # 查的是网段：按条目全等比对
				else ok = inm(n, v)
			}
			if (ok) {
				c = cat(FILENAME)
				if (!(c in seen)) {
					seen[c] = 0
					order[++hits] = c
				}
				seen[c]++
			}
		}
		END {
			if (hits == 0) {
				printf "未命中任何已装分类"
				exit
			}
			printf "命中 %d 个分类：", hits
			for (i = 1; i <= hits && i <= 15; i++) printf " %s(%d)", order[i], seen[order[i]]
			if (hits > 15) printf " …等"
		}
	' "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt 2>/dev/null)

	if [ -z "$_res" ]; then
		end_run "未安装分类，请先执行「更新分类」"
	else
		end_run "$_res"
	fi
}

# extract <geosite:x | geoip:y | x>
cmd_extract() {
	_spec="$1"
	if [ -z "$_spec" ]; then
		end_run "请输入分类，如 geosite:cn"
		return 0
	fi
	if ! valid_target "$_spec"; then
		end_run "非法字符：只允许 字母 数字 . _ : @ ! / -"
		return 0
	fi

	case "$_spec" in
	geosite:*) _f="$RULES_DIR/geosite_${_spec#geosite:}.txt" ;;
	geoip:*)   _f="$RULES_DIR/geoip_${_spec#geoip:}.txt" ;;
	*)         _f="$RULES_DIR/geosite_${_spec}.txt" ;;
	esac

	if [ ! -f "$_f" ]; then
		end_run "分类 $_spec 未安装，请先更新"
		return 0
	fi

	_n=$(wc -l <"$_f")
	_head=$(head -n 20 "$_f" | tr '\n' ' ')
	if [ "$_n" -gt 20 ]; then
		end_run "$_spec 共 $_n 条，前 20 条：$_head"
	else
		end_run "$_spec 共 $_n 条：$_head"
	fi
}

# ---------------------------------------------------------------------------
# restart —— 重启 xray
# ---------------------------------------------------------------------------

cmd_restart() {
	# rc 的通知机制就是「创建标记文件 + 给 init 发 SIGUSR1」：
	# notify_rc.c 只做这两件事，rc.c 的 handle_notifications() 会
	# opendir(/tmp/rc_notification) 扫描、remove 标记、派发事件。
	# 面板的「应用」按钮走的是同一条路（apply.cgi → notify_rc("restart_shadowsocks")）。
	if [ -d /tmp/rc_notification ]; then
		: >/tmp/rc_notification/restart_shadowsocks
		kill -USR1 1 2>/dev/null
		end_run "已通知 rc 重启 xray，约 5 秒后生效"
	else
		# 兜底：通知目录不存在时直接调启停脚本，同样后台跑，不阻塞页面
		( /usr/bin/shadowsocks.sh restart ) >/dev/null 2>&1 </dev/null &
		end_run "已后台重启 xray"
	fi
}

# ---------------------------------------------------------------------------
# 派发
# ---------------------------------------------------------------------------

case "$1" in
rules)
	shift
	case "$1" in
	update)
		shift
		cmd_rules_update "$@"
		;;
	list)
		cmd_rules_list
		;;
	*)
		end_run "未知子命令：rules $1"
		;;
	esac
	;;
lookup)
	shift
	cmd_lookup "$@"
	;;
extract)
	shift
	cmd_extract "$@"
	;;
restart)
	cmd_restart
	;;
*)
	end_run "未知命令：$*"
	;;
esac

exit 0
