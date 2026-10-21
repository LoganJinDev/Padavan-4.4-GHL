------------------------------------------------
-- This file is part of the luci-app-ssr-plus subscribe.lua
-- @author William Chan <root@williamchan.me>
-- 2020/03/15 by chongshengB
------------------------------------------------
require 'nixio'
local cjson = require "cjson"
-- these global functions are accessed all the time by the event handler
-- so caching them is worth the effort
local tinsert = table.insert
local ssub, slen, schar, sbyte, sformat, sgsub = string.sub, string.len, string.char, string.byte, string.format, string.gsub
local b64decode = nixio.bin.b64decode
local cache = {}
local nodeResult = setmetatable({}, { __index = cache })  -- update result
local name = 'shadowsocksr'
local uciType = 'servers'
local subscribe_url = {}
local i = 1
-- 关键词过滤表。
-- 原写法是 echo -n `nvram get ss_keyword`：反引号（以及 $()）的输出会被 shell
-- 再做一次【词分割 + 路径展开】—— 关键词里带 * ? [ 时会被展开成一串文件名，
-- 过滤表整个失真。直接读命令输出，值不经过 shell 解析，也没有多余换行。
local tfilter_words = io.popen("nvram get ss_keyword")
local filter_words = ""
if tfilter_words then
	filter_words = tfilter_words:read("*all") or ""
	tfilter_words:close()
end
filter_words = filter_words:gsub("%s+$", "")

for line in io.lines("/tmp/dlist.txt") do
print(line)
subscribe_url[i] = line
i = i+1
end

local function base64Decode(text)
	local raw = text
	if not text then return '' end
	text = text:gsub("%z", "")
	text = text:gsub("_", "/")
	text = text:gsub("-", "+")
	local mod4 = #text % 4
	text = text .. string.sub('====', mod4 + 1)
	local result = b64decode(text)
	if result then
		return result:gsub("%z", "")
	else
		return raw
	end
end

-- shell 单引号转义：把任意值安全地嵌进 '...' 里。
-- 单引号是 shell 里唯一无法在单引号串内表示的字符，做法是「闭合 → 转义 → 重开」：' -> '\''
--
-- ⚠️ 为什么必须有这个函数：本仓库里「把数据拼进 shell 命令串」是【重复出现】的坑
--    （面板写入路径、ping.sh 的 argv 都踩过同一个）。而订阅内容是完全未受信的远端输入，
--    任何一处漏转义都是 root 权限的任意命令执行。
--    凡是把外部值拼进 io.popen / os.execute 的地方，一律过它。
local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local log = function(...)
	local msg = table.concat({ ... }, " ")
	print(os.date("%Y-%m-%d %H:%M:%S ") .. msg)
	-- msg 里含远端可控的 alias / url（如 log('成功解析: ' .. result.alias)），
	-- 原先直接拼进单引号串 ⇒ 别名里一个 ' 就能逃出引号以 root 执行命令。
	-- 这是与下面 dbus set 并列的第二个注入面，必须一起堵。
	os.execute("logger -t 'SS' " .. shell_quote(msg))
end
-- 分割字符串
local function split(full, sep)
	full = full:gsub("%z", "")  -- 这里不是很清楚 有时候结尾带个\0
	local off, result = 1, {}
	while true do
		local nStart, nEnd = full:find(sep, off)
		if not nEnd then
			local res = ssub(full, off, slen(full))
			if #res > 0 then -- 过滤掉 \0
				tinsert(result, res)
			end
			break
		else
			tinsert(result, ssub(full, off, nStart - 1))
			off = nEnd + 1
		end
	end
	return result
end
-- urlencode
local function get_urlencode(c)
	return sformat("%%%02X", sbyte(c))
end

local function urlEncode(szText)
	local str = szText:gsub("([^0-9a-zA-Z ])", get_urlencode)
	str = str:gsub(" ", "+")
	return str
end

local function get_urldecode(h)
	return schar(tonumber(h, 16))
end
local function UrlDecode(szText)
	return szText:gsub("+", " "):gsub("%%(%x%x)", get_urldecode)
end
-- trim
local function trim(text)
	if not text or text == "" then
		return ""
	end
	return (sgsub(text, "^%s*(.-)%s*$", "%1"))
end
-- md5
local function md5(content)
	-- urlEncode 把 ' 编成 %27、空格编成 +，拼进单引号是安全的（已核实）；
	-- 但句柄仍然显式 close —— 每个节点要算两次 md5（hashkey + grouphashkey），
	-- 几百个节点就是几百个不关的 fd，撞上 ulimit 会让整轮导入中途失败。
	local stdout = io.popen("echo -n '" .. urlEncode(content) .. "'|md5sum|cut -d ' ' -f1")
	local stdout2 = stdout and stdout:read("*all") or ""
	if stdout then
		stdout:close()
	end
	-- assert(nixio.errno() == 0)
	return trim(stdout2)
	--print(stdout)
	--return stdout
end
-- 处理数据
local function processData(szType, content)
	local result = {
	type = szType,
	local_port = 1234,
	kcp_param = '--nocomp'
	}
	if szType == 'ssr' then
		local dat = split(content, "/%?")
		local hostInfo = split(dat[1], ':')
		result.server = hostInfo[1]
		result.server_port = hostInfo[2]
		result.protocol = hostInfo[3]
		result.encrypt_method = hostInfo[4]
		result.obfs = hostInfo[5]
		result.password = base64Decode(hostInfo[6])
		local params = {}
		for _, v in pairs(split(dat[2], '&')) do
			local t = split(v, '=')
			params[t[1]] = t[2]
		end
		result.obfs_param = base64Decode(params.obfsparam)
		result.protocol_param = base64Decode(params.protoparam)
		local group = base64Decode(params.group)
		if group then
			result.alias = "["  .. group .. "] "
		end
		result.alias = result.alias .. base64Decode(params.remarks)
	elseif szType == 'vmess' then
	        local content2 = "[[" .. content .. "]]"
		local info = cjson.decode(content)
                result.type = 'v2ray'
		result.server = info.add
		result.server_port = info.port
		result.transport = info.net
		result.alter_id = info.aid
		result.vmess_id = info.id
		result.alias = info.ps
		result.network = info.net
		-- result.mux = 1
		-- result.concurrency = 8
		if info.net == 'ws' then
			result.ws_host = info.host
			result.ws_path = info.path
		end
		if info.net == 'h2' then
			result.h2_host = info.host
			result.h2_path = info.path
		end
		if info.net == 'tcp' then
			if info.type and info.type ~= "http" then
				info.type = "none"
			end
			result.tcp_guise = info.type
			result.http_host = info.host
			result.http_path = info.path
		end
		if info.net == 'kcp' then
			result.kcp_guise = info.type
			result.mtu = 1350
			result.tti = 50
			result.uplink_capacity = 5
			result.downlink_capacity = 20
			result.read_buffer_size = 2
			result.write_buffer_size = 2
		end
		if info.net == 'quic' then
			result.quic_guise = info.type
			result.quic_key = info.key
			result.quic_security = info.securty
		end
		if info.net == 'httpupgrade' then
			result.httpupgrade_host = info.host
			result.httpupgrade_path = info.path
		end
		if info.net == 'splithttp' then
			result.splithttp_host = info.host
			result.splithttp_path = info.path
		end
		if info.security then
			result.security = info.security
		end
		if info.tls == "tls" or info.tls == "1" then
			result.tls = "1"
			result.tls_host = info.host
			result.insecure = 1
		else
			result.tls = "0"
		end
	elseif szType == 'vless' then
		local idx_sp = 0
		local alias = ""
		if content:find("#") then
			idx_sp = content:find("#")
			alias = content:sub(idx_sp + 1, -1)
		end
		local info = content:sub(1, idx_sp - 1)
		local hostInfo = split(info, "@")
		local host = split(hostInfo[2], ":")
		local userinfo = hostInfo[1]
		local password = userinfo		
		result.alias = UrlDecode(alias)
		result.type = "xray"
		result.server = host[1]
		-- 按照官方的建议 默认验证ssl证书
		result.insecure = "0"
		result.security = "none"
		result.tls = "1"
		if host[2]:find("?") then
			local query = split(host[2], "?")
			result.server_port = query[1]
			local params = {}
			for _, v in pairs(split(UrlDecode(query[2]), '&')) do
				local t = split(v, '=')
				params[t[1]] = t[2]
			end
			result.transport = params.type --vless的传输方式tcp/kcp/ws/http/quic
			result.network = params.type
			if result.transport == 'ws' then
				result.ws_host = params.host
				result.ws_path = params.path
			end
			if result.transport == 'h2' then
				result.h2_host = params.host
				result.h2_path = params.path
			end
			if result.transport == 'tcp' then
				if params.type and params.type ~= "http" then
					params.type = "none"
				end
				result.tcp_guise = params.type
				result.http_host = params.host
				result.http_path = params.path
			end
			if result.transport == 'kcp' then
				result.kcp_guise = params.type
				result.mtu = 1350
				result.tti = 50
				result.uplink_capacity = 5
				result.downlink_capacity = 20
				result.read_buffer_size = 2
				result.write_buffer_size = 2
			end
			if result.transport == 'quic' then
				result.quic_guise = params.type
				result.quic_key = params.key
				result.quic_security = params.security
			end
			if info.net == 'httpupgrade' then
			result.httpupgrade_host = info.host
			result.httpupgrade_path = info.path
			end
			if info.net == 'splithttp' then
			result.splithttp_host = info.host
			result.splithttp_path = info.path
			end
			if params.encryption then
				result.security = params.encryption --vless security默认none
			end
			if params.security == "tls" or params.security == "1" then --传输层security
				result.tls = "1"
				result.tls_host = params.host
				result.insecure = 0
				result.flow = "0"
			elseif params.security == "reality" or params.security == "2" then
				result.tls = "2"
				-- REALITY 的 serverName 取自 sni。链接里同时有 host 时，host 通常是给
				-- ws/http 用的 Host 头，拿它当 serverName 会握手失败，所以 sni 优先
				result.tls_host = params.sni or params.host
				result.insecure = 0
				if params.flow == "xtls-rprx-vision" then
					result.flow = "1"
				else
					result.flow = "2"
				end
				-- REALITY 客户端四件套。xray 对这四个字段是硬要求，少任何一个都会
				-- 拒绝加载整份配置（表现是「科学上网整个不通」，很难指向这里）。
				-- 分享链接里的参数名与配置里的字段名不同，在这里做映射：
				--   pbk -> publicKey   sid -> shortId   fp -> fingerprint   spx -> spiderX
				result.reality_public_key = params.pbk or ""
				result.reality_short_id = params.sid or ""
				result.reality_fingerprint = params.fp or "chrome"
				result.reality_spider_x = params.spx or "/"
			else
				result.tls = "0"
			end
		else
			result.server_port = host[2]
		end
		result.alter_id = 0 --设为level
		result.vmess_id = password
	elseif szType == "ss" then
		local idx_sp = 0
		local alias = ""
		if content:find("#") then
			idx_sp = content:find("#")
			alias = content:sub(idx_sp + 1, -1)
		end
		local info = content:sub(1, idx_sp - 1)
		local hostInfo = split(base64Decode(info), "@")
		local host = split(hostInfo[2], ":")
		local userinfo = base64Decode(hostInfo[1])
		local method = userinfo:sub(1, userinfo:find(":") - 1)
		local password = userinfo:sub(userinfo:find(":") + 1, #userinfo)
		result.alias = UrlDecode(alias)
		result.type = "ss"
		result.server = host[1]
		if host[2]:find("/%?") then
			local query = split(host[2], "/%?")
			result.server_port = query[1]
			local params = {}
			for _, v in pairs(split(query[2], '&')) do
				local t = split(v, '=')
				params[t[1]] = t[2]
			end
			if params.plugin then
				local plugin_info = UrlDecode(params.plugin)
				local idx_pn = plugin_info:find(";")
				if idx_pn then
					result.plugin = plugin_info:sub(1, idx_pn - 1)
					result.plugin_opts = plugin_info:sub(idx_pn + 1, #plugin_info)
				else
					result.plugin = plugin_info
				end
				if result.plugin == "simple-obfs" then
					result.plugin = "obfs-local"
				end
			end
		else
			result.server_port = host[2]:gsub("/","")
		end
		result.encrypt_method_ss = method
		result.password = password
	elseif szType == "ssd" then
		result.type = "ss"
		result.server = content.server
		result.server_port = content.port
		result.password = content.password
		result.encrypt_method_ss = content.encryption
		result.plugin = content.plugin
		result.plugin_opts = content.plugin_options
		result.alias = "[" .. content.airport .. "] " .. content.remarks
	elseif szType == "sip008" then
		result.type = "ss"
		result.server = content.server
		result.server_port = content.server_port
		result.password = content.password
		result.encrypt_method_ss = content.method
		result.plugin = content.plugin
		result.plugin_opts = content.plugin_opts
		result.alias = content.remarks
	elseif szType == "trojan" then
		local idx_sp = 0
		local alias = ""
		if content:find("#") then
			idx_sp = content:find("#")
			alias = content:sub(idx_sp + 1, -1)
		end
		local info = content:sub(1, idx_sp - 1)
		local hostInfo = split(info, "@")
		local host = split(hostInfo[2], ":")
		local userinfo = hostInfo[1]
		local password = userinfo
		result.alias = UrlDecode(alias)
		result.type = "trojan"
		result.server = host[1]
		-- 按照官方的建议 默认验证ssl证书
		result.insecure = "0"
		result.tls = "1"
		if host[2]:find("?") then
			local query = split(host[2], "?")
			result.server_port = query[1]
			local params = {}
			for _, v in pairs(split(query[2], '&')) do
				local t = split(v, '=')
				params[t[1]] = t[2]
			end
			if params.sni then
				-- 未指定peer（sni）默认使用remote addr
				result.tls_host = params.sni
			end
			if params.allowInsecure == "1" then
				result.insecure = "1"
			else
				result.insecure = "0"
			end
		else
			result.server_port = host[2]
		end
		result.password = password
	end
	-- 兜底别名。tostring 包一层是必须的：解析残缺的链接（比如 vless://xxx 没有 @）
	-- 会让 server / server_port 为 nil，直接拼串抛 "attempt to concatenate a nil value"
	-- —— 那会中断整轮导入，后面所有订阅 URL 一起作废，症状是「订阅只剩前几个」。
	if not result.alias then
		result.alias = tostring(result.server or '') .. ':' .. tostring(result.server_port or '')
	end
	-- alias 不参与 hashkey 计算
	local alias = result.alias
	result.alias = nil
	local switch_enable = result.switch_enable
	result.switch_enable = nil
	--print(cjson.encode(result))
	result.hashkey = md5(cjson.encode(result))
	print(result.hashkey)
	result.alias = alias
	result.switch_enable = switch_enable
	return result
end
-- wget
local function wget(url)
	-- url 来自用户填写的订阅地址框，直接拼进双引号串：
	-- 里面一个 " 就能闭合引号，后面跟 $(...) 或 `...` 即以 root 执行。
	-- 用 shell_quote 统一处理，同时显式 close 句柄。
	local stdout = io.popen('curl -s --connect-timeout 15 --retry 5 ' .. shell_quote(url))
	local sresult = stdout and stdout:read("*all") or ""
	if stdout then
		stdout:close()
	end
	return trim(sresult)
end

-- 节点字段统一清洗：剔除 ' 与 \
--
-- 为什么这【不是】顺手清理，而是必须：
--   · ' —— ① 写库走 shell（dbus set 那行），' 会闭合引号；
--          ② 读库走 httpd/src/web_ex.c 的 db_print，它把值原样嵌进 JS 单引号字符串
--             （o["ssconf_basic_json_1"]='<值>';），一个 ' 就让整个页面脚本变成
--             未闭合字符串 —— 表现是「节点管理页面整个白屏/报错」，很难指向订阅内容。
--   · \ —— 面板侧的 XR.clean() 同样剔除，且 xray 配置生成后会经
--          shadowsocks.sh 的 sed 's/\\//g' 剥掉所有反斜杠，带 \ 的密码本来就连不上，
--          留着只会让「面板手工添加」与「订阅导入」两条路径行为不一致。
-- 换言之：面板本来就维持着「节点值不含 ' 与 \」这个不变量，
-- 导入订阅不该是绕过它的后门。
local function sanitize_node(node)
	local stripped = false
	for k, v in pairs(node) do
		if type(v) == "string" and (v:find("'", 1, true) or v:find("\\", 1, true)) then
			node[k] = v:gsub("['\\]", "")
			stripped = true
		end
	end
	return stripped
end

local function check_filer(result)
	do
		local filter_word = split(filter_words, "/")
		print(cjson.encode(filter_word))
		for i, v in pairs(filter_word) do
			-- 第四参 true = 纯文本匹配。不加的话 v 被当成 Lua 模式：
			-- 关键词里的 % . ( ) [ 等会被当元字符（%d 甚至能匹配到任意数字），
			-- 过滤结果与用户实际输入的关键词对不上。
			if result.alias:find(v, 1, true) then
				log('订阅节点关键字过滤:“' .. v ..'” ，该节点被丢弃')
				return true
			end
		end
	end
end
	--local execute = function()
	-- exec
	local add, del = 0, 0
	do
		for k, url in ipairs(subscribe_url) do
			local raw = wget(url)
			if #raw > 0 then
				local nodes, szType
				local groupHash = md5(url)
				cache[groupHash] = {}
				tinsert(nodeResult, {})
				local index = #nodeResult
				-- 订阅内容三种形态，按「先特征、后兜底」判定：
				--   ① ssd://<base64(JSON)>    机场常用
				--   ② 明文 JSON（SIP008）     每项自带 server + method
				--   ③ base64(多行分享链接)    最常见
				if raw:find('ssd://') then
					szType = 'ssd'
					local nEnd = select(2, raw:find('ssd://'))
					-- jsonParse 这个函数在整个仓库里【不存在】，原样调用必抛
					-- "attempt to call a nil value" —— SSD 订阅一条都导不进来。
					-- 改用 cjson.decode 并用 pcall 兜住：远端内容不可信，
					-- 解析失败只该丢这一个订阅，不该让整轮导入崩掉。
					local decoded = base64Decode(raw:sub(nEnd + 1, #raw))
					local okd, obj = pcall(cjson.decode, decoded)
					if okd and type(obj) == "table" and type(obj.servers) == "table" then
						local extra = {
							airport = obj.airport,
							port = obj.port,
							encryption = obj.encryption,
							password = obj.password
						}
						local servers = {}
						-- SS里面包着 干脆直接这样
						for _, server in ipairs(obj.servers) do
							tinsert(servers, setmetatable(server, { __index = extra }))
						end
						nodes = servers
					else
						nodes = {}
						log('SSD 订阅内容不是合法 JSON，已跳过: ' .. tostring(url))
					end
				else
					-- 先试 SIP008：明文 JSON。
					-- 原来这里写的是 `elseif info then`，而 info 是【各分支内的局部变量】，
					-- 在这个作用域里根本不存在（读的是全局 nil）—— 条件恒假，
					-- 于是 SIP008 订阅永远掉进下面的 base64 分支，
					-- 把一段明文 JSON 当 base64 解，结果全部节点被丢弃。
					local okj, obj = pcall(cjson.decode, raw)
					if okj and type(obj) == "table" then
						local servers = obj.servers or obj
						if type(servers) == "table" and type(servers[1]) == "table"
							and servers[1].server and servers[1].method then
							szType = 'sip008'
							nodes = servers
						end
					end
					if not nodes then
						-- ③ base64 多行分享链接。
						-- gsub(" ", "_") 原样保留：分享链接用 base64 的 URL-safe 变体，
						-- 而部分机场把 + 换成了空格，换回 _ 后由 base64Decode 再还原成 /
						nodes = split(base64Decode(raw):gsub(" ", "_"), "\n")
					end
				end
				nodes = nodes or {}
				for _, v in ipairs(nodes) do
					if v then
						local result
						if szType  then
							result = processData(szType, v)
						elseif not szType then
							local node = trim(v)
							local dat = split(node, "://")
							if dat and dat[1] and dat[2] then
								local dat3 = ""
								if dat[3] then
									dat3 = "://" .. dat[3]
								end
								if dat[1] == 'ss' or dat[1] == 'trojan' or dat[1] == 'vless' then
									result = processData(dat[1], dat[2] .. dat3)
								else
									result = processData(dat[1], base64Decode(dat[2]))
								end
							end
						else
							log('跳过未知类型: ' .. szType)
						end
						if result then
							if
								not result.server or
								not result.server_port or
								check_filer(result) or
								result.server:match("[^0-9a-zA-Z%-%.%s]") -- 中文做地址的 也没有人拿中文域名搞，就算中文域也有Puny Code SB 机场
							then
								log('丢弃无效节点: ' .. result.type ..' 节点, ' .. result.alias)
							else
								log('成功解析: ' .. result.type ..' 节点, ' .. result.alias)
								result.grouphashkey = groupHash
								tinsert(nodeResult[index], result)
								cache[groupHash][result.hashkey] = nodeResult[index][#nodeResult[index]]
							end
						end
					end
				end
				log('成功解析节点数量: ' ..#nodes)
			else
				log(url .. ': 获取内容为空')
			end
		end
	end
	-- diff
	do
		if next(nodeResult) == nil then
			log("更新失败，没有可用的节点信息")
			return
		end
		local add, del = 0, 0
		for line in io.lines("/tmp/dlinkold.txt") do
			newline = line
			-- 旧节点号来自文件，但仍只认纯数字：它要拼进 dbus 变量名，
			-- 而紧跟着的是一个【删除】操作 —— 拼错就是把别的节点删掉。
			local oldidx = tostring(line):match("^(%d+)$")
			if not oldidx then
				log('忽略非法节点号: ' .. tostring(line))
			else
				local olddb = io.popen("dbus get ssconf_basic_json_" .. oldidx)
				local old = olddb and olddb:read("*all") or ""
				if olddb then
					olddb:close()
				end
				--print(#old)
				if #old > 1 then
					-- pcall 兜住：库里可能有手工写入或旧版本遗留的非 JSON 值，
					-- 一次 decode 失败不该让整轮 diff 中断（那样新增节点也一起没了）。
					local okold, oldobj = pcall(cjson.decode, old)
					old = okold and oldobj or nil
					if type(old) == "table" then
						if old.grouphashkey or old.hashkey then -- 没有 hash 的不参与删除
							if not nodeResult[old.grouphashkey] or not nodeResult[old.grouphashkey][old.hashkey] then
								-- ★ 这里原本写的是 ..i —— i 是【读订阅列表时】的循环变量，
								--   跑到 diff 阶段早已停在最后一个订阅 URL 的序号上，
								--   于是每删一个节点都在删同一个（错误的）变量：
								--   真正的过期节点一个都没删掉，某个无辜节点却被反复删。
								--   正确的是本轮迭代的 line（旧节点号）。
								local fh = io.popen("dbus remove ssconf_basic_json_" .. oldidx)
								if fh then
									fh:close()
								end
								del = del + 1
							else
								-- 标记一下
								setmetatable(nodeResult[old.grouphashkey][old.hashkey], { __index = { _ignore = true } })
							end
						else
							if not old.coustom then
								old.alias = tostring(old.server or '') .. ':' .. tostring(old.server_port or '')
							end
							log('忽略手动添加的节点: ' .. tostring(old.alias))
						end
					end
				end
			end
		end
		local ssrindext = io.popen('dbus list ssconf_basic_|grep _json_ | cut -d "=" -f1|cut -d "_" -f4|sort -rn|head -n1')
		local ssrindex = ssrindext and ssrindext:read("*all") or ""
		if ssrindext then
			ssrindext:close()
		end
		if #ssrindex == 0 then
			ssrindex = 1
		else
			-- tonumber 可能返回 nil（输出异常时），nil + 1 会直接抛错中断整轮入库
			ssrindex = (tonumber(ssrindex) or 0) + 1
		end
		for k, v in ipairs(nodeResult) do
			for kk, vv in ipairs(v) do
				if not vv._ignore then				
					-- ★★ 这里原先是 "='" .. cjson.encode(vv) .. "'" —— 单引号拼接。
					--    cjson.encode 只转义双引号，【不转义单引号】，所以订阅里任一字段
					--    出现一个 ' 就闭合引号、逃出字符串，后面跟什么就以 root 执行什么。
					--    例如 remarks 写成  a';reboot;#  导入订阅即重启路由器；
					--    写成  a';<任意命令>;#  就是完整的 root RCE。
					--    现在两道防线：
					--      ① sanitize_node() 在入库前剔除 ' 与 \（与面板 XR.clean 一致）；
					--      ② 这里再用 shell_quote 转义 —— 即便将来有人绕过 ① 也断不了命令。
					if sanitize_node(vv) then
						log('节点字段含不支持的字符（单引号/反斜杠），已剔除: ' .. tostring(vv.alias))
					end
					local fh = io.popen("dbus set ssconf_basic_json_" .. ssrindex .. "=" .. shell_quote(cjson.encode(vv)))
					if fh then
						fh:close()
					end
					ssrindex = ssrindex + 1
					add = add + 1

				end
			end
		end
		log('新增节点数量: ' .. add, '删除节点数量: ' .. del)
		log('订阅更新成功')
		end
