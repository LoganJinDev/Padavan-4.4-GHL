#!/bin/sh
#
# Copyright (C) 2017 openwrt-ssr
# Copyright (C) 2017 yushi studio <ywb94@qq.com>
# Copyright (C) 2018 lean <coolsnowwolf@gmail.com>
# Copyright (C) 2019 chongshengB <bkye@vip.qq.com>
# Copyright (C) 2022 TurBoTse <860018505@qq.com>
# Copyright (C) 2023 simonchen
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

NAME=shadowsocksr
pppoemwan=`nvram get pppoemwan_enable`
http_username=`nvram get http_username`
CONFIG_FILE=/tmp/${NAME}.json
CONFIG_UDP_FILE=/tmp/${NAME}_u.json
CONFIG_SOCK5_FILE=/tmp/${NAME}_s.json
v2_json_file="/tmp/v2-redir.json"
trojan_json_file="/tmp/tj-redir.json"
server_count=0
redir_tcp=0
v2ray_enable=0
redir_udp=0
tunnel_enable=0
local_enable=0
pdnsd_enable_flag=0
chinadnsng_enable_flag=0
wan_bp_ips="/tmp/whiteip.txt"
wan_fw_ips="/tmp/blackip.txt"
lan_fp_ips="/tmp/lan_ip.txt"
lan_gm_ips="/tmp/lan_gmip.txt"
run_mode=`nvram get ss_run_mode`
lan_con=`nvram get lan_con`
GLOBAL_SERVER=`nvram get global_server`
socks=""
SS_RULES=/usr/bin/ss-rules
[ -x /etc/storage/ss-rules ] && SS_RULES=/etc/storage/ss-rules

log() {
	logger -t "$NAME" "$@"
	echo "$(date "+%Y-%m-%d %H:%M:%S") $@" >> "/tmp/ssrplus.log"
}

find_bin() {
	case "$1" in
	ss) ret="/usr/bin/ss-redir" ;;
	ss-local) ret="/usr/bin/ss-local" ;;
	ssr) ret="/usr/bin/ssr-redir" ;;
	ssr-local) ret="/usr/bin/ssr-local" ;;
	ssr-server) ret="/usr/bin/ssr-server" ;;
	v2ray|xray)
		if [ -f "/usr/bin/$1" ]; then
			ret="/usr/bin/$1"
		else
			bin=$(echo -e "v2ray\nxray" | grep -v $1)
			ret="/usr/bin/$bin"
		fi
		;;
	trojan) ret="/usr/bin/trojan" ;;
	socks5) ret="/usr/bin/ipt2socks" ;;
	esac
	echo $ret
}

run_bin() {
	(if [ "$(nvram get ss_cgroups)" = "1" ]; then
	 	echo 0 > /sys/fs/cgroup/cpu/$NAME/tasks
	 	echo 0 > /sys/fs/cgroup/memory/$NAME/tasks
	 fi
	 "$@" > /dev/null 2>&1
	) &
}

cgroups_init() {
	if [ "$(nvram get ss_cgroups)" = "1" ]; then
		cpu_limit=$(nvram get ss_cgoups_cpu_s)
		mem_limit=$(nvram get ss_cgoups_mem_s)
		log "启用进程资源限制, CPU: $cpu_limit, 内存: $mem_limit"
		mkdir -p /sys/fs/cgroup/cpu/$NAME
		mkdir -p /sys/fs/cgroup/memory/$NAME
		echo $cpu_limit > /sys/fs/cgroup/cpu/$NAME/cpu.shares
		echo $mem_limit > /sys/fs/cgroup/memory/$NAME/memory.limit_in_bytes
		limit_bytes="$(cat /sys/fs/cgroup/memory/$NAME/memory.limit_in_bytes)"
		[ -n "$limit_bytes" ] && export GOMEMLIMIT="$limit_bytes"
	fi
}

cgroups_cleanup() {
	cat /sys/fs/cgroup/cpu/$NAME/tasks > /sys/fs/cgroup/cpu/tasks
	cat /sys/fs/cgroup/memory/$NAME/tasks > /sys/fs/cgroup/memory/tasks
	rmdir /sys/fs/cgroup/cpu/$NAME
	rmdir /sys/fs/cgroup/memory/$NAME
}

gen_config_file() {
	#fastopen="false"
	case "$2" in
	0) config_file=$CONFIG_FILE && local stype=$(nvram get d_type) ;;
	1) config_file=$CONFIG_UDP_FILE && local stype=$(nvram get ud_type) ;;
	*) config_file=$CONFIG_SOCK5_FILE && local stype=$(nvram get s5_type) ;;
	esac
	local type=$stype
	case "$type" in
	ss)
		lua /etc_ro/ss/genssconfig.lua $1 $3 >$config_file
		sed -i 's/\\//g' $config_file
		;;
	ssr)
		lua /etc_ro/ss/genssrconfig.lua $1 $3 >$config_file
		sed -i 's/\\//g' $config_file
		;;
	trojan)
		v2ray_enable=1
		if [ "$2" = "0" ]; then
			lua /etc_ro/ss/gentrojanconfig.lua $1 nat 1080 >$trojan_json_file
			sed -i 's/\\//g' $trojan_json_file
		else
			lua /etc_ro/ss/gentrojanconfig.lua $1 client 10801 >/tmp/trojan-ssr-reudp.json
			sed -i 's/\\//g' /tmp/trojan-ssr-reudp.json
		fi
		;;
	v2ray|xray)
		# 两种节点共用 genxrayconfig.lua：它按节点 type 字段自动分 vmess/vless 协议，
		# 并且带 routing 段（分流规则）、ACL、FakeDNS、REALITY 支持。
		# 旧版 genv2config.lua 不生成 routing，用它等于把分流规则整份丢掉 —— 已废弃。
		#
		# 分类小文本放在 /tmp/ss_rules（内存盘），重启后是空的。这里在生成配置之前
		# 把它从 flash 解回来，否则 genxrayconfig.lua 读不到 geosite_*/geoip_*.txt，
		# routing 段会退化成只剩兜底规则 —— 开机后分流静默失效，页面却看不出来。
		# 恢复是幂等的（已有内容就跳过），失败也不阻断，最多退回「没分类」的旧行为。
		[ -x /etc_ro/ss/xrayctl.sh ] && /etc_ro/ss/xrayctl.sh rules restore >/dev/null 2>&1
		v2ray_enable=1
		if [ "$2" = "1" ]; then
			lua /etc_ro/ss/genxrayconfig.lua $1 udp 1080 >/tmp/v2-ssr-reudp.json
			sed -i 's/\\//g' /tmp/v2-ssr-reudp.json
		else
			lua /etc_ro/ss/genxrayconfig.lua $1 tcp 1080 >$v2_json_file
			sed -i 's/\\//g' $v2_json_file
		fi
		;;
	esac
}

get_arg_out() {
	router_proxy="1"
	case "$router_proxy" in
	1) echo "-o" ;;
	2) echo "-O" ;;
	esac
}

start_rules() {
    log "正在添加防火墙规则..."
	lua /etc_ro/ss/getconfig.lua $GLOBAL_SERVER > /tmp/server.txt
	server=`cat /tmp/server.txt`
	rm -f /tmp/server.txt
	cat /etc/storage/ss_ip.sh | grep -v '^!' | grep -v "^$" >$wan_fw_ips
	cat /etc/storage/ss_wan_ip.sh | grep -v '^!' | grep -v "^$" >$wan_bp_ips
	#resolve name
	if echo $server | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then
		server=${server}
	elif [ "$server" != "${server#*:[0-9a-fA-F]}" ]; then
		server=${server}
	else
		server=$(resolveip -4 -t 3 $server | awk 'NR==1{print}')
		if echo $server | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then
			echo $server >/etc/storage/ssr_ip
		else
			server=$(cat /etc/storage/ssr_ip)
		fi
	fi
	local_port="1080"
	lan_ac_ips=$lan_ac_ips
	lan_ac_mode="b"
	#if [ "$GLOBAL_SERVER" == "$UDP_RELAY_SERVER" ]; then
	#	ARG_UDP="-u"
	if [ "$UDP_RELAY_SERVER" != "nil" ]; then
		ARG_UDP="-U"
		lua /etc_ro/ss/getconfig.lua $UDP_RELAY_SERVER > /tmp/userver.txt
		udp_server=`cat /tmp/userver.txt`
		rm -f /tmp/userver.txt
		udp_local_port="1080"
	fi
	if [ -n "$lan_ac_ips" ]; then
		case "$lan_ac_mode" in
		w | W | b | B) ac_ips="$lan_ac_mode$lan_ac_ips" ;;
		esac
	fi
	#ac_ips="b"
	gfwmode=""
	if [ "$run_mode" = "gfw" ]; then
		gfwmode="-g"
	elif [ "$run_mode" = "router" ]; then
		gfwmode="-r"
	elif [ "$run_mode" = "oversea" ]; then
		gfwmode="-c"
	elif [ "$run_mode" = "all" ]; then
		gfwmode="-z"
	fi
	if [ "$lan_con" = "0" ]; then
		rm -f $lan_fp_ips
		lancon="all"
		lancons="全部IP走代理..."
		cat /etc/storage/ss_lan_ip.sh | grep -v '^!' | grep -v "^$" >$lan_fp_ips
	elif [ "$lan_con" = "1" ]; then
		rm -f $lan_fp_ips
		lancon="bip"
		lancons="指定 IP 走代理: 请到规则管理页面添加需要走代理的 IP..."
		cat /etc/storage/ss_lan_bip.sh | grep -v '^!' | grep -v "^$" >$lan_fp_ips
	fi
	rm -f $lan_gm_ips
	cat /etc/storage/ss_lan_gmip.sh | grep -v '^!' | grep -v "^$" >$lan_gm_ips
	dports=$(nvram get s_dports)
	if [ $dports = "0" ]; then
		proxyport="--syn"
	else
		proxyport="-m multiport --dports 22,53,587,465,995,993,143,80,443,3389 --syn"
	fi
	$SS_RULES \
		-s "$server" \
		-l "$local_port" \
		-S "$udp_server" \
		-L "$udp_local_port" \
		-a "$ac_ips" \
		-i "" \
		-b "$wan_bp_ips" \
		-w "$wan_fw_ips" \
		-p "$lan_fp_ips" \
		-G "$lan_gm_ips" \
		-D "$proxyport" \
		-k "$lancon" \
		$(get_arg_out) $gfwmode $ARG_UDP
	return $?
}

start_redir_tcp() {
	ARG_OTA=""
	gen_config_file $GLOBAL_SERVER 0 1080
	stype=$(nvram get d_type)
	local bin=$(find_bin $stype)
	[ ! -f "$bin" ] && log "Main node:Can't find $bin program, can't start!" && return 1
	if [ "$(nvram get ss_threads)" = "0" ]; then
		threads=$(cat /proc/cpuinfo | grep 'processor' | wc -l)
	else
		threads=$(nvram get ss_threads)
	fi
	log "正在启动 $stype 服务器..."
	case "$stype" in
	ss | ssr)
		last_config_file=$CONFIG_FILE
		pid_file="/tmp/ssr-retcp.pid"
		for i in $(seq 1 $threads); do
			run_bin $bin -c $CONFIG_FILE $ARG_OTA -f /tmp/ssr-retcp_$i.pid
			usleep 500000
		done
		redir_tcp=1
		log "Shadowsocks/ShadowsocksR $threads 线程启动成功..."
		;;
	trojan)
		for i in $(seq 1 $threads); do
			run_bin $bin --config $trojan_json_file
			usleep 500000
		done
		log "已运行 $($bin --version 2>&1 | head -1)"
		;;
	v2ray)
		run_bin $bin -config $v2_json_file
		log "已运行 $($bin -version | head -1)"
		;;
	xray)
		run_bin $bin -config $v2_json_file
		log "已运行 $($bin -version | head -1)"
		;;	
	socks5)
		for i in $(seq 1 $threads); do
			run_bin lua /etc_ro/ss/gensocks.lua $GLOBAL_SERVER 1080
			usleep 500000
		done
		;;
	esac
	return 0
}

start_redir_udp() {
	if [ "$UDP_RELAY_SERVER" != "nil" ]; then
		redir_udp=1
		utype=$(nvram get ud_type)
		log "正在启动 $utype 游戏 UDP 中继服务器..."
		local bin=$(find_bin $utype)
		[ ! -f "$bin" ] && log "UDP TPROXY Relay:Can't find $bin program, can't start!" && return 1
		case "$utype" in
		ss | ssr)
			ARG_OTA=""
			gen_config_file $UDP_RELAY_SERVER 1 1080
			last_config_file=$CONFIG_UDP_FILE
			pid_file="/var/run/ssr-reudp.pid"
			run_bin $bin -c $last_config_file $ARG_OTA -U -f /var/run/ssr-reudp.pid
			;;
		v2ray)
			gen_config_file $UDP_RELAY_SERVER 1
			run_bin $bin -config /tmp/v2-ssr-reudp.json
			;;
		xray)
			gen_config_file $UDP_RELAY_SERVER 1
			run_bin $bin -config /tmp/v2-ssr-reudp.json
			;;	
		trojan)
			gen_config_file $UDP_RELAY_SERVER 1
			$bin --config /tmp/trojan-ssr-reudp.json >/dev/null 2>&1 &
			run_bin ipt2socks -U -b 0.0.0.0 -4 -s 127.0.0.1 -p 10801 -l 1080
			;;
		socks5)
			echo "1"
			;;
		esac
	fi
	return 0
}

stop_dns_proxy() {
	pgrep dns2tcp | args kill
	pgrep dnsproxy | args kill	
}

start_dns_proxy() {
	pdnsd_enable=$(nvram get pdnsd_enable) # 0: dnsproxy , 1: dns2tcp
	pdnsd_enable_flag=$pdnsd_enable
	dnsstr="$(nvram get tunnel_forward)"
	dnsserver=$(echo "$dnsstr" | awk -F '#' '{print $1}')
	if [ $pdnsd_enable = 1 ]; then
	    log "启动 dns2tcp：5353 端口..."
		# 将dnsserver (上游国外DNS: 比如 8.8.8.8) 放入ipset:gfwlist，强制走SS_SPEC_WAN_FW代理
		ipset add gfwlist $dnsserver 2>/dev/null
		dns2tcp -L"127.0.0.1#5353" -R"$dnsserver" >/dev/null 2>&1 &
	elif [ $pdnsd_enable = 0 ]; then
		log "启动 dnsproxy：5353 端口..."
		# 将dnsserver (上游国外DNS: 比如 8.8.8.8) 放入ipset:gfwlist，强制走SS_SPEC_WAN_FW代理
		ipset add gfwlist $dnsserver 2>/dev/null
		dnsproxy -d -p 5353 -R $dnsserver >/dev/null 2>&1 &
	else
		log "DNS解析方式不支持该选项: $pdnsd_enable , 建议选择dnsproxy"
	fi
}

start_dns() {
	echo "create china hash:net family inet hashsize 1024 maxelem 65536" >/tmp/china.ipset
	awk '!/^$/&&!/^#/{printf("add china %s'" "'\n",$0)}' /etc/storage/chinadns/chnroute.txt >>/tmp/china.ipset
	ipset -! flush china
	ipset -! restore </tmp/china.ipset 2>/dev/null
	rm -f /tmp/china.ipset
	start_chinadns() {
		ss_chdns=$(nvram get ss_chdns)
		if [ $ss_chdns = 1 ]; then
			chinadnsng_enable_flag=1
			local_chnlist_file='/etc/storage/chinadns/chnlist_mini.txt'
			if [ -f "$local_chnlist_file" ]; then
			  log "启动chinadns分流，仅国外域名走DNS代理..."
			  chinadns-ng -b 0.0.0.0 -l 65353 -c $(nvram get china_dns) -t 127.0.0.1#5353 -4 china -M -m $local_chnlist_file >/dev/null 2>&1 &
			else
			  log "启动chinadns分流，全部域名走DNS代理...本次不使用本地cdn域名文件$local_chnlist_file, 下次你自已可以创建它，文件中每行表示一个域名（不用要子域名）"
			  chinadns-ng -b 0.0.0.0 -l 65353 -c $(nvram get china_dns) -t 127.0.0.1#5353 -4 china >/dev/null 2>&1 &
			fi
			# adding upstream chinadns-ng 
			sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
			sed -i '/server=127.0.0.1/d' /etc/storage/dnsmasq/dnsmasq.conf
			cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#65353
EOF
		fi
		# dnsmasq optimization
		sed -i '/min-cache-ttl/d' /etc/storage/dnsmasq/dnsmasq.conf
		sed -i '/dns-forward-max/d' /etc/storage/dnsmasq/dnsmasq.conf
		cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
min-cache-ttl=1800
dns-forward-max=1000
EOF
		# restart dnsmasq
		killall dnsmasq
		/usr/sbin/dnsmasq >/dev/null 2>&1 &
	}
	case "$run_mode" in
	router)
		ipset add gfwlist $dnsserver 2>/dev/null
		# 不论chinadns-ng打开与否，都重启dns_proxy 
		# 原因是针对gfwlist ipset有一个专有的dnsmasq配置表（由ss-rule创建放在/tmp/dnsmasq.dom/gfwlist_list.conf)
		# 需要查询上游dns_proxy在本地5353端口
		stop_dns_proxy
		start_dns_proxy
		start_chinadns
	;;
	gfw)
		dnsstr="$(nvram get tunnel_forward)"
		dnsserver=$(echo "$dnsstr" | awk -F '#' '{print $1}')
		#dnsport=$(echo "$dnsstr" | awk -F '#' '{print $2}')
		ipset add gfwlist $dnsserver 2>/dev/null
		stop_dns_proxy
		start_dns_proxy
		start_chinadns
		log "开始处理 GFWList..."
		;;
	oversea)
		ipset add gfwlist $dnsserver 2>/dev/null
		mkdir -p /etc/storage/dnsmasq.oversea
		sed -i '/dnsmasq-ss/d' /etc/storage/dnsmasq/dnsmasq.conf
		sed -i '/dnsmasq.oversea/d' /etc/storage/dnsmasq/dnsmasq.conf
		cat >>/etc/storage/dnsmasq/dnsmasq.conf <<EOF
conf-dir=/etc/storage/dnsmasq.oversea
EOF
;;
	*)
		ipset -N ss_spec_wan_ac hash:net 2>/dev/null
		ipset add ss_spec_wan_ac $dnsserver 2>/dev/null
	;;
	esac
	/sbin/restart_dhcpd
}

# 广告过滤：下载规则文件并落盘到 /tmp/dnsmasq.dom/anti-ad-for-dnsmasq.conf
# ★ 调用点在 ssp_start 之前（见文件末尾的 case start），而 dnsmasq 的重启发生在
#   ssp_start 之内（start_dns → start_chinadns → restart_dhcpd）⇒ 文件先落地、后加载。
#   所以「开关打开没效果」只有两个硬前提：① ss_enable=1（否则整条链不跑）；
#   ② start_redir_tcp 成功（否则走不到 start_dns，文件写了但 dnsmasq 不重启）。
start_AD() {
	mkdir -p /tmp/dnsmasq.dom
	ad_url="$(nvram get ss_adblock_url)"

	# 形态守卫。这个值来自网页输入框，最终会进 curl 的参数列表。
	# ★ 必须挡「以 - 开头」：`curl ... "$URL"` 里 $URL 虽然加了引号、不会发生词分割，
	#   但 curl 收到单个 argv "-o/etc/storage/x" 时会把它当成写文件选项 ——
	#   引号挡不住，因为它本来就是一个合法 argv。（同 ssrcrules_update.sh 的 url_ok()）
	case "$ad_url" in
	''|*[![:print:]]*|*[[:space:]]*|-*)
		log "广告过滤：下载地址为空或含空白/控制字符，已跳过本次下载"
		return 1
		;;
	esac

	rm -f /tmp/adnew.conf /tmp/adnew.conf.conv
	# --fail：HTTP 4xx/5xx 直接算失败。否则 404 的错误页 / 门户认证页会被当规则存下来。
	# --max-time：原代码只有 --connect-timeout，挡不住「连上了但一直不发数据」。
	#   60s × (1 + 2 次重试) = 本次下载的最坏耗时上限，同时给 httpd 的同步阻塞划了界。
	if ! curl -s -f -o /tmp/adnew.conf --connect-timeout 10 --max-time 60 --retry 2 "$ad_url"; then
		log "广告过滤：规则下载失败（网络异常或地址失效），保留原有规则不覆盖"
		rm -f /tmp/adnew.conf
		return 1
	fi

	# 内容合法性：curl 的 -o 在传输【之前】就建文件 ⇒ 单看「文件存在」恒为真
	# （原代码的 [ ! -f ] 分支因此永远不可达，连接失败也照样打「下载成功」）。
	# 这里既看格式也看条数：被截断的半成品同样要挡掉，不能覆盖已有的好规则。
	#
	# ★ 格式判据必须是 '^address=/' 而不是 '^address='（实测两个官方规则文件的头部）：
	#   dnsmasq 版 anti-ad-for-dnsmasq.conf → `address=/000491b06a.com/`
	#   SmartDNS 版 anti-ad-for-smartdns.conf → `address /000491b06a.com/#`（空格分隔 + 结尾 #）
	#   两者【不通用】。松判据 '^address=' 挡不住空格形态的文件，而 dnsmasq 遇到无法
	#   解析的 conf 行会【直接拒绝启动】⇒ 一旦 SmartDNS 版文件被丢进 conf-dir，
	#   整个 DNS 都会挂。所以这里必须严判：宁可真规则被拒，也不能放进坏行。
	ad_cnt=$(grep -c '^address=/' /tmp/adnew.conf 2>/dev/null)
	if [ "${ad_cnt:-0}" -ge 100 ]; then
		cp /tmp/adnew.conf /tmp/dnsmasq.dom/anti-ad-for-dnsmasq.conf
	else
		# 不是 dnsmasq 原生格式 ⇒ 可能是 ABP 格式（||domain^），转换后再判一次。
		# ★ 原代码这一段是死代码：`check = \`grep -wq ...\`` 等号带空格 ⇒ shell 把
		#   check 当命令执行，且 -q 抑制输出 ⇒ $check 恒为空 ⇒ 永远走 cp 分支。
		grep '^||[^*]*\^$' /tmp/adnew.conf 2>/dev/null \
			| sed -e 's:||:address=/:; s:\^:/0.0.0.0:' > /tmp/adnew.conf.conv
		ad_cnt=$(grep -c '^address=/' /tmp/adnew.conf.conv 2>/dev/null)
		if [ "${ad_cnt:-0}" -lt 100 ]; then
			log "广告过滤：下载到的内容不是规则文件（仅 ${ad_cnt:-0} 条），已放弃，保留原有规则"
			rm -f /tmp/adnew.conf /tmp/adnew.conf.conv
			return 1
		fi
		mv /tmp/adnew.conf.conv /tmp/dnsmasq.dom/anti-ad-for-dnsmasq.conf
	fi
	rm -f /tmp/adnew.conf /tmp/adnew.conf.conv
	log "广告过滤已启用：共 $ad_cnt 条规则"
	return 0
}

# ========== 启动 Socks5 代理 ==========
start_local() {
	local s5_port=$(nvram get socks5_port)
	local local_server=$(nvram get socks5_enable)
	[ "$local_server" == "nil" ] && return 1
	[ "$local_server" == "same" ] && local_server=$GLOBAL_SERVER
	local type=$(nvram get s5_type)
	local bin=$(find_bin $type)
	[ ! -f "$bin" ] && log "Global_Socks5:Can't find $bin program, can't start!" && return 1
	case "$type" in
	ss | ssr)
		local name="Shadowsocks"
		local bin=$(find_bin ss-local)
		[ ! -f "$bin" ] && log "Global_Socks5:Can't find $bin program, can't start!" && return 1
		[ "$type" == "ssr" ] && name="ShadowsocksR"
		gen_config_file $local_server 3 $s5_port
		run_bin $bin -c $CONFIG_SOCK5_FILE -u -f /var/run/ssr-local.pid
		log "Global_Socks5:$name Started!"
		;;
	v2ray|xray)
		# 同 gen_config_file：两种节点共用 genxrayconfig.lua（按节点 type 自动分 vmess/vless）
		lua /etc_ro/ss/genxrayconfig.lua $local_server tcp 0 $s5_port >/tmp/v2-ssr-local.json
		sed -i 's/\\//g' /tmp/v2-ssr-local.json
		run_bin $bin -config /tmp/v2-ssr-local.json
		log "Global_Socks5:$($bin -version | head -1) Started!"
		;;
	trojan)
		lua /etc_ro/ss/gentrojanconfig.lua $local_server client $s5_port >/tmp/trojan-ssr-local.json
		sed -i 's/\\//g' /tmp/trojan-ssr-local.json
		run_bin $bin --config /tmp/trojan-ssr-local.json
		log "Global_Socks5:$($bin --version 2>&1 | head -1) Started!"
		;;
	*)
		[ -e /proc/sys/net/ipv6 ] && local listenip='-i ::'
		run_bin microsocks $listenip -p $s5_port ssr-local
		log "Global_Socks5:$type Started!"
		;;
	esac
	local_enable=1
	return 0
}

rules() {
	[ "$GLOBAL_SERVER" = "nil" ] && return 1
	UDP_RELAY_SERVER=$(nvram get udp_relay_server)
	if [ "$UDP_RELAY_SERVER" = "same" ]; then
		UDP_RELAY_SERVER=$GLOBAL_SERVER
	fi
	if start_rules; then
		return 0
	else
		return 1
	fi
}

start_watchcat() {
	if [ $(nvram get ss_watchcat) = 1 ]; then
		let total_count=server_count+redir_tcp+redir_udp+tunnel_enable+v2ray_enable+local_enable+pdnsd_enable_flag+chinadnsng_enable_flag
		if [ $total_count -gt 0 ]; then
			#param:server(count) redir_tcp(0:no,1:yes)  redir_udp tunnel kcp local gfw
			/usr/bin/ss-monitor $server_count $redir_tcp $redir_udp $tunnel_enable $v2ray_enable $local_enable $pdnsd_enable_flag $chinadnsng_enable_flag >/dev/null 2>&1 &
		fi
	fi
}

auto_update() {
	sed -i '/update_chnroute/d' /etc/storage/cron/crontabs/$http_username
	sed -i '/update_gfwlist/d' /etc/storage/cron/crontabs/$http_username
	sed -i '/ss-watchcat/d' /etc/storage/cron/crontabs/$http_username
	if [ $(nvram get ss_update_chnroute) = "1" ]; then
		cat >>/etc/storage/cron/crontabs/$http_username <<EOF
0 7 * * * /usr/bin/update_chnroute.sh > /dev/null 2>&1
EOF
	fi
	if [ $(nvram get ss_update_gfwlist) = "1" ]; then
		cat >>/etc/storage/cron/crontabs/$http_username <<EOF
0 8 * * * /usr/bin/update_gfwlist.sh > /dev/null 2>&1
EOF
	fi
}

# ========== 启动 SS ==========
ssp_start() { 
	ss_enable=`nvram get ss_enable`
	if rules; then
		cgroups_init
		if start_redir_tcp; then
			start_redir_udp
			# 广告过滤。★ 位置只能是这里，不能挪到 ssp_start 外面 —— 它有两个硬前提：
			#   ① 代理已经起来（start_redir_tcp 刚跑完），start_AD 里的 curl 才走得了代理。
			#      原先这段在 case start 里、ssp_start 之前，那时代理还没起，只能直连
			#      raw.githubusercontent.com —— 实测 14~19 秒且经常失败，走代理只要 2.56 秒。
			#   ② 规则文件必须先落地、dnsmasq 后加载。dnsmasq 的重启发生在下面的
			#      start_dns 里（start_chinadns 的 killall dnsmasq + restart_dhcpd），
			#      所以这里正好是「文件已写好、dnsmasq 还没重启」的唯一窗口。
			#      若挪到 ssp_start 之后，文件写了但 dnsmasq 不重启，反广告就不生效。
			#   ③ 顺带修掉 restart 分支的不一致：restart 只做 ssp_close + ssp_start，
			#      原先不碰 AD 开关 ⇒ 改了广告过滤地址、或把开关关掉之后按「应用」重启，
			#      规则既不更新也不删。现在 start 与 restart 共用这一段。
			if [ "$(nvram get ss_adblock)" = "1" ]; then
				start_AD
			else
				# ★ 关闭时必须【删掉规则文件】，只关开关不够：
				#   ss-rules 的 ipset_r() 会无条件把 conf-dir=/tmp/dnsmasq.dom/ 写回 dnsmasq.conf
				#   （flush_r() 删掉的那一行紧接着又被加回来）⇒ 不删文件的话，关掉开关后
				#   dnsmasq 一重启照样加载陈旧的反广告规则 —— 用户以为关了，其实没关。
				#   原代码全树只有写入、没有任何 rm，只有重启路由器（/tmp 是 tmpfs）才真关得掉。
				rm -f /tmp/dnsmasq.dom/anti-ad-for-dnsmasq.conf
			fi
			start_dns
		fi
	fi
	start_local
	start_watchcat
	auto_update
	ENABLE_SERVER=$(nvram get global_server)
	[ "$ENABLE_SERVER" = "nil" ] && return 1
	log "已启动科学上网..."
	log "内网IP控制为: $lancons"
	nvram set check_mode=0
	if [ "$pppoemwan" = 0 ]; then
		/usr/bin/detect.sh
	fi
}

# ========== 关闭 SS ==========
ssp_close() {
	rm -rf /tmp/cdn
	$SS_RULES -f
	kill -9 $(ps | grep ss-monitor | grep -v grep | awk '{print $1}') >/dev/null 2>&1
	kill_process
	cgroups_cleanup
	sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
	sed -i '/server=127.0.0.1/d' /etc/storage/dnsmasq/dnsmasq.conf
	sed -i '/cdn/d' /etc/storage/dnsmasq/dnsmasq.conf
	sed -i '/gfwlist/d' /etc/storage/dnsmasq/dnsmasq.conf
	sed -i '/dnsmasq.oversea/d' /etc/storage/dnsmasq/dnsmasq.conf
	if [ -f "/etc/storage/dnsmasq-ss.d" ]; then
		rm -f /etc/storage/dnsmasq-ss.d
	fi
	clear_iptable
	/sbin/restart_dhcpd
	if [ "$pppoemwan" = 0 ]; then
		/usr/bin/detect.sh
	fi
}


clear_iptable() {
	s5_port=$(nvram get socks5_port)
	iptables -t filter -D INPUT -p tcp --dport $s5_port -j ACCEPT 2>/dev/null
	iptables -t filter -D INPUT -p tcp --dport $s5_port -j ACCEPT 2>/dev/null
	ip6tables -t filter -D INPUT -p tcp --dport $s5_port -j ACCEPT 2>/dev/null
	ip6tables -t filter -D INPUT -p tcp --dport $s5_port -j ACCEPT 2>/dev/null
}

kill_process() {
	v2ray_process=$(pidof v2ray || pidof xray)
	if [ -n "$v2ray_process" ]; then
		log "关闭 V2Ray 进程..."
		killall v2ray xray >/dev/null 2>&1
		kill -9 "$v2ray_process" >/dev/null 2>&1
	fi

	ssredir=$(pidof ss-redir)
	if [ -n "$ssredir" ]; then
		log "关闭 ss-redir 进程..."
		killall ss-redir >/dev/null 2>&1
		kill -9 "$ssredir" >/dev/null 2>&1
	fi

	rssredir=$(pidof ssr-redir)
	if [ -n "$rssredir" ]; then
		log "关闭 ssr-redir 进程..."
		killall ssr-redir >/dev/null 2>&1
		kill -9 "$rssredir" >/dev/null 2>&1
	fi

	sslocal_process=$(pidof ss-local)
	if [ -n "$sslocal_process" ]; then
		log "关闭 ss-local 进程..."
		killall ss-local >/dev/null 2>&1
		kill -9 "$sslocal_process" >/dev/null 2>&1
	fi

	trojandir=$(pidof trojan)
	if [ -n "$trojandir" ]; then
		log "关闭 trojan 进程..."
		killall trojan >/dev/null 2>&1
		kill -9 "$trojandir" >/dev/null 2>&1
	fi
	
	ipt2socks_process=$(pidof ipt2socks)
	if [ -n "$ipt2socks_process" ]; then
		log "关闭 ipt2socks 进程..."
		killall ipt2socks >/dev/null 2>&1
		kill -9 "$ipt2socks_process" >/dev/null 2>&1
	fi

	socks5_process=$(pidof srelay)
	if [ -n "$socks5_process" ]; then
		log "关闭 socks5 进程..."
		killall srelay >/dev/null 2>&1
		kill -9 "$socks5_process" >/dev/null 2>&1
	fi

	ssrs_process=$(pidof ssr-server)
	if [ -n "$ssrs_process" ]; then
		log "关闭 ssr-server 进程..."
		killall ssr-server >/dev/null 2>&1
		kill -9 "$ssrs_process" >/dev/null 2>&1
	fi

	cnd_process=$(pidof chinadns-ng)
	if [ -n "$cnd_process" ]; then
		log "关闭 chinadns-ng 进程..."
		killall chinadns-ng >/dev/null 2>&1
		kill -9 "$cnd_process" >/dev/null 2>&1
	fi

	dns2tcp_process=$(pidof dns2tcp)
	if [ -n "$dns2tcp_process" ]; then
		log "关闭 dns2tcp 进程..."
		killall dns2tcp >/dev/null 2>&1
		kill -9 "$dns2tcp_process" >/dev/null 2>&1
	fi

	dnsproxy_process=$(pidof dnsproxy)
	if [ -n "$dnsproxy_process" ]; then
		log "关闭 dnsproxy 进程..."
		killall dnsproxy >/dev/null 2>&1
		kill -9 "$dnsproxy_process" >/dev/null 2>&1
	fi
	
	microsocks_process=$(pidof microsocks)
	if [ -n "$microsocks_process" ]; then
		log "关闭 socks5 服务端进程..."
		killall microsocks >/dev/null 2>&1
		kill -9 "$microsocks_process" >/dev/null 2>&1
	fi
}

# ========== 启用备用服务器 ==========
ressp() {
	BACKUP_SERVER=$(nvram get backup_server)
	start_redir $BACKUP_SERVER
	start_rules $BACKUP_SERVER
	start_dns
	start_local
	start_watchcat
	auto_update
	ENABLE_SERVER=$(nvram get global_server)
	log "备用服务器启动成功！"
	log "内网IP控制为: $lancons"
}

case $1 in
start)
	# 广告过滤的开关判定与规则文件落地已移入 ssp_start（start_redir_tcp 之后、
	# start_dns 之前），start 与 restart 共用，理由见那里的注释
	ssp_start
	echo 3 > /proc/sys/vm/drop_caches
	;;
stop)
	ssp_close
	echo 3 > /proc/sys/vm/drop_caches
	;;
restart)
	ssp_close
	ssp_start
	echo 3 > /proc/sys/vm/drop_caches
	;;
reserver)
	ssp_close
	ressp
	echo 3 > /proc/sys/vm/drop_caches
	;;
*)
	echo "check"
	#exit 0
	;;
esac

