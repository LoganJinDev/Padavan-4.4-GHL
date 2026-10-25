local cjson = require "cjson"

-- urltest_node.lua —— 读出某个节点的协议类型，供 urltest.sh 分派生成器
--
-- 为什么单独做一个小脚本：节点类型存在节点 JSON 的 type 字段里，而 JSON 在 dbus。
-- shell 里没有 JSON 解析器，用 grep/sed 去抠 "type":"xxx" 会随着字段顺序变化而失效
-- （cjson 输出的键顺序是哈希序，不是插入序）⇒ 解析必须交给 lua。
--
-- 用法：urltest_node.lua <节点号>
--   输出：ss / ssr / trojan / v2ray / xray，解析不出来则什么都不输出
--
-- ★ 输出【不带换行】：调用方是 shell 的 $( )，多一个换行虽然会被 $( ) 吃掉，
--   但一旦哪天改成写文件或喂给别的命令，尾换行就会变成脏数据。不写最省心。

local n = arg[1]

-- 节点号会被拼进 dbus 变量名，必须是纯数字。
-- 与 ping.sh / ssping.lua 的入参守卫同一理由：拼进命令的变量不校验，
-- 等于把命令拼接权交出去。
if not n or not n:match("^%d+$") then
	os.exit(0)
end

local fh = io.popen("dbus get ssconf_basic_json_" .. n)
local raw = fh:read("*all")
fh:close()

-- dbus 里没有这个键（节点已被删）时 cjson.decode 会抛错。
-- 本脚本是被后台并发的测速进程调的，报错只会静默丢失，不如安静退出。
local ok, node = pcall(cjson.decode, raw)
if not ok or type(node) ~= "table" then
	os.exit(0)
end

io.write(tostring(node.type or ""))
