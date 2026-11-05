#!/bin/sh
#
# 按 nvram 变量 tmp_size_mb 调整 /tmp（tmpfs）的容量上限。
#
# 本脚本是「界面点【扩大 /tmp】」与「开机恢复」两条路径的【唯一实现】，
# 目的就是避免两处各写一套阈值 —— 否则很容易出现「页面填 80M、重启后回落 50M」
# 这种两边不一致的经典问题（改造前 web_ex.c 里就是一处硬编码 50M）。
#
# 用法：
#   tmp_resize.sh            按 nvram 里的 tmp_size_mb 调整（开机路径）
#   tmp_resize.sh <MB>       按给定值调整（便于命令行排查）
#
# 语义：
#   tmp_size_mb 未设置 / 非纯数字  ⇒ 直接退出，【保持现状】。
#     开机路径下这意味着沿用 dev_init.sh 算出的自动值（24M；MemTotal >= 160000KB 的机型 50M），
#     也就是说：没有配置过的机器行为与改造前【逐字节一致】，零回归风险。
#     ★ 注意「保持现状」是字面意思：清空配置后 /tmp 不会当场缩回去，要到下次开机
#       才由 dev_init.sh 重新按自动规则挂载。这是有意的 —— 见下面「为什么不能直接缩」。
#
# ★★ 关于「调小」：tmpfs【不能】缩到比当前已用还小，这是内核的硬约束，不是本脚本的策略。
#   linux-4.4.x/mm/shmem.c 的 shmem_remount_fs() 头一件事就是
#       if (percpu_counter_compare(&sbinfo->used_blocks, config.max_blocks) > 0)
#               goto out;              /* error 保持 -EINVAL */
#   即「新上限 < 已用页数」时 remount 直接失败、一个字节都不改。
#   ⇒ 所以这里【先量已用、再抬到已用】，而不是让它去撞那个 EINVAL ——
#     撞上去的后果是「界面填 20、实际还是 50」且日志只有一句「失败」，
#     比抬上去更难解释。日志里把两个数都打出来，看到的就不是魔法。
#
# ★★ 量已用必须用 df，【不能】用 du：tmpfs 按 inode 引用计费，
#   被进程 fd 吊着的「已删除」inode 照样算进 used_blocks，而 du 遍历目录项、
#   对那种 inode 完全失明（实测差 80 倍）。用 du 会算出偏小的已用值，
#   于是又放行一个必然失败的 remount。
#

TMP_MNT=/tmp

# ---------- 1. 取目标值 ----------
if [ -n "$1" ]; then
	_mb="$1"
else
	_mb=$(nvram get tmp_size_mb)
fi

# 只接受纯数字。注意这里【不能用 command -v 之类的探测】：本设备 busybox 上
# command -v 返回 127，`[ ! command -v X ]` 是恒假的 rc=2，探测本身就会骗人。
case "$_mb" in
''|*[!0-9]*)
	exit 0
	;;
esac

# 去掉前导零：busybox 的 test 对 "016" 这种值的处理与十进制预期不一致，
# 与其赌它的行为，不如在这里就归一化成十进制字面量。
_mb=$(printf '%s\n' "$_mb" | sed -e 's/^0*//' -e 's/^$/0/')

# ---------- 2. 夹取范围 ----------
# 下限 16M：与 dev_init.sh 的 -l（低内存模式）取值一致，是本项目已经认可的可用值。
#   不设更高下限是有意的 —— 现在写满 /tmp 会明确报错（upload.c 会看 fwrite/fflush 返回值），
#   不再静默产短文件，所以「故意配小以省内存」是一个安全的合法选择，不该被工具拦掉。
[ "$_mb" -lt 16 ] && _mb=16

# 上限：不超过可用内存的 1/4，且硬顶 256M。
#   ★ 比的是 MemTotal 而不是标称容量 —— MemTotal 是【扣除内核与驱动预留之后】的值
#     （GHL 物理 512MB 只报 448076KB），拿标称值算会高估可用内存。
#   ★ 1/4 是「最坏情况下 tmpfs 最多吃掉多少 RAM」的预算：真把 /tmp 塞满时
#     仍有 3/4 留给转发面、代理进程与页缓存，不至于直接 OOM。
#   ★ 下限 50 是给 128MB 机型兜底的：那类机器 MemTotal/4 只有 30 左右，
#     但 50M 是改造前所有机型都能拿到的值，不能因为引入这个变量而变少。
_mem=0
while read _k _v _rest; do
	if [ "$_k" = "MemTotal:" ]; then
		_mem="$_v"
		break
	fi
done < /proc/meminfo
case "$_mem" in
''|*[!0-9]*) _mem=0 ;;
esac
if [ "$_mem" -gt 0 ]; then
	_cap=$(( _mem / 1024 / 4 ))
	[ "$_cap" -lt 50 ] && _cap=50
	[ "$_cap" -gt 256 ] && _cap=256
	# cap 与 floor 冲突时以 cap 为准 —— 取不到就宁可比用户要的小，也不能要得比内存还多
	if [ "$_mb" -gt "$_cap" ]; then
		_mb="$_cap"
	fi
fi

# ---------- 3. 不能缩到比「已用」还小 ----------
# 取整必须【向上】。内核比的是页数：已用 30.5MiB（7808 页）配 max_blocks=30MiB（7680 页）
# 就是 used > max ⇒ EINVAL。向下取整会把这种情况放进 mount，白失败一次。
# df 输出第 2 行是 /tmp 自己：Filesystem 1K-blocks Used Available Use% Mounted on
_df=$(df -k "$TMP_MNT" 2>/dev/null | awk 'NR==2 {print int(($3+1023)/1024)}')
case "$_df" in
''|*[!0-9]*) _df=0 ;;
esac
if [ "$_df" -gt 0 ] && [ "$_mb" -le "$_df" ]; then
	# 以已用为准，哪怕这会让结果超过上面算出的内存预算 ——
	# 预算的意义是「别主动要太多」，而不是「宁可 remount 失败也不许超过」。
	logger -t "tmp_resize" "请求 ${_mb}M 小于 /tmp 已用的 ${_df}M，内核不允许缩小，改按 ${_df}M 应用"
	_mb="$_df"
fi

# ---------- 4. 应用 ----------
if ! mount -t tmpfs -o remount,rw,size="${_mb}M" tmpfs "$TMP_MNT"; then
	logger -t "tmp_resize" "调整 /tmp 为 ${_mb}M 失败"
	exit 1
fi

logger -t "tmp_resize" "/tmp 容量已设为 ${_mb}M"

# ---------- 5. 把【实际生效值】写回 nvram ----------
# 目的：让界面上的输入框显示真实生效的值，而不是用户手打的原始值。
# 否则「填 999 → 实际 61」会让那个框长期显示一个不存在的数字，
# 下次点按钮时又拿它当输入，永远对不上。
#
# ★ 只在值确实变了才写，不无脑 commit —— 开机路径每次都会跑本脚本，
#   无条件写等于每次开机都擦写一次 nvram。
# ★ 开机路径实际上不会触发写：nvram 里的值要么来自上一次成功应用（已经过这里的夹取，
#   因而是可达的），要么为空（第 1 步就 exit 了）。唯一能让它变化的输入是
#   「已用」，而 autostart.sh 跑得很早、/tmp 基本是空的 ⇒ 收敛、不来回抖。
_cur=$(nvram get tmp_size_mb)
if [ "$_cur" != "$_mb" ]; then
	# 注意必须是 k=v 形式：本设备 nvram set 只认等号，
	# `nvram set k v` 会被静默当成 unset（把变量删掉，且返回 0）。
	nvram set tmp_size_mb="$_mb"
	nvram commit
	logger -t "tmp_resize" "实际生效值 ${_mb}M 已写回 nvram（原值 ${_cur:-空}）"
fi

exit 0
