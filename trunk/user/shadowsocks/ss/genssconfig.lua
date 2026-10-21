local cjson = require "cjson"
local server_section = arg[1]

-- 节点序号会被直接拼进 dbus 变量名（"dbus get ssconf_basic_json_" .. 序号），
-- 必须是纯数字。调用方传的是 nvram 里的节点序号（global_server /
-- udp_relay_server / socks5_enable），正常路径一定是数字；未配置节点时是空串，
-- 这里安静退出，比让下面的 cjson.decode("") 抛错、在日志里留一堆 Lua 报错干净
if not server_section or not server_section:match("^%d+$") then
	os.exit(0)
end
--local proto = arg[2]
local local_port = arg[2]

local ssrindext = io.popen("dbus get ssconf_basic_json_" .. server_section)
local servertmp = ssrindext:read("*all")
local server = cjson.decode(servertmp)
if server.plugin == "simple-obfs" then
server.plugin = "obfs-local"
end
local fast_open = false
local f = io.popen("uname -r | awk -F '.' '{print $1\".\"$2;}'") -- runs command
local v = f:read("*a") -- read linux version
if tonumber(v) > 3.7 then
  fast_open = true
end

local ss = {
	server = server.server,
	server_port = server.server_port,
	local_address = "0.0.0.0",
	local_port = local_port,
	password = server.password,
	timeout = 60,
	method = server.encrypt_method_ss,
	plugin = server.plugin,
	plugin_opts = server.plugin_opts,
	reuse_port = true,
	fast_open = fast_open
}

print(cjson.encode(ss))
