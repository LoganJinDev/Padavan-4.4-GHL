--[[
	genxrayconfig.lua —— xray 主配置生成器

	调用（沿用原签名，勿改）：
		lua /etc_ro/ss/genxrayconfig.lua <节点序号> <tcp|udp> <本地端口> [socks端口]
	产物：stdout 的 JSON，由 shadowsocks.sh 重定向到 /tmp/v2-redir.json 或 /tmp/v2-ssr-reudp.json

	在原有「单出站」基础上增加：
		· 多出站：default(全局节点) / direct / block / node_<序号>(规则按需引用)
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

-- 按节点字段生成 vless 出站。字段映射沿用原实现，勿改
local function build_node_outbound(server, tag)
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

	return {
		protocol = "vless",
		tag = tag,
		settings = {
			vnext = {
				{
					address = server.server,
					port = tonumber(server.server_port),
					users = {
						{
							id = server.vmess_id,
							flow = (server.flow == '1') and "xtls-rprx-vision" or ((server.flow == '2') and "xtls-rprx-vision-udp443" or ""),
							level = tonumber(server.alter_id),
							encryption = server.security
						}
					}
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
					type = server.tcp_guise, -- 伪装
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
local function make_resolver(outbounds, server_section)
	local known = { default = true, direct = true, block = true }
	return function(tag)
		if known[tag] then
			return tag
		end
		local idx = tag and tag:match("^node_(%d+)$")
		if not idx or idx == server_section then
			return "default"
		end
		local node = load_node(idx)
		if not node or not buildable(node) then
			return "default"
		end
		outbounds[#outbounds + 1] = build_node_outbound(node, tag)
		known[tag] = true
		return tag
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

	local resolve = make_resolver(outbounds, server_section)
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
