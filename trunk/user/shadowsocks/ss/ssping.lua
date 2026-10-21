local cjson = require "cjson"

-- 单引号包裹 + 内部单引号转义成 '\''。与 dlink.lua 的 shell_quote 同一写法。
--
-- 为什么这个文件也必须转义：这里读出的 JSON 直接来自 dbus（最初由 dlink.lua
-- 从远端订阅 URL 写入），字段里出现一个 ' 就能从单引号里逃出去，以 root 执行
-- 拼接在后面的命令。dlink.lua 那道 sanitize_node 是第一层防线，管不到：
--   · 在加它之前就已经存进 dbus 的旧数据
--   · 面板与其它路径写入的节点
-- 同一数据源、同一攻击模式的注入面必须一起堵，所以这里自己再转义一次。
local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local server_ping = arg[1]
local server_lost = arg[2]
local server_s = arg[3]

-- 节点序号直接拼进 dbus 变量名，必须是纯数字。
-- 与 ping.sh 的入参守卫同一理由：拼进命令的变量不校验，等于把命令拼接权交出去
if not server_s or not server_s:match("^%d+$") then
	os.exit(0)
end

local olddb = io.popen("dbus get ssconf_basic_json_" .. server_s)
local raw = olddb:read("*all")
olddb:close()

-- dbus 里没有这个键（节点已被删）时 cjson.decode 会抛错，取字段再抛一次。
-- ping.sh 是后台并发跑的，报错只会静默丢失，不如在这里安静退出
local ok, old = pcall(cjson.decode, raw)
if not ok or type(old) ~= "table" then
	os.exit(0)
end

old["ping"] = server_ping
old["lost"] = server_lost
print(cjson.encode(old))

local fh = io.popen("dbus set ssconf_basic_json_" .. server_s .. "=" .. shell_quote(cjson.encode(old)))
if fh then
	fh:close()
end

-- 日志同理：原先 alias 是裸拼进单引号串的，别名里一个 ' 就能追加任意命令
io.popen("logger -t 'SS' " .. shell_quote(
	"节点(" .. tostring(old.alias) .. ") 延迟:" .. tostring(server_ping) ..
	"ms 丢包:" .. tostring(server_lost)))
