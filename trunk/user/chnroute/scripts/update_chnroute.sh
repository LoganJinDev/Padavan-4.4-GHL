#!/bin/sh

# CHNRoute 列表更新
#
# 上游原版（备份见同目录 auto_baks/）用 `set -e -o pipefail` 且没有任何 trap：
#   * 第 15 行「开始更新」与第 28 行「更新完成」之间，mkdir / rm / curl / curl|awk /
#     mv / mtd_storage.sh save 任何一步失败，脚本都在中间直接退出；
#   * `set -e` 对失败的命令【一个字都不打印】；
#   * crontab 调用自带 `> /dev/null 2>&1`，stderr 也一并丢弃。
# 结果：这个脚本 100% 不可能报错，用户永远只看到「开始更新」那一行。
# （同源缺陷 update_gfwlist.sh 已于 2026-10-23 修复，此处按同一形态对齐。）
#
# 另外原版第 19 行的条件极性是反的：
#   `if [ -z "$CHNROUTE_URL" ]` —— URL 为空时拿【空串】去 curl（curl 直接非零退出，
#   配合 set -e 立刻静默死），而 URL 非空时（出厂默认就非空）反而忽略它、固定走 apnic。
#   也就是说界面上那个 ss_chnroute_url 输入框一直是摆设，改它没有任何效果。
# 本版改成 -n：URL 非空就用 URL，为空才回落到 apnic 官方数据。
#
# ⚠️ 极性修好之后 ss_chnroute_url 才【真正生效】，它的出厂默认值于是成了实际数据源。
#    实测 clang.cn 的两个变体覆盖并不等价（同一站点、同一生成器，只差文件名）：
#      all_cn.txt       (IPNetDB 版) 比 apnic 少 17.57% 的地址空间，含 1.3.0.0/16 等整块国内分配
#      all_cn_apnic.txt (APNIC 版)   与 apnic 直连转换【双向零缺口】(342,940,928 地址 / 4118 段)
#    故 shared/src/defaults.c 的默认值已一并改为 all_cn_apnic.txt，保证切换后国内覆盖不变。
#    注意：设备上已经写进 nvram 的旧值不受 defaults.c 影响，需要在界面上改成 _apnic 那个 URL。

NAME=chnroute
CHNROUTE_URL="$(nvram get ss_chnroute_url)"

log() {
	logger -t "$NAME" "$@"
	echo "$(date "+%Y-%m-%d %H:%M:%S") $@" >> "/tmp/ssrplus.log"
}

# 统一失败出口：任何失败都必须留下带【步骤名】的一行，否则又是一次静默死亡
die() {
	log "CHNRoute 更新失败：$1"
	rm -f /tmp/chinadns_chnroute.txt
	exit 1
}

# 未开启自动更新且不是强制调用时直接退出（AND-OR 列表，不再依赖 set -e）
if [ "$1" != "force" ] && [ "$(nvram get ss_update_chnroute)" != "1" ]; then
	exit 0
fi

log "CHNRoute 开始更新..."

[ -d /etc/storage/chinadns/ ] || mkdir -p /etc/storage/chinadns/ || die "创建 /etc/storage/chinadns/ 失败"
rm -f /tmp/chinadns_chnroute.txt

# 下载：URL 非空就用 URL，为空才回落到 apnic（原版极性写反了）
if [ -n "$CHNROUTE_URL" ]; then
	n=0
	while [ "$n" -lt 3 ]; do
		n=$((n + 1))
		curl -s -o /tmp/chinadns_chnroute.txt --connect-timeout 10 --retry 3 "$CHNROUTE_URL" && break
		[ "$n" -lt 3 ] && sleep 5
	done
	[ -s /tmp/chinadns_chnroute.txt ] || die "下载订阅失败（已重试 3 轮）：$CHNROUTE_URL"
else
	log "ss_chnroute_url 为空，回落到 APNIC 官方数据"
	curl -s --connect-timeout 10 --retry 3 http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest | \
		awk -F\| '/CN\|ipv4/ { printf("%s/%d\n", $4, 32-log($5)/log(2)) }' > /tmp/chinadns_chnroute.txt
	[ -s /tmp/chinadns_chnroute.txt ] || die "APNIC 数据下载或转换失败"
fi

# 条目数守卫：截断、空响应、以及把 HTML 错误页当数据存下来，都会让条数掉下来。
# 此时绝不能覆盖已有的好列表 —— china 列表不全正是「国内无法访问」的成因。
count=$(grep -c . /tmp/chinadns_chnroute.txt)
case "$count" in
	''|*[!0-9]*)	die "统计条目数失败（count=[$count]）" ;;
esac
[ "$count" -ge 1000 ] || die "下载内容异常，仅 $count 条（< 1000），保留原列表不覆盖"

mv -f /tmp/chinadns_chnroute.txt /etc/storage/chinadns/chnroute.txt || die "写入 /etc/storage/chinadns/chnroute.txt 失败"
mtd_storage.sh save >/dev/null 2>&1 || log "警告：mtd_storage.sh save 失败，chnroute 本次未持久化（重启后会丢失）"
log "CHNRoute 更新完成！共 $count 条"
echo 3 > /proc/sys/vm/drop_caches

# 列表变了要重建 china ipset，否则规则里还是旧集合。
# 注意用 if 而不是 `A && B || C`：后者在 A 为假时也会执行 C，会打出一条假的失败警告。
if [ -f /usr/bin/shadowsocks.sh ] && [ "$(nvram get ss_enable)" = "1" ] && [ "$(nvram get ss_run_mode)" = "router" ]; then
	/usr/bin/shadowsocks.sh restart >/dev/null 2>&1 || log "警告：shadowsocks.sh restart 失败，china ipset 仍是旧列表（重启路由器后生效）"
fi
