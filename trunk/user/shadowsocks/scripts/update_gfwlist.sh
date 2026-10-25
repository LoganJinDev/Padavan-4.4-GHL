#!/bin/sh

# GFWList 订阅更新
#
# 上游原版用 `set -e -o pipefail` 且没有任何 trap，而两条结果日志全都写在
# if 的成功分支里。后果是：mkdir / curl / lua / awk / rm / mv 任何一步失败，
# 脚本都会在「开始更新」与「更新完成」之间静默退出 ——
#   * set -e 对失败的命令【一个字都不打印】；
#   * cron 调用自带 `> /dev/null 2>&1`，stderr 也一并丢弃。
# 用户看到的就是「只有 GFWList 开始更新...，没有下文」。
# 2026-10-23 08:00:16 那次正是这个现象（开机 60 秒、代理栈启动 17 秒时触发；
# 11 分钟后用同样的 nvram 与 URL 手动执行则正常打出了「更新完成」）。
#
# 本版拆掉「静默」这个根因：每一步显式判返回码，失败就带【步骤名 + 返回码】
# 打一条结果日志再退出。裸 set -e 被去掉 —— 它无法告诉你死在哪一步。
# 下一次真出问题时，日志自己就会指明是哪一步，无需再靠推测。

NAME=shadowsocksr

log() {
	logger -t "$NAME" "$@"
	echo "$(date "+%Y-%m-%d %H:%M:%S") $@" >> "/tmp/ssrplus.log"
}

# 统一失败出口：保证任何路径都留下一条【带原因】的结果日志，并清理临时文件
die() {
	log "GFWList 更新失败：$1"
	rm -f /tmp/gfwlist_list_origin.conf /tmp/gfwlist_list.conf
	exit 1
}

# 非 force 调用且自动更新开关未开 → 静默退出（这是预期行为，不记日志）
if [ "$1" != "force" ] && [ "$(nvram get ss_update_gfwlist)" != "1" ]; then
	exit 0
fi

GFWLIST_URL="$(nvram get ss_gfwlist_url)"
[ -n "$GFWLIST_URL" ] || die "ss_gfwlist_url 为空"

log "GFWList 开始更新..."

[ -d /etc/storage/gfwlist/ ] || mkdir -p /etc/storage/gfwlist/ || die "创建 /etc/storage/gfwlist/ 失败"

# 开机早期 WAN 刚上线、代理栈刚起来时下载容易失败（订阅域名本身在 GFWList 里，
# 会被刚启动的隧道接管）。这里做 3 轮重试，每轮之间等 5 秒。
i=0
while [ $i -lt 3 ]; do
	i=$((i + 1))
	curl -s -o /tmp/gfwlist_list_origin.conf --connect-timeout 10 --retry 3 "$GFWLIST_URL" && break
	[ $i -lt 3 ] && sleep 5
done
# 判产物大小而不是只看 curl 返回码：0 字节的 200 也是废数据
[ -s /tmp/gfwlist_list_origin.conf ] || die "下载订阅失败（已重试 3 轮）"

lua /etc_ro/ss/gfwupdate.lua || die "gfwupdate.lua 执行失败（返回码 $?）"
[ -f /tmp/gfwlist_list.conf ] || die "gfwupdate.lua 未产出 /tmp/gfwlist_list.conf"

count=`awk '{print NR}' /tmp/gfwlist_list.conf|tail -n1`
[ -n "$count" ] || die "统计条目数失败"
if [ "$count" -gt 1000 ]; then
	rm -f /etc/storage/gfwlist/gfwlist_list.conf
	mv -f /tmp/gfwlist_list.conf /etc/storage/gfwlist/gfwlist_list.conf || die "落盘 gfwlist_list.conf 失败"
	# 持久化失败不算更新失败（文件已在 /etc/storage 里，本次生效），但重启会丢，必须出声
	mtd_storage.sh save >/dev/null 2>&1 || log "警告：mtd_storage.sh save 失败，gfwlist 本次不持久化（重启后会丢）"
	log "GFWList 更新完成！共 $count 条"
	echo 3 > /proc/sys/vm/drop_caches
	if [ "$(nvram get ss_enable)" = 1 ]; then
		# 重建 dnsmasq 规则失败不影响 gfwlist 本身，但分流会用到旧规则，要出声
		lua /etc_ro/ss/gfwcreate.lua || log "警告：gfwcreate.lua 执行失败，dnsmasq 规则未重建"
		log "正在重启 ShadowSocksR Plus..."
		/usr/bin/shadowsocks.sh stop
		/usr/bin/shadowsocks.sh start
	fi
else
	die "下载内容异常，条目数 $count ≤ 1000"
fi
rm -f /tmp/gfwlist_list_origin.conf
rm -f /tmp/gfwlist_list.conf
