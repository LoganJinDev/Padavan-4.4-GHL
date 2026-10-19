#!/bin/sh
nvram_ttyd_port="$(nvram get ttyd_port)"
[ -z "$nvram_ttyd_port" ] && nvram set ttyd_port=7681 && nvram commit
port=${nvram_ttyd_port:-"7681"}

# ttyd 独立登录凭据，与路由器管理密码分开存放（见 系统管理 - 服务 页面）
ttyd_user="$(nvram get ttyd_user)"
ttyd_pass="$(nvram get ttyd_pass)"

func_start(){
	# 安全闸门：凭据为空时拒绝启动，避免 LAN 内出现免密 root shell
	if [ -z "$ttyd_user" ] || [ -z "$ttyd_pass" ]; then
		logger -t ttyd "拒绝启动：ttyd_user / ttyd_pass 未配置，请先在 系统管理 - 服务 页面设置登录凭据"
		echo "ttyd: 拒绝启动，ttyd_user / ttyd_pass 未配置"
		return 1
	fi

	logger -t ttyd "启动 ttyd，监听端口 $port，登录用户 $ttyd_user"
	start-stop-daemon -S -b -x ttyd -- -i br0 -p "$port" -c "$ttyd_user:$ttyd_pass" -W -t disableReconnect=true -t disableLeaveAlert=true login
}

func_stop(){
	killall -q ttyd
}

case "$1" in
start)
        func_start
        ;;
stop)
        func_stop
        ;;
restart)
        func_stop
        func_start
        ;;
*)
        echo "Usage: $0 { start | stop | restart }"
        exit 1
        ;;
esac
