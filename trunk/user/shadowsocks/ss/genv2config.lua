local cjson = require "cjson"
local server_section = arg[1]

-- 节点序号会被直接拼进 dbus 变量名（"dbus get ssconf_basic_json_" .. 序号），
-- 必须是纯数字。调用方传的是 nvram 里的节点序号（global_server /
-- udp_relay_server / socks5_enable），正常路径一定是数字；未配置节点时是空串，
-- 这里安静退出，比让下面的 cjson.decode("") 抛错、在日志里留一堆 Lua 报错干净
if not server_section or not server_section:match("^%d+$") then
	os.exit(0)
end
local proto = arg[2]
local local_port = arg[3] or "0"
local socks_port = arg[4] or "0"

-- 代理自身出站的 fwmark，必须与 ss-rules 里 SS_SPEC_WAN_AC 链首的豁免规则一致。
-- 原理与取值说明见 genxrayconfig.lua 的 FW_MARK 注释（两处必须同步）。
local FW_MARK = 0xff
local ssrindext = io.popen("dbus get ssconf_basic_json_" .. server_section)
local servertmp = ssrindext:read("*all")
local server = cjson.decode(servertmp)
local v2ray = {
	log = {
		-- error = "/tmp/ssrplus.log",
		loglevel = "warning"
	},
	-- 传入连接
	inbound = (local_port ~= "0") and {
		port = local_port,
		protocol = "dokodemo-door",
		settings = {
			network = proto,
			followRedirect = true
		},
		sniffing = {
			enabled = true,
			destOverride = { "http", "tls" }
		}
	} or nil,
	-- 开启 socks 代理
	inboundDetour = (proto == "tcp" and socks_port ~= "0") and {
		{
		protocol = "socks",
		port = socks_port,
			settings = {
				auth = "noauth",
				udp = true
			}
		}
	} or nil,
	-- 传出连接
	outbound = {
		protocol = "vmess",
		settings = {
			vnext = {
				{
					address = server.server,
					port = tonumber(server.server_port),
					users = {
						{
							id = server.vmess_id,
							alterId = tonumber(server.alter_id),
							security = server.security
						}
					}
				}
			}
		},
	-- 底层传输配置
		streamSettings = {
			network = server.transport or "tcp",
			security = (server.tls == '1') and "tls" or "none",
			-- sockopt.mark：代理自身出站打 fwmark，绕开 ss-rules 的透明代理劫持链，
			-- 避免自环（原理与取值见 genxrayconfig.lua 的 FW_MARK 注释，两处必须一致）。
			sockopt = {mark = FW_MARK,},
			tlsSettings = {allowInsecure = (server.insecure ~= "0") and true or false,serverName=server.tls_host,},
		tcpSettings = (server.transport == "tcp") and {
			header = {
				type = server.tcp_guise,
				request = {
					path = {server.http_path} or {"/"},
					headers = {Host = {server.http_host} or {}}
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
			wsSettings = (server.transport == "ws") and (server.ws_path or server.ws_host or server.tls_host) and {
				-- ws
				path = server.ws_path,
				headers = (server.ws_host or server.tls_host) and {
					-- headers
					Host = server.ws_host or server.tls_host
				} or nil
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
			} or nil
		},
		mux = {
			enabled = (server.mux == "1") and true or false,
			concurrency = tonumber(server.concurrency)
		}
	},

	-- 额外传出连接
	outboundDetour = {
		{
			protocol = "freedom",
			tag = "direct",
			settings = { keep = "" }
		}
	}
}

print(cjson.encode(v2ray))
