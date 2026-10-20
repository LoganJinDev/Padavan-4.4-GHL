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

DL_BASE="https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release"
V2R_BASE="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
META_BASE="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite"
GEOIP_BASE="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text"

# 默认域名分类。刻意不含 geolocation-!cn（543KB）与 gfwlist（617KB）——
# 「其余全走代理」由 routing 的兜底规则承担，装这两份纯属浪费内存。
DEFAULT_GEOSITE="cn gfw geolocation-cn tld-cn google apple icloud steam private category-ads-all category-games"

# 默认 IP 分类。geoip:ru 有 447KB，不默认装。
DEFAULT_GEOIP="cn private"

log() {
	logger -t ssrules "$@"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

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

	if [ $# -gt 0 ]; then
		for spec in "$@"; do
			case "$spec" in
			geosite:*) update_geosite "${spec#geosite:}" ;;
			geoip:*) update_geoip "${spec#geoip:}" ;;
			*) log "无法识别：$spec（需写成 geosite:xxx 或 geoip:xxx）" ;;
			esac
		done
	else
		for c in $DEFAULT_GEOSITE; do
			update_geosite "$c"
		done
		for c in $DEFAULT_GEOIP; do
			update_geoip "$c"
		done
	fi

	log "更新结束，明细见 $LOG_FILE"
}

main "$@"
