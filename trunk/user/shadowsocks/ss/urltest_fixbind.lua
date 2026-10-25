local cjson = require "cjson"

-- urltest_fixbind.lua —— 把测速临时实例的监听地址强制改成 127.0.0.1
--
-- 为什么必须有这一步：四个配置生成器都把本地监听地址写成 0.0.0.0
--     genssconfig.lua:30     local_address = "0.0.0.0"
--     genssrconfig.lua:20    local_address = "0.0.0.0"
--     gentrojanconfig.lua:21 local_addr    = "0.0.0.0"
--     genxrayconfig.lua       socks 入站根本不写 listen（xray 默认同样是 0.0.0.0）
--
-- 生产路径上这没问题：主代理本来就该让局域网内的设备用。但测速实例是【临时的、
-- 一次性的】，它们只需要被 127.0.0.1 上的 curl 访问。不改的话，每次点「URL测试」
-- 都会在局域网上多出 4 个开放代理（1089-1092），其中 xray 那路还是 auth="noauth"
-- ⇒ 同一局域网里的任何人都能拿用户自己买的节点上网。测速期间白送一个开放中继。
--
-- 为什么用 Lua 重写而不是 sed：cjson 输出的键顺序是哈希序，不是插入序。
-- 想用 sed 在 "protocol":"socks" 旁边插一个 "listen" 字段，是在赌两个键在文本里
-- 相邻 —— 换个节点、换个 lua 版本就失效。解析-改-再编码与键序无关。
--
-- ★ 解析失败 / 一个字段都没改到，都必须返回非 0：调用方据此把该节点判为失败。
--   宁可少测一个节点，也不能在「没能确认绑定地址」的时候把 0.0.0.0 的配置放出去跑。

local cfg = arg[1]
if not cfg or cfg == "" then
	os.exit(1)
end

local fh = io.open(cfg, "r")
if not fh then
	os.exit(1)
end
local raw = fh:read("*all")
fh:close()

local ok, conf = pcall(cjson.decode, raw)
if not ok or type(conf) ~= "table" then
	os.exit(1)
end

-- 「改到了东西没有」必须单独记账，不能靠「没报错」当成功：
-- 生成器哪天换了字段名，这里会一个字段都匹配不上、照样写出一个 0.0.0.0 的配置，
-- 而返回值是 0 ⇒ 静默放行。这正是「守卫不会响 = 没有守卫」那一类。
local changed = false

-- ss / ssr 用 local_address，trojan 用 local_addr（两个键名不一样，都要管）
if conf.local_address ~= nil then
	conf.local_address = "127.0.0.1"
	changed = true
end
if conf.local_addr ~= nil then
	conf.local_addr = "127.0.0.1"
	changed = true
end

-- xray：入站是数组，每个入站都要自己指定 listen。
-- 这里不区分 protocol：测速实例的每一个入站都是本机入口，全都只该听回环。
if type(conf.inbounds) == "table" then
	for _, inb in ipairs(conf.inbounds) do
		if type(inb) == "table" then
			inb.listen = "127.0.0.1"
			changed = true
		end
	end
end

if not changed then
	os.exit(1)
end

-- ★ 重新编码时必须自己把反斜杠归一化掉，否则会把调用方刚做过的归一化【撤销】。
--
--   链路是：生成器 → sed -i 's/\\//g'（urltest.sh，与 shadowsocks.sh 的
--   gen_config_file() 一致）→ 本脚本。而 cjson 的转义表（lua_cjson.c:161）把 / 编成
--   "\/"，所以 cjson.encode() 的输出里一定带反斜杠转义 ⇒ 只解析-改-编码、不做归一化
--   的话，sed 那一趟等于白跑，临时实例拿到的配置与生产路径产生的【不是同一形态】。
--
--   这里做的是与那条 sed 逐字节等价的操作（剥掉所有反斜杠），而不是「把 \/ 换成 /」：
--   目标是「本脚本的输出 == 生产路径的输出」，不是「语义上等价」。
--   剥反斜杠对解码结果无害 —— cjson.decode 本就把 \/ 解成 /。
--
--   为什么必须匹配生产形态而不是"反正 JSON 合法就行"：生产路径剥反斜杠这条规则本身
--   就说明有人认定过目标程序不认带反斜杠的配置，但本机没有 ARM 的目标二进制可跑，
--   这个假设无法验证。让两条路径产出同一形态，假设就整个消失了，不必去赌。
local encoded = cjson.encode(conf)
encoded = encoded:gsub("%\\", "")

local out = io.open(cfg, "w")
if not out then
	os.exit(1)
end
out:write(encoded)
out:close()

os.exit(0)
