#!/bin/sh
# 用法: setaccount.sh <account> <password> <defaults.h> [board.h]
#
# 语义：传了值就按【宏名】改写 SYS_USER_ROOT / DEF_ROOT_PASSWORD；
#       没传就一个 #define 都不动（沿用出厂默认值）。
#       defaults.h 与 board.h 都覆盖 —— board.h 的定义会盖住 defaults.h，
#       只改一个就会出现「改了一半」的错值。
#
# ★ 旧实现用【绝对行号】（28s / 47s）—— 那是照上游 defaults.h 的 60 行版本写死的。
#   commit 303108e3c 把 defaults.h 改成 81 行（插 #ifndef 守卫 + 注释块）后行号整体
#   位移，第 47 行变成 #endif ⇒ 密码替换静默失效（sed 不报错、退出码 0，只是什么都没干）。
#   按宏名匹配就不受行号位移影响。

account=$1
password=$2
defaultfile=$3
boardfile=$4

if [ ! -f "$defaultfile" ]; then
	echo "setaccount.sh: 找不到 $defaultfile" >&2
	exit 1
fi

# sed 替换串里 & 与 \ 有特殊含义，先转义，避免静默改成错值
esc() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }

# 只在【该文件确实定义了这个宏】时才改写；宏不存在时 sed 自然不匹配，等同不动
set_macro() {
	_macro=$1
	_val=$(esc "$2")
	for _f in "$defaultfile" "$boardfile"; do
		[ -n "$_f" ] || continue
		[ -f "$_f" ] || continue
		sed -i "s|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*${_macro}[[:space:]][[:space:]]*\)\"[^\"]*\"|\1\"${_val}\"|" "$_f"
	done
}

if [ -n "$account" ]; then
	set_macro SYS_USER_ROOT "$account"
fi
if [ -n "$password" ]; then
	set_macro DEF_ROOT_PASSWORD "$password"
fi
