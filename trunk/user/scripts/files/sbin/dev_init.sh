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
	# 这里按物理内存自适应：≥256MB 的机型给 50M，小内存机型维持 24M 不动。
	# ★ tmpfs 的 size= 是【上限】不是预分配，调大本身不占 RAM，只有真写进去才占，
	#   所以对内存富裕的机型没有代价。
	mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
	# 非数字 / 读不到 ⇒ 当 0 处理，走保守的 24M，别让 -ge 比较报错
	case "$mem_total" in
	''|*[!0-9]*) mem_total=0 ;;
	esac
	if [ "$mem_total" -ge 262144 ]; then
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

