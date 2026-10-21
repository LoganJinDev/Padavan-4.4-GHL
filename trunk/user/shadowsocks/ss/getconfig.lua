local cjson = require "cjson"
local server_section = arg[1]

-- 节点序号会被直接拼进 dbus 变量名（"dbus get ssconf_basic_json_" .. 序号），
-- 必须是纯数字。调用方传的是 nvram 里的节点序号（global_server /
-- udp_relay_server / socks5_enable），正常路径一定是数字；未配置节点时是空串，
-- 这里安静退出，比让下面的 cjson.decode("") 抛错、在日志里留一堆 Lua 报错干净
if not server_section or not server_section:match("^%d+$") then
	os.exit(0)
end

local ssrindext = io.popen("dbus get ssconf_basic_json_" .. server_section)
local servertmp = ssrindext:read("*all")
local server = cjson.decode(servertmp)
print(server.server)