#!/bin/sh
#
# EasyTier 二进制下载器（Padavan 移植版）
#
# 用法： easytier_download.sh download|check|clean
#   download —— 下载并校验 easytier-core / easytier-cli 到 /tmp/easytier/
#   check    —— 只校验已存在的文件，不下载（可带参数：check <core路径> <cli路径>）
#   clean    —— 清掉下载缓存与暂存目录
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
#   `easytier-core -h | wc -l > 3` 当完整性判据   对二进制做 sha256 比对（钉死在
#                                              脚本内，不提供 nvram 覆盖）
#   curl -k / wget --no-check-certificate       不关闭 TLS 证书校验
#   unzip -j -d /tmp（解到世界可写的根目录）      解到私有暂存子目录 /tmp/easytier_dl，
#                                              再按精确路径搬走
#   chmod +x（755，任何本地用户可执行）           chmod 700（只有 root 能读能执行）
#   下载失败静默换下一个代理、无校验             校验不过 ⇒ 删文件 + 拒绝安装 + 返回 1
#
# ---------------------------------------------------------------------------
# 关于第三方加速代理
# ---------------------------------------------------------------------------
# 官方用了 4 个第三方 GitHub 加速站。代理能做的坏事是「替换二进制」，而 sha256
# 钉死之后这条路被堵死了 —— 代理无法伪造出哈希一致的字节。剩下的只是可用性风险
# （代理挂了 / 代理返回错误页），那表现为下载失败，不是安全问题。
# 所以本脚本保留代理做回退，但**顺序是直连优先**，且每一步之后都强制校验。
# 可用 nvram easytier_download_proxy 覆盖代理列表（留空 = 只用直连）。
#
set -f

ET_DIR=/tmp/easytier
ET_CORE=$ET_DIR/easytier-core
ET_CLI=$ET_DIR/easytier-cli
ET_STAGE=/tmp/easytier_dl
ET_LOG=/tmp/easytier.log

# ---------------------------------------------------------------------------
# 版本与指纹 —— 升级二进制就是改这三行，随固件一起发
# ---------------------------------------------------------------------------
# 上游发布物： easytier-linux-mipsel-v2.6.4.zip
#   zip 内只有两个文件，带 easytier-linux-mipsel/ 目录前缀，没有 web 控制台
#   （上游对 webconsole 声明 depends on !(mips||mipsel)）
ET_VER=v2.6.4
ET_ARCH=mipsel

# 全量 zip 的 sha256 —— 第一道闸门，挡住「解压出奇怪东西」这类问题
ET_ZIP_SHA256=7c93bcc9e9276f102b5299b0773941db7fd1d99ad04bac42b479a0d979ef5220

# 两个二进制的 sha256 —— 第二道闸门，也是真正决定「执行什么字节」的那一道
#   easytier-core 6687000 B
ET_CORE_SHA256=2ae281fb79b9026a00a4c9e5bfce6c007f155d919881d64c2a91795011d3a245
#   easytier-cli  2692152 B
ET_CLI_SHA256=b99664c7c956d5a16d708a32f9928955c0ed777ae7e1d9eeda986b623ff27de4

ET_ZIP_NAME=easytier-linux-${ET_ARCH}-${ET_VER}.zip
ET_ZIP_URL="https://github.com/EasyTier/EasyTier/releases/download/${ET_VER}/${ET_ZIP_NAME}"
ET_ZIP_INNER="easytier-linux-${ET_ARCH}"

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

# 指定路径的两个文件是否都合法。哈希常量是本文件私有的，集中在这一处，
# 调用方可以传任意路径（大闪存机型的二进制在 /usr/bin，不在 /tmp）。
et_paths_ok() {
	et_verify "$1" "$ET_CORE_SHA256" || return 1
	et_verify "$2" "$ET_CLI_SHA256" || return 1
	return 0
}

et_installed_ok() {
	et_paths_ok "$ET_CORE" "$ET_CLI"
}

# ---------------------------------------------------------------------------
# 下载
# ---------------------------------------------------------------------------

# 取代理列表：nvram 覆盖优先。★ 注意「留空」与「没设」的区别 ——
# 没设（nvram 返回空串）走内置默认列表；显式设成 "-" 表示只用直连。
et_proxy_list() {
	_p=$(nvram get easytier_download_proxy)
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

et_download() {
	if et_installed_ok; then
		et_log "二进制已存在且校验通过，跳过下载"
		return 0
	fi

	# 固件内置机型（CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN=y）根本不需要下载。
	# ★ 只判存在、不判哈希：内置那份的完整性由固件镜像本身的校验保证，
	#   在设备上再算一次 6.4 MiB 的 sha256 要好几秒，收益为零。
	if [ -x /usr/bin/easytier-core ]; then
		et_log "检测到固件内置二进制 /usr/bin/easytier-core，跳过下载"
		return 0
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

	_zip=$ET_STAGE/$ET_ZIP_NAME
	_ok=0

	# ① 直连
	et_log "尝试直连下载 $ET_ZIP_URL"
	if et_fetch "$ET_ZIP_URL" "$_zip"; then
		_ok=1
	fi

	# ② 代理回退（可用性兜底；完整性由下面的 sha256 保证）
	if [ "$_ok" != "1" ]; then
		for _tpl in $(et_proxy_list); do
			_purl=$(echo "$_tpl" | sed "s|{url}|$ET_ZIP_URL|")
			et_log "尝试代理下载 $_purl"
			if et_fetch "$_purl" "$_zip"; then
				_ok=1
				break
			fi
		done
	fi

	if [ "$_ok" != "1" ]; then
		et_log "错误：所有下载源均失败，请手动下载 $ET_ZIP_NAME 后放到 $ET_STAGE/"
		return 1
	fi

	# ---- 第一道闸门：整包校验 ----
	if ! et_verify "$_zip" "$ET_ZIP_SHA256"; then
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

	# ---- 第二道闸门：逐个二进制校验 ----
	if ! et_verify "$_src/easytier-core" "$ET_CORE_SHA256"; then
		rm -rf "$ET_STAGE"
		et_log "错误：easytier-core 校验失败，已删除，拒绝安装"
		return 1
	fi
	if ! et_verify "$_src/easytier-cli" "$ET_CLI_SHA256"; then
		rm -rf "$ET_STAGE"
		et_log "错误：easytier-cli 校验失败，已删除，拒绝安装"
		return 1
	fi
	et_log "两个二进制校验均通过"

	# ---- 安装 ----
	# ★ 先删旧的再搬。只搬这两个精确路径的文件，暂存目录里其它东西一概不搬。
	mkdir -p "$ET_DIR" || { rm -rf "$ET_STAGE"; return 1; }
	rm -f "$ET_CORE" "$ET_CLI"
	cp "$_src/easytier-core" "$ET_CORE" || { rm -rf "$ET_STAGE"; return 1; }
	cp "$_src/easytier-cli"  "$ET_CLI"  || { rm -rf "$ET_STAGE"; return 1; }

	# ★ 700 而不是 755：这两个文件是 root 执行的特权二进制，
	#   没有任何理由让设备上其它身份读它或执行它。
	chmod 700 "$ET_CORE" "$ET_CLI"

	# 搬完再校验一次（防止 cp 过程出错 —— 磁盘满是最常见的静默损坏原因）
	if ! et_installed_ok; then
		rm -f "$ET_CORE" "$ET_CLI"
		rm -rf "$ET_STAGE"
		et_log "错误：安装后复校失败，已回滚删除"
		return 1
	fi

	rm -rf "$ET_STAGE"
	et_log "安装完成：$ET_CORE / $ET_CLI（权限 700）"
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
	echo "FAIL 二进制缺失或校验不通过"
	exit 1
		;;
	clean)
		rm -rf "$ET_STAGE"
		et_log "已清理暂存目录 $ET_STAGE"
		;;
	*)
	echo "用法: $0 {download|check|clean} [core路径 cli路径]"
		;;
esac
