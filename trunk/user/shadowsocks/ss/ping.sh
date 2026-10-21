#!/bin/sh
# 节点探活：ICMP 优先，TCP 兜底
#
# 原实现只用 ICMP。机场节点普遍在入口屏蔽 ICMP，导致所有机场节点
# 一律显示 failed（丢包 100%），而节点其实可用。
# 现在：ICMP 通就走 ICMP（自建节点，精度最高、不发多余请求）；
#       ICMP 不通则回落到 TCP 握手计时（机场节点）。
#
# 入参 $1 = 节点序号（对应 dbus 变量 ssconf_basic_json_<n>）
# 出参：调用 ssping.lua，把 ping / lost 写回该节点的 JSON

n=$1

# 节点号必须是非空纯数字：它会被拼进 dbus 变量名，也可能被当成选项。
# 调用方式：allping.sh 从 dbus list 的变量名里切出来（天然是数字），
# web_ex.c 用 doSystem("/etc_ro/ss/ping.sh %s", dbvar) 拼进来。
case "$n" in ''|*[!0-9]*) exit 0 ;; esac

# 自行解析 JSON 取 host 与 port。
# 不能复用 getconfig.lua —— 它只输出 server，拿不到 server_port。
j=`dbus get "ssconf_basic_json_$n"`
h=${j#*\"server\":\"}; h=${h%%\"*}
p=${j#*\"server_port\":\"}; p=${p%%\"*}

# ⚠️ 合法性校验：$h / $p 的来源是【节点 JSON】，而节点 JSON 由订阅导入写入
#    （dlink.lua 的 dbus set ssconf_basic_json_<n>，内容直接来自远端订阅 URL），
#    也就是说这两个值外部可控。
#
#    下面三处旧的调用点都是【不加引号】的：ping -4 $h ... / http://$h:$p
#    于是 $h 里的空白会被词分割成额外参数，且以 - 开头的值会被 ping/curl
#    当成【选项】—— 订阅里写 "server":"-f 1.2.3.4" 就等于让本机以 root 身份
#    发 flood ping 打攻击者指定的目标（路由器变 DoS 发射源）。这是真实攻击面。
#
#    两道防线：
#      ① 这里丢掉形态非法的值（空 / 以 - 开头 / 端口非数字）；
#      ② 下面所有引用点一律加引号 —— 加引号后词分割与路径展开都不再发生，
#         所以空白和通配符不再需要单独过滤，域名、IPv4、IPv6 字面量照常可用。
#    宁可这个节点显示 failed，也不能把畸形值喂给 root 权限的 ping/curl。
case "$h" in ''|-*) h="" ;; esac
case "$p" in ''|*[!0-9]*) p="" ;; esac

ping_time=""
ping_loss=""

# ---- 1) ICMP ----
# -c 3 -w 3：3 次探测、最多等 3 秒。
# 原为 -c 5 -w 5。缩短是因为 allping.sh 每 19 个节点才 sleep 10 秒，
# 而「ICMP 被屏蔽」正是机场节点的常见路径，得给它 + TCP 兜底留出余量
# （3 + 3 = 6 秒 < 10 秒）。
#
# ⚠️ 取值必须锚定到具体那一行（/round-trip/ 与 /packet loss/），
#    不能照抄上游的 awk -F '/' '{print $4}'：
#    ping -q 是多行输出，而 awk 是【逐行】打印 —— 没有分隔符的行 $4 为空，
#    于是每个非 round-trip 行都吐一个空行，拼出来是 "\n\n\n\n66"，
#    原样写进 JSON 就成了脏数据（面板上数字前面挂一串空行）。
#    上游之所以没露馅，是因为它写的是 echo $ping_text（不加引号），
#    靠 shell 词分割把换行压成空格，才恰好只剩一行。
#    这里不依赖词分割，显式按行内容取；丢包那一列的第二段 awk
#    也不能省 —— packet loss 行的 $3 是 "0% packet loss"，$1 才是 "0%"。
if [ -n "$h" ]; then
	txt=`ping -4 -c 3 -w 3 -q "$h" 2>/dev/null`
	ping_time=`echo "$txt" | awk -F '/' '/round-trip/{print $4}'`
	ping_loss=`echo "$txt" | awk -F ', ' '/packet loss/{print $3}' | awk '{print $1}'`
fi

if [ -n "$ping_time" ]; then
	ping_time=`echo "$ping_time" | sed 's/\..*//g'`
else
	# ---- 2) TCP 兜底 ----
	# %{time_connect} = 三次握手完成耗时（秒），换算成毫秒。
	#
	# 健康判据用 %{http_code} 而不是 shell 的 $?：
	#   · 000 = 一个字节 HTTP 响应都没收到，是明确的「死」哨兵；
	#   · $? 会被 shell 语义污染 —— 写成 echo "$(curl ...) $?" 时，
	#     $? 在参数展开阶段就被替换为展开前的状态，不是 curl 的。
	# 实测：TLS 端口用 http:// 连会回 400（抗封锁伪装站的正常反应），
	#       死端口回 000。故判据是「非 000 即活」，不是「必须是 200」。
	if [ -n "$h" ] && [ -n "$p" ]; then
		r=`curl -s -o /dev/null -w '%{http_code} %{time_connect}' --connect-timeout 2 -m 3 "http://$h:$p" 2>/dev/null`
		code=${r%% *}
		t=${r##* }
		if [ -n "$code" ] && [ "$code" != "000" ] && [ -n "$t" ]; then
			ping_time=`echo "$t" | awk '{printf "%d", $1 * 1000}'`
			ping_loss="0%"
		fi
	fi
fi

# ---- 3) 两条路都拿不到 → failed ----
if [ -z "$ping_time" ]; then
	ping_time="failed"
	[ -z "$ping_loss" ] && ping_loss="100%"
fi

lua /etc_ro/ss/ssping.lua "$ping_time" "$ping_loss" "$n"
