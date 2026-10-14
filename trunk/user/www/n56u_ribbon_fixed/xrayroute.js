/*
 * xrayroute.js —— 分流规则 / 访问控制 / Geo 查询 三个页面共用的前端工具
 *
 * 数据通路（三条，都在这里封装）：
 *   写        POST /applydb.cgi?p=xray   体为 & 分隔的 key=value
 *   读        GET  /dbconf?p=xray,ss     响应是一段 JS，执行后产生 window.db_xray / window.db_ss
 *   执行命令  POST /apply.cgi            action_mode = ' SystemCmd '，值写进 httpd 的 SystemCmd 缓冲
 *
 * 为什么写值必须过 clean()：
 *   服务端 applydb_cgi 最后是 doSystem("dbus set %s='%s'", key, value)
 *   —— 值被包在 shell 单引号里。而 jQuery 1.x 的 $.param 内部用 encodeURIComponent，
 *   它不转义单引号。前端漏一个 ' 过去，后端就是引号断裂 + 命令注入。
 *   所以 clean() 放在 postPairs() 内部，任何页面都绕不过去。
 *
 * 为什么读值也必须干净：
 *   服务端 db_print 是 websWrite("o[\"%s\"]='%s';", key, value)，原样嵌入 JS 单引号字符串。
 *   值里带真换行 → 整个页面脚本变成未闭合字符串；带反斜杠 → 被 JS 再转义一次，
 *   JSON.parse 会拿到非法字符。多行列表因此一律存成「单行、空白分隔」。
 */
(function (global) {
	'use strict';

	// ---------------------------------------------------------------- 工具

	// 单行化 + 去掉会破坏 dbus/JS/shell 三方的字符
	function clean(s) {
		if (s === null || s === undefined) {
			return '';
		}
		return String(s)
			.replace(/[\r\n\t]+/g, ' ')
			.replace(/['\\]/g, '')
			.replace(/ +/g, ' ')
			.replace(/^ | $/g, '');
	}

	// textarea（多行）→ dbus（单行、空白分隔）
	// 顺带砍掉行内注释：引擎按空白切词，"domain:a.com # 备注" 会把「备注」当成一个域名条目
	function packList(s) {
		if (!s) {
			return '';
		}
		var out = [];
		var lines = String(s).split(/\r?\n/);
		for (var i = 0; i < lines.length; i++) {
			var t = clean(lines[i].replace(/#.*$/, ''));
			if (t) {
				out.push(t);
			}
		}
		return out.join(' ');
	}

	// dbus（单行、空白分隔）→ textarea（多行）
	function unpackList(s) {
		if (!s) {
			return '';
		}
		return clean(s).split(' ').join('\n');
	}

	// HTML 文本转义；dbus 里的值来自用户输入，插进 innerHTML 前必须过一遍
	function esc(s) {
		if (s === null || s === undefined) {
			return '';
		}
		return String(s)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;');
	}

	function J() {
		return global.jQuery;
	}

	// ---------------------------------------------------------------- 读

	// 取 dbconf 并执行它（content-type 是 text/javascript，dataType:script 会让 jQuery 求值）
	function jget(url, cb) {
		J().ajax({
			url: url + (url.indexOf('?') < 0 ? '?' : '&') + '_=' + (new Date()).getTime(),
			type: 'get',
			dataType: 'script',
			cache: false,
			success: function () {
				cb();
			},
			error: function () {
				cb();
			}
		});
	}

	// 读 xray 全部键（键很少，轮询命令状态时用这个）
	function loadXray(cb) {
		jget('/dbconf?p=xray', function () {
			cb(global.db_xray || {});
		});
	}

	// 读 xray + ss（需要节点列表时用这个，ss 的键多，只在页面初始化时调）
	function loadAll(cb) {
		jget('/dbconf?p=xray,ss', function () {
			cb(global.db_xray || {}, global.db_ss || {});
		});
	}

	// ---------------------------------------------------------------- 写

	// pairs 形如 {"xray_route_enable":"1","xray_rule_r1":"{...}"}
	// 每个值统一过 clean()；jQuery 负责 URL 编码，服务端 unescape 会还原
	function postPairs(pairs, cb) {
		var body = {};
		for (var k in pairs) {
			if (Object.prototype.hasOwnProperty.call(pairs, k)) {
				body[k] = clean(pairs[k]);
			}
		}
		J().post('/applydb.cgi?p=xray', body, function () {
			if (cb) {
				cb();
			}
		}).fail(function () {
			if (cb) {
				cb('写入失败：请求未完成');
			}
		});
	}

	// 删键：服务端 applydb_cgi 认特殊值 "deleting"（web_ex.c:2114）
	function delKey(key, cb) {
		if (!key) {
			return;
		}
		var o = {};
		o[key] = 'deleting';
		postPairs(o, cb);
	}

	// ---------------------------------------------------------------- 规则模型

	// 扫 dbus 里所有匹配 re 的键，取捕获组里最大的序号 +1
	// 注意正则不能带 g 标志，否则 exec 会记忆 lastIndex，同一个正则复用时会漏匹配
	function next_seq(x, re) {
		var max = 0;
		for (var k in x) {
			var m = re.exec(k);
			if (m) {
				var n = parseInt(m[1], 10);
				if (n > max) {
					max = n;
				}
			}
		}
		return max + 1;
	}

	// 规则 id 形如 r1 / r2
	function nextRuleId(x) {
		return 'r' + next_seq(x, /^xray_rule_r(\d+)$/);
	}

	// ACL 条目 id 形如 a1 / a2
	function nextAclId(x) {
		return 'a' + next_seq(x, /^xray_acl_a(\d+)$/);
	}

	function parseJson(s) {
		try {
			var o = JSON.parse(s);
			return (o && typeof o === 'object') ? o : null;
		} catch (e) {
			return null;
		}
	}

	// 按 xray_route_order 的顺序读出规则数组；坏 JSON 的条目跳过但记下 id
	function rules(x) {
		var out = [];
		var order = (x.xray_route_order || '').split(',');
		for (var i = 0; i < order.length; i++) {
			var id = order[i].replace(/^ +| +$/g, '');
			if (!id) {
				continue;
			}
			var r = parseJson(x['xray_rule_' + id]);
			if (r) {
				r.id = id;
				out.push(r);
			}
		}
		return out;
	}

	function orderOf(x) {
		var out = [];
		var order = (x.xray_route_order || '').split(',');
		for (var i = 0; i < order.length; i++) {
			var id = order[i].replace(/^ +| +$/g, '');
			if (id) {
				out.push(id);
			}
		}
		return out;
	}

	// ACL 条目，结构与 rules() 同构，只是换了键前缀与顺序键
	function acls(x) {
		var out = [];
		var order = (x.xray_acl_order || '').split(',');
		for (var i = 0; i < order.length; i++) {
			var id = order[i].replace(/^ +| +$/g, '');
			if (!id) {
				continue;
			}
			var a = parseJson(x['xray_acl_' + id]);
			if (a) {
				a.id = id;
				out.push(a);
			}
		}
		return out;
	}

	// 规则的匹配摘要，列表页一列显示
	function summary(r) {
		var d = (r.domain_list || '').split(' ').filter(function (v) { return v; });
		var p = (r.ip_list || '').split(' ').filter(function (v) { return v; });
		var out = [];
		if (d.length) {
			out.push('域名 ' + d.slice(0, 2).join(', ') + (d.length > 2 ? ' 等' + d.length + '条' : ''));
		}
		if (p.length) {
			out.push('IP ' + p.slice(0, 2).join(', ') + (p.length > 2 ? ' 等' + p.length + '条' : ''));
		}
		return out.length ? out.join('；') : '(空规则，已跳过)';
	}

	// ---------------------------------------------------------------- 出站节点

	// 引擎侧的 tag 空间是固定的，见 genxrayconfig.lua 的 make_resolver：
	//   default / direct / block / node_<dbus 节点序号>
	function nodes() {
		var list = [
			{ tag: 'default', label: '默认节点（不匹配任何规则时）', fixed: 1 },
			{ tag: 'direct', label: '直连（不走代理）', fixed: 0 },
			{ tag: 'block', label: '拦截（丢弃）', fixed: -1 }
		];
		var ss = global.db_ss || {};
		for (var k in ss) {
			if (k.indexOf('ssconf_basic_json_') !== 0) {
				continue;
			}
			var idx = k.substring('ssconf_basic_json_'.length);
			if (!/^\d+$/.test(idx)) {
				continue;
			}
			var label = '节点 ' + idx;
			var o = parseJson(ss[k]);
			if (o) {
				label = '[' + (o.type || '?') + '] ' + (o.alias || ('节点 ' + idx));
			}
			list.push({ tag: 'node_' + idx, label: label, fixed: null, idx: parseInt(idx, 10) });
		}
		list.sort(function (a, b) {
			if (a.idx === null || a.idx === undefined) {
				return (b.idx === null || b.idx === undefined) ? 0 : -1;
			}
			if (b.idx === null || b.idx === undefined) {
				return 1;
			}
			return a.idx - b.idx;
		});
		return list;
	}

	function nodeLabel(tag) {
		var ns = nodes();
		for (var i = 0; i < ns.length; i++) {
			if (ns[i].tag === tag) {
				return ns[i].label;
			}
		}
		return tag ? tag + '（节点已删除）' : '(未设置)';
	}

	// 往 <select> 里填出站选项。extra 是额外选项数组，如 ACL 的「遵循分流」
	function fillSelect(el, cur, extra) {
		if (!el) {
			return;
		}
		var ns = nodes().concat(extra || []);
		var html = '';
		for (var i = 0; i < ns.length; i++) {
			html += '<option value="' + esc(ns[i].tag) + '"' +
				(ns[i].tag === cur ? ' selected="selected"' : '') + '>' + esc(ns[i].label) + '</option>';
		}
		el.innerHTML = html;
	}

	// ---------------------------------------------------------------- 执行命令

	// POST 后轮询 dbus 状态。
	//
	// 关于完成时机：/apply.cgi 的 SystemCmd 分支会 302 到 current_page，
	// 而那个页面的 ASP 体 nvram_dump("syscmd.log","syscmd.sh") 会触发 httpd 真正
	// 执行命令并等它结束。XHR 会跟随 302 并等完响应体 —— 所以 success 回调触发时
	// 命令至少已经跑到 fork 点。异步命令（分类更新）之后靠轮询 xray_action_run 收尾。
	//
	// 这里刻意不复刻上游 getResponse() 那次额外 GET：它会让 sys_script 看到空的
	// SystemCmd 从而执行 `echo -n > /tmp/syscmd.log` 把日志清掉（web_ex.c:153）。
	// 结果走 dbus，不走那个日志。
	function runCmd(cmd, onDone) {
		post(' SystemCmd ', 'console_response.asp', { SystemCmd: cmd }, function () {
			waitIdle(onDone);
		});
	}

	// 统一表单 POST，用于 action_mode 机制（Command / Restart 等）
	function post(actionMode, currentPage, fields, cb) {
		var body = {
			action_mode: actionMode,
			current_page: currentPage,
			next_page: currentPage
		};
		for (var k in fields) {
			if (Object.prototype.hasOwnProperty.call(fields, k)) {
				body[k] = fields[k];
			}
		}
		J().post('/apply.cgi', body, function () {
			if (cb) {
				cb();
			}
		}).fail(function () {
			if (cb) {
				cb();
			}
		});
	}

	// 轮询直到 xray_action_run 不再是 '1'
	function waitIdle(onDone, triesLeft) {
		var left = (triesLeft === undefined) ? 80 : triesLeft;
		loadXray(function (x) {
			if (x.xray_action_run !== '1' || left <= 0) {
				onDone(x.xray_action_status || '', x);
				return;
			}
			setTimeout(function () {
				waitIdle(onDone, left - 1);
			}, 1500);
		});
	}

	// 重启 xray：走 xrayctl.sh，与面板「应用」按钮同一条 rc 通路
	function restart(cb) {
		runCmd('/etc_ro/ss/xrayctl.sh restart', cb);
	}

	// ---------------------------------------------------------------- 页面状态显示

	// 在指定元素里显示一行状态；busy 时加个转圈提示
	function status(el, msg, busy) {
		if (!el) {
			return;
		}
		el.innerHTML = (busy ? '<span class="label label-warning">处理中</span> ' : '') + esc(msg || '');
	}

	global.XR = {
		clean: clean,
		packList: packList,
		unpackList: unpackList,
		esc: esc,
		jget: jget,
		loadXray: loadXray,
		loadAll: loadAll,
		postPairs: postPairs,
		delKey: delKey,
		nextRuleId: nextRuleId,
		nextAclId: nextAclId,
		parseJson: parseJson,
		rules: rules,
		acls: acls,
		orderOf: orderOf,
		summary: summary,
		nodes: nodes,
		nodeLabel: nodeLabel,
		fillSelect: fillSelect,
		runCmd: runCmd,
		post: post,
		waitIdle: waitIdle,
		restart: restart,
		status: status
	};
})(window);
