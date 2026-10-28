#!/bin/sh
# 用法: setwifi.sh <2gssid> <2gpwd> <5gssid> <5gpwd> <defaults.h> [board.h]
#
# 语义：传了值就按【宏名】改写 DEF_WLAN_2G_SSID / DEF_WLAN_5G_SSID /
#       DEF_WLAN_2G_PSK / DEF_WLAN_5G_PSK；没传就一个 #define 都不动。
#       defaults.h 与 board.h 都覆盖（board.h 会盖住 defaults.h）。
#
# ★ 旧实现用【绝对行号】（40s / 41s / 44s / 45s）—— 照上游 defaults.h 的 60 行版本写死。
#   commit 303108e3c 把 defaults.h 改成 81 行后行号整体位移，第 40/41 行变成 #endif 与
#   注释、44/45 行变成 DHCP 池的 #ifndef/#endif ⇒ 四条 sed 全部静默失效。
#   于是云编译传的 wifi2gssid=Padavan 从来没生效过，设备一直用板型出厂 SSID。
#
# ★ SSID 在 defaults.h 里是 BOARD_PID "_%s"（不是字符串字面量），所以这里替换【整行右值】，
#   而不是像 PSK 那样只换引号内的内容。DEF_WLAN_*_GSSID（访客网络）不在改写范围内。

wifi_2g_ssid=$1
wifi_2g_pwd=$2
wifi_5g_ssid=$3
wifi_5g_pwd=$4
defaultfile=$5
boardfile=$6

if [ ! -f "$defaultfile" ]; then
	echo "setwifi.sh: 找不到 $defaultfile" >&2
	exit 1
fi

# sed 替换串里 & 与 \ 有特殊含义，先转义，避免静默改成错值
esc() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }

# 宏的右值本来就是字符串字面量：只换引号内的内容
set_quoted() {
	_macro=$1
	_val=$(esc "$2")
	for _f in "$defaultfile" "$boardfile"; do
		[ -n "$_f" ] || continue
		[ -f "$_f" ] || continue
		sed -i "s|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*${_macro}[[:space:]][[:space:]]*\)\"[^\"]*\"|\1\"${_val}\"|" "$_f"
	done
}

# 宏的右值是表达式（BOARD_PID "_%s"）：整段右值替换成字符串字面量
set_expr() {
	_macro=$1
	_val=$(esc "$2")
	for _f in "$defaultfile" "$boardfile"; do
		[ -n "$_f" ] || continue
		[ -f "$_f" ] || continue
		sed -i "s|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*${_macro}[[:space:]][[:space:]]*\).*$|\1\"${_val}\"|" "$_f"
	done
}

if [ -n "$wifi_2g_ssid" ]; then
	set_expr DEF_WLAN_2G_SSID "$wifi_2g_ssid"
fi
if [ -n "$wifi_5g_ssid" ]; then
	set_expr DEF_WLAN_5G_SSID "$wifi_5g_ssid"
fi
if [ -n "$wifi_2g_pwd" ]; then
	set_quoted DEF_WLAN_2G_PSK "$wifi_2g_pwd"
fi
if [ -n "$wifi_5g_pwd" ]; then
	set_quoted DEF_WLAN_5G_PSK "$wifi_5g_pwd"
fi
