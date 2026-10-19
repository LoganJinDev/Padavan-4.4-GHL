#!/bin/sh
#
# Copyright (C) 2022 TurBoTse <860018505@qq.com>
#
#nvram set ntp_ready=0

mkdir -p /tmp/dnsmasq.dom
logger -t "防止 DNSmasq 启动失败，创建/tmp/dnsmasq.dom/"

# ap relay monitor [simonchen]
if [ ! -x /etc/storage/sh_ezscript.sh ]; then
	cp /usr/bin/sh_ezscript.sh /etc/storage/sh_ezscript.sh
fi
if [ -x /etc/storage/ap_script.sh ]; then
	/etc/storage/ap_script.sh >/dev/null 2>&1 &
else
	cp /usr/bin/ap_script.sh /etc/storage/ap_script.sh
fi

smartdns_conf="/etc/storage/smartdns_custom.conf"
dnsmasq_Conf="/etc/storage/dnsmasq/dnsmasq.conf"
smartdns_Ini="/etc/storage/smartdns_conf.ini"
sdns_port=$(nvram get sdns_port)

logger -t "自动启动" "正在检查路由是否已连接互联网..."
count=0
while :
do
	ping -c 1 -W 1 -q 223.5.5.5 1>/dev/null 2>&1
	if [ "$?" == "0" ]; then
		break
	fi
	sleep 5
	ping -c 1 -W 1 -q baidu.com 1>/dev/null 2>&1
	if [ "$?" == "0" ]; then
		break
	fi
	sleep 5
	count=$((count+1))
	if [ $count -gt 18 ]; then
		break
	fi
done

if [ $(nvram get pppoemwan_enable) = 1 ] ; then
sleep 20
fi

if [ $(nvram get sqm_enable) = 1 ] ; then
sleep 10
logger -t "自动启动" "正在启动 SQM QOS..."
/usr/lib/sqm/run.sh
fi

# 按设备限速必须排在 SQM 之后，两个原因：
#   ① 上行限速挂在 br0 的 ingress 上，而 SQM 每次启动都会 del + add 这个 qdisc，
#      先起 lanlimit 的话它挂的过滤器会被 SQM 立刻清掉；
#   ② runmode_2/4 会把 hw_nat_mode 设成 2 并 modprobe hw_nat（重新打开硬件
#      加速），先起 lanlimit 的话它刚关掉的硬件加速会被 SQM 再打开，限速静默失效。
# 配置里没有有效条目时 lanlimit.sh 自己会跳过；SQM 总开关关着时它也会自行退出
if [ -f "/etc/storage/lanlimit.conf" ] ; then
	logger -t "自动启动" "正在启动 按设备限速..."
	/usr/bin/lanlimit.sh start
fi

if [ $(nvram get adbyby_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 Adbyby plus..."
/usr/bin/adbyby.sh start
fi

if [ $(nvram get adg_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 adguardhome..."
/usr/bin/adguardhome.sh start
fi

if [ $(nvram get ss_enable) = 1 ] ; then
logger -t "自动启动" "正在启动科学上网..."
/usr/bin/shadowsocks.sh start
fi

if [ $(nvram get sdns_enable) = 1 ] ; then
   if [ -f "$smartdns_conf" ] ; then
       sed -i '/去广告/d' $smartdns_conf
       sed -i '/adbyby/d' $smartdns_conf
       sed -i '/no-resolv/d' "$dnsmasq_Conf"
       sed -i '/server=127.0.0.1#'"$sdns_portd"'/d' "$dnsmasq_Conf"
       sed -i '/port=0/d' "$dnsmasq_Conf"
       rm  -f "$smartdns_Ini"
   fi
logger -t "自动启动" "正在启动 SmartDNS..."
/usr/bin/smartdns.sh start
fi

if [ $(nvram get aliddns_enable) = 1 ] ; then
logger -t "自动启动" "正在启动阿里 ddns..."
/usr/bin/aliddns.sh start
fi

if [ $(nvram get ddnsto_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 ddnsto..."
/usr/bin/ddnsto.sh start
fi

if [ $(nvram get aliyundrive_enable) = 1 ] ; then
logger -t "自动启动" "正在启动阿里云盘..."
/usr/bin/aliyundrive-webdav.sh start
fi

if [ $(nvram get zerotier_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 zerotier..."
/usr/bin/zerotier.sh start
fi

if [ $(nvram get wireguard_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 wireguard..."
/usr/bin/wireguard.sh start
fi

if [ $(nvram get frpc_enable) = 1 ] ; then
logger -t "自动启动" "正在启动 frp client..."
/usr/bin/frp.sh start
fi