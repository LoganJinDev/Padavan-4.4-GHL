<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - <#menu5_38#></title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">

<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/engage.itoggle.css">

<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/bootstrap/js/bootstrap.min.js"></script>
<script type="text/javascript" src="/bootstrap/js/engage.itoggle.min.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/itoggle.js"></script>
<script type="text/javascript" src="/client_function.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/help_b.js"></script>
<script>
var $j = jQuery.noConflict();

$j(document).ready(function() {
	
	init_itoggle('easytier_enable');
	init_itoggle('easytier_masq');
	init_itoggle('easytier_disable_p2p');
	init_itoggle('easytier_dhcp');
	init_itoggle('easytier_latency_first');
	init_itoggle('easytier_disable_ipv6');
	init_itoggle('easytier_enable_exit_node');
	init_itoggle('easytier_disable_encryption');
	init_itoggle('easytier_disable_upnp');
	init_itoggle('easytier_private_mode');
	init_itoggle('easytier_multi_thread');
	init_itoggle('easytier_check_enable');

	// P3 日志区块：等 DOM 就绪再初始化（要绑事件、要读 textarea）
	et_log_init();

	// 二进制版本下拉框：回填已保存的值（见 et_ver_init 的注释）
	et_ver_init();
});

</script>
<script>

<% login_state_hook(); %>


function initial(){
	show_banner(2);
	show_menu(5,17,0);
	showmenu();
	show_footer();

	// nvram 里还没有 easytier_bin_state 这个键时，格子是空的
	if ($j.trim($j("#et_bin_state").text()) === "")
		$j("#et_bin_state").text("（未检测，点右侧「刷新状态」）");

}
function showmenu(){
showhide_div('allink', found_app_aliddns());
showhide_div('zelink', found_app_zerotier());
showhide_div('ddlink', found_app_ddnsto());
showhide_div('wilink', found_app_wireguard());
showhide_div('frlink', found_app_frp());
showhide_div('et_rwfs_row', support_mtd_rwfs());
}

function applyRule(){
//	if(validForm()){
		showLoading();
		
		document.form.action_mode.value = " Restart ";
		document.form.current_page.value = "/Advanced_easytier.asp";
		document.form.next_page.value = "";
		
		document.form.submit();
//	}
}

function done_validating(action){
	refreshpage();
}

function et_syscmd(cmd, onDone){
	// 走 SystemCmd 通道执行一条命令，把回显交给 onDone。
	// ★ 两段式：POST /apply.cgi 只是把命令【登记】进 sys_script，
	//   紧接着的 GET /console_response.asp 才是真正的执行扳机。
	//   少了第二段，命令永远不会跑（而且不报任何错）。
	// ★ 第二段用 complete 而不是 success：GET 失败时也要回调，
	//   否则调用方会永远停在「处理中」，一个错误都看不到。
	// ★ 不做 timeout：httpd 单进程阻塞，命令跑多久这里就等多久。
	$j.ajax({
		type: "POST",
		url: "/apply.cgi",
		data: {
			action_mode: " SystemCmd ",
			current_page: "console_response.asp",
			next_page: "console_response.asp",
			SystemCmd: cmd
		},
		success: function(){
			$j.ajax({
				type: "GET",
				url: "/console_response.asp",
				dataType: "text",
				complete: function(xhr){
					onDone(xhr && xhr.responseText ? $j.trim(xhr.responseText) : "");
				}
			});
		},
		error: function(){ onDone(""); }
	});
}

// 持久存储（RWFS）：只挂载，绝不格式化。
// ★ 脚本末行给一句机器可读的判决词 rwfs_state=<词>，其余是给人看的。
//   这里只拿判决词做一句中文结论，完整回显原样落到详情框 —— 不解析 HTML，
//   回显里有路径，一律当纯文本。
var et_rwfs_mib = 0;
function et_rwfs_show(t){
	var m = /rwfs_state=([a-z]+)/.exec(t || "");
	var word = m ? m[1] : "";
	var sz = /rwfs_size_mib=([0-9]+)/.exec(t || "");
	if (sz) et_rwfs_mib = parseInt(sz[1], 10) || 0;
	var map = {
		mounted:   "已挂载",
		unmounted: "未挂载（开关已开）",
		off:       "挂载开关未开",
		absent:    "本机没有该分区",
		error:     "失败，详见下方输出"
	};
	$j("#et_rwfs_state").text(map[word] || (t ? "命令返回了无法识别的输出（本机可能没有该分区）" : "命令通道无响应"));
	// ★ 破坏性按钮平时不显示 —— 只有真卡在「附加失败 / 卷表丢失」时才露出来。
	//   两条判据：判决词是 error，或脚本给了 rwfs_rebuild=1。
	//   ★ 只判 error 不够：status 在 R3G 那种机器上给的是 unmounted。
	var need = (word === "error") || /rwfs_rebuild=1/.test(t || "");
	$j("#et_rwfs_format_btn").css("display", need ? "" : "none");
	$j("#et_info_out").val(t || "(无输出)");
}

function et_rwfs_enable(){
	// ★ 把「不格式化」写在确认框里：用户对「启用存储」这类按钮的默认预期
	//   就是「会不会清掉我的东西」，不写清楚他会不敢点。
	if (!confirm("将把 RWFS 分区挂载到 /media/mtd_rwfs，并把 EasyTier 二进制改放到那上面。\n\n本操作只挂载，不会格式化，分区里原有的数据不受影响。\n\n继续？")) return;
	$j("#et_rwfs_state").text("正在启用…");
	et_syscmd("rwfs2ubi.sh enable", et_rwfs_show);
}

function et_rwfs_status(){
	$j("#et_rwfs_state").text("正在读取…");
	et_syscmd("rwfs2ubi.sh status", et_rwfs_show);
}

// ★ 破坏性操作：只在「启用持久存储」失败、且状态说明分区卷表已丢失时才需要。
//   两道闸门 —— 这里要求输入小写 ERASE，脚本自己也要求第二个词是 ERASE。
function et_rwfs_format(){
	var cap = et_rwfs_mib > 0 ? "（约 " + et_rwfs_mib + " MiB）" : "";
	var s = prompt("★ 这会【永久抹掉】RWFS 分区上的全部内容" + cap + "，无法恢复。\n\n只在「启用持久存储」失败、且状态里说明分区结构已损坏时才需要这么做。\n\n确认请输入大写 ERASE（区分大小写），其它任何输入都会取消：");
	if (s !== "ERASE") return;
	$j("#et_rwfs_state").text("正在重建…");
	et_syscmd("rwfs2ubi.sh format ERASE", et_rwfs_show);
}

// 把回显写进二进制状态格（单行）。
function et_bin_state_show(t){
	$j("#et_bin_state").text(t || "命令通道无响应");
}

function easytier_dl(){
	// ★ 版本必须随命令带过去：这个按钮走的是 SystemCmd 通道，不是表单提交，
	//   下拉框里选的值不会自己进 nvram。不带的话服务端读到的还是旧版本号，
	//   于是提示「二进制已存在且校验通过（旧版本号），无需下载」，且零报错。
	var v = $j("#easytier_version").val() || "";
	// ★ 这个值会被拼进服务端命令串（sh -c 解释），所以这里必须过滤；
	//   服务端 setver 还会再校验一遍 —— 两道都要，不能只靠一道。
	if (v !== "" && !et_ver_ok(v)) {
		$j("#et_bin_state").text("版本号格式非法，已中止");
		return;
	}
	$j("#et_bin_state").text("正在下载…");
	et_syscmd("easytier.sh dl " + (v === "" ? "default" : v), et_bin_state_show);
}

function easytier_state(){
	et_syscmd("easytier.sh state", et_bin_state_show);
}

// 二进制详情（P4）：路径 / 来源 / 大小 / 所在分区剩余空间。
// ★ 与「刷新状态」分工：状态给单行结论并做 sha256 校验（要等 1~3 秒）；
//   详情只读环境事实，不哈希、秒回。两者刻意不重叠。
// ★ 与「连接信息」的四个按钮不同：这里不查 RPC，二进制缺失时也能跑，
//   正是排障最需要的那一刻。
// ★ 回显里含路径，一律走 .val() 当纯文本写进 textarea，绝不解析 HTML。
function easytier_bininfo(){
	$j("#et_info_state").text("正在读取…");
	$j("#et_info_out").val("");
	et_syscmd("easytier.sh bininfo", function(t){
		$j("#et_info_out").val(t || "(无输出)");
		$j("#et_info_state").text(t ? "" : "命令通道无响应");
	});
}

// ---------------------------------------------------------------------------
// 日志区块（P3）
//
// ★★ 为什么不用「服务端 dump 进 textarea」这个最像先例的写法
//    （Advanced_frp_log.asp 就是这么写的）：那条路最终落到 aspbw.c 的 do_f()，
//    而 do_f 是【裸 fputs】，零转义。日志里只要出现 textarea 的结束标签紧跟着
//    script 标签，就能逃出 textarea 的 RCDATA 上下文 ⇒ 在管理员会话里执行任意
//    脚本（存储型 XSS）。而 easytier.log 是【混合日志】：easytier-core 自己的
//    stdout 也追加进同一个文件，里面有对端主机名 / 网络名这类远端可控字符串。
//    ⇒ 走 SystemCmd 通道取文本，再用 .val() 赋值。.val() 设的是 value 属性，
//    永不解析 HTML，天然免疫。
//    （上面刻意不写具体的标签字面量与服务端脚本标记：本页是 ASP，脚本块里出现
//      「小于号+百分号」会被服务端当真的脚本块执行；而 textarea 的结束标签写进
//      JS 注释里虽然无害，却会让下面的反向判据失去判别力。）
//
// ★ 为什么「级别下拉框」换成「关键字搜索框」：本文件是混合日志，我们自己写的
//   事件行（启动/停止/通断检测状态翻转）不带级别词，只有 core 的行带。用级别
//   过滤会把最该看的行静默藏掉。搜索框能覆盖级别过滤（直接输 ERROR），且无歧义。
// ---------------------------------------------------------------------------

var ET_LOG_TIMER = null;   // 自动刷新定时器
var ET_LOG_BUSY  = false;  // 在途标记
var ET_LOG_RAW   = "";     // 最近一次取回的原始文本（供搜索框重放）

// 去掉 ANSI 颜色转义。
// ★ 刻意放在前端而不是交给 sed：busybox sed 自己只认 \n \t \r 三种反斜杠转义
//   （sed.c 的 copy_parsing_escapes），\x1b 能否生效取决于 libc 的 regex，而那部分
//   源码没随 busybox 进本仓库 ⇒ 在仓库内无法证实。放前端是确定且可测的。
function et_log_strip_ansi(s){
	return String(s === null || s === undefined ? "" : s).replace(/\x1b\[[0-9;]*m/g, "");
}

// 按搜索框内容过滤行。空关键字 = 原样返回。
function et_log_filter(s){
	var kw = $j.trim($j("#et_log_kw").val());
	if (kw === "") return s;
	var arr = s.split("\n"), out = [];
	for (var i = 0; i < arr.length; ++i){
		if (arr[i].indexOf(kw) >= 0) out.push(arr[i]);
	}
	return out.join("\n");
}

// 把文本写进 textarea。★ 只走 .val()，绝不写 innerHTML。
function et_log_paint(){
	var ta = $j("#et_log_text");
	ta.val(et_log_filter(ET_LOG_RAW));
	if (ta[0]) ta.scrollTop(ta[0].scrollHeight);   // 贴到底部，最新的行在末尾
}

function et_log_show(t){
	ET_LOG_RAW = et_log_strip_ansi(t);
	et_log_paint();
}

// 拉一次日志。
// ★ 在途标记是必须的：httpd 是单进程 select 循环，SystemCmd 只有一个
//   static 缓冲槽，重叠的 POST 会互相踩。
function et_log_refresh(){
	if (ET_LOG_BUSY) return;
	ET_LOG_BUSY = true;
	var n = $j("#et_log_lines").val() || "300";
	et_syscmd("easytier.sh log " + n, function(t){
		ET_LOG_BUSY = false;
		et_log_show(t);
	});
}

function et_log_clear(){
	if (ET_LOG_BUSY) return;
	if (!confirm("确定清空日志？只清空文件，不影响正在运行的隧道。")) return;
	ET_LOG_BUSY = true;
	et_syscmd("easytier.sh logclear", function(t){
		ET_LOG_BUSY = false;
		et_log_show(t);
		et_log_refresh();   // 紧接着把清空后的真实内容再拉一次
	});
}

// 自动刷新。★ 页面在后台就不刷：httpd 单进程，后台标签页定时打命令会拖慢整机。
function et_log_autorefresh(on){
	if (ET_LOG_TIMER){ clearInterval(ET_LOG_TIMER); ET_LOG_TIMER = null; }
	if (!on) return;
	ET_LOG_TIMER = setInterval(function(){
		if (document.hidden) return;
		et_log_refresh();
	}, 5000);
}

function et_log_download(){
	try {
		var blob = new Blob([ET_LOG_RAW], {type: "text/plain;charset=utf-8"});
		var url = URL.createObjectURL(blob);
		var a = document.createElement("a");
		a.href = url;
		a.download = "easytier.log";
		document.body.appendChild(a);
		a.click();
		document.body.removeChild(a);
		setTimeout(function(){ URL.revokeObjectURL(url); }, 10000);
	} catch (e) {
		alert("当前浏览器不支持直接下载，请用搜索框筛选后手动复制。");
	}
}

// 初始化：特性探测 + 绑事件 + 首次拉取。
function et_log_init(){
	if (typeof Blob === "undefined" || typeof URL === "undefined" || !URL.createObjectURL)
		$j("#et_log_dl").hide();
	$j("#et_log_kw").on("input keyup", et_log_paint);
	$j("#et_log_lines").on("change", et_log_refresh);
	$j("#et_log_auto").on("change", function(){ et_log_autorefresh(this.checked); });
	et_log_refresh();
}

// 连接信息 11 种查询各自的「处理中」提示。
// ★ 这个对象同时充当 kind 的白名单 —— 与 easytier.sh 里 et_info 的 case 白名单一一对应，
//   两边各挡一道。★ 键必须与后端 11 个 case 臂逐字一致：这里少一个，界面上就多一个
//   「点了没反应」的死选项（easytier_info 会静默 return）；这里多一个，后端会回
//   用法行而不是数据。改动任一侧都要同步另一侧。
var ET_INFO_BUSY = {
	peer:       "正在查询对端列表…",
	route:      "正在查询路由表…",
	node:       "正在查询本机信息…",
	conn:       "正在查询连接器…",
	stun:       "正在查询 NAT 类型…",
	peercenter: "正在查询中继服务器…",
	vpnportal:  "正在查询 VPN 门户…",
	proxy:      "正在查询子网代理…",
	acl:        "正在查询 ACL 规则…",
	mapped:     "正在查询端口映射…",
	stats:      "正在查询运行统计…"
};

// 连接信息：把 easytier-cli 的一张表渲染进只读文本框。
// ★ 用 .val() 写 <textarea>，不用 .html()/.text() 写 div —— .val() 不解析 HTML，
//   命令回显里的任何字符都只当文本，天然没有 XSS 面
//   （与 Shadowsocks_GeoView.asp 的 #result 同一手法）。
function easytier_info(kind){
	if (!ET_INFO_BUSY.hasOwnProperty(kind)) { return; }
	$j("#et_info_state").text("处理中…");
	$j("#et_info_out").val("");
	et_syscmd("easytier.sh info " + kind, function(t){
		$j("#et_info_out").val(t || "(无输出)");
		$j("#et_info_state").text(t ? "" : "命令通道无响应");
	});
}

// 「查询」按钮：从下拉框取 kind。
// ★ 白名单仍由 easytier_info 内的 hasOwnProperty 兜底，而不是靠「下拉框里只有合法值」——
//   下拉框的值虽然是页面常量，但「前端传什么后端就查什么」这条链路不该依赖 UI 的表现。
function et_info_query(){
	easytier_info($j("#et_info_kind").val());
}

// ---------------------------------------------------------------------------
// 二进制版本（task 3）
//
// ★★ 为什么必须 et_ver_init() 回填：<select> 里原本只有「跟随固件默认版本」一个
//    选项。用户存过 v2.7.0 后刷新页面，若不把这个值重新插成 option 并选中，浏览器
//    提交的是【第一个】选项 ⇒ 值被静默改回空 ⇒ 用户的版本选择凭空消失，零报错。
//    这是 <select> + 运行时选项最典型的坑。
// ★★ 所以 select 的初始 HTML 带 disabled：选项要等这次回调才知道。若在回调返回前
//    就点了「应用本页设置」，disabled 控件【不会】被提交 ⇒ nvram 里那个键保持原值，
//    而不是被浏览器当成「选中第一项」写成空。回调无论如何都会把它解禁。
// ★ 为什么走 SystemCmd 而不是服务端 nvram_get_x：这个值经 apply.cgi 原样转发，
//    是不可信输入；服务端拼进 HTML 等于开一个 XSS 面（本页其它 nvram 值都是我们
//    自己在设备上生成的，这个不是）。经 easytier_download.sh 的 selver 校验后再给，
//    拿到的一定是 vN.N.N 形态的纯文本。
// ---------------------------------------------------------------------------

function et_ver_ok(v){
	return /^v[0-9]+\.[0-9]+\.[0-9]+$/.test(v);
}

// 往版本下拉框里插一个选项（已存在则不重复插）。sel 为真时同时选中它。
// ★ 用 createElement + createTextNode，不碰任何 HTML 解析路径：v 虽已在服务端
//   校验过，这里再挡一道的成本是零。
function et_ver_add_option(v, sel){
	if (!et_ver_ok(v)) return;
	var box = $j("#easytier_version");
	if (box.find("option").filter(function(){ return this.value === v; }).length === 0){
		var op = document.createElement("option");
		op.value = v;
		op.appendChild(document.createTextNode(v));
		box.append(op);
	}
	if (sel) box.val(v);
}

// 回填已保存的版本，并把下拉框解禁。selver 未选或值非法时打空 ⇒ 保持默认项不动。
function et_ver_init(){
	et_syscmd("easytier_download.sh selver", function(t){
		if (t) et_ver_add_option(t, true);
		$j("#easytier_version").removeAttr("disabled");
	});
}

// 拉取可用版本列表并逐个插入。
function et_ver_list(){
	$j("#et_ver_state").text("正在查询…");
	et_syscmd("easytier_download.sh versions", function(t){
		$j("#easytier_version").removeAttr("disabled");
		var arr = (t || "").split("\n"), n = 0;
		for (var i = 0; i < arr.length; ++i){
			var v = $j.trim(arr[i]);
			if (et_ver_ok(v)){ et_ver_add_option(v, false); ++n; }
		}
		if (n > 0){
			$j("#et_ver_state").text("已列出 " + n + " 个可用版本");
		} else {
			// ★★ 一个都没解析出来时必须把【原始回显】显示出来：versions 失败时打的
			//    是中文原因（网络失败 / 解析不出等），被上面那个正则一滤就全没了，
			//    界面只剩「正在查询…」永远停在那儿 —— 排障最需要的那句话恰好被
			//    自己的过滤器吃掉。
			$j("#et_ver_state").text(t || "命令通道无响应");
		}
	});
}



</script>
</head>

<body onload="initial();" onunLoad="return unload_body();">

<div class="wrapper">
	<div class="container-fluid" style="padding-right: 0px">
		<div class="row-fluid">
			<div class="span3"><center><div id="logo"></div></center></div>
			<div class="span9" >
				<div id="TopBanner"></div>
			</div>
		</div>
	</div>

	<div id="Loading" class="popup_bg"></div>

	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

	<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">

	<input type="hidden" name="current_page" value="Advanced_easytier.asp">
	<input type="hidden" name="next_page" value="">
	<input type="hidden" name="next_host" value="">
	<input type="hidden" name="sid_list" value="EASYTIER;">
	<input type="hidden" name="group_id" value="">
	<input type="hidden" name="action_mode" value="">
	<input type="hidden" name="action_script" value="">


	<div class="container-fluid">
		<div class="row-fluid">
			<div class="span3">
				<!--Sidebar content-->
				<!--=====Beginning of Main Menu=====-->
				<div class="well sidebar-nav side_nav" style="padding: 0px;">
					<ul id="mainMenu" class="clearfix"></ul>
					<ul class="clearfix">
						<li>
							<div id="subMenu" class="accordion"></div>
						</li>
					</ul>
				</div>
			</div>

			<div class="span9">
				<!--Body content-->
				<div class="row-fluid">
					<div class="span12">
						<div class="box well grad_colour_dark_blue">
							<h2 class="box_head round_top"><#menu5_30#> - <#menu5_38#></h2>
							<div class="round_bottom">
							<div>
                            <ul class="nav nav-tabs" style="margin-bottom: 10px;">
								<li id="allink" style="display:none">
                                    <a href="Advanced_aliddns.asp"><#menu5_23_1#></a>
                                </li>
								<li id="zelink" style="display:none">
                                    <a href="Advanced_zerotier.asp"><#menu5_32_1#></a>
                                </li>
								<li id="ddlink" style="display:none">
                                    <a href="Advanced_ddnsto.asp"><#menu5_34_1#></a>
                                </li>
								<li id="wilink" style="display:none">
                                    <a href="Advanced_wireguard.asp"><#menu5_35_1#></a>
                                </li>
								<li id="frlink" style="display:none">
                                    <a href="Advanced_frp.asp"><#menu5_25_1#></a>
                                </li>
								<li class="active">
                                    <a href="Advanced_easytier.asp"><#menu5_38_1#></a>
                                </li>
                            </ul>
                        </div>
								<div class="row-fluid">
									<div id="tabMenu" class="submenuBlock"></div>
									<div class="alert alert-info" style="margin: 10px;">
									<p>EasyTier 是一个去中心化的异地组网工具：节点之间自动 P2P 打洞，无需公网 IP，也不需要中心服务器。<br>
									同一网络内所有节点的「网络名称」与「网络密钥」必须完全一致。<br>
									「对端节点」只在首次互通时用到（填任意一个已知节点的地址即可），之后会自动发现其余节点。<br>
									「对外通告的网段」把本机所在的局域网共享给其他节点；「出口节点」则把本机流量交给对方出去。<br>
									</p>
									</div>



									<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">

										<tr>
										<th width="30%" style="border-top: 0 none;">启用 EasyTier 组网</th>
											<td style="border-top: 0 none;">
													<div class="main_itoggle">
													<div id="easytier_enable_on_of">
														<input type="checkbox" id="easytier_enable_fake" <% nvram_match_x("", "easytier_enable", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_enable", "0", "value=0"); %>  />
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="easytier_enable" id="easytier_enable_1" class="input" value="1" <% nvram_match_x("", "easytier_enable", "1", "checked"); %> /><#checkbox_Yes#>
													<input type="radio" value="0" name="easytier_enable" id="easytier_enable_0" class="input" value="0" <% nvram_match_x("", "easytier_enable", "0", "checked"); %> /><#checkbox_No#>
												</div>
				</td>

										</tr>
										<tr>
										<th>网络名称（必填；同一网络的所有节点必须一致）</th>
				<td>
					<input type="text" class="input" name="easytier_network_name" id="easytier_network_name" style="width: 320px" value="<% nvram_get_x("","easytier_network_name"); %>" />
				</td>

										</tr>
										<tr>
										<th>网络密钥（可选；同一网络的所有节点必须一致）</th>
				<td>
					<input type="password" class="input" name="easytier_network_secret" id="easytier_network_secret" style="width: 320px" value="<% nvram_get_x("","easytier_network_secret"); %>" />
				</td>

										</tr>
										<tr>
										<th>本机虚拟 IP（格式 10.126.126.1/24，留空自动分配）</th>
				<td>
					<input type="text" class="input" name="easytier_ipv4" id="easytier_ipv4" style="width: 200px" value="<% nvram_get_x("","easytier_ipv4"); %>" />
				</td>

										</tr>
										<tr>
										<th>对端节点（每行一个，格式 host:端口 或 tcp://host:端口）</th>
				<td>
					<textarea rows="4" wrap="off" spellcheck="false" class="span12" name="easytier_peers" id="easytier_peers" style="font-family:'Courier New'; font-size:12px;"><% nvram_get_x("","easytier_peers"); %></textarea>
				</td>

										</tr>
										<tr>
										<th>对外通告的网段（多个用逗号分隔，例 192.168.9.0/24）</th>
				<td>
					<input type="text" class="input" name="easytier_proxy_networks" id="easytier_proxy_networks" style="width: 420px" value="<% nvram_get_x("","easytier_proxy_networks"); %>" />
				</td>

										</tr>
										<tr>
										<th>出口节点（多个用逗号分隔，例 exit.example.com）</th>
				<td>
					<input type="text" class="input" name="easytier_exit_nodes" id="easytier_exit_nodes" style="width: 320px" value="<% nvram_get_x("","easytier_exit_nodes"); %>" />
				</td>

										</tr>
										<tr>
										<th>本机主机名（留空用设备名）</th>
				<td>
					<input type="text" class="input" name="easytier_hostname" id="easytier_hostname" style="width: 200px" value="<% nvram_get_x("","easytier_hostname"); %>" />
				</td>

										</tr>
										<tr>
										<th>MTU（留空用默认；跨公网建议 1300）</th>
				<td>
					<input type="text" class="input" name="easytier_mtu" id="easytier_mtu" style="width: 120px" value="<% nvram_get_x("","easytier_mtu"); %>" />
				</td>

										</tr>
										<tr>
										<th>监听端口（默认 11010）</th>
				<td>
					<input type="text" class="input" name="easytier_listen_port" id="easytier_listen_port" style="width: 120px" value="<% nvram_get_x("","easytier_listen_port"); %>" />
				</td>

										</tr>
										<tr>
										<th>虚拟网卡名（默认 et0）</th>
				<td>
					<input type="text" class="input" name="easytier_dev_name" id="easytier_dev_name" style="width: 120px" value="<% nvram_get_x("","easytier_dev_name"); %>" />
				</td>

										</tr>
										<tr>
										<th>开启 NAT 伪装（子网代理 / 出口节点需要，默认开）</th>
				<td>
													<div class="main_itoggle">
													<div id="easytier_masq_on_of">
														<input type="checkbox" id="easytier_masq_fake" <% nvram_match_x("", "easytier_masq", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_masq", "0", "value=0"); %>  />
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="easytier_masq" id="easytier_masq_1" class="input" value="1" <% nvram_match_x("", "easytier_masq", "1", "checked"); %> /><#checkbox_Yes#>
													<input type="radio" value="0" name="easytier_masq" id="easytier_masq_0" class="input" value="0" <% nvram_match_x("", "easytier_masq", "0", "checked"); %> /><#checkbox_No#>
												</div>
				</td>

										</tr>
										<tr>
										<th>禁用 P2P 打洞（只走中转节点）</th>
				<td>
													<div class="main_itoggle">
													<div id="easytier_disable_p2p_on_of">
														<input type="checkbox" id="easytier_disable_p2p_fake" <% nvram_match_x("", "easytier_disable_p2p", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_disable_p2p", "0", "value=0"); %>  />
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="easytier_disable_p2p" id="easytier_disable_p2p_1" class="input" value="1" <% nvram_match_x("", "easytier_disable_p2p", "1", "checked"); %> /><#checkbox_Yes#>
													<input type="radio" value="0" name="easytier_disable_p2p" id="easytier_disable_p2p_0" class="input" value="0" <% nvram_match_x("", "easytier_disable_p2p", "0", "checked"); %> /><#checkbox_No#>
												</div>
				</td>

										</tr>
										<tr>
										<th>RPC 端口（留空用默认 127.0.0.1:15888）</th>
				<td>
					<input type="text" class="input" name="easytier_rpc_port" id="easytier_rpc_port" style="width: 200px" value="<% nvram_get_x("","easytier_rpc_port"); %>" />
				</td>

										</tr>
										<tr>
										<th>日志级别</th>
				<td>
					<select name="easytier_log_level" class="input">
						<option value="error" <% nvram_match_x("", "easytier_log_level", "error", "selected"); %>>error</option>
						<option value="warn" <% nvram_match_x("", "easytier_log_level", "warn", "selected"); %>>warn</option>
						<option value="info" <% nvram_match_x("", "easytier_log_level", "info", "selected"); %>>info</option>
						<option value="debug" <% nvram_match_x("", "easytier_log_level", "debug", "selected"); %>>debug</option>
						<option value="trace" <% nvram_match_x("", "easytier_log_level", "trace", "selected"); %>>trace</option>
					</select>
				</td>

										</tr>
										<tr>
										<th>下载代理（只影响二进制下载；留空走内置代理，填 - 表示只走直连）</th>
				<td>
					<input type="text" class="input" name="easytier_download_proxy" id="easytier_download_proxy" style="width: 420px" value="<% nvram_get_x("","easytier_download_proxy"); %>" />
				</td>

										</tr>
										<tr>
										<th>二进制版本（选好后点「下载 / 校验二进制」即按该版本下载并生效；选「跟随固件默认版本」全程不联网取指纹）</th>
				<td>
					<select name="easytier_version" id="easytier_version" class="input" style="width: 200px" disabled="disabled">
						<option value="">跟随固件默认版本</option>
					</select>
					<input class="btn" type="button" value="查询可用版本" onclick="et_ver_list()" style="margin-left: 8px;" />
					<span id="et_ver_state" style="margin-left: 8px; color: #888;"></span>
				</td>

										</tr>
										<tr>
										<th>二进制状态</th>
				<td>
					<span id="et_bin_state" style="margin-right: 12px;"><% nvram_get_x("","easytier_bin_state"); %></span>
					<input class="btn" type="button" value="下载 / 校验二进制" onclick="easytier_dl()" />
					<input class="btn" type="button" value="刷新状态" onclick="easytier_state()" style="margin-left: 8px;" />
					<div style="margin-top: 6px; color: #888;">约 8.9 MiB，后台下载；小闪存机型固件不含二进制，须先下载到 /tmp。</div>
					<div style="margin-top: 6px; color: #888;">★ 版本列表点「查询可用版本」从 EasyTier 官方仓库实时拉取，不在固件里写死。校验指纹随之分两路：选「跟随固件默认版本」时比对固件内置的 sha256 常量（全程不联网）；选了具体版本时改用官方发布 API 返回的资产摘要（经 TLS 取得）。两条路下完都必校验，校验不过不会覆盖现有二进制。</div>
					<div style="margin-top: 6px; color: #888;">★ 仍未移植 OpenWrt 版的「自己上传二进制」：那要放开任意文件，就只能退回「跑一下 -h、看输出里有没有 easytier 字样」这种格式探测，等于把校验降级成猜测 —— 故不移植。</div>
				</td>

										</tr>
										<tr id="et_rwfs_row" style="display:none">
										<th>持久存储（RWFS / UBIFS）<br>
											<span style="color:#888; font-weight:normal;">大闪存机型（MI-R3G / MI-R3P）出厂带一块独立于固件的分区，掉电和刷机都不丢。把 EasyTier 二进制放上去，重启后不必重新下载 8.9 MiB。<b>本操作只挂载，绝不格式化</b>，分区里原有的数据不受影响。</span></th>
										<td>
					<input class="btn" type="button" value="启用持久存储" onclick="et_rwfs_enable()" />
					<input class="btn" type="button" value="查看状态" onclick="et_rwfs_status()" style="margin-left: 8px;" />
					<input class="btn" type="button" id="et_rwfs_format_btn" value="格式化并重建" onclick="et_rwfs_format()" style="margin-left: 8px; display:none;" />
					<span id="et_rwfs_state" style="margin-left: 12px; color: #888;"></span>
					<div style="margin-top: 6px; color: #888;">启用后需重启（或重新点一次「下载 / 校验二进制」）才会把二进制搬到新落点。</div>
				</td>
										</tr>
										<tr>
										<th>连接信息 / 二进制详情（只读；走本机查询，不影响隧道）</th>
				<td>
					<!-- 11 种查询共用一个下拉框 + 一个查询按钮：按钮式排到第 11 个会挤满一行，
					     且与后端 et_info 的 case 白名单不再一一对应（此前只有 4 个按钮）。
					     ★ 刻意【不给 name】：没有 name 就不会被 apply.cgi 当作 nvram 键写盘。 -->
					<select id="et_info_kind" class="input" style="width: 200px">
						<option value="peer">对端列表</option>
						<option value="route">路由表</option>
						<option value="node">本机信息</option>
						<option value="conn">连接器</option>
						<option value="stun">NAT 类型</option>
						<option value="peercenter">中继服务器</option>
						<option value="vpnportal">VPN 门户</option>
						<option value="proxy">子网代理</option>
						<option value="acl">ACL 规则</option>
						<option value="mapped">端口映射</option>
						<option value="stats">运行统计</option>
					</select>
					<input class="btn" type="button" value="查询" onclick="et_info_query()" style="margin-left: 8px;" />
					<input class="btn" type="button" value="二进制详情" onclick="easytier_bininfo()" style="margin-left: 8px;" />
					<span id="et_info_state" style="margin-left: 12px; color: #888;"></span>
					<div style="margin-top: 6px;">
						<textarea id="et_info_out" rows="14" class="span12" readonly="readonly" wrap="off" spellcheck="false" style="font-family:'Courier New'; font-size:12px;"></textarea>
					</div>
					<div style="margin-top: 6px; color: #888;">先点「刷新状态」确认二进制就绪；隧道未运行时查询会报 RPC 连接失败，属正常。</div>
				</td>

										</tr>
										<tr>
										<th colspan="2" style="background: #eef3f8;">高级选项（不确定就保持默认；改动会重启隧道）</th>
										</tr>
										<tr>
										<th>虚拟 IP 用 DHCP 获取（勾选后忽略上面的「本机虚拟 IP」）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_dhcp_on_of">
							<input type="checkbox" id="easytier_dhcp_fake" <% nvram_match_x("", "easytier_dhcp", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_dhcp", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_dhcp" id="easytier_dhcp_1" class="input" value="1" <% nvram_match_x("", "easytier_dhcp", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_dhcp" id="easytier_dhcp_0" class="input" value="0" <% nvram_match_x("", "easytier_dhcp", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>延迟优先（优先选低延迟路径，牺牲部分吞吐）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_latency_first_on_of">
							<input type="checkbox" id="easytier_latency_first_fake" <% nvram_match_x("", "easytier_latency_first", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_latency_first", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_latency_first" id="easytier_latency_first_1" class="input" value="1" <% nvram_match_x("", "easytier_latency_first", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_latency_first" id="easytier_latency_first_0" class="input" value="0" <% nvram_match_x("", "easytier_latency_first", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>禁用 IPv6（隧道内不走 IPv6）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_disable_ipv6_on_of">
							<input type="checkbox" id="easytier_disable_ipv6_fake" <% nvram_match_x("", "easytier_disable_ipv6", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_disable_ipv6", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_disable_ipv6" id="easytier_disable_ipv6_1" class="input" value="1" <% nvram_match_x("", "easytier_disable_ipv6", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_disable_ipv6" id="easytier_disable_ipv6_0" class="input" value="0" <% nvram_match_x("", "easytier_disable_ipv6", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>允许本机作为出口节点（其他节点可经本机上网）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_enable_exit_node_on_of">
							<input type="checkbox" id="easytier_enable_exit_node_fake" <% nvram_match_x("", "easytier_enable_exit_node", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_enable_exit_node", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_enable_exit_node" id="easytier_enable_exit_node_1" class="input" value="1" <% nvram_match_x("", "easytier_enable_exit_node", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_enable_exit_node" id="easytier_enable_exit_node_0" class="input" value="0" <% nvram_match_x("", "easytier_enable_exit_node", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>关闭数据加密（性能略高，但隧道内明文，仅限可信网络）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_disable_encryption_on_of">
							<input type="checkbox" id="easytier_disable_encryption_fake" <% nvram_match_x("", "easytier_disable_encryption", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_disable_encryption", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_disable_encryption" id="easytier_disable_encryption_1" class="input" value="1" <% nvram_match_x("", "easytier_disable_encryption", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_disable_encryption" id="easytier_disable_encryption_0" class="input" value="0" <% nvram_match_x("", "easytier_disable_encryption", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>加密算法（留空 = 默认 aes-gcm）</th>
				<td>
					<select name="easytier_encryption_algorithm" class="input">
						<option value="" <% nvram_match_x("", "easytier_encryption_algorithm", "", "selected"); %>>默认（aes-gcm）</option>
						<option value="aes-gcm" <% nvram_match_x("", "easytier_encryption_algorithm", "aes-gcm", "selected"); %>>aes-gcm</option>
						<option value="aes-256-gcm" <% nvram_match_x("", "easytier_encryption_algorithm", "aes-256-gcm", "selected"); %>>aes-256-gcm</option>
						<option value="chacha20" <% nvram_match_x("", "easytier_encryption_algorithm", "chacha20", "selected"); %>>chacha20</option>
						<option value="xor" <% nvram_match_x("", "easytier_encryption_algorithm", "xor", "selected"); %>>xor（不加密，最快）</option>
					</select>
					<div style="margin-top: 6px; color: #888;">本机型二进制只认这 4 种。上游 LuCI 里的 openssl-* 三项是 2.7.0 的枚举项，在 v2.6.4 上填了会让 easytier-core 直接退出。</div>
				</td>

										</tr>
										<tr>
										<th>数据压缩（留空 = 不压缩）</th>
				<td>
					<select name="easytier_compression" class="input">
						<option value="" <% nvram_match_x("", "easytier_compression", "", "selected"); %>>不压缩</option>
						<option value="none" <% nvram_match_x("", "easytier_compression", "none", "selected"); %>>none</option>
						<option value="zstd" <% nvram_match_x("", "easytier_compression", "zstd", "selected"); %>>zstd</option>
					</select>
					<div style="margin-top: 6px; color: #888;">只允许 none / zstd。其他值会让 easytier-core 直接崩溃（panic），隧道起不来。</div>
				</td>

										</tr>
										<tr>
										<th>默认连接协议（留空 = 自动）</th>
				<td>
					<select name="easytier_default_protocol" class="input">
						<option value="" <% nvram_match_x("", "easytier_default_protocol", "", "selected"); %>>自动</option>
						<option value="tcp" <% nvram_match_x("", "easytier_default_protocol", "tcp", "selected"); %>>tcp</option>
						<option value="udp" <% nvram_match_x("", "easytier_default_protocol", "udp", "selected"); %>>udp</option>
						<option value="ws" <% nvram_match_x("", "easytier_default_protocol", "ws", "selected"); %>>ws</option>
						<option value="wss" <% nvram_match_x("", "easytier_default_protocol", "wss", "selected"); %>>wss</option>
					</select>
					<div style="margin-top: 6px; color: #888;">只影响「优先尝试哪种协议」，不影响能否连通。</div>
				</td>

										</tr>
										<tr>
										<th>禁用 UPnP 端口映射（默认允许自动映射）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_disable_upnp_on_of">
							<input type="checkbox" id="easytier_disable_upnp_fake" <% nvram_match_x("", "easytier_disable_upnp", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_disable_upnp", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_disable_upnp" id="easytier_disable_upnp_1" class="input" value="1" <% nvram_match_x("", "easytier_disable_upnp", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_disable_upnp" id="easytier_disable_upnp_0" class="input" value="0" <% nvram_match_x("", "easytier_disable_upnp", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>私有模式（只与手动填写的对端互联，不做公共节点发现）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_private_mode_on_of">
							<input type="checkbox" id="easytier_private_mode_fake" <% nvram_match_x("", "easytier_private_mode", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_private_mode", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_private_mode" id="easytier_private_mode_1" class="input" value="1" <% nvram_match_x("", "easytier_private_mode", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_private_mode" id="easytier_private_mode_0" class="input" value="0" <% nvram_match_x("", "easytier_private_mode", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>多线程（关闭可降低低端设备负载）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_multi_thread_on_of">
							<input type="checkbox" id="easytier_multi_thread_fake" <% nvram_match_x("", "easytier_multi_thread", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_multi_thread", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_multi_thread" id="easytier_multi_thread_1" class="input" value="1" <% nvram_match_x("", "easytier_multi_thread", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_multi_thread" id="easytier_multi_thread_0" class="input" value="0" <% nvram_match_x("", "easytier_multi_thread", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>多线程数（留空用二进制默认值 2；仅多线程开启时有意义）</th>
				<td>
					<input type="text" class="input" name="easytier_multi_thread_count" id="easytier_multi_thread_count" style="width: 120px" value="<% nvram_get_x("","easytier_multi_thread_count"); %>" />
					<div style="margin-top: 6px; color: #888;">只接受数字。</div>
				</td>

										</tr>
										<tr>
										<th>SOCKS5 代理端口（留空 = 不开；1-65535）</th>
				<td>
					<input type="text" class="input" name="easytier_socks5" id="easytier_socks5" style="width: 120px" value="<% nvram_get_x("","easytier_socks5"); %>" />
					<div style="margin-top: 6px; color: #888;">这是【无认证】代理，且 easytier-core 固定监听 0.0.0.0（所有接口）。本固件只在 LAN 可达，不会自动放行到 WAN；确需公网访问请自行在防火墙页加规则。</div>
				</td>

										</tr>
										<tr>
										<th colspan="2" style="background: #eef3f8;">通断检测（周期性探测；全不通则自动重启隧道）</th>
										</tr>
										<tr>
										<th>启用通断检测（隧道起来后才会探测）</th>
				<td>
						<div class="main_itoggle">
						<div id="easytier_check_enable_on_of">
							<input type="checkbox" id="easytier_check_enable_fake" <% nvram_match_x("", "easytier_check_enable", "1", "value=1 checked"); %><% nvram_match_x("", "easytier_check_enable", "0", "value=0"); %>  />
						</div>
						</div>
						<div style="position: absolute; margin-left: -10000px;">
							<input type="radio" value="1" name="easytier_check_enable" id="easytier_check_enable_1" class="input" value="1" <% nvram_match_x("", "easytier_check_enable", "1", "checked"); %> /><#checkbox_Yes#>
							<input type="radio" value="0" name="easytier_check_enable" id="easytier_check_enable_0" class="input" value="0" <% nvram_match_x("", "easytier_check_enable", "0", "checked"); %> /><#checkbox_No#>
						</div>
				</td>

										</tr>
										<tr>
										<th>检测目标 IP（空格分隔多个）</th>
				<td>
					<input type="text" class="input" name="easytier_check_ip" id="easytier_check_ip" style="width: 300px" value="<% nvram_get_x("","easytier_check_ip"); %>" />
					<div style="margin-top: 6px; color: #888;">只接受 IPv4，非法项会被自动忽略。★ 判定规则是「【所有】目标都 ping 不通」才算故障 —— 所以别只填一个对端节点，最好掺一个稳定的公网地址（例如 223.5.5.5）。</div>
				</td>

										</tr>
										<tr>
										<th>检测周期（分钟，1-1440）</th>
				<td>
					<input type="text" class="input" name="easytier_check_time" id="easytier_check_time" style="width: 120px" value="<% nvram_get_x("","easytier_check_time"); %>" />
					<div style="margin-top: 6px; color: #888;">外网本身不通时会自动跳过本轮（避免宽带掉线被误判成隧道故障）；连续两轮全部不可达才重启，避免目标自身抖动导致重启循环。</div>
				</td>

										</tr>
										<tr>
										<th colspan="2" style="background: #eef3f8;">运行日志（最近若干行；含 easytier-core 自身输出）</th>
										</tr>
										<tr>
										<th>日志内容</th>
				<td>
						<div style="margin-bottom: 6px;">
							显示行数
							<select id="et_log_lines" class="input" style="width: 90px">
								<option value="100">100</option>
								<option value="300" selected="selected">300</option>
								<option value="1000">1000</option>
							</select>
							&nbsp;搜索 <input type="text" id="et_log_kw" class="input" style="width: 180px" placeholder="关键字，如 ERROR / 已恢复" />
							&nbsp;<label style="display: inline;"><input type="checkbox" id="et_log_auto" /> 自动刷新(5s)</label>
							&nbsp;<input type="button" class="btn" value="刷新" onclick="et_log_refresh()" />
							<input type="button" class="btn" value="清空" onclick="et_log_clear()" />
							<input type="button" class="btn" id="et_log_dl" value="下载" onclick="et_log_download()" />
						</div>
						<textarea id="et_log_text" rows="18" readonly="readonly" wrap="off" style="width: 100%; box-sizing: border-box; height: 340px; font-family: 'Courier New', Courier, monospace; font-size: 12px;"></textarea>
						<div style="margin-top: 6px; color: #888;">★ 本文件是混合日志：本脚本的事件行（启动/停止/通断检测状态翻转）+ easytier-core 自身的 stdout。搜索框是纯前端过滤，只影响显示。清空只清空文件，不影响运行中的隧道。</div>
				</td>
										</tr>
										<tr>
											<td colspan="4" style="border-top: 0 none;">
												<br />
												<center><input class="btn btn-primary" style="width: 219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
											</td>
										</tr>
</table>

										
								</div>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>

	</form>

	<div id="footer"></div>
</div>
</body>
</html>

