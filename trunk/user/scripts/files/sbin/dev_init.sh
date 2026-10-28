#!/bin/sh

mount -t proc proc /proc
mount -t sysfs sysfs /sys
[ -d /proc/bus/usb ] && mount -t usbfs usbfs /proc/bus/usb

size_tmp="24M"
size_var="4M"
size_etc="6M"

if [ "$1" == "-l" ] ; then
	size_tmp="8M"
	size_var="1M"
else
	# /tmp 默认 24M 对刷机不够用：固件包 25.25 MiB，Web 升级要先把整包写进 /tmp，
	# 24M 直接放不下 —— 每次刷机都得先去页面上手动「扩大 /tmp」到 50M 才行。
	# 这里按 MemTotal 自适应：内存富裕的机型给 50M，小内存机型维持 24M 不动。
	# ★ tmpfs 的 size= 是【上限】不是预分配，调大本身不占 RAM，只有真写进去才占，
	#   所以对内存富裕的机型没有代价。
	# ★★ 阈值为什么是 160000 而不是 262144（物理 256MB）：
	#    MemTotal 是【物理内存扣除内核与 WiFi 驱动预保留】之后的可用值，永远小于物理值。
	#    实测 GHL（物理 512MB）报 448076KB，即保留约 74MiB。
	#    旧值 262144 是拿物理值当门槛，256MB 机型永远达不到 ⇒ 静默退回 24M。
	#    而 24M 装不下整包：R3P 的固件分区就是 24MiB，包体按定义超过 24M。
	#    取值约束（两侧都要卡住）：
	#      下界 —— 必须高于任何 128MB 机型的 MemTotal 上限 131072（128MB 物理 ⇒ ≤131072），
	#              否则小内存机型会被误判成 50M；
	#      上界 —— 必须低于任何 256MB 机型的最坏 MemTotal：256MB 即便按 GHL 同比例
	#              保留 74MiB，仍有约 185000KB。
	#    160000 落在 (131072, 185000) 区间内，两侧都留了余量。
	# ★★ 这里【绝不能】写成 `awk ... 2>/dev/null` —— 本内核 CONFIG_DEVTMPFS is not set，
	#    开机时 /dev 还是 squashfs 里的只读目录（squashfs 存不了字符设备节点），
	#    /dev/null 要等本脚本【后面】把 tmpfs 挂到 /dev 并跑完 mdev -s 之后才诞生。
	#    而这段代码在那两件事【之前】—— 那个时点上 /dev/null 尚不存在，`2>/dev/null`
	#    重定向必然失败；重定向一失败，整条简单命令就【不执行】了，mem_total 会是空串，
	#    于是静默退回 24M（真机实证：同一段代码在当前环境跑得对，开机时却算不出 50M）。
	#    所以只用纯 shell 读 /proc/meminfo（/proc 在本脚本开头就挂好了）。
	#    循环体里只用内建命令（[ / 赋值 / break），不会吞掉 stdin。
	mem_total=0
	while read _k _v _rest; do
		if [ "$_k" = "MemTotal:" ]; then
			mem_total="$_v"
			break
		fi
	done < /proc/meminfo
	# 非数字 / 读不到 ⇒ 当 0 处理，走保守的 24M，别让 -ge 比较报错
	case "$mem_total" in
	''|*[!0-9]*) mem_total=0 ;;
	esac
	if [ "$mem_total" -ge 160000 ]; then
		size_tmp="50M"
	fi
fi

mount -t tmpfs tmpfs /dev   -o size=8K
mount -t tmpfs tmpfs /etc   -o size=$size_etc,noatime
mount -t tmpfs tmpfs /home  -o size=1M
mount -t tmpfs tmpfs /media -o size=8K
mount -t tmpfs tmpfs /mnt   -o size=8K
mount -t tmpfs tmpfs /tmp   -o size=$size_tmp
mount -t tmpfs tmpfs /var   -o size=$size_var

mkdir /dev/pts
mount -t devpts devpts /dev/pts

mount -t debugfs debugfs /sys/kernel/debug

ln -sf /etc_ro/mdev.conf /etc/mdev.conf
mdev -s

# create dirs
mkdir -p -m 777 /var/lock
mkdir -p -m 777 /var/locks
mkdir -p -m 777 /var/private
mkdir -p -m 700 /var/empty
mkdir -p -m 777 /var/lib
mkdir -p -m 777 /var/log
mkdir -p -m 777 /var/run
mkdir -p -m 777 /var/tmp
mkdir -p -m 777 /var/spool
mkdir -p -m 777 /var/lib/misc
mkdir -p -m 777 /var/state
mkdir -p -m 777 /var/state/parport
mkdir -p -m 777 /var/state/parport/svr_statue
mkdir -p -m 777 /tmp/var
mkdir -p -m 777 /tmp/hashes
mkdir -p -m 777 /tmp/modem
mkdir -p -m 777 /tmp/rc_notification
mkdir -p -m 777 /tmp/rc_action_incomplete
mkdir -p -m 700 /home/root
mkdir -p -m 700 /home/root/.ssh
mkdir -p -m 755 /etc/storage
mkdir -p -m 755 /etc/ssl
mkdir -p -m 755 /etc/Wireless
mkdir -p -m 750 /etc/Wireless/RT2860
mkdir -p -m 750 /etc/Wireless/iNIC

# mount cgroupfs if kernel provides cgroups
if [ -e /proc/cgroups ] && [ -d /sys/fs/cgroup ]; then
	if ! mountpoint -q /sys/fs/cgroup; then
		mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup
	fi
	(cd /sys/fs/cgroup
	for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
		mkdir -p $sys
		if ! mountpoint -q $sys; then
			if ! mount -n -t cgroup -o $sys cgroup $sys; then
				rmdir $sys || true
			fi
		fi
	done)
	if [ -e /sys/fs/cgroup/memory/memory.use_hierarchy ]; then
		echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy
	fi
fi

# extract storage files
mtd_storage.sh load

touch /etc/resolv.conf

if [ -f /etc_ro/openssl.cnf ]; then
	cp -f /etc_ro/openssl.cnf /etc/ssl
fi

# create symlinks
ln -sf /home/root /home/admin
ln -sf /proc/mounts /etc/mtab
ln -sf /etc_ro/ethertypes /etc/ethertypes
ln -sf /etc_ro/protocols /etc/protocols
ln -sf /etc_ro/services /etc/services
ln -sf /etc_ro/shells /etc/shells
ln -sf /etc_ro/profile /etc/profile
ln -sf /etc_ro/e2fsck.conf /etc/e2fsck.conf
ln -sf /etc_ro/ipkg.conf /etc/ipkg.conf

# tune linux kernel
echo 65536        > /proc/sys/fs/file-max
echo "1024 65535" > /proc/sys/net/ipv4/ip_local_port_range

# fill storage
mtd_storage.sh fill

# prepare ssh authorized_keys
if [ -f /etc/storage/authorized_keys ] ; then
	cp -f /etc/storage/authorized_keys /home/root/.ssh
	chmod 600 /home/root/.ssh/authorized_keys
fi

# setup htop default color
if [ -f /usr/bin/htop ]; then
	mkdir -p /home/root/.config/htop
	echo "color_scheme=6" > /home/root/.config/htop/htoprc
fi

# perform start script
if [ -x /etc/storage/start_script.sh ] ; then
	/etc/storage/start_script.sh
fi

