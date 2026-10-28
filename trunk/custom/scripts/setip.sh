#!/bin/sh
# 用法: setip.sh <lanip> <defaults.h> <CN.dict> [board.h]
#
# 语义：
#   lanip 非空 —— 按【宏名】改写 defaults.h 与 board.h 里的 DEF_LAN_ADDR /
#     DEF_LAN_DHCP_BEG / DEF_LAN_DHCP_END，并同步刷新 CN.dict 里的提示文案。
#   lanip 为空 —— 一个 #define 都不动，直接沿用板型默认值；此时只从 board.h
#     读出 DEF_LAN_ADDR 去刷新 CN.dict 提示文案，保证页面提示与实际地址一致。
#
# ★ 旧实现按【字面量 "192.168.2.1"】替换 —— 对任何在 board.h 里定义过
#   DEF_LAN_ADDR 的板型（GHL=192.168.9.1、MI-R3G=192.168.32.1、MI-R3P=192.168.31.1）
#   都是空操作：CI 传进来的 lanip 会被 board.h 里的写死值静默盖掉，且不报任何错。
#   所以改成按宏名改写，且 defaults.h 与 board.h 两个文件都覆盖 ——
#   board.h 的 #ifndef 守卫会盖住 defaults.h，只改一个就会出现「改了一半」的错地址。

lanip=$1
defaultfile=$2
dicfile=$3
boardfile=$4

if [ ! -f "$defaultfile" ]; then
	echo "setip.sh: 找不到 $defaultfile" >&2
	exit 1
fi
if [ ! -f "$dicfile" ]; then
	echo "setip.sh: 找不到 $dicfile" >&2
	exit 1
fi

# 从 board.h 取板型默认地址（取第一条；缩进容忍 1 个或多个空白）
board_lanip=""
if [ -n "$boardfile" ] && [ -f "$boardfile" ]; then
	board_lanip=$(sed -n 's/^[[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*DEF_LAN_ADDR[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' "$boardfile" | head -n 1)
fi

if [ -z "$lanip" ]; then
	# 没显式传地址 ⇒ 板型默认值就是当前生效地址，只用来刷新提示文案
	lanip=$board_lanip
	if [ -z "$lanip" ]; then
		echo "setip.sh: 未传 lanip，且 $boardfile 里没有 DEF_LAN_ADDR，沿用上游通用默认值，跳过"
		exit 0
	fi
	sed -i "s/192\.168\.2\.1/$lanip/g" "$dicfile"
	exit 0
fi

# 由 lanip 推出同网段的 DHCP 池
oc1=${lanip%%.*}
x=${lanip#*.*}
oc2=${x%%.*}
x=${x#*.*}
oc3=${x%%.*}
dhcpfrom=$oc1"."$oc2"."$oc3".100"
dhcpto=$oc1"."$oc2"."$oc3".244"

# 按宏名改写（不是按字面量）：默认值可能是任意网段，按字面量匹配必然漏
for f in "$defaultfile" "$boardfile"; do
	[ -n "$f" ] || continue
	[ -f "$f" ] || continue
	sed -i \
		-e 's|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*DEF_LAN_ADDR[[:space:]][[:space:]]*\)"[^"]*"|\1"'"$lanip"'"|' \
		-e 's|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*DEF_LAN_DHCP_BEG[[:space:]][[:space:]]*\)"[^"]*"|\1"'"$dhcpfrom"'"|' \
		-e 's|^\([[:space:]]*#[[:space:]]*define[[:space:]][[:space:]]*DEF_LAN_DHCP_END[[:space:]][[:space:]]*\)"[^"]*"|\1"'"$dhcpto"'"|' \
		"$f"
done

sed -i "s/192\.168\.2\.1/$lanip/g" "$dicfile"
