--[[
	genxrayconfig.lua —— xray 主配置生成器

	调用（沿用原签名，勿改）：
		lua /etc_ro/ss/genxrayconfig.lua <节点序号> <tcp|udp> <本地端口> [socks端口]
	产物：stdout 的 JSON，由 shadowsocks.sh 重定向到 /tmp/v2-redir.json 或 /tmp/v2-ssr-reudp.json

	在原有「单出站」基础上增加：
		· 多出站：default(全局节点) / direct / block / node_<序号>(规则按需引用)
		· 前置代理：分流规则 / 访问控制里的「前置代理」字段非空时，该规则的基础出站
		  会链到前置节点之后（streamSettings.sockopt.dialerProxy），并生成一个
		  形如 node_5_via_node_3 的独立出站，见 make_resolver
		· routing 段：由 xrayroute.lua 生成，顺序为 [ACL 规则] → [分流规则] → [兜底 default]
		· fakeDns：xray_fakedns=1 时启用；勾了 FakeDNS 的分流规则的域名才走假 IP，
		  一条都没勾时对所有域名生效（见 xrayroute.lua 的域名收集与 build_dns）

	谨慎：本文件产物随后会被 shadowsocks.sh 执行 `sed -i 's/\\//g'`，
	即 JSON 里所有反斜杠都会被剥掉 —— 因此任何条目都不得含反斜杠。
]]

-- 让 require 能找到同目录的 xrayroute.lua（固件里两者都在 /etc_ro/ss/）
package.path = "/etc_ro/ss/?.lua;" .. package.path

local cjson = require "cjson"
local xrayroute = require "xrayroute"

local server_section = arg[1]
local proto = arg[2]
local local_port = arg[3] or "0"
local socks_port = arg[4] or "0"

-- FakeDNS 地址池：与 passwall2 保持一致
local FAKE_IP_POOL = "198.18.0.0/15"

-- 读一个节点，字段取自 dbus 的节点库 ssconf_basic_json_<序号>
local function load_node(idx)
	local fp = io.popen("dbus get ssconf_basic_json_" .. idx)
	local raw = fp and fp:read("*all") or ""
	if fp then
		fp:close()
	end
	if raw == "" then
		return nil
	end
	local ok, obj = pcall(cjson.decode, raw)
	if not ok or type(obj) ~= "table" or not obj.server then
		return nil
	end
	return obj
end

-- 传入连接（dokodemo-door + 透明代理 + 域名嗅探）
local function build_inbound(fakedns_on)
	local dest = { "http", "tls" }
	if fakedns_on then
		dest[#dest + 1] = "fakedns"
	end
	return {
		port = local_port,
		protocol = "dokodemo-door",
		settings = {
			network = proto,
			followRedirect = true
		},
		sniffing = {
			enabled = true,
			destOverride = dest
		}
	}
end

-- 按节点字段生成 vmess 或 vless 出站。字段映射沿用原实现，勿改
--
-- dialer_proxy（可选）：前置代理出站的 tag。非空时本出站不自己直连目标服务器，
--   而是把 TCP 拨号交给那个出站去完成 —— 即「本节点挂在前置节点后面」的链式代理，
--   对应面板上「分流规则 / 访问控制」里的「前置代理」。
--   xray 的字段是 streamSettings.sockopt.dialerProxy。
--   传 nil 时 sockopt 整段不生成（而不是生成空表），与加这个参数之前逐字节一致。
local function build_node_outbound(server, tag, dialer_proxy)
	-- TLS / REALITY 两段先算好再塞进表里。直接写在表构造式里的话每段都是一串 and/or
	-- 三元，把整个函数的圈复杂度顶到远超门禁（lizard 报 CCN 50+），拆出来既降复杂度也好读。
	local tls_settings, reality_settings
	if server.tls == '1' then
		tls_settings = {
			allowInsecure = (server.insecure ~= "0") and true or false,
			serverName = server.tls_host
		}
	elseif server.tls == '2' then
		-- REALITY 客户端必须给全 serverName / fingerprint / publicKey / shortId，
		-- 少任何一个 xray 都拒绝加载 —— 且是整份配置失败，不是单条出站失效，
		-- 分流规则与其它节点会一起失效。
		-- 原实现只写 allowInsecure + serverName，所以面板导入 reality 链接后
		-- xray 直接起不来（报 empty "fingerprint"）。面板目前还没有存公钥/短 ID
		-- 的字段，要配合 UI 一起补。
		reality_settings = {
			serverName = server.tls_host,
			fingerprint = server.reality_fingerprint or "chrome",
			publicKey = server.reality_public_key,
			shortId = server.reality_short_id or "",
			spiderX = server.reality_spider_x or "/"
		}
	end

	-- VMess 与 VLess 的 users 结构不同：VMess 认 alterId/security，VLess 认 flow/encryption/level。
	-- 节点的 type 字段就是协议标识 —— 面板下拉框 value="v2ray" 显示 Vmess、value="xray" 显示 VLess，
	-- 而 shadowsocks.sh 只按 type 挑配置生成器，所以这里必须跟着 type 分协议。
	-- 不分的话 VMess 节点会被写成 vless 出站：JSON 合法、xray 也能加载，但协议对不上根本连不通，
	-- 而且 vmess 的 flow 字段还会被 vless 分支错当 XTLS flow。
	local is_vmess = (server.type == "v2ray")
	local user_entry
	if is_vmess then
		user_entry = {
			id = server.vmess_id,
			alterId = tonumber(server.alter_id) or 0,
			security = server.security or "auto"
		}
	else
		user_entry = {
			id = server.vmess_id,
			flow = (server.flow == '1') and "xtls-rprx-vision" or ((server.flow == '2') and "xtls-rprx-vision-udp443" or ""),
			level = tonumber(server.alter_id),
			encryption = server.security
		}
	end

	return {
		protocol = is_vmess and "vmess" or "vless",
		tag = tag,
		settings = {
			vnext = {
				{
					address = server.server,
					port = tonumber(server.server_port),
					users = { user_entry }
				}
			}
		},
		-- 底层传输配置
		streamSettings = {
			network = server.transport,
			security = (server.tls == '1') and "tls" or ((server.tls == '2') and "reality" or "none"),
			tlsSettings = tls_settings,
			realitySettings = reality_settings,
			tcpSettings = (server.transport == "tcp" and server.tls ~= '2') and {
				header = {
					-- tcp_guise 可能为空（面板「TCP 伪装」没填时就是 nil）：cjson 会把它编成
					-- "type":null 或整个键漏掉，xray 报 invalid TCP header config 直接拒载
					-- 整份配置 —— 连分流带节点一起失效。兜底成 "none" 与 xray 默认语义一致。
					type = server.tcp_guise or "none", -- 伪装
					request = {
						path = server.http_path or { "/" },
						headers = {
							Host = server.http_host or {}
						}
					} or {}
				}
			} or nil,
			kcpSettings = (server.transport == "kcp") and {
				mtu = tonumber(server.mtu),
				tti = tonumber(server.tti),
				uplinkCapacity = tonumber(server.uplink_capacity),
				downlinkCapacity = tonumber(server.downlink_capacity),
				congestion = (server.congestion == "1") and true or false,
				readBufferSize = tonumber(server.read_buffer_size),
				writeBufferSize = tonumber(server.write_buffer_size),
				header = {
					type = server.kcp_guise
				}
			} or nil,
			wsSettings = (server.transport == "ws") and (server.ws_path ~= nil or server.ws_host ~= nil) and {
				path = server.ws_path,
				headers = (server.ws_host ~= nil) and {
					Host = server.ws_host
				} or nil,
			} or nil,
			grpcSettings = (server.transport == "grpc") and (server.grpc_path ~= nil) and {
				serviceName = server.grpc_path
			} or nil,
			httpSettings = (server.transport == "h2") and {
				path = server.h2_path,
				host = server.h2_host,
			} or nil,
			quicSettings = (server.transport == "quic") and {
				security = server.quic_security,
				key = server.quic_key,
				header = {
					type = server.quic_guise
				}
			} or nil,
			httpupgradeSettings = (server.transport == "httpupgrade") and (server.httpupgrade_path ~= nil or server.httpupgrade_host ~= nil) and {
				path = server.httpupgrade_path,
				headers = (server.httpupgrade_host ~= nil) and {
					Host = server.httpupgrade_host
				} or nil,
			} or nil,
			splithttpSettings = (server.transport == "splithttp") and (server.splithttp_path ~= nil or server.splithttp_host ~= nil) and {
				path = server.splithttp_path,
				headers = (server.splithttp_host ~= nil) and {
					Host = server.splithttp_host
				} or nil,
			} or nil,
			-- 前置代理：sockopt.dialerProxy 指向另一个出站的 tag，xray 会先用那个出站
			-- 建立到本出站服务器的 TCP 连接，再由本出站跑自己的协议握手。
			-- 注意 tag 里不能出现反斜杠（本文件头部第 14-15 行：产物会被
			-- sed -i 's/\\//g' 剥掉所有反斜杠，反斜杠会被无声吃掉导致 tag 对不上）。
			sockopt = dialer_proxy and { dialerProxy = dialer_proxy } or nil,
		},
		mux = {
			enabled = (server.mux == "1") and true or false,
			concurrency = tonumber(server.concurrency)
		}
	}
end

-- 只有 v2ray/xray 类型节点才能按上面的字段映射生成 vless 出站
local function buildable(node)
	local t = node.type
	return t == nil or t == "v2ray" or t == "xray"
end

-- 出站解析器：把规则里写的 tag 变成真实存在的出站
--   default / direct / block 直接可用
--   node_<序号> 按需构建；指向全局节点时复用 default；未知或不支持的节点回落 default
--
-- 第二个参数 preproxy 是「前置代理」（面板上分流规则 / 访问控制的同名下拉框）：
--   非空时把基础出站【链到】前置节点之后，并另建一个独立出站返回给规则用，
--   而不是就地改基础出站 —— 同一个基础出站会被多条规则引用（还有 routing 的兜底
--   规则写死 "default"），就地改会让没设前置代理的规则一起被牵连。
local function make_resolver(outbounds, server_section, server)
	local known = { default = true, direct = true, block = true }
	-- 节点缓存：一个序号可能被「基础出站」和「前置出站」各要一次，而 load_node
	-- 每次都要 fork 一个 dbus 进程去读 nvram，缓存掉能省掉一半的进程开销。
	-- 用 false 记「读过但读不到」，与 nil 区分开，避免反复重试。
	local cache = { [tostring(server_section)] = server }
	local function node_at(idx)
		local key = tostring(idx)
		if cache[key] == nil then
			cache[key] = load_node(key) or false
		end
		return cache[key] or nil
	end

	-- 把 tag 解析成真实存在的出站 tag，必要时现场构建并追加进出站表
	local function ensure(tag)
		if known[tag] then
			return tag
		end
		local idx = tag and tag:match("^node_(%d+)$")
		if not idx then
			return "default"
		end
		if idx == tostring(server_section) then
			-- 指向全局节点：复用已有的 default 出站，不重复建
			return "default"
		end
		local node = node_at(idx)
		if not node or not buildable(node) then
			return "default"
		end
		outbounds[#outbounds + 1] = build_node_outbound(node, tag)
		known[tag] = true
		return tag
	end

	return function(tag, preproxy)
		local base = ensure(tag)
		-- direct / block 是本地出站（freedom / blackhole），既没有可挂 sockopt 的
		-- 传输层，链前置代理也没有任何意义，直接返回
		if base == "direct" or base == "block" then
			return base
		end
		-- 前置代理存的是节点序号（面板下拉框的 value 是 node_<n> 里的 <n>）。
		-- 空串 / 非数字（老数据没有这个字段时就是 nil）一律视为「不使用前置代理」，
		-- 这样升级固件后旧规则的行为与升级前完全一致。
		local pidx = tostring(preproxy or "")
		if not pidx:match("^%d+$") then
			return base
		end
		local ptag = ensure("node_" .. pidx)
		-- 前置就是基础出站本身 ⇒ 自链。xray 会把这种循环依赖判为配置错误并拒绝
		-- 加载【整份配置】，连分流带节点一起失效，所以必须在这里挡掉。
		if ptag == base then
			return base
		end
		-- 同一个 (基础, 前置) 组合可能被多条规则引用，复用已经建好的那个出站
		local vtag = base .. "_via_" .. ptag
		if known[vtag] then
			return vtag
		end
		-- 基础出站若是 default，它对应的节点就是全局节点 server（已在缓存里）
		local src = (base == "default") and server or node_at(base:match("^node_(%d+)$"))
		if not src or not buildable(src) then
			return base
		end
		outbounds[#outbounds + 1] = build_node_outbound(src, vtag, ptag)
		known[vtag] = true
		return vtag
	end
end

-- DNS 段。只在 FakeDNS 开关打开时生成，避免动到当前能用的解析链路。
--
-- fakedns_domains 非空 ⇒ 只有名单里的域名拿假 IP；
--                  为空 ⇒ 对所有域名生效（面板契约，见 Shadowsocks_RuleEdit.asp）。
--
-- ★ 关键：带名单时 fakedns 条目【必须】加 skipFallback = true。
-- 原因是 xray 1.8.24 的 app/dns/dns.go sortClients()：域名匹配只决定候选【顺序】，
-- 之后还有一轮 fallback，把所有没标 skipFallback 的 DNS 全部追加进候选 ——
-- 而 fakedns 对任何域名都能编出一个假 IP，进了候选就必胜，
-- 结果是名单怎么写都会变成全局假 IP（实测：名单外的 example.com 也拿到 198.19.x.x）。
-- 加了 skipFallback，fakedns 只能靠域名匹配进场，匹配不上就彻底出局。
-- 实测对照（同版本 macOS 二进制，判别式用名单外的 example.com）：
--   带 skipFallback → 104.20.23.154（真 IP）；不带 → 198.18.207.203（假 IP）
local function build_dns(fakedns_domains)
	local servers = {}
	if fakedns_domains and #fakedns_domains > 0 then
		servers[#servers + 1] = {
			address = "fakedns",
			domains = fakedns_domains,
			skipFallback = true
		}
	else
		servers[#servers + 1] = "fakedns"
	end
	-- 上游放后面：fakedns 匹配不上的域名由它做真实解析
	servers[#servers + 1] = xrayroute.dbus_get("xray_remote_dns") or "1.1.1.1"
	return { servers = servers }
end

local function main()
	local server = load_node(server_section)
	if not server then
		io.stderr:write("genxrayconfig: 节点 " .. tostring(server_section) .. " 读取失败\n")
		os.exit(1)
	end

	-- FakeDNS 只在透明代理（dokodemo-door）模式有意义：它靠入站的 sniffer 把假 IP
	-- 还原成域名。本地 socks 模式（local_port=0，见 shadowsocks.sh 的 v2-ssr-local）
	-- 没有这个入站，开了只会把假 IP 发给客户端又还原不回来，客户端 DNS 直接坏掉。
	local fakedns_on = (local_port ~= "0") and (xrayroute.dbus_get("xray_fakedns") == "1")

	-- 基础出站。default 是全局节点，也是 routing 的最终兜底
	local outbounds = {
		build_node_outbound(server, "default"),
		{
			protocol = "freedom",
			tag = "direct",
			settings = { keep = "" }
		},
		{
			protocol = "blackhole",
			tag = "block",
			settings = { response = { type = "none" } }
		}
	}

	local resolve = make_resolver(outbounds, server_section, server)
	local routing, fakedns_domains = xrayroute.build_routing(resolve)

	-- 传入连接。用新式 inbounds 数组键，不用 deprecated 的 inbound/inboundDetour：
	-- xray 的 FakeDNS 后处理只扫 InboundConfigs（app/conf/conf_fakedns.go 的
	-- FakeDNSPostProcessingStage.Process），扫不到就误报
	-- "Defined FakeDNS but haven't enabled FakeDNS destOverride at any inbound"，
	-- 而 loglevel 是 warning，这条会真打进路由器日志，误导后续排障。
	local inbounds = {}
	if local_port ~= "0" then
		inbounds[#inbounds + 1] = build_inbound(fakedns_on)
	end
	-- 开启 socks 代理
	if proto == "tcp" and socks_port ~= "0" then
		inbounds[#inbounds + 1] = {
			protocol = "socks",
			port = socks_port,
			settings = {
				auth = "noauth",
				udp = true
			}
		}
	end

	local xray = {
		log = {
			-- error = "/tmp/ssrplus.log",
			loglevel = "warning"
		},
		-- 空数组在 cjson 里会被编码成 {} 而不是 []，所以为空时给 nil
		inbounds = (#inbounds > 0) and inbounds or nil,
		dns = fakedns_on and build_dns(fakedns_domains) or nil,
		fakeDns = fakedns_on and { ipPool = FAKE_IP_POOL, poolSize = 65535 } or nil,
		outbounds = outbounds,
		routing = routing
	}

	print(cjson.encode(xray))
end

main()
