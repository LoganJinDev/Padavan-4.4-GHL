#!/bin/sh
#
# RWFS 分区管理器（/proc/mtd 里名为 "RWFS" 的那一块 MTD，大闪存机型才有）。
#
# 用法：
#   rwfs2ubi.sh              等价于 ensure
#   rwfs2ubi.sh status       打印状态。首行/末行含 rwfs_state=<判决词>，其余人读。
#   rwfs2ubi.sh ensure       按 nvram 开关幂等挂载。只挂，不写 nvram，绝不格式化。
#   rwfs2ubi.sh enable       打开开关（nvram mtd_rwfs_mount=1）并当场挂载
#   rwfs2ubi.sh disable      卸载并关掉开关
#   rwfs2ubi.sh format yes   ★破坏性★ 擦除整块并重建 UBI 卷（第二个词必须是 yes）
#
# rwfs_state 的取值：mounted / unmounted / off / absent / error
#
# ★★ 为什么「无参数」从「格式化」改成「挂载」
#   旧版无参数时会无条件执行 mtd_write erase。而真机（MI-R3G）上这块 RWFS 是
#   【一块合法的 UBI 镜像，但卷表（layout volume）已经丢失】—— 实测 ubiattach
#   报 error 22 (Invalid argument)，内核 dmesg 逐字给出：
#       ubi10 error: ubi_read_volume_table: the layout volume was not found
#       ubi10 error: ubi_attach_mtd_dev: failed to attach mtd10, error -22
#   三处内核源码钉死了这个判决（既不是「没格式化」，也不是「偏移不对」）：
#     ① io.c:684  validate_ec_hdr() 会检查 vid_hdr_offset，不符就打印
#        "bad VID header offset" 并 dump_stack()。dmesg 里【没有】这一句
#        ⇒ 每个 PEB 的 EC 头都校验通过 ⇒ 内核用的就是 2048 这个偏移。
#     ② build.c:703  vid_hdr_offset 传 0 时默认取 ec_hdr_alsize = 2048
#        ⇒ ubiattach -O 2048 与默认行为完全等价，加了也没用。
#     ③ vtbl.c:795  ubi_find_av() 找不到 layout volume 且 ai->is_empty == 0
#        时直接 return -EINVAL（attach.c:1194：is_empty 只在坏块 <= 2 时才为 1）。
#        分区上有 36.5 MiB 数据 ⇒ 必然走这个分支。
#   ⇒ 结论：这块分区【结构上无法附加】，除非重建。里面那 36.5 MiB 是别的固件
#     留下的孤儿数据（残留串是 OpenWrt 的 luci-app-easytier / S99easytier /
#     zerotier.nft，Padavan 不用 luci），且镜像 lnum=386 > 本分区 296 个 PEB
#     ⇒ 当初是写给更大的分区的，几何一变卷表就废了。
#   ⇒ 但「要不要抹掉」是用户的决定，不是脚本的。所以默认路径只挂载；重建必须
#     由一个显式动词触发（format + 第二个词 yes + 界面上输入 yes 的二次确认）。
#
# ★ 空卷为什么能用（本设计不依赖 mkfs.ubifs —— 本固件里根本没有它）
#   ubimkvol 建出来的卷没有任何已映射的 LEB ⇒ mount_ubifs() 里
#   check_volume_empty() 置 c->empty = 1 ⇒ ubifs_read_superblock()（sb.c:542）
#   调 create_default_filesystem()，该函数的注释逐字就是
#   "format empty UBI volume"。⇒ 挂载这个动作本身就把空卷格式化成了可用的
#   空 UBIFS，所以「出厂空白机型开箱即可用」成立。
#
# ★ 判据纪律（本脚本只做「能证明该做」的事）
#   - ensure 永不格式化：分区里是空的还是满的，它都只挂载。
#   - format 先卸再擦：还挂着就拒绝，绝不隔着挂载点去擦底层设备。
#   - ★ 刻意【不做】「分区非空就拒绝格式化」这种守卫：用户点格式化，正是因为
#     分区里有东西。一个总在响的守卫等于没有守卫。真正的闸门是
#     「显式动词 format + 第二个词 yes + 界面上的二次确认」这三道。
#
# ★ 与 rc 里 mount_rwfs_partition()（rc/src/common_ex.c:658）的分工
#   rc 在开机时按同一个 nvram 键挂一次；本脚本是它的幂等补丁。rc 那次失败
#   （或还没跑到）时，autostart.sh 里那道 ensure 会补上，代价几十毫秒。

MP=/media/mtd_rwfs
NVRAM_KEY=mtd_rwfs_mount

log_msg() { logger -t rwfs "$*" 2>/dev/null; }
die() { echo "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 分区识别
# ---------------------------------------------------------------------------

# /proc/mtd 里 RWFS 那一行，形如： mtd10: 02500000 00020000 "RWFS"
rwfs_line() { grep '"RWFS"' /proc/mtd 2>/dev/null | head -n 1; }

# 解析出 RWFS_IDX / RWFS_SIZE / RWFS_ERASE（后两个单位是字节）。
# ★ 不用旧版的 `cut -c4-5` 按列切序号：那只在序号恰好两位时对，
#   mtd9 会切出 "9:"、mtd100 会切出 "10"（少一位）。按前缀剥才稳。
rwfs_info() {
	_l=$(rwfs_line)
	[ -n "$_l" ] || return 1
	# 靠单词拆分取三段：$1=mtd10:  $2=02500000  $3=00020000
	set -- $_l
	RWFS_IDX=$(echo "$1" | sed 's/^mtd//; s/:$//')
	RWFS_SIZE=$((0x$2))
	RWFS_ERASE=$((0x$3))
	[ -n "$RWFS_IDX" ] || return 1
	return 0
}

# ---------------------------------------------------------------------------
# 状态判定
# ---------------------------------------------------------------------------

rwfs_mounted() { grep -qs " $MP " /proc/mounts; }

# ★ 用 /sys 判「UBI 已附加」，不用 /dev 节点：内核那边的真相才是真相，
#   /dev 只是用户态的镜像（还慢半拍，见下面 rwfs_make_node 的注释）。
#   这和 rc 里 is_module_loaded() 查 /sys/module 是同一个道理。
rwfs_attached() { [ -d "/sys/class/ubi/ubi$RWFS_IDX" ]; }
rwfs_has_vol() { [ -d "/sys/class/ubi/ubi${RWFS_IDX}_0" ]; }

# 分区头 4 字节是不是 UBI 的幻数 "UBI#"（55 42 49 23）。
# ★ 这是「能不能安全格式化」的【唯一】判据：
#     是 UBI# ⇒ 分区里是 UBI 数据，抹掉就没了；
#     不是   ⇒ 空白或别的格式，抹掉不损失任何东西。
# ★ 用 hexdump 而不是 od：本机 BusyBox 里没有 od（rc=127），hexdump 在。
# ★ 只读 4 字节，代价可忽略。
rwfs_magic_is_ubi() {
	_m=$(dd if="/dev/mtd$RWFS_IDX" bs=4 count=1 2>/dev/null \
	     | hexdump -v -n 4 -e '4/1 "%02x"' 2>/dev/null)
	[ "$_m" = "55424923" ]
}

# 保证设备节点存在。
# ★ 为什么不是死代码：本机 /dev 是 size=8k 的 tmpfs，内核 config 里没有
#   CONFIG_DEVTMPFS ⇒ 节点全靠 hotplug（/proc/sys/kernel/hotplug = /sbin/mdev）
#   建。而 uevent 拉起 mdev 是【异步】的：ubiattach 返回时 mdev 可能还没跑完，
#   此刻 mount 会因为「设备不存在」而失败 —— 症状会被误读成「文件系统坏了」。
#   内核已通过 sysfs 给出主次设备号，自己建一个就绕开了这个竞态。
rwfs_make_node() {
	_dev=$1; _type=$2; _sys=$3
	[ -e "$_dev" ] && return 0
	[ -r "$_sys" ] || return 1
	_mm=$(cat "$_sys")
	mknod "$_dev" "$_type" "${_mm%%:*}" "${_mm#*:}" 2>/dev/null
	[ -e "$_dev" ]
}

# ---------------------------------------------------------------------------
# 动作
# ---------------------------------------------------------------------------

do_mount_now() {
	rwfs_mounted && return 0

	# ubi 在本机是内建的（CONFIG_MTD_UBI=y，内建模块不产 .ko，modprobe 必然
	# 失败）。所以先看 /sys，只有真不在才尝试加载，且失败不算错。
	[ -d /sys/module/ubi ] || modprobe ubi 2>/dev/null

	rwfs_attached || ubiattach -p "/dev/mtd$RWFS_IDX" -d "$RWFS_IDX" >/dev/null 2>&1

	if ! rwfs_attached; then
		echo "rwfs_state=error"
		# ★ 两种失败必须分开说 —— 出路完全不同。判据就是分区头的幻数。
		if rwfs_magic_is_ubi; then
			echo "附加失败：分区上是合法的 UBI 镜像，但它的卷表（layout volume）已丢失，"
			echo "内核报 ubi_read_volume_table: the layout volume was not found。"
			echo "这通常是别的固件写进去、之后分区几何变了留下的孤儿数据，结构上无法再挂上。"
			echo "★ 要恢复只能重建，而那会【永久抹掉】分区里的全部内容。"
		else
			echo "附加失败：分区头不是 UBI 幻数，说明它从没格式化过（或内容是别的格式）。"
			echo "★ 这种情况重建不会损失任何数据。"
		fi
		echo "确认后显式执行：rwfs2ubi.sh format yes"
		return 1
	fi

	# ★ 已附加但没有 0 号卷 ⇒ 自动建一个。为什么这一步安全且必需：
	#   - 已附加 ⇒ 分区有可用的卷表（内核要么找到了，要么对空白分区建了空卷表，
	#     见 vtbl.c:806 create_empty_lvol）。
	#   - UBI 保证卷之间绝不重叠，新卷只从未分配的 LEB 里取 ⇒ 建 0 号卷
	#     碰不到任何已有卷的数据。
	#   - 空卷挂上去时 UBIFS 会【自动格式化】（fs/ubifs/sb.c:542 →
	#     create_default_filesystem()）⇒ 不需要 mkfs.ubifs，本固件里也没有它。
	#   ⇒ 这是「出厂空白的大闪存机型开箱即可用」的唯一途径，且幂等
	#     （只在 0 号卷缺失时触发）。
	if ! rwfs_has_vol; then
		log_msg "RWFS 已附加但无 0 号卷，自动创建"
		rwfs_make_node "/dev/ubi$RWFS_IDX" c "/sys/class/ubi/ubi$RWFS_IDX/dev"
		ubimkvol "/dev/ubi$RWFS_IDX" -m -N rwfs >/dev/null 2>&1
		if ! rwfs_has_vol; then
			echo "rwfs_state=error"
			echo "UBI 已附加，但 0 号卷缺失且自动创建失败。"
			echo "要重建，请显式执行：rwfs2ubi.sh format yes"
			return 1
		fi
	fi

	mkdir -p "$MP"
	rwfs_make_node "/dev/ubi${RWFS_IDX}_0" b "/sys/class/ubi/ubi${RWFS_IDX}_0/dev"

	if mount -t ubifs "/dev/ubi${RWFS_IDX}_0" "$MP" 2>/dev/null; then
		log_msg "RWFS 已挂载到 $MP"
		echo "rwfs_state=mounted"
		echo "已挂载到 $MP。"
		return 0
	fi

	echo "rwfs_state=error"
	echo "挂载失败：/dev/ubi${RWFS_IDX}_0 存在，但内核拒绝了 UBIFS 挂载。"
	echo "要擦除并重建，请显式执行：rwfs2ubi.sh format yes"
	return 1
}
do_ensure() {
	if [ "$(nvram get $NVRAM_KEY)" != "1" ]; then
		echo "rwfs_state=off"
		echo "挂载开关（nvram $NVRAM_KEY）不是 1，未做任何事。"
		echo "要启用：rwfs2ubi.sh enable，或在管理界面点「启用持久存储」。"
		return 0
	fi

	if ! rwfs_info; then
		echo "rwfs_state=absent"
		echo "本机没有名为 RWFS 的 MTD 分区（小闪存机型正常如此），未做任何事。"
		return 0
	fi

	if rwfs_mounted; then
		echo "rwfs_state=mounted"
		echo "RWFS 已经挂在 $MP，未做任何事。"
		return 0
	fi

	do_mount_now
}

do_enable() {
	rwfs_info || die "本机没有 RWFS 分区，无法启用。"
	nvram set $NVRAM_KEY=1 && nvram commit
	do_mount_now
}

do_disable() {
	if rwfs_mounted; then
		umount "$MP" || die "卸载 $MP 失败（可能仍被占用），开关未改动。"
	fi
	nvram set $NVRAM_KEY=0 && nvram commit
	echo "rwfs_state=off"
	echo "已卸载并关闭挂载开关。"
	return 0
}

do_status() {
	if ! rwfs_info; then
		echo "rwfs_state=absent"
		echo "分区      : 本机没有名为 RWFS 的 MTD 分区（小闪存机型正常如此）"
		return 0
	fi

	echo "分区      : 存在（mtd$RWFS_IDX，$((RWFS_SIZE / 1024)) KiB，擦除块 $((RWFS_ERASE / 1024)) KiB）"
	if [ "$(nvram get $NVRAM_KEY)" = "1" ]; then
		echo "挂载开关  : 开"
	else
		echo "挂载开关  : 关"
	fi
	if rwfs_attached; then echo "UBI 附加  : 是"; else echo "UBI 附加  : 否"; fi
	# 未附加时顺带报一下分区头 —— 用户据此就能知道「格式化安不安全」。
	if ! rwfs_attached; then
		if rwfs_magic_is_ubi; then
			echo "分区内容  : 合法 UBI 但卷表已丢失 ⇒ 重建会毁掉里面约 $((RWFS_SIZE / 1048576)) MiB 内容"
		else
			echo "分区内容  : 非 UBI（空白或其它格式）⇒ 重建不损失数据"
		fi
	fi

	if rwfs_mounted; then
		echo "挂载点    : $MP（已挂载）"
		_av=$(df -k "$MP" 2>/dev/null | awk 'NR==2 {print $4}')
		_tot=$(df -k "$MP" 2>/dev/null | awk 'NR==2 {print $2}')
		case "$_av" in ''|*[!0-9]*) _av=0 ;; esac
		case "$_tot" in ''|*[!0-9]*) _tot=0 ;; esac
		echo "空间      : 共 $((_tot / 1024)) MiB，可用 $((_av / 1024)) MiB"
		echo "rwfs_state=mounted"
	else
		echo "挂载点    : $MP（未挂载）"
		if [ "$(nvram get $NVRAM_KEY)" = "1" ]; then
			echo "rwfs_state=unmounted"
		else
			echo "rwfs_state=off"
		fi
	fi
	return 0
}

do_format() {
	[ "$1" = "yes" ] || die "格式化会【擦除整块 RWFS 上的全部数据】。
确认要这么做，请显式执行：rwfs2ubi.sh format yes"

	# ★ 用 type 而不是 command -v：本机 BusyBox 没有 command -v（rc=127），
	#   写成 [ ! command -v X ] 会恒假，守卫静默失效。
	for _t in ubiattach ubidetach ubiformat ubimkvol mtd_write; do
		type "$_t" >/dev/null 2>&1 || die "缺少工具 $_t，已中止，未擦除任何数据。"
	done

	rwfs_info || die "本机没有 RWFS 分区。"

	if rwfs_mounted; then
		umount "$MP" 2>/dev/null
		rwfs_mounted && die "卸载 $MP 失败（仍被占用），已中止，未擦除任何数据。"
	fi

	ubidetach -p "/dev/mtd$RWFS_IDX" >/dev/null 2>&1

	echo "正在擦除 /dev/mtd$RWFS_IDX …"
	mtd_write erase "/dev/mtd$RWFS_IDX" || die "擦除失败，已中止。"
	ubiformat "/dev/mtd$RWFS_IDX" -y -q || die "ubiformat 失败，已中止。"
	ubiattach -p "/dev/mtd$RWFS_IDX" -d "$RWFS_IDX" || die "附加失败，已中止。"

	rwfs_make_node "/dev/ubi$RWFS_IDX" c "/sys/class/ubi/ubi$RWFS_IDX/dev"
	ubimkvol "/dev/ubi$RWFS_IDX" -m -N rwfs || die "建卷失败，已中止。"

	nvram set $NVRAM_KEY=1 && nvram commit

	if do_mount_now; then
		echo "已完成：RWFS 已重新格式化并挂载到 $MP。"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

case "$1" in
	''|ensure) do_ensure ;;
	status)   do_status ;;
	enable)   do_enable ;;
	disable)  do_disable ;;
	format)   do_format "$2" ;;
	*)
		echo "用法：rwfs2ubi.sh [status|ensure|enable|disable|format yes]" >&2
		echo "无参数 = ensure（幂等挂载，绝不格式化）。" >&2
		exit 1
		;;
esac
