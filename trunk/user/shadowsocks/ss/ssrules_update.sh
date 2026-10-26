#!/bin/sh
#
# ssrcrules_update.sh —— 分流规则分类小文本更新
#
# 产物落 /tmp/ss_rules/（内存盘，读起来快）：
#   geosite_<分类>.txt   域名类，每行 domain:x / full:x / keyword:x，或带 :@属性 后缀
#   geoip_<分类>.txt     IP 类，每行裸 CIDR
# 这些文件由 xrayroute.lua 在生成 xray 配置时展开成具体规则。
#
# 本脚本只管写 /tmp。落 flash 由调用方 xrayctl.sh 负责（persist_rules）：
# 全部 13 个分类约 587 KB，bzip2 后约 116 KB，能塞进 512 KB 的 /etc/storage，
# 但 storage 是所有配置共用的，所以要连 mtd_storage.sh 的退出码一起判 —— 见那边注释。
#
# 用法：
#   ssrcrules_update.sh                  更新默认清单
#   ssrcrules_update.sh geosite:xxx ...  只更新指定分类（可混 geosite:/geoip:）
#   ssrcrules_update.sh list             列出已装分类
#
# 分类源（三级回退，先命中先用）：
#   1. Loyalsoldier/domain-list-custom:release  类型前缀完整（domain:/full:/regexp:）
#   2. Loyalsoldier/v2ray-rules-dat:release     与路由器上 geosite.dat 同一份分类体系
#   3. MetaCubeX/meta-rules-dat:meta/geo/geosite 覆盖全（约千个分类），但只区分后缀匹配
# geoip 只有 Loyalsoldier/geoip:release/text 一个源。
#
# 已知取不到的分类：geosite:ir、geosite:ru-blocked
#   这两个是 Loyalsoldier 的 geosite.dat 专有分类，上游没有任何文本形态。
#   引用它们的规则，域名部分会展开为空（IP 部分照常生效）。

RULES_DIR="/tmp/ss_rules"
LOG_FILE="/tmp/ssrules.log"

UA="Mozilla/5.0 (Linux; Padavan)"
CONNECT_TIMEOUT=15
RETRY=2

# ---- 下载源的内置默认值 ----------------------------------------------------
# ★ 这四个值【必须】留在脚本里，不能只靠界面上的 dbus 键：开机流程
#   （shadowsocks.sh 的 `xrayctl.sh rules restore`）与 xrayctl.sh 的 extract
#   都会跑本脚本，此时 dbus 键可能还不存在（新刷机 / storage 被清空）。
#   下面 resolve_sources() 里「dbus 键优先、读不到就用这里」就是靠这四个兜底。
DL_BASE_DEF="https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release"
V2R_BASE_DEF="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
META_BASE_DEF="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite"
GEOIP_BASE_DEF="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text"

# 默认域名分类。刻意不含 geolocation-!cn（543KB）与 gfwlist（617KB）——
# 「其余全走代理」由 routing 的兜底规则承担，装这两份纯属浪费内存。
#
# 后 10 个（tiktok…facebook）只有 MetaCubeX 那个源有，体积都很小（压缩后合计约 5.6KB），
# 但都是「分流时最常单独指定」的流媒体/社交类 —— 不预装的话用户查 geosite:tiktok
# 会看到「未安装」，得先自己想办法把它装进来。xrayctl.sh 的 extract 已支持按需装，
# 这里预装是为了让「更新分类」一次就把常用集合备齐。
DEFAULT_GEOSITE="cn gfw geolocation-cn tld-cn google apple icloud steam private category-ads-all category-games tiktok netflix youtube telegram twitter disney spotify openai instagram facebook"

# 默认 IP 分类。geoip:ru 有 447KB，不默认装。
DEFAULT_GEOIP="cn private"

log() {
	logger -t ssrules "$@"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# ---- 下载源解析（可在「分流规则」页面自定义）-------------------------------
# 最终 URL = "${xray_dl_prefix}${原始 BASE URL}"
#   前缀为空 ⇒ 直接用原始 BASE（改动前的行为，零回归）
#   前缀非空 ⇒ 例：前缀 https://ghproxy.net/ + 原始 https://raw.githubusercontent.com/...
#              ⇒ https://ghproxy.net/https://raw.githubusercontent.com/...（ghproxy 约定）
# 前缀存在的意义是应对 raw.githubusercontent.com 被墙，四个源统一过它。

# 形态守卫。这个值来自网页输入框，最终会进 curl 的参数列表。
# ★ 只挡「会让 curl 参数错位」的形态，不做白名单字符集 ——
#   xrayctl.sh 的 valid_target() 是 ^[A-Za-z0-9._:@!/-]+$，它【不允许 % & ? =】，
#   照抄会把带 query 的镜像源全部挡掉。
# ★ 必须挡「以 - 开头」：`fetch "$URL" "$tmp"` 里 $URL 虽然加了引号、不会发生词分割，
#   但 curl 收到单个 argv "-o/etc/storage/x" 时会把它当成写文件选项 —— 引号挡不住，
#   因为它本来就是一个合法 argv。同「订阅内容 = 未受信输入」的既有教训。
url_ok() {
	case "$1" in
	-*) return 1 ;;
	*[![:print:]]*) return 1 ;;
	*[[:space:]]*) return 1 ;;
	esac
	return 0
}

# 取一个下载源：dbus 键优先；键不存在 / 值为空 / 形态非法 ⇒ 回落到内置默认值。
# ★ 非法值必须【回落】而不是照用：否则用户填错一个字符，四个源会一起静默失效，
#   而表现只是「更新分类」全部报取不到，很难指回这个输入框。
source_or() {
	_key="$1"
	_def="$2"
	_val="$(dbus get "$_key" 2>/dev/null)"
	if [ -z "$_val" ]; then
		printf '%s' "$_def"
		return 0
	fi
	if url_ok "$_val"; then
		printf '%s' "$_val"
	else
		log "警告：$_key 的值形态非法（含空白/控制字符或以 - 开头），已回落到内置默认值"
		printf '%s' "$_def"
	fi
}

# 前缀 + 原始 URL。单独抽出来是为了让「拼接顺序」只有一个写点 ——
# 顺序写反是静默失效：拼出来的串在语法上仍然"像"一个 URL，只是永远取不到。
join_url() {
	printf '%s%s' "$DL_PREFIX" "$1"
}

resolve_sources() {
	DL_PREFIX="$(dbus get xray_dl_prefix 2>/dev/null)"
	if [ -n "$DL_PREFIX" ] && ! url_ok "$DL_PREFIX"; then
		log "警告：xray_dl_prefix 的值形态非法（含空白/控制字符或以 - 开头），已忽略该前缀"
		DL_PREFIX=""
	fi
	DL_BASE="$(join_url "$(source_or xray_dl_base "$DL_BASE_DEF")")"
	V2R_BASE="$(join_url "$(source_or xray_dl_v2r "$V2R_BASE_DEF")")"
	META_BASE="$(join_url "$(source_or xray_dl_meta "$META_BASE_DEF")")"
	GEOIP_BASE="$(join_url "$(source_or xray_dl_geoip "$GEOIP_BASE_DEF")")"
}

resolve_sources

# 下载到指定文件。用 -f：HTTP 404 直接返回非零，避免把「404: Not Found」正文当内容存下来
fetch() {
	curl -fsSL -A "$UA" --connect-timeout $CONNECT_TIMEOUT --retry $RETRY -o "$2" "$1" 2>/dev/null
}

# 域名文本归一化：裸域名补 domain: 前缀。
# 必须补 —— xray 对无前缀条目走 Domain_Plain（子串匹配），"aa.com" 会命中 "xaa.com.evil.net"。
# 已有的类型前缀与 :@属性后缀一律原样保留（@属性由 xrayroute.lua 在生成期过滤）。
norm_domain() {
	awk '
		{ sub(/\r$/, "") }
		/^[[:space:]]*#/ { next }
		/^[[:space:]]*$/ { next }
		{
			sub(/^[[:space:]]+/, "")
			sub(/[[:space:]]+$/, "")
			if ($0 ~ /^[a-z]+:/) { print; next }
			sub(/^\+\./, "")
			print "domain:" $0
		}'
}

# MetaCubeX 的 YAML 归一化：payload 段每行 "- +.example.com"，或 "- example.com"
norm_yaml() {
	awk -v q="'" '
		{ sub(/\r$/, "") }
		/^[[:space:]]*#/ { next }
		/^[[:space:]]*(payload|version):/ { next }
		{
			sub(/^[[:space:]]*-[[:space:]]*/, "")
			sub(/^[[:space:]]+/, "")
			sub(/[[:space:]]+$/, "")
			gsub(q, "")
			if ($0 == "") { next }
			if ($0 ~ /^[a-z]+:/) { print; next }
			sub(/^\+\./, "")
			print "domain:" $0
		}'
}

# geoip 文本是裸 CIDR，只清空行与注释
norm_geoip() {
	awk '
		{ sub(/\r$/, "") }
		/^[[:space:]]*#/ { next }
		/^[[:space:]]*$/ { next }
		{ sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }'
}

# 分类名只允许字母数字、下划线、连字符、点、叹号 —— 挡住路径穿越
safe_name() {
	case "$1" in
	"" | */* | *..*) return 1 ;;
	esac
	case "$1" in
	*[!A-Za-z0-9_.!-]*) return 1 ;;
	esac
	return 0
}

# 更新一个 geosite 分类
update_geosite() {
	name="$1"
	safe_name "$name" || { log "geosite:$name 分类名非法，跳过"; return 1; }
	out="$RULES_DIR/geosite_$name.txt"
	tmp="$RULES_DIR/.tmp.$$"
	rm -f "$tmp"

	if fetch "$DL_BASE/$name.txt" "$tmp"; then
		norm_domain <"$tmp" | sort -u >"$out"
	elif fetch "$V2R_BASE/$name.txt" "$tmp"; then
		norm_domain <"$tmp" | sort -u >"$out"
	elif fetch "$META_BASE/$name.yaml" "$tmp"; then
		norm_yaml <"$tmp" | sort -u >"$out"
	else
		rm -f "$tmp"
		log "geosite:$name 三个源都取不到，跳过"
		return 1
	fi
	rm -f "$tmp"
	log "geosite:$name -> $(wc -l <"$out") 条"
}

# 更新一个 geoip 分类
update_geoip() {
	name="$1"
	safe_name "$name" || { log "geoip:$name 分类名非法，跳过"; return 1; }
	out="$RULES_DIR/geoip_$name.txt"
	tmp="$RULES_DIR/.tmp.$$"
	rm -f "$tmp"

	if fetch "$GEOIP_BASE/$name.txt" "$tmp"; then
		norm_geoip <"$tmp" | sort -u >"$out"
		rm -f "$tmp"
		log "geoip:$name -> $(wc -l <"$out") 条"
	else
		rm -f "$tmp"
		log "geoip:$name 下载失败，跳过"
		return 1
	fi
}

# 列出已装分类与体积
list_installed() {
	total=0
	for f in "$RULES_DIR"/geosite_*.txt "$RULES_DIR"/geoip_*.txt; do
		[ -f "$f" ] || continue
		size=$(wc -c <"$f")
		total=$((total + size))
		echo "$(basename "$f")  ${size}B  $(wc -l <"$f") 行"
	done
	echo "合计 ${total}B / 目录 $RULES_DIR"
}

main() {
	if [ "$1" = "list" ]; then
		list_installed
		return 0
	fi

	mkdir -p "$RULES_DIR" || {
		log "无法创建 $RULES_DIR"
		exit 1
	}
	# 清掉上次中断留下的临时文件
	rm -f "$RULES_DIR"/.tmp.*

	# ★ 统计本次真正下载成功的分类数。
	#   update_geosite/update_geoip 的约定是 0=本次确实下载并写入了新文件，
	#   非 0=跳过（三个源都取不到 / 分类名非法）。这两个函数每次都是无条件
	#   下载覆盖，没有「已是最新就不下载」的路径 ⇒ 非 0 就是真失败。
	#   全部失败时必须以非零退出：调用方 xrayctl.sh 只看退出码，否则会把
	#   「一个都没下到」当成成功，界面上打出「更新完成并已持久化」，还会把
	#   陈旧的 /tmp 内容重新打包写进 flash。
	ok=0
	bad=0

	if [ $# -gt 0 ]; then
		for spec in "$@"; do
			case "$spec" in
			geosite:*) update_geosite "${spec#geosite:}" ;;
			geoip:*) update_geoip "${spec#geoip:}" ;;
			*) log "无法识别：$spec（需写成 geosite:xxx 或 geoip:xxx）" ; continue ;;
			esac
			if [ $? -eq 0 ]; then
				ok=$((ok + 1))
			else
				bad=$((bad + 1))
			fi
		done
	else
		for c in $DEFAULT_GEOSITE; do
			if update_geosite "$c"; then
				ok=$((ok + 1))
			else
				bad=$((bad + 1))
			fi
		done
		for c in $DEFAULT_GEOIP; do
			if update_geoip "$c"; then
				ok=$((ok + 1))
			else
				bad=$((bad + 1))
			fi
		done
	fi

	if [ "$ok" -eq 0 ]; then
		log "更新失败：$bad 个分类全部跳过（源不可达或分类名非法），未写入任何新文件"
		return 1
	fi
	if [ "$bad" -gt 0 ]; then
		log "更新结束：$ok 个成功 / $bad 个跳过，明细见 $LOG_FILE"
	else
		log "更新结束：$ok 个全部成功，明细见 $LOG_FILE"
	fi
	# 给调用方（xrayctl.sh 的 do_update）一行机器可读的本次计数，它据此把状态
	# 文案里的「本次成功几个」与「分类库现在有几个」分开说 —— 后者是
	# summarize() 数的 $RULES_DIR 现状，与本次是否真下载无关。
	# log() 只写 logger 与 $LOG_FILE、从不碰 stdout，所以这行是 stdout 上唯一的
	# 机器可读输出，调用方按前缀抓取不会误命中别的内容。
	echo "UPDATE_RESULT ok=$ok bad=$bad"
	return 0
}

main "$@"
