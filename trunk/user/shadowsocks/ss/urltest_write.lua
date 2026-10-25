local cjson = require "cjson"

-- urltest_write.lua —— 把一次 URL 测速的结果写回节点 JSON
--
-- 形态完全照 ssping.lua（同一个数据源、同一个写入位置，必须同一套转义与守卫）。
--
-- 用法：urltest_write.lua <节点号> <毫秒数|空>
--   毫秒数是纯数字 ⇒ urltest = 数字（与 ping 字段同形，前端能直接排序）
--   空串或非数字 ⇒ urltest = "failed"（与 ping 失败时的字符串同形）
--   无论成败都写 urltest_ts：用来区分「这轮的结果」和「上轮留下的残值」。
--
-- 持久性：订阅更新不会抹掉这两个字段 —— dlink.lua:657 的 `if not vv._ignore`
-- 对已存在的节点直接跳过、不重写。

-- 单引号包裹 + 内部单引号转义成 '\''。与 dlink.lua / ssping.lua 的 shell_quote 同一写法。
--
-- 为什么这个文件也必须转义：这里读出的 JSON 直接来自 dbus（最初由 dlink.lua
-- 从远端订阅 URL 写入），字段里出现一个 ' 就能从单引号里逃出去，以 root 执行
-- 拼接在后面的命令。同一数据源、同一攻击模式的注入面必须一起堵。
local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local n = arg[1]
local result = arg[2]

-- 节点序号直接拼进 dbus 变量名，必须是纯数字
if not n or not n:match("^%d+$") then
	os.exit(0)
end

local fh = io.popen("dbus get ssconf_basic_json_" .. n)
local raw = fh:read("*all")
fh:close()

-- dbus 里没有这个键（节点已被删）时 cjson.decode 会抛错，取字段再抛一次。
-- 测速是后台并发跑的，报错只会静默丢失，不如在这里安静退出。
local ok, old = pcall(cjson.decode, raw)
if not ok or type(old) ~= "table" then
	os.exit(0)
end

-- 成功判据是「纯数字」。空串（实例没起来 / 端口没监听 / 探测失败）一律走 failed 分支。
local is_ok = result ~= nil and result:match("^%d+$") ~= nil

if is_ok then
	old["urltest"] = tonumber(result)
else
	old["urltest"] = "failed"
end
old["urltest_ts"] = os.time()

-- ★ 只编码一次：ssping.lua 是编码两次（print 一次、写 dbus 一次），
--   两处用同一个表达式所以结果一致，但多一次编码就多一次出错的机会。
local out = cjson.encode(old)

local wh = io.popen("dbus set ssconf_basic_json_" .. n .. "=" .. shell_quote(out))
if wh then
	wh:close()
end

-- ★ 显示串显式用 if，不用 `A and B or C`：后者在 B 为假值（false/nil）时会给错分支，
--   本仓库已有过这条教训。
local disp
if is_ok then
	disp = tostring(result) .. "ms"
else
	disp = "failed"
end

-- 日志同理：alias 是裸拼进单引号串的，别名里一个 ' 就能追加任意命令
io.popen("logger -t 'SS' " .. shell_quote(
	"节点(" .. tostring(old.alias) .. ") URL测速:" .. disp))
