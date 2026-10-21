local cjson = require "cjson"

-- 单引号包裹 + 内部单引号转义成 '\''。与 dlink.lua / ssping.lua 的 shell_quote 同一写法。
--
-- 为什么这个文件必须转义，而且比 ssping.lua 更急：
--   server.server / server.server_port 来自 dbus ssconf_basic_json_<n>，最初由 dlink.lua
--   从远端订阅 URL 写入 —— 是不可信输入。原先这一行是【裸拼接】，连引号都没有：
--       'ipt2socks -s ' ..server.server.. ' -p ' ..server.server_port..
--   所以 server 里出现一个【空格】就能另起一条命令，以 root 执行（不需要引号）。
--   而入库侧的 sanitize_node 只剔除 ' 和 \ —— 不剔空格、; | & $ 反引号，
--   对「本来就没有引号」的拼接点一个字都挡不住。两侧防线不可互替，这里自己再转义一次。
local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local server_section = arg[1]
local local_port = arg[2]

-- 节点序号直接拼进 dbus 变量名，必须是纯数字（与 ssping.lua 的入参守卫同一理由）
if not server_section or not server_section:match("^%d+$") then
	os.exit(0)
end

-- 本地端口同样会被拼进命令，只接受纯数字。调用方固定传 1080，加守卫是为了
-- 将来换调用方时不至于把拼接权交出去
if not local_port or not local_port:match("^%d+$") then
	os.exit(0)
end

local ssrindext = io.popen("dbus get ssconf_basic_json_" .. server_section)
local servertmp = ssrindext:read("*all")
ssrindext:close()

-- dbus 里没有这个键（节点已被删）时 cjson.decode 会抛错，取字段时再抛一次。
-- 调用链在开机脚本里，报错只会静默丢失，不如在这里安静退出
local ok, server = pcall(cjson.decode, servertmp)
if not ok or type(server) ~= "table" then
	os.exit(0)
end

-- 缺字段时原写法会抛「attempt to concatenate a nil value」，同样是静默失败。
-- 显式退出，语义更清楚
if server.server == nil or server.server_port == nil then
	os.exit(0)
end

io.popen('ipt2socks -s ' .. shell_quote(server.server) .. ' -p ' .. shell_quote(server.server_port) .. ' -l ' .. shell_quote(local_port) .. ' -r -4 -R >/dev/null 2>&1 &')
