#!/bin/sh
# 构建期固件体积守卫：确认生成的 .trx 能整份塞进该板型 DTS 里 "firmware" 分区。
#
# 为什么需要这道闸门：
#   Padavan 的整个 rootfs 是【单个只读 squashfs】，没有 opkg、没有可写包覆盖层
#   ⇒ 固件必须是单个 .trx，且必须整份落在 DTS 的 firmware 分区内。
#   仓库里原本【没有任何】体积校验，超了照样"构建成功"，
#   产出的却是刷进去就起不来的砖（刷机走 mtd_write，按名字写 firmware 分区）。
#
# 用法: check_fw_size.sh <PRODUCT_ID> <trx> [trx2 ...]
# 退出码:
#   0 = 通过
#   1 = 超限（硬失败，调用方应中止发布）
#   2 = 无法判定（找不到板型目录 / DTB 名 / dts / firmware 分区）
#       —— 这种情况【不】阻断构建，只告警：守卫宁可漏报，也不能把好固件拦死。
#
# 环境变量: REPO_ROOT 可覆盖仓库根（默认由脚本位置推 ../../..）

set -u

PID="${1:-}"
if [ -z "$PID" ]; then
	echo "用法: $0 <PRODUCT_ID> <trx> [trx2 ...]" >&2
	exit 2
fi
shift

if [ "$#" -eq 0 ]; then
	echo "用法: $0 <PRODUCT_ID> <trx> [trx2 ...]" >&2
	exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

BOARD_DIR="$ROOT/trunk/configs/boards/$PID"
KCFG="$BOARD_DIR/kernel-4.4.x.config"
DTS_DIR="$ROOT/trunk/linux-4.4.x/arch/mips/boot/dts/ralink"

if [ ! -f "$KCFG" ]; then
	echo "⚠️  [size-guard] 找不到板型内核配置: $KCFG —— 跳过体积校验"
	exit 2
fi

# DTB 名由板型内核配置决定，不是由 target 名推出来的（两者未必同名）
DTB_NAME=$(sed -n 's/^CONFIG_RALINK_BUILTIN_DTB_NAME="\([^"]*\)"[[:space:]]*$/\1/p' "$KCFG" | head -n 1)
if [ -z "$DTB_NAME" ]; then
	echo "⚠️  [size-guard] $KCFG 里没有 CONFIG_RALINK_BUILTIN_DTB_NAME —— 跳过体积校验"
	exit 2
fi

DTS="$DTS_DIR/$DTB_NAME.dts"
if [ ! -f "$DTS" ]; then
	echo "⚠️  [size-guard] 找不到 DTS: $DTS —— 跳过体积校验"
	exit 2
fi

# firmware 分区可能在 dts 本身（小米两款是内联的），也可能在被它 #include 的
# *-layout.dtsi 里（GHL 走 mt7621-spi-32m-layout.dtsi）。这里只展开一层 include ——
# 仓库里所有 layout 都是这么组织的，实测 68 个 dts 全覆盖。
CAND="$DTS"
for inc in $(sed -n 's/^[[:space:]]*#include[[:space:]]*"\([^"]*\.dtsi\)".*/\1/p' "$DTS"); do
	[ -f "$DTS_DIR/$inc" ] && CAND="$CAND $DTS_DIR/$inc"
done

# 取 "firmware" 标签之后紧跟的那条 reg = <addr size>
FW_REG=$(awk '
	/label[[:space:]]*=[[:space:]]*"firmware"/ { hit=1; next }
	hit && /reg[[:space:]]*=[[:space:]]*</ {
		s = $0
		sub(/.*</, "", s)
		sub(/>.*/, "", s)
		n = split(s, a, /[[:space:]]+/)
		if (n >= 2) { print a[1], a[2]; exit }
	}
' $CAND | head -n 1)

if [ -z "$FW_REG" ]; then
	echo "⚠️  [size-guard] 在 $DTB_NAME.dts（含其 include）里找不到 firmware 分区 —— 跳过体积校验"
	exit 2
fi

FW_ADDR=${FW_REG% *}
FW_SIZE_HEX=${FW_REG#* }
case "$FW_SIZE_HEX" in
0x*|0X*) : ;;
*)
	echo "⚠️  [size-guard] firmware 分区 size 不是十六进制: $FW_SIZE_HEX —— 跳过体积校验"
	exit 2
	;;
esac
FW_SIZE=$((FW_SIZE_HEX))

# 统一按 B 比：web 升级的预检也是拿文件大小直接比分区大小（upload.c 的 get_mtd_size），
# 所以这里不加任何头部/对齐余量，比的就是同一对数。
rc=0
for trx in "$@"; do
	if [ ! -f "$trx" ]; then
		echo "⚠️  [size-guard] 找不到固件文件: $trx"
		if [ "$rc" != "1" ]; then rc=2; fi
		continue
	fi
	SZ=$(wc -c < "$trx" | tr -d "[:space:]")
	SZ_MIB=$(awk -v b="$SZ" 'BEGIN{printf "%.2f", b/1048576}')
	LIM_MIB=$(awk -v b="$FW_SIZE" 'BEGIN{printf "%.2f", b/1048576}')
	NAME=$(basename "$trx")
	if [ "$SZ" -gt "$FW_SIZE" ]; then
		OVER=$((SZ - FW_SIZE))
		OVER_MIB=$(awk -v b="$OVER" 'BEGIN{printf "%.2f", b/1048576}')
		echo "❌ [size-guard] $NAME  $SZ B ($SZ_MIB MiB) > firmware 分区 $FW_SIZE B ($LIM_MIB MiB)  超出 $OVER B ($OVER_MIB MiB)"
		echo "❌ [size-guard] $PID 的固件装不进 $FW_ADDR 起的 firmware 分区 —— 刷进去起不来，已中止发布"
		rc=1
	else
		SLACK=$((FW_SIZE - SZ))
		SLACK_MIB=$(awk -v b="$SLACK" 'BEGIN{printf "%.2f", b/1048576}')
		echo "✅ [size-guard] $NAME  $SZ B ($SZ_MIB MiB) <= firmware 分区 $FW_SIZE B ($LIM_MIB MiB)  余量 $SLACK B ($SLACK_MIB MiB)"
		# 余量不足 512 KiB 时提醒一句：下一轮加插件很可能就顶爆
		if [ "$SLACK" -lt 524288 ]; then
			echo "⚠️  [size-guard] 余量不足 512 KiB，再加插件会超限"
		fi
	fi
done

exit $rc
