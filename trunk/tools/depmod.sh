#!/bin/sh
#
# ⚠️ 本脚本是树外内核模块（ipset 的 xt_set.ko + ipset/*.ko、antfs.ko）进入 romfs 的
# 【唯一】安装路径 —— 内核自带的 scripts/depmod.sh 只管树内模块，不会装这些。
# 它一旦静默半途而废，模块就静默缺失：用户态 /sbin/ipset 仍在（由 user/ipset 自己
# 的 romfs 规则安装），内核侧子系统却不在，于是 ss-rules 里所有 `-m set --match-set`
# 规则全部失败，只剩最后那条无条件兜底规则，结果【所有流量（含国内）一起走代理】。
#
# 历史上正是「下面两处 cp -f 完全没有错误检查、脚本也没有 set -e」让这个问题藏了
# 很久：源文件缺失时 cp 报错但脚本继续往下跑，退出码仍是 0，构建看起来完全成功。
# 所以这里让任何一步失败都直接中断构建（与 trunk/Makefile 的 romfs 产物校验一起
# 构成构建期双重保险）。
set -e

depmod_bin="/sbin/depmod"

# check env
if [ -z "${ROOTDIR}" ]; then
	echo "ROOTDIR is not set!"
	exit 1
fi

if [ -z "${KERNELRELEASE}" ]; then
	echo "KERNELRELEASE is not set!"
	exit 1
fi

if [ -z "${INSTALL_MOD_PATH}" ]; then
	echo "INSTALL_MOD_PATH is not set!"
	exit 1
fi

if [ ! -x "$depmod_bin" ]; then
	echo "$depmod_bin is not found! Please install package module-init-tools (kmod)"
	exit 1
fi

ipset_dir="${ROOTDIR}/build/ipset-7.11/kernel/net/netfilter"
moddir="${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/kernel/net/netfilter"

# 安装源必须先存在。缺了就是 ipset 压根没编译出来（CONFIG_FIRMWARE_INCLUDE_IPSET
# 不是 y，或 user/ipset 构建失败）。这里直接报错而不是静默跳过 —— 静默跳过的症状
# 是「用户态 ipset 在、内核侧不在」，极难定位。
if [ ! -f "$ipset_dir/xt_set.ko" ]; then
	echo "depmod.sh: ❌ 安装源不存在: $ipset_dir/xt_set.ko" >&2
	echo "depmod.sh:    请确认 CONFIG_FIRMWARE_INCLUDE_IPSET=y 且 user/ipset 已成功编译" >&2
	exit 1
fi
if ! ls "$ipset_dir/ipset/"*.ko >/dev/null 2>&1; then
	echo "depmod.sh: ❌ $ipset_dir/ipset/ 下没有任何 .ko（ipset 内核模块未编译）" >&2
	exit 1
fi

mkdir -p "${moddir}/ipset"
cp -f "$ipset_dir/xt_set.ko" "$moddir"
cp -f "$ipset_dir/ipset/"*.ko "${moddir}/ipset"

# cp 返回 0 不等于目标真的存在（磁盘满、权限、只读挂载都可能骗过它），
# 所以再断言一次产物。这一条就是「模块静默缺失」的最后一道拦截。
if [ ! -f "$moddir/xt_set.ko" ]; then
	echo "depmod.sh: ❌ xt_set.ko 未能安装到 $moddir" >&2
	exit 1
fi
if ! ls "${moddir}/ipset/"*.ko >/dev/null 2>&1; then
	echo "depmod.sh: ❌ ipset/*.ko 未能安装到 ${moddir}/ipset/" >&2
	exit 1
fi

if [ "$CONFIG_FIRMWARE_INCLUDE_ANTFS" = "y" ] ; then
	antfs_dir="${ROOTDIR}/build/antfs-07.19"
	if [ ! -f "$antfs_dir/antfs.ko" ]; then
		echo "depmod.sh: ❌ CONFIG_FIRMWARE_INCLUDE_ANTFS=y 但 $antfs_dir/antfs.ko 不存在" >&2
		exit 1
	fi
	mkdir -p "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/kernel/antfs"
	cp -f "$antfs_dir/"antfs.ko "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/kernel/antfs"
fi

# call depmod
if ! $depmod_bin -ae -F System.map -b "${INSTALL_MOD_PATH}" -r ${KERNELRELEASE}; then
	echo "depmod.sh: ❌ depmod 执行失败: $depmod_bin -ae -F System.map -b ${INSTALL_MOD_PATH} -r ${KERNELRELEASE}" >&2
	exit 1
fi

# depmod 的实质产物是 modules.dep（下面只删 .bin 等衍生文件，不删它本身）。
# 它不在就说明模块依赖表没建起来，模块按需加载会全部失败。
if [ ! -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.dep" ]; then
	echo "depmod.sh: ❌ depmod 未生成 modules.dep，模块将无法按需加载" >&2
	exit 1
fi

# clear unneeded depmod files
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.alias"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.alias.bin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.dep.bin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.devname"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.softdep"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.symbols"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.symbols.bin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.builtin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.builtin.bin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.builtin.alias.bin"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/modules.order"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/build"
rm -f "${INSTALL_MOD_PATH}/lib/modules/${KERNELRELEASE}/source"
