#!/bin/sh
# 批量探活全部节点。
#
# 调用方：httpd/src/web_ex.c 的 applydb_store()
#     doSystem("/etc_ro/ss/allping.sh")      —— 注意是【同步】的：httpd fork 后
# 一直等到本脚本退出才回 HTTP 响应，面板的「ping全部」按钮才会走 success 回调。
#
# 节点清单来自 dbus 变量名：ssconf_basic_json_<n>  →  取 <n>。
#   cut -d '_' -f 4 之后即使 JSON 值里含下划线也不影响：
#   第 4 段是 "1={...}"，再按 '=' 切一刀就只剩序号。
#
# 并发策略：每批 19 个后台并发，然后 sleep 10 秒等这一批跑完。
#   ⚠️ 这就是 ping.sh 必须把最坏路径压在 10 秒内的原因
#      （ICMP -w 3 秒 + TCP 兜底 -m 3 秒 = 6 秒 < 10 秒）。
#      改 ping.sh 的超时参数时必须回来复核这里。
#
# 批大小是 19（不是 20）：num 从 1 数到 19 是 19 次 ping，第 19 次之后才睡。

num=1
dbus list ssconf_basic_json | cut -d '_' -f 4 | cut -d '=' -f 1 > /tmp/dlinkping.txt
logger -t "SS" "开始ping全部节点,cpu使用率可能会短暂升高..."
while read line
do
	# ① 先 ping，再判断要不要睡。
	#    原实现是 if [ "$num" != "20" ] 才 ping，else 只 sleep —— 于是 num 到 20 的
	#    那一次迭代【既不 ping 也不重置】，$line 被整条丢掉：第 20 个节点永远拿不到
	#    新数据。而且重置写成 num=1 后紧接着 num=`expr $num + 1`，计数器永久错位一格，
	#    导致之后每隔 19 个又漏一个（实测漏 20、39、58…）。改成「先干活后计数」后
	#    每个节点都恰好被 ping 一次。
	# ② $line 加引号：值虽然来自 dbus 变量名（天然是数字），但不加引号就会走词分割与
	#    路径展开；ping.sh 内部也有纯数字守卫兜底，两道防线都在。
	# ③ < /dev/null 不能省：后台进程默认继承本 while 循环的 stdin（即 /tmp/dlinkping.txt），
	#    一旦它去读 stdin，后续迭代就再也 read 不到行 —— 表现为「只 ping 了前几个节点」。
	/etc_ro/ss/ping.sh "$line" >/dev/null 2>&1 < /dev/null &
	if [ "$num" -ge 19 ]; then
		sleep 10
		num=1
	else
		num=`expr $num + 1`
	fi
done < /tmp/dlinkping.txt
# ④ 等最后一批跑完再报「已ping完」。
#    否则最后一批最多 19 个 ping.sh 还在飞，本脚本就已经退出、httpd 立刻回响应、
#    面板 2 秒后刷新表格 —— 刷新时结果还没写回 dbus，用户看到的是上一轮的旧延迟，
#    而日志却说已经 ping 完了。wait 的代价有上界（≤ ping.sh 的 6 秒），换来日志与
#    面板数据都可信。
wait
logger -t "SS" "已ping完所有节点,延迟和丢包率仅供参考,实际以连接速度为准！"
