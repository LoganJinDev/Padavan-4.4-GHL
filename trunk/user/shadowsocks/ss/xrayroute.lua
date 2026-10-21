--[[
	xrayroute.lua —— xray routing 段生成器（分流规则引擎）

	职责：
		读取面板写入 dbus 的分流规则，把 geosite:/geoip: 分类展开成具体条目，
		产出 xray 的 routing 段（末尾必带无条件兜底规则）。

	调用方：genxrayconfig.lua 通过 require("xrayroute") 使用，本文件不单独执行。
	运行环境：固件内 Lua 5.1.5 + lua-cjson 2.1.0 —— 禁用 goto / table.unpack / 位运算。
]]

local cjson = require "cjson"

local M = {}

-- 分类小文本库目录。/tmp 是内存盘；512KB 的 /etc/storage 放不下（cn+gfw+geoip:cn 就约 337KB）
M.rules_dir = "/tmp/ss_rules"

-- 已知的域名匹配前缀。xray 侧对应：
--   domain:  后缀匹配（走 Domain_Domain）
--   full:    全等匹配（走 Domain_Full）
--   keyword: 子串匹配（走 Domain_Plain）
--   regexp:  正则（本方案生成期一律丢弃，原因见 expand_domain_line）
local KNOWN_PREFIX = { domain = 1, full = 1, keyword = 1, regexp = 1 }

-- 已读过的分类文件缓存，避免同一分类被多条规则重复读盘
local file_cache = {}

-- 读取一个 dbus 键；取不到或为空返回 nil
--
-- 键名会被直接拼进 shell 命令，必须先过白名单。这不是洁癖：id 来自 dbus 里的
-- xray_route_order / xray_acl_order（逗号分隔的 id 串），而那两个键是面板经
-- apply.cgi 写进去的，值本身没有任何服务端校验。往 order 里塞一个
-- "1; touch /tmp/x" 这样的 id，拼出来就是 `dbus get xray_rule_1; touch /tmp/x`，
-- 以 root 执行 —— 与本目录其它生成器踩的是同一个坑。
-- 全部 6 个调用点的键名都是 xray_ 加纯字母数字下划线（id 只有 r<N> / a<N>
-- 两种形态，见 xrayroute.js 的 nextRuleId / nextAclId），所以白名单收紧到
-- [%w_] 不影响任何正常路径。将来若要引入带 - 或 . 的键名，请连同这里的白名单
-- 一起改，别绕过去。
function M.dbus_get(key)
	if type(key) ~= "string" or not key:match("^[%w_]+$") then
		return nil
	end
	local fp = io.popen("dbus get " .. key .. " 2>/dev/null")
	if not fp then
		return nil
	end
	local val = fp:read("*all")
	fp:close()
	if not val then
		return nil
	end
	val = val:gsub("%s+$", "")
	if val == "" then
		return nil
	end
	return val
end

-- 读取分类文本，返回去掉空行与 # 注释后的行数组；文件不存在返回空数组
function M.read_lines(path)
	local cached = file_cache[path]
	if cached then
		return cached
	end
	local lines = {}
	local fp = io.open(path, "r")
	if fp then
		-- 循环变量改名、修剪结果用局部量承接：Lua 5.4/5.5 起 for 的控制变量是 const，
		-- 原先那句 `line = line:gsub(...)` 在 5.5 下直接编译不过。设备上是 5.1.5，
		-- 两种写法语义完全相同 —— 改掉只是让本机的 luac -p 能重新当语法闸门用，
		-- 顺便去掉一个将来换 Lua 版本就会炸的暗雷
		for raw in fp:lines() do
			local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
			if line ~= "" and line:sub(1, 1) ~= "#" then
				lines[#lines + 1] = line
			end
		end
		fp:close()
	end
	file_cache[path] = lines
	return lines
end

-- 拆一行域名/IP 条目，返回 prefix(可能为 nil)、value、attrs[]
-- 兼容两种属性写法：
--   Loyalsoldier release 文本：domain:cf-china.info:@cn
--   社区 domain-list 文本：    domain:cf-china.info @cn
local function split_entry(line)
	local attrs = {}
	local head, attr = line:match("^(.*):@([%w_!%-]+)$")
	while head do
		table.insert(attrs, 1, attr)
		line = head
		head, attr = line:match("^(.*):@([%w_!%-]+)$")
	end
	local bare, rest = line:match("^(%S+)%s+@(.+)$")
	if bare then
		line = bare
		for a in rest:gmatch("[%w_!%-]+") do
			attrs[#attrs + 1] = a
		end
	end
	local prefix, value = line:match("^(%a+):(.+)$")
	if prefix and KNOWN_PREFIX[prefix] then
		return prefix, value, attrs
	end
	return nil, line, attrs
end

-- 属性过滤：want 为空则全收；否则要求条目带全部指定属性
-- 与 xray 的 AttributeList 一致（AND 语义；无属性的条目在指定属性时不匹配）
local function attr_hit(attrs, want)
	if #want == 0 then
		return true
	end
	for i = 1, #want do
		local found = false
		for j = 1, #attrs do
			if attrs[j] == want[i] then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

-- 展开 geosite:<分类>[@属性] —— 域名类
local function expand_geosite(name, want)
	local out = {}
	local lines = M.read_lines(M.rules_dir .. "/geosite_" .. name .. ".txt")
	for i = 1, #lines do
		local prefix, value, attrs = split_entry(lines[i])
		-- regexp 一律丢弃：shadowsocks.sh 生成 JSON 后会对产物做 sed 's/\\//g'，
		-- 反斜杠被剥掉的正则必然变形，宁可少一条也不能给出错误规则
		if prefix ~= "regexp" and attr_hit(attrs, want) then
			-- 归一化：裸域名补 domain: 前缀。
			-- 不补的话 xray 走 Domain_Plain = 子串匹配，"aa.com" 会命中 "xaa.com.evil.net"
			out[#out + 1] = (prefix or "domain") .. ":" .. value
		end
	end
	return out
end

-- 展开 geoip:<分类> —— IP 类；文本是裸 CIDR
local function expand_geoip(name)
	local out = {}
	local lines = M.read_lines(M.rules_dir .. "/geoip_" .. name .. ".txt")
	for i = 1, #lines do
		local _, value = split_entry(lines[i])
		if value and value ~= "" then
			out[#out + 1] = value
		end
	end
	return out
end

-- 展开规则文本里的一行域名条目
function M.expand_domain_line(line)
	local spec = line:match("^geosite:(.+)$")
	if spec then
		local name, attrstr = spec:match("^([^@]+)@(.+)$")
		if not name then
			name, attrstr = spec, ""
		end
		local want = {}
		for a in attrstr:gmatch("[%w_!%-]+") do
			want[#want + 1] = a:lower()
		end
		return expand_geosite(name:lower(), want)
	end
	local prefix, value = split_entry(line)
	if prefix == "regexp" then
		return {}
	end
	return { (prefix or "domain") .. ":" .. value }
end

-- 展开规则文本里的一行 IP 条目
function M.expand_ip_line(line)
	local spec = line:match("^geoip:(.+)$")
	if spec then
		return expand_geoip(spec:lower())
	end
	local _, value = split_entry(line)
	if value and value ~= "" then
		return { value }
	end
	return {}
end

-- 展开一段规则文本（domain_list 或 ip_list 字段），kind = "domain" | "ip"
--
-- 注意分隔符：面板把多行列表存成「单行、空白分隔」，本函数因此按空白切词而不是按换行切。
-- 原因是读取链路 web_ex.c 的 db_print 把 dbus 值原样塞进 JS 单引号字符串
-- （o["xray_rule_r1"]='<值>';）—— 值里只要带真换行，整个页面脚本就变成未闭合字符串而全盘报错。
-- 存成单行是唯一能同时让 JS 侧和 dbus 侧都安全的形式。
function M.expand_list(text, kind)
	local out = {}
	if not text or text == "" then
		return out
	end
	-- 切词；顺带把孤立的 "@属性" 粘回前一个词条，兼容 "domain:x.com @cn" 这种空格式老写法
	local toks = {}
	for tok in text:gmatch("%S+") do
		if tok:sub(1, 1) == "#" then
			-- 面板保存时已剔除整行注释；这里只兜底挡掉落单的 #
		elseif tok:sub(1, 1) == "@" and #toks > 0 then
			toks[#toks] = toks[#toks] .. " " .. tok
		else
			toks[#toks + 1] = tok
		end
	end
	for i = 1, #toks do
		local add
		if kind == "domain" then
			add = M.expand_domain_line(toks[i])
		else
			add = M.expand_ip_line(toks[i])
		end
		local n = #out
		for j = 1, #add do
			out[n + j] = add[j]
		end
	end
	return out
end

-- 读一条分流规则的 JSON（dbus xray_rule_<id>），解析失败返回 nil
function M.load_rule(id)
	local raw = M.dbus_get("xray_rule_" .. id)
	if not raw then
		return nil
	end
	local ok, obj = pcall(cjson.decode, raw)
	if not ok or type(obj) ~= "table" then
		return nil
	end
	return obj
end

-- 往 rules 里追加一条 field 规则；list 为空则什么都不加并返回 false。
--
-- 域名与 IP 必须拆成两条独立规则，这是本引擎最容易被写错的一点：
-- xray 同一条规则内的各字段是「与」关系 —— app/router/condition.go 的
-- ConditionChan.Apply 逐个条件判断，任一不中整条即不中，
-- 而 passwall2 与用户预期是「域名命中 或 IP 命中」。
-- 不拆的话 "geosite:cn" + "geoip:cn" 会要求域名和 IP 同时属于大陆，
-- 大陆域名配境外 CDN 的流量会被误送去代理。
local function add_rule(rules, tag, net, list, field)
	if #list == 0 then
		return false
	end
	local rule = { type = "field", outboundTag = tag, [field] = list }
	if net then
		rule.network = net
	end
	rules[#rules + 1] = rule
	return true
end

--[[ ── 访问控制（ACL）────────────────────────────────────────────────

	语义：命中本条目「来源」的流量直接走它指定的出站，不再看后面的分流规则。
	xray 按顺序匹配、先中先赢，因此 ACL 规则必须排在分流规则【之前】。

	xray 的 source 匹配器只认 IP/CIDR（app/router/condition.go 里 SourceIPMatcher
	收的是 net.IP），而面板让用户填 MAC 更自然，所以在【生成配置时】把 MAC 解析成 IP：
	先查 /tmp/dnsmasq.leases（当前租约），再查 /proc/net/arp（静态 IP 或刚上线、
	还没走完 DHCP 的设备）。

	代价要说清楚：设备换了 IP 要重新生成一次配置才生效。页面上的「应用」按钮
	正是干这个的，所以这不是缺陷 —— 但用户在 ACL 页面改完必须点应用。
]]

-- MAC(小写) -> IP 表。一次配置生成里多条 ACL 条目共用，只读一遍盘
local mac_map_cache = nil

local function mac_ip_map()
	if mac_map_cache then
		return mac_map_cache
	end
	local map = {}
	local fp = io.open("/tmp/dnsmasq.leases", "r")
	if fp then
		-- 格式：过期时间 MAC IP 主机名 客户端ID
		for line in fp:lines() do
			local m, ip = line:match("^%s*%S+%s+(%S+)%s+(%S+)")
			if m then
				map[m:lower()] = ip
			end
		end
		fp:close()
	end
	fp = io.open("/proc/net/arp", "r")
	if fp then
		fp:read("*l") -- 跳过表头
		-- 格式：IP 类型 标志 MAC 掩码 设备
		for line in fp:lines() do
			local ip, flags, m = line:match("^%s*(%S+)%s+%S+%s+(%S+)%s+(%S+)")
			-- flags 为 0x0 的是未完成表项；MAC 全 0 的是无效表项 —— 都不采信。
			-- 租约表优先：已在 map 里的不覆盖（DHCP 记录比 ARP 缓存更权威）
			if m and flags ~= "0x0" and m ~= "00:00:00:00:00:00" and not map[m:lower()] then
				map[m:lower()] = ip
			end
		end
		fp:close()
	end
	mac_map_cache = map
	return map
end

-- 判定来源串是 MAC 还是 IP/CIDR；都不像则返回 nil。
-- 面板已经拦了一道，这里再挡一次：配置是另一条链路写进来的，不能假设它干净
local function source_kind(s)
	if type(s) ~= "string" then
		return nil
	end
	s = s:lower()
	if s:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
		return "mac", s
	end
	if s:match("^%d+%.%d+%.%d+%.%d+$") or s:match("^%d+%.%d+%.%d+%.%d+/%d+$") then
		return "ip", s
	end
	return nil
end

-- 把一条 ACL 条目的来源列表解析成 xray 能吃的 IP/CIDR 数组。
-- MAC 解不出 IP 就丢掉那个来源（设备当前不在线）；全丢光则该条目整条跳过
local function resolve_sources(sources)
	local out = {}
	if type(sources) ~= "table" then
		return out
	end
	local map = mac_ip_map()
	for i = 1, #sources do
		local kind, val = source_kind(sources[i])
		if kind == "ip" then
			out[#out + 1] = val
		elseif kind == "mac" and map[val] then
			out[#out + 1] = map[val]
		end
	end
	return out
end

-- 生成 ACL 规则数组（调用方负责插在分流规则之前）。
-- 未启用、或没有任何有效条目时返回空数组。
-- 出站为 "follow" 表示「该设备按分流规则处理」，本身不产出规则
function M.build_acl(resolve)
	local rules = {}
	if M.dbus_get("xray_acl_enable") ~= "1" then
		return rules
	end
	local order = M.dbus_get("xray_acl_order") or ""
	for id in order:gmatch("[^,]+") do
		local raw = M.dbus_get("xray_acl_" .. id)
		if raw then
			local ok, a = pcall(cjson.decode, raw)
			if ok and type(a) == "table" and a.enabled ~= "0"
				and a.outbound and a.outbound ~= "" and a.outbound ~= "follow" then
				local ips = resolve_sources(a.sources)
				if #ips > 0 then
					rules[#rules + 1] = {
						type = "field",
						source = ips,
						network = "tcp,udp",
						-- 第二个参数是「前置代理」：非空时解析器会把该出站链到前置节点之后，
						-- 返回的是另一个（形如 node_5_via_node_3 的）出站 tag。
						outboundTag = resolve(a.outbound, a.preproxy)
					}
				end
			end
		end
	end
	return rules
end

-- 把各条规则的域名桶并成一个去重列表。
-- 去重是必要的：geosite:cn 与 geosite:geolocation-cn 这类相邻分类大量重叠，
-- 重复项喂给 DNS 匹配器只会白白撑大配置文件。
-- 返回空数组代表「一条都没勾」，调用方据此退回「对所有域名生效」
local function merge_fakedns_domains(buckets)
	local out, seen = {}, {}
	for i = 1, #buckets do
		local list = buckets[i]
		for j = 1, #list do
			local v = list[j]
			if not seen[v] then
				seen[v] = true
				out[#out + 1] = v
			end
		end
	end
	return out
end

-- 展开一条分流规则并追加进 rules；返回是否加进了 IP 规则。
-- fakedns_buckets 收集勾了 FakeDNS 的规则的域名（可能为空数组，表示没勾）
local function apply_one_rule(rules, fakedns_buckets, resolve, id)
	local r = M.load_rule(id)
	if not r or r.enabled == "0" then
		return false
	end
	local domain = M.expand_list(r.domain_list, "domain")
	local ip = M.expand_list(r.ip_list, "ip")
	-- 只有 network 没有域名/IP 的规则会变成无条件规则，吃掉后面所有规则，直接跳过
	if #domain == 0 and #ip == 0 then
		return false
	end
	-- 第二个参数是「前置代理」（面板同名下拉框，存节点序号）。解析器会据此把该出站
	-- 链到前置节点之后，返回另一个出站 tag；没设前置代理时返回值与旧行为一致。
	local tag = resolve(r.outbound, r.preproxy)
	local net = (r.network and r.network ~= "") and r.network or nil
	add_rule(rules, tag, net, domain, "domain")
	local has_ip = add_rule(rules, tag, net, ip, "ip")
	-- 这条规则点了名要 FakeDNS：把它的域名并进假 IP 名单。
	-- 只取域名 —— FakeDNS 作用在域名解析环节，纯 IP 规则谈不上
	if r.fakedns == "1" then
		fakedns_buckets[#fakedns_buckets + 1] = domain
	end
	return has_ip
end

-- 生成 routing 段。参数 resolve 是调用方给的解析函数：resolve(期望tag, 前置代理) -> 实际tag
-- 第二个参数可为 nil（未设前置代理），解析器必须容忍
--
-- 返回两个值：
--   1. routing 表 —— 无任何规则时为 nil（调用方据此不写 routing 段，退化成旧行为）
--   2. fakedns 域名数组 —— 所有勾了 FakeDNS 的规则的域名并集去重，可能为空
function M.build_routing(resolve)
	local rules = {}
	local buckets = {}
	local has_ip = false

	-- ① ACL 排最前：被点名的设备直接定下出站，不再走分流规则
	local acl = M.build_acl(resolve)
	for i = 1, #acl do
		rules[#rules + 1] = acl[i]
	end

	-- ② 分流规则。与 ACL 是两件独立的事，所以 ACL 不受分流总开关影响
	if M.dbus_get("xray_route_enable") == "1" then
		for id in (M.dbus_get("xray_route_order") or ""):gmatch("[^,]+") do
			if apply_one_rule(rules, buckets, resolve, id) then
				has_ip = true
			end
		end
	end

	if #rules == 0 then
		return nil, {}
	end
	-- 兜底：不匹配任何规则的流量走默认节点。xray 按顺序匹配，这条必须最后
	rules[#rules + 1] = { type = "field", network = "tcp,udp", outboundTag = "default" }
	return {
		-- 域名规则都不中时再解析成 IP 去匹配 geoip 规则；没有 IP 规则就不解析，省一次 DNS
		domainStrategy = has_ip and "IPIfNonMatch" or "AsIs",
		rules = rules
	}, merge_fakedns_domains(buckets)
end

return M
