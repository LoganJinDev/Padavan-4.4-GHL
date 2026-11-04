#!/bin/sh
#
# EasyTier 二进制下载器（Padavan 移植版）
#
# 用法： easytier_download.sh download|check|clean|versions|curver|defver|selver|setver|needdl
#   download —— 下载并校验 easytier-core / easytier-cli 到 /tmp/easytier/
#   check    —— 只校验已存在的文件，不下载（可带参数：check <core路径> <cli路径>）
#   clean    —— 清掉暂存目录与版本列表缓存
#   versions —— 从官方仓库取可选版本列表（带 1 小时缓存）
#   curver   —— 打印「本机已安装的版本」，无安装记录则打空
#   defver   —— 打印固件钉死的默认版本（内置机型用它报版本，它没有安装记录）
#   selver   —— 打印「用户选中的版本」，没选或非法则打空
#   setver   —— 落盘本次要装的版本（带参数 = 该版本，不带 = 清除选择、跟随默认）
#   needdl   —— 问「要不要下载」：不需要则打原因并退出 1，需要则退出 0
#
# 用途：GHL 这类小闪存机型不把 8.94 MiB 的二进制编进固件（根分区只有 29 MB，
# 余量 1.19 MiB），改为首次使用时从 GitHub 下载到 /tmp。大闪存机型（MI-R3G /
# MI-R3P）走 CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN 直接编进固件，不需要本脚本。
#
# ---------------------------------------------------------------------------
# 与官方 OpenWrt download.sh 的差异（每一处都是安全修复）
# ---------------------------------------------------------------------------
#   官方做法                                   本脚本做法
#   ----------------------------------------   ------------------------------
#   `easytier-core -h | wc -l > 3` 当完整性判据   对二进制做 sha256 比对
#   curl -k / wget --no-check-certificate       不关闭 TLS 证书校验
#   unzip -j -d /tmp（解到世界可写的根目录）      解到私有暂存子目录 /tmp/easytier_dl，
#                                              再按精确路径搬走
#   chmod +x（755，任何本地用户可执行）           chmod 700（只有 root 能读能执行）
#   下载失败静默换下一个代理、无校验             校验不过 ⇒ 删文件 + 拒绝安装 + 返回 1
#   只能装它自带的那个版本                       可选版本（官方仓库动态获取）
#
# ---------------------------------------------------------------------------
# ★★★ 版本选择与「校验从哪来」（本脚本的核心设计）
# ---------------------------------------------------------------------------
# 用户诉求：版本不要写死在固件里，要能跟着官方仓库走。
# 难点：一旦版本可变，「固件里钉死的 sha256 常量」就失效了 —— 拿旧指纹去校验
#       新版本必然失败，而放弃校验等于把「执行什么字节」的决定权交给下载链路。
#
# 解法是把「版本」和「指纹」分成两个来源，各自都不可被中间人篡改：
#
#   默认版本（nvram easytier_version 为空或非法）
#       ⇒ 指纹 = 固件里钉死的三个常量（本文件下半部分）。★ 全程不联网取指纹。
#         这条路径与改造前【逐字节等价】，老机型行为零变化。
#
#   其他版本（用户在界面上选了 vX.Y.Z）
#       ⇒ 指纹 = 官方 API 的资产摘要
#         https://api.github.com/repos/EasyTier/EasyTier/releases/tags/vX.Y.Z
#         走 TLS ⇒ 等于「GitHub 亲口说这个文件名对应这份字节」。
#       ⇒ 拿到摘要后才下载 zip，比对通过才解压。
#
# ★ 为什么不是「用 releases 列表一次取全部版本的指纹」：那份 JSON 有 1.7 MB /
#   约 4.4 万行，busybox awk 在 MT7621 上要几十秒，而这条路径是同步阻塞 httpd 的。
#   tags 列表只有 13 KB / 302 行 ⇒ 「轻量列表 + 下载时按需取单个摘要」。
#
# ★ 为什么不用 prerelease 标志筛版本：上游把绝大多数版本都标成 prerelease
#   （v2.7.0 / v2.6.3 / v2.6.2 / v2.6.1 / v2.6.0 / v2.5.0 …），这个标志在这里
#   不是稳定性信号，按它筛会把新版全滤掉。
#
# ★★★ GitHub 只对 v2.3.1 及更新的版本提供资产摘要（v2.3.0 及更老是 null）。
#   碰到 null 一律【拒绝安装并说明原因】，绝不降级成「不校验就装」。
#
# ---------------------------------------------------------------------------
# 关于第三方加速代理
# ---------------------------------------------------------------------------
# 官方用了 4 个第三方 GitHub 加速站。代理能做的坏事是「替换二进制」，而 sha256
# 钉死之后这条路被堵死了 —— 代理无法伪造出哈希一致的字节。剩下的只是可用性风险
# （代理挂了 / 代理返回错误页），那表现为下载失败，不是安全问题。
# 所以本脚本保留代理做回退，但**顺序是直连优先**，且每一步之后都强制校验。
# 可用 nvram easytier_download_proxy 覆盖代理列表（留空 = 只用直连）。
# ★ 实测：代理对 api.github.com 的转发大多不可用（gh-proxy.com 回 404，
#   ghproxy.net / ghfast.top 回 403），所以 API 走的代理回退基本是「快速失败」。
#   设备直连 api.github.com 是通的（实测 200），不依赖代理。
#
set -f

ET_DIR=/tmp/easytier
ET_CORE=$ET_DIR/easytier-core
ET_CLI=$ET_DIR/easytier-cli
ET_STAGE=/tmp/easytier_dl
ET_LOG=/tmp/easytier.log

# 大闪存机型编进固件的那一份。★ 用来区分「校验的对象是内置的还是 /tmp 的」——
# 内置那份的指纹随固件钉死，与用户选的版本无关。
ET_SYS_CORE=/usr/bin/easytier-core
ET_SYS_CLI=/usr/bin/easytier-cli

# ---------------------------------------------------------------------------
# 默认版本与指纹 —— 升级固件自带的二进制就是改下面这几行，随固件一起发
# ---------------------------------------------------------------------------
# 上游发布物： easytier-linux-mipsel-v2.6.4.zip
#   zip 内只有两个文件，带 easytier-linux-mipsel/ 目录前缀，没有 web 控制台
#   （上游对 webconsole 声明 depends on !(mips||mipsel)）
ET_DEF_VER=v2.6.4
ET_ARCH=mipsel

# 全量 zip 的 sha256 —— 第一道闸门，挡住「解压出奇怪东西」这类问题
ET_ZIP_SHA256=7c93bcc9e9276f102b5299b0773941db7fd1d99ad04bac42b479a0d979ef5220

# 两个二进制的 sha256 —— 第二道闸门，也是真正决定「执行什么字节」的那一道
#   easytier-core 6687000 B
ET_CORE_SHA256=2ae281fb79b9026a00a4c9e5bfce6c007f155d919881d64c2a91795011d3a245
#   easytier-cli  2692152 B
ET_CLI_SHA256=b99664c7c956d5a16d708a32f9928955c0ed777ae7e1d9eeda986b623ff27de4

# zip 内层目录名：只跟架构有关，与版本无关
ET_ZIP_INNER="easytier-linux-${ET_ARCH}"

# ---------------------------------------------------------------------------
# 版本选择的运行态（都在 tmpfs 上，重启即清）
# ---------------------------------------------------------------------------
# 官方仓库 API 基址
ET_API=https://api.github.com/repos/EasyTier/EasyTier

# 版本列表缓存。第 1 行是抓取时刻（epoch），第 2 行起是版本号。
# ★ 缓存的意义：GitHub 匿名限额是 60 次/小时，界面上多点几次就会打满。
ET_VER_CACHE=/tmp/easytier_versions.txt
ET_VER_TTL=3600

# 安装记录：本机 /tmp 里那两个二进制【实际是什么版本、指纹是多少】。
#   第 1 行 版本号，第 2 行 core 的 sha256，第 3 行 cli 的 sha256
# ★ 只在「zip 摘要已通过 + 装完复校通过」之后才写 ⇒ 它一旦存在就是可信的。
# ★ 为什么必须存：非默认版本没有固件常量可对照，否则每次刷新状态都会判
#   「校验不通过」并反复重下。存的是「我们自己校验通过的那份的指纹」，
#   用来抓后续的损坏/截断（/tmp 被写满是最常见的静默损坏原因）。
ET_VER_STATE=$ET_DIR/installed.sha256

# 中间产物（用完即删）
ET_VER_RAW=/tmp/easytier_tags.json
ET_REL_RAW=/tmp/easytier_release.json

# 代理回退列表（直连失败后才用）。带 {url} 占位。
ET_PROXYS_DEFAULT="https://ghproxy.net/{url}
https://gh-proxy.com/{url}
https://ghfast.top/{url}"

# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

et_log() {
	logger -t easytier "$1" 2>/dev/null
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$ET_LOG"
}

# sha256 计算器：本仓库 busybox 已编译 SHA256SUM；桌面端（本地自测）用 shasum。
# ★ 用 `type` 而不是 `command -v` —— 本设备的 shell 没有 command 内建，
#   `[ ! command -v X ]` 恒为假（rc=2），会把「没有工具」误判成「有工具」。
et_sha256() {
	if type sha256sum >/dev/null 2>&1; then
		sha256sum "$1" 2>/dev/null | awk '{print $1}'
	elif type shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
	else
		echo ""
	fi
}

# 校验单个文件：匹配返回 0，不匹配/算不出返回 1
et_verify() {
	_f="$1"
	_want="$2"
	[ -f "$_f" ] || return 1
	_got=$(et_sha256 "$_f")
	if [ -z "$_got" ]; then
		et_log "错误：设备上没有 sha256sum / shasum，无法校验"
		return 1
	fi
	if [ "$_got" = "$_want" ]; then
		return 0
	fi
	et_log "错误：$(basename "$_f") 校验失败  期望 $_want  实际 $_got"
	return 1
}

# ---------------------------------------------------------------------------
# 版本号：校验 / 选择
# ---------------------------------------------------------------------------

# 严格 vN.N.N。★ 不抄 et_valid_ip4 里那句 `0*[0-9]*`（拒前导零）——
#   本函数的分段由 `v` 开头且各段在 [0-9] 类内，前导零在这里无害；
#   而且那句 glob 在 busybox 里的实际行为很微妙（实测 `0` 不匹配 `0*[0-9]*`），
#   照抄一个自己没完全吃透的模式是给自己埋雷。
# ★ 这条顺带把 `nightly` 挡在外面（官方 tags 里没有 nightly，它只是个 release），
#   与「tags 列表只取 vN.N.N」构成两道互相独立的闸门。
et_valid_ver() {
	case "$1" in
		v[0-9]*.[0-9]*.[0-9]*) ;;
		*) return 1 ;;
	esac
	# ★ 这里【不能】再加一句「把非 [0-9.] 字符一律拒掉」的守卫。
	#   那会把开头的 `v` 也当成非法字符 ⇒ 30 个真实 tag 全被拒 ⇒ et_sel_ver
	#   永远回落到默认版本 ⇒ 界面选了 v2.7.0 却静默装成 v2.6.4（零报错）。
	#   非法字符交给下面的分段循环判定：IFS=. 切开后，任何不属于 0-9 的字符
	#   必然落在某一段里；首段之外出现的 `v` 同样落进纯数字那一条判据。
	_vv_save=$IFS
	IFS=.
	set -- $1
	IFS=$_vv_save
	[ $# -eq 3 ] || return 1
	_vv_first=1
	for _vv_o in "$@"; do
		# 首段允许 v 前缀，其余段必须纯数字
		if [ "$_vv_first" = "1" ]; then
			case "$_vv_o" in v[0-9]*) _vv_o=${_vv_o#v} ;; *) return 1 ;; esac
			_vv_first=0
		fi
		case "$_vv_o" in ''|*[!0-9]*) return 1 ;; esac
	done
	return 0
}

# 本次要装的版本：nvram 里合法就用它，否则回落到固件钉死的默认版本。
# ★ nvram 值是不可信输入（apply.cgi 只是转发），所以【在消费侧】校验，
#   与 et_load_cfg 校验 socks5 / 检测 IP 是同一个姿态。
et_sel_ver() {
	_sv=$(nvram get easytier_version 2>/dev/null)
	if et_valid_ver "$_sv"; then
		echo "$_sv"
	else
		echo "$ET_DEF_VER"
	fi
}

# 落盘「本次要装的版本」—— setver 子命令的实现，et_sel_ver 的写侧。
# ★ 为什么需要这个写入口：界面「下载」按钮走的是 httpd 的 SystemCmd 通道，
#   不是表单提交 ⇒ 下拉框里选的版本【不会】自己进 nvram。少了这一步，
#   用户选了 v2.6.3 点下载，needdl 读到的仍是 nvram 里的旧值，于是报
#   「二进制已存在且校验通过（旧版本号），无需下载」，且零报错。
#   修法不是让界面先去点「应用本页设置」，而是让下载这个动作自带版本 ——
#   一个动作一个意图，中间不依赖用户再点别的按钮。
# ★ 入参来自界面（不可信），必须在【这里】再校验一遍：调用方校验过不等于
#   这里可以不校验，何况这个值要被写进 nvram。
# ★ 非法值【不回显】：这个值会经 et_state_echo 落进 nvram 的
#   easytier_bin_state，而那一格是服务端渲染的 ⇒ 回显未校验的输入等于
#   开一个存储型 XSS 面。要排查去 /tmp/syscmd.log，那里有完整命令串。
# ★ 必须 commit：apply.cgi 那条路是 commit 的（httpd web_ex.c 的
#   asus_nvram_commit），这条不是的话重启后选择丢失，表现成
#   「换完版本、重启又变回去了」。
et_set_ver() {
	if [ $# -eq 0 ]; then
		# 不带参数 = 清除选择、跟随固件默认版本
		nvram set easytier_version=
		nvram commit
		echo "已设为跟随固件默认版本（$ET_DEF_VER）"
		return 0
	fi
	if ! et_valid_ver "$1"; then
		echo "版本号非法，已中止"
		return 1
	fi
	nvram set easytier_version="$1"
	nvram commit
	echo "已选定版本 $1"
	return 0
}

# ---------------------------------------------------------------------------
# 安装记录
# ---------------------------------------------------------------------------

et_read_state() {
	[ -f "$ET_VER_STATE" ] || return 1
	_ST_VER=$(sed -n '1p' "$ET_VER_STATE" 2>/dev/null)
	_ST_CORE=$(sed -n '2p' "$ET_VER_STATE" 2>/dev/null)
	_ST_CLI=$(sed -n '3p' "$ET_VER_STATE" 2>/dev/null)
	[ -n "$_ST_VER" ] && [ -n "$_ST_CORE" ] && [ -n "$_ST_CLI" ] || return 1
	return 0
}

et_write_state() {
	mkdir -p "$ET_DIR" 2>/dev/null
	printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$ET_VER_STATE" || return 1
	# ★ 600：里面是 /tmp 那份二进制的指纹，没必要让别的身份读
	chmod 600 "$ET_VER_STATE" 2>/dev/null
	return 0
}

# 指定路径的两个文件是否都合法。
# ★ 失败原因写进全局 ET_PO_REASON —— 与 easytier.sh 里 et_check_link 的
#   ET_CKREASON 同一套做法：返回码给判定，原因另走变量。
#   （界面要显示「为什么不通过」，只给 0/1 会把版本不一致说成「文件损坏」。）
ET_PO_REASON=""
et_paths_ok() {
	ET_PO_REASON=""

	# ① 固件内置那一份：指纹随固件钉死，与用户选的版本无关。
	#    ★ 必须【按路径】判定而不是按版本判定 —— 大闪存机型重启后 /tmp 清空，
	#      easytier.sh 会回落到 /usr/bin 那份，此时若拿「用户选的版本」去
	#      校验内置文件，会把一份完好的内置二进制报成「校验不通过」。
	if [ "$1" = "$ET_SYS_CORE" ]; then
		et_verify "$1" "$ET_CORE_SHA256" || { ET_PO_REASON="固件内置二进制校验失败"; return 1; }
		et_verify "$2" "$ET_CLI_SHA256"  || { ET_PO_REASON="固件内置二进制校验失败"; return 1; }
		return 0
	fi

	# ② /tmp 那一份：优先对照本机安装记录（记录里带着它自己的版本号）
	_sel=$(et_sel_ver)
	if et_read_state; then
		if [ "$_ST_VER" != "$_sel" ]; then
			ET_PO_REASON="已安装 $_ST_VER，与选中的 $_sel 不一致，请重新下载"
			return 1
		fi
		et_verify "$1" "$_ST_CORE" || { ET_PO_REASON="文件与安装记录不符，可能已损坏"; return 1; }
		et_verify "$2" "$_ST_CLI"  || { ET_PO_REASON="文件与安装记录不符，可能已损坏"; return 1; }
		return 0
	fi

	# ③ 没有安装记录：只有「选中的就是固件钉死版本」时才能回落到常量
	if [ "$_sel" = "$ET_DEF_VER" ]; then
		et_verify "$1" "$ET_CORE_SHA256" || { ET_PO_REASON="校验失败（对照固件钉死指纹）"; return 1; }
		et_verify "$2" "$ET_CLI_SHA256"  || { ET_PO_REASON="校验失败（对照固件钉死指纹）"; return 1; }
		return 0
	fi
	ET_PO_REASON="选中 $_sel 但没有本机安装记录，无法校验，请重新下载"
	return 1
}

et_installed_ok() {
	et_paths_ok "$ET_CORE" "$ET_CLI"
}

# ---------------------------------------------------------------------------
# 网络取数
# ---------------------------------------------------------------------------

# 取代理列表：nvram 覆盖优先。★ 注意「留空」与「没设」的区别 ——
# 没设（nvram 返回空串）走内置默认列表；显式设成 "-" 表示只用直连。
et_proxy_list() {
	_p=$(nvram get easytier_download_proxy 2>/dev/null)
	if [ -z "$_p" ]; then
		echo "$ET_PROXYS_DEFAULT"
	elif [ "$_p" = "-" ]; then
		echo ""
	else
		echo "$_p"
	fi
}

# 拉一个 URL 到指定文件。curl 优先（三机型都编了 CONFIG_FIRMWARE_INCLUDE_CURL），
# 回落 busybox wget。★ 都不带「关闭证书校验」的开关。
et_fetch() {
	_url="$1"
	_out="$2"
	rm -f "$_out"
	if type curl >/dev/null 2>&1; then
		# -f 让 HTTP 4xx/5xx 变成失败（否则会存下一个错误页，后面才知道是垃圾）
		curl -fL --connect-timeout 10 --retry 2 --retry-delay 2 \
			-o "$_out" "$_url" >/dev/null 2>&1
		[ -s "$_out" ] && return 0
		return 1
	fi
	if type wget >/dev/null 2>&1; then
		wget -q -T 10 -t 2 -O "$_out" "$_url" >/dev/null 2>&1
		[ -s "$_out" ] && return 0
		return 1
	fi
	et_log "错误：既没有 curl 也没有 wget，无法下载"
	return 1
}

# 直连优先，失败再逐个试代理。★ 这里【不】做任何完整性判断 ——
#   完整性一律由调用方随后的 sha256 负责（代理只影响可用性，不影响安全）。
et_fetch_any() {
	if et_fetch "$1" "$2"; then
		return 0
	fi
	for _fa_tpl in $(et_proxy_list); do
		_fa_url=$(echo "$_fa_tpl" | sed "s|{url}|$1|")
		et_log "尝试代理下载 $_fa_url"
		if et_fetch "$_fa_url" "$2"; then
			return 0
		fi
	done
	return 1
}

# 从 tags JSON 里取版本号，一行一个。
# ★ 必须精确匹配 vN.N.N 且整行只有这一个键 —— 嵌套的 commit 对象里没有 name 键
#   （实测 30 个标签的 "name" 全在同一缩进层），所以这条判据无歧义。
# ★ 不锚缩进：列表端点与单标签端点的缩进不同，锚缩进等于把解析器绑死在某一端点上。
et_parse_tags() {
	awk '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		line ~ /^"name": "v[0-9]+\.[0-9]+\.[0-9]+",$/ {
			s = line
			sub(/^"name": "/, "", s)
			sub(/",$/, "", s)
			print s
		}
	' "$1"
}

# 从 release JSON 里取某个资产名的 sha256。
# 输出： OK <hash> / NODIGEST / NOASSET
# ★ 必须锚在【恰好是 "name": "<文件名>", 的那一行】上。browser_download_url
#   里也含同样的文件名，从它往后扫会拿到【下一个】资产的 digest（静默取错）。
# ★ mips 与 mipsel 两个资产紧邻，名字只差 "el" ⇒ 必须整行相等，不能用子串。
et_parse_digest() {
	awk -v want="$2" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		line == "\"name\": \"" want "\"," { hit = 1; next }
		hit && !done && line ~ /^"digest": / {
			done = 1
			if (line ~ /^"digest": "sha256:/) {
				s = line; sub(/^"digest": "sha256:/, "", s); sub(/".*$/, "", s); print "OK " s
			} else { print "NODIGEST" }
			exit
		}
		END { if (!done) print "NOASSET" }
	' "$1"
}

# ---------------------------------------------------------------------------
# 版本列表（供界面下拉框）
# ---------------------------------------------------------------------------

# 打印可选版本列表，一行一个，新版本在前（顺序即官方 tags 的顺序）。
# ★ 缓存 1 小时：GitHub 匿名限额 60 次/小时，界面多点几次就会打满。
#   `versions force` 可强制刷新。
# ★ 解析出 0 个版本一律当【失败】报，绝不能把空列表当成「上游没有版本」——
#   被门户劫持 / 代理返回错误页都会走到这里，静默返回空会让界面显示空下拉框。
et_versions() {
	if [ "$1" != "force" ] && [ -f "$ET_VER_CACHE" ]; then
		_vt0=$(sed -n '1p' "$ET_VER_CACHE" 2>/dev/null)
		case "$_vt0" in ''|*[!0-9]*) _vt0=0 ;; esac
		if [ $(( $(date +%s) - _vt0 )) -lt "$ET_VER_TTL" ]; then
			sed -n '2,$p' "$ET_VER_CACHE"
			return 0
		fi
	fi

	rm -f "$ET_VER_RAW"
	if ! et_fetch_any "$ET_API/tags?per_page=30" "$ET_VER_RAW"; then
		echo "获取版本列表失败：网络不可达（直连与代理均失败）"
		return 1
	fi
	_vlist=$(et_parse_tags "$ET_VER_RAW")
	rm -f "$ET_VER_RAW"
	if [ -z "$_vlist" ]; then
		echo "获取版本列表失败：响应无法解析（可能被门户或代理劫持）"
		return 1
	fi
	{
		date +%s
		echo "$_vlist"
	} > "$ET_VER_CACHE"
	echo "$_vlist"
	return 0
}

# 取某个 tag 下 mipsel zip 的官方 sha256。成功则打到 stdout，失败打原因并返回 1。
# ★ 这是「非默认版本」唯一的可信指纹来源：API 走 TLS，等于 GitHub 亲口说
#   「这个 tag 的这个文件名对应这份字节」。
et_api_zip_sha256() {
	_av="$1"
	_an="$2"
	rm -f "$ET_REL_RAW"
	if ! et_fetch_any "$ET_API/releases/tags/$_av" "$ET_REL_RAW"; then
		echo "获取版本 $_av 的发布信息失败：网络不可达"
		return 1
	fi
	_ar=$(et_parse_digest "$ET_REL_RAW" "$_an")
	rm -f "$ET_REL_RAW"
	case "$_ar" in
		"OK "*)
			echo "${_ar#OK }"
			return 0
			;;
		NODIGEST)
			echo "版本 $_av 未提供官方 sha256 摘要（GitHub 只对较新版本提供），无法校验，拒绝安装"
			return 1
			;;
		*)
			echo "版本 $_av 的发布里找不到 $_an（该版本可能没有 mipsel 包）"
			return 1
			;;
	esac
}

# ---------------------------------------------------------------------------
# 下载
# ---------------------------------------------------------------------------

# 是否需要下载。不需要时把【原因】打到 stdout 并返回 1；需要则返回 0 且无输出。
# ★ 抽成独立函数是因为有两个消费方：et_download 自己，以及 easytier.sh 的
#   easytier_dl()（它要在起后台任务之前先告诉用户「无需下载」）。条件若在两边
#   各抄一份，版本选择一改就只会更新一份 ⇒ 症状是「选了 v2.7.0 却因内置二进制
#   被判无需下载」，静默且零报错。
# ★ 返回码给判定、原因走 stdout —— 与 et_check_link 的 ET_CKREASON、
#   et_paths_ok 的 ET_PO_REASON 同一套做法。
et_need_download() {
	_ver=$(et_sel_ver)
	# 已装且校验通过 ⇒ 不重复下。★ 这一步对非默认版本也成立：
	#   et_paths_ok 会拿安装记录里的版本号与「本次选中的版本」比对。
	if et_installed_ok; then
		echo "二进制已存在且校验通过（$_ver），无需下载"
		return 1
	fi
	# 固件内置机型（CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN=y）本来不需要下载。
	# ★ 只判存在、不判哈希：内置那份的完整性由固件镜像本身的校验保证，
	#   在设备上再算一次 6.4 MiB 的 sha256 要好几秒，收益为零。
	# ★ 但【指定了别的版本】时不能跳过 —— 那正是「用 /tmp 那份覆盖内置那份」
	#   的用法，而 et_resolve_bins 本来就优先 /tmp，下到 /tmp 即生效，
	#   不需要也不应该去动 /usr/bin。
	if [ -x "$ET_SYS_CORE" ] && [ "$_ver" = "$ET_DEF_VER" ]; then
		echo "固件已内置二进制，且未指定其他版本，无需下载"
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 解压到私有暂存目录：第一道闸门（整包 sha256）+ 解压 + 产物存在性检查。
#   $1 = zip 路径   $2 = 期望的整包 sha256
# 失败时清掉整个暂存目录并返回 1（原因由 et_log 写日志，本函数不往 stdout 打东西）。
# ★ 抽出来的理由：这段有 5 条错误路径，每条都是「记日志 + 清暂存 + return 1」，
#   留在 et_download 里会把「编排」和「解压细节」搅在一起。
# ---------------------------------------------------------------------------
et_unpack_stage() {
	_zip="$1"
	_zipsha="$2"
	_src=$ET_STAGE/x/$ET_ZIP_INNER

	# ---- 第一道闸门：整包校验 ----
	if ! et_verify "$_zip" "$_zipsha"; then
		rm -rf "$ET_STAGE"
		et_log "错误：zip 整包校验失败，已删除。下载源可能被劫持或版本不匹配"
		return 1
	fi
	et_log "zip 整包校验通过"

	# ---- 解压到私有暂存目录（保留目录前缀，不用 -j） ----
	if ! type unzip >/dev/null 2>&1; then
		et_log "错误：设备上没有 unzip，无法解压"
		rm -rf "$ET_STAGE"
		return 1
	fi
	# ★ 目标目录必须【先建出来】：busybox 的 unzip 不会自己创建 -d 指定的
	#   目录（GNU unzip 会）—— 不建就是 "can't change directory to ..."
	#   直接失败。Padavan 用的正是 busybox，所以这行是必需的，不是冗余防御。
	if ! mkdir -p "$ET_STAGE/x"; then
		et_log "错误：无法创建解压目录 $ET_STAGE/x"
		rm -rf "$ET_STAGE"
		return 1
	fi
	# ★ 不吞 stderr：上面那条 busybox 差异若被丢进 /dev/null，日志里只会剩
	#   一句「解压失败」，排查时完全看不出原因 —— 这个 bug 就是这么躲过一轮的。
	if ! _uerr=$(unzip -q -o "$_zip" -d "$ET_STAGE/x" 2>&1); then
		et_log "错误：解压失败 —— $(printf '%s' "$_uerr" | head -n 3 | tr '\n' ' ')"
		rm -rf "$ET_STAGE"
		return 1
	fi

	# 立刻删掉 zip 腾空间，后面的搬移只需要 8.94 MiB
	rm -f "$_zip"

	_src=$ET_STAGE/x/$ET_ZIP_INNER
	if [ ! -f "$_src/easytier-core" ] || [ ! -f "$_src/easytier-cli" ]; then
		et_log "错误：解压结果里找不到 easytier-core / easytier-cli"
		rm -rf "$ET_STAGE"
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 第二道闸门 + 安装 + 搬完复校 + 写安装记录。
#   $1 = 版本号（只用于日志与写记录）
# 前置：暂存目录里已有解压好的两个二进制，且 zip 整包摘要已通过。
# ★★ 还依赖调用方先设好两个【全局】变量（本文件的既有风格：函数间用 _ 前缀全局
#    变量传状态，shell 没有真正的局部变量）：
#      _core_sha / _cli_sha —— 默认版本时是固件常量（非空），用户指定版本时是空串。
#    本函数按「空/非空」分流走哪一道校验。少设一个就会被当成「用户指定版本」，
#    静默从「对照固件常量」退化成「只算一遍指纹记下来」—— 校验强度掉一档且不报错。
# ★ 抽出来的理由：这一段是「决定什么字节最终落到 $ET_CORE/$ET_CLI」的全部逻辑，
#   是安全上最该被单独看懂、单独测的一段，不该埋在下载编排的中间。
# ---------------------------------------------------------------------------
et_install_stage() {
	_ver="$1"
	_src=$ET_STAGE/x/$ET_ZIP_INNER

	# ---- 第二道闸门 ----
	if [ -n "$_core_sha" ]; then
		# 默认版本：逐个二进制与固件常量比对（最强的一道）
		if ! et_verify "$_src/easytier-core" "$_core_sha"; then
			rm -rf "$ET_STAGE"
			et_log "错误：easytier-core 校验失败，已删除，拒绝安装"
			return 1
		fi
		if ! et_verify "$_src/easytier-cli" "$_cli_sha"; then
			rm -rf "$ET_STAGE"
			et_log "错误：easytier-cli 校验失败，已删除，拒绝安装"
			return 1
		fi
		et_log "两个二进制校验均通过（对照固件钉死指纹）"
	else
		# 非默认版本：zip 摘要已通过 ⇒ 解出来的字节就是 GitHub 发布的那份。
		# 把实际指纹算出来记下，供后续 check 复用。
		_core_sha=$(et_sha256 "$_src/easytier-core")
		_cli_sha=$(et_sha256 "$_src/easytier-cli")
		if [ -z "$_core_sha" ] || [ -z "$_cli_sha" ]; then
			rm -rf "$ET_STAGE"
			et_log "错误：设备上没有 sha256sum / shasum，无法记录指纹，拒绝安装"
			return 1
		fi
		et_log "zip 摘要已通过；记录本版指纹 core=$_core_sha cli=$_cli_sha"
	fi

	# ---- 安装 ----
	# ★ 先删旧的再搬。只搬这两个精确路径的文件，暂存目录里其它东西一概不搬。
	mkdir -p "$ET_DIR" || { rm -rf "$ET_STAGE"; return 1; }
	rm -f "$ET_CORE" "$ET_CLI"
	cp "$_src/easytier-core" "$ET_CORE" || { rm -rf "$ET_STAGE"; return 1; }
	cp "$_src/easytier-cli"  "$ET_CLI"  || { rm -rf "$ET_STAGE"; return 1; }

	# ★ 700 而不是 755：这两个文件是 root 执行的特权二进制，
	#   没有任何理由让设备上其它身份读它或执行它。
	chmod 700 "$ET_CORE" "$ET_CLI"

	# 搬完再校验一次。★ 直接与【上面那对指纹】比 —— 对默认版本它是固件常量，
	#   对非默认版本它是暂存目录里那份的实际指纹，两种情形都恰好是
	#   「刚校验通过的那份字节」，所以这一步抓的正是 cp 过程本身的损坏
	#   （磁盘满是最常见的静默损坏原因），与版本无关。
	if ! et_verify "$ET_CORE" "$_core_sha" || ! et_verify "$ET_CLI" "$_cli_sha"; then
		rm -f "$ET_CORE" "$ET_CLI"
		rm -rf "$ET_STAGE"
		et_log "错误：安装后复校失败，已回滚删除"
		return 1
	fi

	# ★ 安装记录最后写：只有全部校验都过了它才会出现，
	#   所以「记录存在」本身就意味着「那两个文件是我们校验通过的那份」。
	if ! et_write_state "$_ver" "$_core_sha" "$_cli_sha"; then
		rm -f "$ET_CORE" "$ET_CLI"
		rm -rf "$ET_STAGE"
		et_log "错误：无法写入安装记录 $ET_VER_STATE，已回滚删除"
		return 1
	fi

	rm -rf "$ET_STAGE"
	et_log "安装完成：$ET_CORE / $ET_CLI（版本 $_ver，权限 700）"
	return 0
}

et_download() {
	# ★ 只问一次并把原因收下来 —— et_need_download 内部要算两个二进制的 sha256
	#   （6.7 MiB + 2.7 MiB，设备上要好几秒），问两遍等于白算一遍。
	if _nd=$(et_need_download); then
		: # 需要下载，继续往下走
	else
		et_log "$_nd"
		return 0
	fi

	_ver=$(et_sel_ver)
	_zipname="easytier-linux-${ET_ARCH}-${_ver}.zip"
	_zipurl="https://github.com/EasyTier/EasyTier/releases/download/${_ver}/${_zipname}"

	# 期望指纹：默认版本用固件常量（不联网）；其他版本先取官方摘要。
	# ★ 顺序很关键：摘要在下载 9 MB 之前取 ⇒ 版本号写错/该版本没有摘要时
	#   立刻失败，不浪费一次大文件下载。
	if [ "$_ver" = "$ET_DEF_VER" ]; then
		_zipsha=$ET_ZIP_SHA256
		_core_sha=$ET_CORE_SHA256
		_cli_sha=$ET_CLI_SHA256
		et_log "版本 $_ver（固件钉死），指纹取自固件常量"
	else
		if ! _zipsha=$(et_api_zip_sha256 "$_ver" "$_zipname"); then
			et_log "错误：$_zipsha"
			return 1
		fi
		# 非默认版本 API 只给 zip 的摘要，没有逐二进制摘要 ⇒ 两个二进制的
		# 指纹留空，下面改为「以 zip 摘要已通过为准，并记录实际指纹」。
		_core_sha=""
		_cli_sha=""
		et_log "版本 $_ver（用户指定），指纹取自官方 API：$_zipsha"
	fi

	# 空间预检：zip 8.94 MiB + 解压 8.94 MiB 同时存在，需要 ~18 MiB 峰值。
	# ★ Padavan 没有 /overlay，官方那句 `df -k | awk '/\/overlay$/'` 必然取空。
	_avail=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
	[ -z "$_avail" ] && _avail=0
	if [ "$_avail" -lt 20000 ]; then
		et_log "错误：/tmp 剩余 ${_avail}KB，不足 20000KB，放弃下载"
		return 1
	fi

	# 私有暂存目录。★ 绝不 `unzip -j -d /tmp` —— /tmp 是 1777 世界可写，
	# 解到根目录等于把「远端 zip 能覆盖哪些文件」的控制权交出去。
	rm -rf "$ET_STAGE"
	mkdir -p "$ET_STAGE" || return 1

	_zip=$ET_STAGE/$_zipname

	# 直连优先 + 代理回退（可用性兜底；完整性由下面的 sha256 保证）
	et_log "尝试直连下载 $_zipurl"
	if ! et_fetch_any "$_zipurl" "$_zip"; then
		et_log "错误：所有下载源均失败，请手动下载 $_zipname 后放到 $ET_STAGE/"
		rm -rf "$ET_STAGE"
		return 1
	fi

	# ---- 第一道闸门 + 解压 + 产物存在性 ----
	if ! et_unpack_stage "$_zip" "$_zipsha"; then
		return 1
	fi

	# ---- 第二道闸门 + 安装 + 复校 + 写记录 ----
	if ! et_install_stage "$_ver"; then
		return 1
	fi

	return 0
}

# ---------------------------------------------------------------------------

case "$1" in
	download)
		et_download
		;;
	check)
	# 可选参数：显式指定要校验的两个路径（$2=core $3=cli）。
	# ★ 为什么需要：大闪存机型把二进制编进了固件（/usr/bin），而本脚本的
	#   ET_CORE/ET_CLI 写死 /tmp —— easytier.sh 的 state 要校验「实际在用的
	#   那一份」，所以把路径传进来。不传则维持原行为（校验 /tmp 下那两个）。
	_chk_core="${2:-$ET_CORE}"
	_chk_cli="${3:-$ET_CLI}"
	if et_paths_ok "$_chk_core" "$_chk_cli"; then
		echo "OK  $_chk_core"
		echo "OK  $_chk_cli"
		exit 0
	fi
	# ★ 失败原因必须带出来：只回一句「校验不通过」会把「版本不一致」
	#   和「文件损坏」说成同一件事，界面只能给出误导性的下一步。
	echo "FAIL $ET_PO_REASON"
	exit 1
		;;
	selver)
	# 打印「用户选中的版本」；nvram 里没有或非法则打【空】（界面据此显示
	# 「跟随固件默认版本」）。★ 与 et_sel_ver 的区别：那个会回落到默认版本
	# （下载时用），这个不回落到 —— 界面要区分「用户明确选了」与「没选」。
	# ★ 界面【不】直接读 nvram 渲染：这个值是不可信输入（apply.cgi 只转发），
	#   让它在服务端拼进 HTML 等于开一个 XSS 面。经本脚本校验后再给，
	#   界面拿到的必定是 vN.N.N 形态的纯文本。
	_sv=$(nvram get easytier_version 2>/dev/null)
	if et_valid_ver "$_sv"; then
		echo "$_sv"
	fi
	;;
	setver)
	# 落盘本次要装的版本（界面「下载」按钮随命令携带）。不带参数 = 清除选择。
	# ★ 必须 shift：不 shift 的话「不带参数」会变成「传了一个空版本号」，
	#   走校验分支报「版本号非法」，而语义上不带参数是合法的清除动作。
	shift
	et_set_ver "$@"
	exit $?
		;;
	defver)
	# 打印固件钉死的默认版本。★ 供 easytier.sh 报「固件内置那份是什么版本」——
	#   内置那份没有安装记录（记录只记 /tmp 那份），curver 对它打空。
	echo "$ET_DEF_VER"
	;;
	needdl)
	# 供 easytier.sh 询问「点下载到底会不会真的下」。
	# ★ 不需要时原因走 stdout、退出码 1；需要时无输出、退出码 0 ——
	#   与 et_paths_ok/ET_PO_REASON、et_check_link/ET_CKREASON 同一套做法。
	et_need_download
	exit $?
		;;
	versions)
		et_versions "$2"
		;;
	curver)
	# 打印本机 /tmp 那份的版本；没有安装记录（例如固件内置机型）打空。
	# ★ 与 et_sel_ver 的区别：那个是「用户选了哪个」，这个是「实际装的是哪个」。
	if et_read_state; then
		echo "$_ST_VER"
	fi
		;;
	clean)
		rm -rf "$ET_STAGE"
		rm -f "$ET_VER_CACHE" "$ET_VER_RAW" "$ET_REL_RAW"
		et_log "已清理暂存目录 $ET_STAGE 与版本列表缓存"
		;;
	*)
	echo "用法: $0 {download|check|clean|versions|curver|defver|selver|setver|needdl} [core路径 cli路径]"
		;;
esac
