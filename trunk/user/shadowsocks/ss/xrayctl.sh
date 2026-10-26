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
#   xrayctl.sh rules restore                          把分类从 flash 解回内存盘
#   xrayctl.sh lookup <域名|IP|CIDR>                  查该目标命中哪些分类
#   xrayctl.sh extract <geosite:x|geoip:y|x>          打印某个分类的条目；
#                                                     未装时按需下载（后台跑，不阻塞页面）
#   xrayctl.sh restart                                重启 xray（等价面板「应用」）
#

RULES_DIR="/tmp/ss_rules"
UPDATER="/etc_ro/ss/ssrules_update.sh"
RUN_LOG="/tmp/ssrules.run.log"
LOCK_DIR="/tmp/xrayctl.lock"
LOCK_TIMEOUT=900

# 分类小文本的持久化落点。
# /tmp 是内存盘，重启即失；分类原文 587 KB 压完约 116 KB，塞得进 flash。
# 放子目录而不是 /etc/storage 根，与既有的 chinadns/ 、gfwlist/ 保持一致
# （mtd_storage.sh 的 func_tarb 是 `find * ! -type d`，两层都收）。
RULES_BLOB_DIR="/etc/storage/ss_rules"
RULES_BLOB="$RULES_BLOB_DIR/rules.tar.bz2"
BLOB_TMP="/tmp/ss_rules.tar.bz2"
SAVE_LOG="/tmp/ss_rules.save.log"
MTD_SAVE="/sbin/mtd_storage.sh"

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
# 分类持久化 —— /tmp 是内存盘，重启即失，必须留一份在 flash
# ---------------------------------------------------------------------------

# 把 $RULES_DIR 打包压进 flash。返回 0 = 已落盘。
#
# ⚠️ 为什么必须看 mtd_storage.sh 的退出码，而不能像 chnroute / gfwlist 那样丢掉：
# func_save() 判的是**整份 storage 压缩后**的大小（`fsz >= 16 && fsz <= mtd_part_size`，
# 本机实测 mtd_part_size = 524288）。超限时它只打一行 "Error! Invalid storage final
# data size" 然后 result=1 —— **一个字节都不写**，用户之后改的所有路由器配置全部
# 无声地不落盘。这比「分类丢了」严重得多。
#
# 所以这里不做体积预测（预测要再跑一遍 tar+bzip2，在 MT7621 上要几秒到几十秒，
# 而且未必准），而是照常写、看退出码、失败就把自己那份撤掉再存一次，
# 让 storage 回到原样。chnroute 那种文本能再压 7 倍所以从不触限，
# 我们这个包已经是 bzip2 产物，体积会原样计入总量，性质不同。
persist_rules() {
	[ -d "$RULES_DIR" ] || return 0

	mkdir -p "$RULES_BLOB_DIR" 2>/dev/null
	# 先进分类目录再打包，包内是相对路径（./geosite_cn.txt …），
	# 解包时才能原样铺回 $RULES_DIR
	( cd "$RULES_DIR" && tar cf - . ) 2>/dev/null | bzip2 -9 >"$BLOB_TMP" 2>/dev/null
	if [ ! -s "$BLOB_TMP" ]; then
		rm -f "$BLOB_TMP"
		logger -t xrayctl "分类打包失败，本次未持久化"
		return 1
	fi
	mv -f "$BLOB_TMP" "$RULES_BLOB"

	if ! "$MTD_SAVE" save >"$SAVE_LOG" 2>&1; then
		# 退出码非 0 = 尺寸超限 / mtd_write 失败 / storage 被锁，三种情况 flash
		# 都没写进去。撤掉自己这份再存一次，免得把用户其它配置一直卡在超限状态
		rm -f "$RULES_BLOB"
		"$MTD_SAVE" save >/dev/null 2>&1
		logger -t xrayctl "分类持久化失败，Storage 余量不足，已放弃（详见 $SAVE_LOG）"
		return 1
	fi
	# 与 chnroute / gfwlist 的收尾一致，让刚读过的那批页缓存立刻释放
	sync
	echo 3 >/proc/sys/vm/drop_caches
	return 0
}

# 按需把分类从 flash 解回内存盘。已经有内容就不动 —— 以 /tmp 里的为准，
# 那可能是刚更新过的、比 flash 里新的版本。
ensure_rules() {
	if [ -n "$(ls "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt 2>/dev/null)" ]; then
		return 0
	fi
	# 从没更新过：静默返回，不算错误
	[ -f "$RULES_BLOB" ] || return 1

	mkdir -p "$RULES_DIR" 2>/dev/null
	bzcat "$RULES_BLOB" 2>/dev/null | tar xf - -C "$RULES_DIR" 2>/dev/null
	# 成败看落盘结果，不看管道退出码 —— 管道的 $? 只反映最后一环
	if [ -n "$(ls "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt 2>/dev/null)" ]; then
		logger -t xrayctl "已从 flash 恢复分类到 $RULES_DIR"
		return 0
	fi
	logger -t xrayctl "分类包 $RULES_BLOB 解包失败，分流规则将退化为只按 IP/兜底匹配"
	return 1
}

# rules restore —— 供开机路径（shadowsocks.sh 生成 xray 配置之前）与手工调用。
# 刻意不写 dbus：开机时没人在看页面，写了只会覆盖上一次的操作结果
cmd_rules_restore() {
	if ensure_rules; then
		echo "分类已就绪：$(summarize)"
	else
		echo "无可恢复的分类包（$RULES_BLOB 不存在），请执行「更新分类」"
	fi
}

# ---------------------------------------------------------------------------
# rules update —— 更新分类小文本（异步）
# ---------------------------------------------------------------------------

# 真正干活的函数，在后台子 shell 里跑，三个流都已被调用方重定向走
do_update() {
	"$UPDATER" "$@" >"$RUN_LOG" 2>&1
	_rc=$?
	_s=$(summarize)

	# 从 $RUN_LOG 里取本次计数 —— ssrcrules_update.sh 结束时会在 stdout 打一行
	# UPDATE_RESULT ok=N bad=M。用纯参数展开解析，不引 sed 正则。
	# 抓不到（脚本没跑到那一步，例如 mkdir 失败直接 exit 1）时留空，文案退回
	# 「本次结果未知」，绝不去猜一个数字。
	_ok=""
	_bad=""
	_line=$(grep '^UPDATE_RESULT ' "$RUN_LOG" 2>/dev/null | tail -n 1)
	case "$_line" in
	UPDATE_RESULT\ ok=*)
		_ok=${_line#UPDATE_RESULT ok=}
		_ok=${_ok%% *}
		_bad=${_line##*bad=}
		;;
	esac
	if [ -n "$_ok" ]; then
		_this="本次 $_ok 个成功"
		if [ "$_bad" -gt 0 ]; then
			_this="$_this / $_bad 个跳过"
		fi
	else
		_this="本次结果未知"
	fi

	if [ "$_rc" -eq 0 ]; then
		# 更新成功就把分类压进 flash，否则重启后 $RULES_DIR 一空，分流规则整份失效。
		# 持久化失败不能算成更新失败 —— 分类本身是好的，只是重启后会丢，
		# 状态文案要如实区分这两种情况。
		# ★ 文案里「分类库现状」四个字不能省：$_s 来自 summarize()，数的是
		#   $RULES_DIR 里现存的文件，含上次留下的旧文件。不加这层说明的话，
		#   「本次 1 个成功」配「23 个分类 / 611 KB」会被读成「本次下了 23 个」。
		if persist_rules; then
			end_run "更新完成（$_this），已持久化。分类库现状：$_s"
		else
			end_run "更新完成（$_this），但持久化失败（重启后会丢）。分类库现状：$_s"
		fi
	else
		# 非 0 = 一个分类都没下到（ssrules_update.sh 的 main 只在 ok=0 时返回 1）。
		# 这时【不】调 persist_rules：把陈旧的 /tmp 内容重新打包写进 flash 毫无
		# 意义，只会白重写一遍 storage，还可能把 storage 顶到体积上限而连带
		# 让用户其它配置全部落不了盘。
		end_run "更新失败（$_this，退出码 $_rc），未持久化。分类库现状：$_s，详见 /tmp/ssrules.log"
	fi
	rm -rf "$LOCK_DIR"
}

# 抢更新锁。0=拿到 1=已被占着 2=建不出锁目录（/tmp 满或只读）
#
# 陈旧锁检查：上次异常退出（断电、被 kill）会留下锁目录，让按钮永久卡在
# 「已在更新中」。用锁目录里的时间戳判断，超过 LOCK_TIMEOUT 秒就当作失效清掉。
#
# 为什么抽成函数：rules update 与 extract 的按需下载共用同一把锁 —— 两者都在
# 跑 ssrcrules_update.sh 往 $RULES_DIR 写文件，并发会互相踩（一个正在 tar 打包，
# 另一个往里写，压出来的包是半截的，而 persist_rules 看不出这一点）。
acquire_lock() {
	if [ -d "$LOCK_DIR" ] && [ -f "$LOCK_DIR/ts" ]; then
		_now=$(date +%s)
		_st=$(cat "$LOCK_DIR/ts" 2>/dev/null)
		if [ -n "$_st" ] && [ $((_now - _st)) -gt $LOCK_TIMEOUT ]; then
			rm -rf "$LOCK_DIR"
		fi
	fi
	if [ -d "$LOCK_DIR" ]; then
		return 1
	fi
	mkdir -p "$LOCK_DIR" 2>/dev/null || return 2
	date +%s >"$LOCK_DIR/ts"
	return 0
}

cmd_rules_update() {
	acquire_lock
	case $? in
	1)
		end_run "已在更新中，请稍候…"
		return 0
		;;
	2)
		end_run "无法创建锁目录 $LOCK_DIR"
		return 0
		;;
	esac

	begin_run "正在更新分类…"
	# 三个流全部重定向并丢给 /dev/null：后台任务不能握着 httpd 的
	# /tmp/syscmd.log 文件描述符不放，否则响应结束后还往已复用的文件里写
	( do_update "$@" ) >/dev/null 2>&1 </dev/null &
}

# ---------------------------------------------------------------------------
# rules list —— 列出已装分类
# ---------------------------------------------------------------------------

cmd_rules_list() {
	# 重启后内存盘是空的，先解回来再列，否则用户会以为分类丢了
	ensure_rules
	if [ ! -d "$RULES_DIR" ]; then
		end_run "分类未安装，请先执行「更新分类」"
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

# spec → /tmp 里的落点文件。
# 裸名（不带 geosite:/geoip: 前缀）优先当域名类 —— 绝大多数分类都是域名类；
# 只有在 geoip 那份确实存在而 geosite 那份不存在时才取 geoip。
# 判「哪个存在」而不是「猜一个」，是为了让「已装但类型写错」也能被查出来。
resolve_spec() {
	case "$1" in
	geosite:*) printf '%s' "$RULES_DIR/geosite_${1#geosite:}.txt" ;;
	geoip:*)   printf '%s' "$RULES_DIR/geoip_${1#geoip:}.txt" ;;
	*)
		if [ -f "$RULES_DIR/geoip_$1.txt" ] && [ ! -f "$RULES_DIR/geosite_$1.txt" ]; then
			printf '%s' "$RULES_DIR/geoip_$1.txt"
		else
			printf '%s' "$RULES_DIR/geosite_$1.txt"
		fi
		;;
	esac
}

# lookup <域名|IP|CIDR>
cmd_lookup() {
	# 同上：重启后 /tmp 是空的，不先解回来查什么都是「未命中任何已装分类」
	ensure_rules
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

# 生成某个已装分类的摘要文本（前 20 条）。纯函数：只 printf，不碰 dbus 也不碰锁
spec_summary() {
	# 剥掉 wc 可能补的前导空格：这是本文件唯一一处把 wc 结果拼进【字符串】的地方，
	# 别处（summarize / cmd_rules_list）都是喂给 $(( )) 做算术，空格会被自动吃掉。
	# 不剥的话状态栏会显示成「共        2 条」。busybox 的 wc 不加宽，
	# 但剥一下零成本，也让这条文案不依赖 wc 的具体实现。
	_n=$(wc -l <"$2" | tr -d ' \t')
	_head=$(head -n 20 "$2" | tr '\n' ' ')
	if [ "$_n" -gt 20 ]; then
		printf '%s' "$1 共 $_n 条，前 20 条：$_head"
	else
		printf '%s' "$1 共 $_n 条：$_head"
	fi
}

# 按需安装一个分类。在后台子 shell 里跑（三个流已被调用方重定向走）。
# 只下一个分类，复用 ssrcrules_update.sh 的「指定分类」模式，不重复实现下载链路。
#
# ⚠️ 判据是产物文件在不在，不是 $?：ssrules_update.sh 的 main() 最后一条命令是
# log()，退出码恒为 0 —— 看 $? 会把「下载失败」当成成功，然后对着一个不存在的
# 文件报「共 0 条」，用户还以为装上了。
do_extract_install() {
	_spec="$1"
	case "$_spec" in
	geosite:* | geoip:*)
		"$UPDATER" "$_spec" >>"$RUN_LOG" 2>&1
		;;
	*)
		# 裸名：先按域名类试，没落地再按 IP 类试
		"$UPDATER" "geosite:$_spec" >>"$RUN_LOG" 2>&1
		[ -f "$RULES_DIR/geosite_$_spec.txt" ] ||
			"$UPDATER" "geoip:$_spec" >>"$RUN_LOG" 2>&1
		;;
	esac

	_f="$(resolve_spec "$_spec")"
	if [ ! -f "$_f" ]; then
		_msg="分类 $_spec 取不到（检查拼写；上游没有这个分类，或网络不通，详见 /tmp/ssrules.log）"
	elif persist_rules; then
		# 新装的分类也要进 flash —— 不落盘的话重启后 ensure_rules 解出来的旧包里
		# 没有它，引用它的规则会静默退化成只按 IP 匹配
		_msg="$(spec_summary "$_spec" "$_f")"
	else
		_msg="分类 $_spec 已下载（$_f），但持久化失败，重启后会丢"
	fi

	# 先放锁再报完成：页面一看到 run=0 就让用户能再点，
	# 若锁还没撤，那一下会被「已在更新中」挡回去
	rm -rf "$LOCK_DIR"
	end_run "$_msg"
}

# extract <geosite:x | geoip:y | x>
cmd_extract() {
	ensure_rules
	_spec="$1"
	if [ -z "$_spec" ]; then
		end_run "请输入分类，如 geosite:cn"
		return 0
	fi
	if ! valid_target "$_spec"; then
		end_run "非法字符：只允许 字母 数字 . _ : @ ! / -"
		return 0
	fi

	# ⚠️ 2026-10-21 修复：带冒号但不是已知前缀 ⇒ 几乎都是拼写错误
	#    （实测用户输入 geoside:tiktok，少了一个 o，却看到「未安装」而以为功能坏了）。
	#
	#    不在这里拦的话，resolve_spec 的裸名分支会把它当成【分类名】，
	#    拼出 geosite_geoside:tiktok.txt 这种带冒号的畸形路径，然后走完整的
	#    按需下载链路 —— 三个源 × 连接超时 × 重试。用户盯着「正在按需下载…」
	#    等几十秒才等到一句「取不到」，期间完全看不出是自己拼错了
	#    （实测 extract geosite:zzznotexist 在 6 秒后仍停在「未安装，正在按需下载…」）。
	#    这里直接秒回，并把正确格式摆出来让用户自己对照。
	case "$_spec" in
	*:*)
		case "$_spec" in
		geosite:* | geoip:*) ;;
		*)
			end_run "未知前缀「${_spec%%:*}」，只支持 geosite: 或 geoip:（检查拼写，如 geosite:tiktok）"
			return 0
			;;
		esac
		;;
	esac

	_f="$(resolve_spec "$_spec")"
	if [ -f "$_f" ]; then
		# 已装：同步直接打印，秒回。不占锁，也不动 xray_action_run 的语义
		end_run "$(spec_summary "$_spec" "$_f")"
		return 0
	fi

	# 未装：按需下载。
	#
	# 为什么放后台而不是同步：httpd 是单进程 select 循环，SystemCmd 走 doSystem
	# 是阻塞的 —— 同步下载在网络不通时要走完 15s 连接超时 × 最多 3 个源 × 2 次
	# 重试，整个 Web UI 会跟着冻住近两分钟。放后台后由页面已有的 waitIdle 轮询
	# 收尾（runCmd 内部就是「触发 → 轮询 xray_action_run」），结果文本照样从
	# xray_action_status 读回来，用户仍然只点一次。
	#
	# begin_run 必须在前台先调：它是「命令已被受理」的唯一信号。若放进后台子
	# shell，主命令会先返回，页面的 GET console_response.asp 一回来就可能读到
	# 旧的 run=0 而立刻收尾，拿到上一次的陈旧状态。
	acquire_lock
	case $? in
	1)
		end_run "分类正在更新中，请稍后再试"
		return 0
		;;
	2)
		end_run "无法创建锁目录 $LOCK_DIR"
		return 0
		;;
	esac

	begin_run "分类 $_spec 未安装，正在按需下载…"
	( do_extract_install "$_spec" ) >/dev/null 2>&1 </dev/null &
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
	restore)
		cmd_rules_restore
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
