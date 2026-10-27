<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - <#menu5_16#></title>
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
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/xrayroute.js"></script>

<script>
var $j = jQuery.noConflict();

var X = {};
var ROWS = [];

function initial(){
	show_banner(2);
	// ★ 方案2：科学上网合并为一条 9 项导航栏，本页由第 4 项移到第 8 项。
	show_menu(5,13,8);
	show_footer();
	load_all();
}

function load_all(){
	XR.status($j('#status_line')[0], '读取中…', true);
	XR.loadAll(function(x, ss){
		X = x;
		ROWS = XR.acls(x);
		$j('#acl_enable')[0].checked = (x.xray_acl_enable === '1');
		$j('#acl_enable_state')[0].innerHTML = (x.xray_acl_enable === '1')
			? '<span class="label label-success">已启用</span>'
			: '<span class="label">已停用</span>';
		render_rows();
		XR.status($j('#status_line')[0], '', false);
	});
}

function save_global(){
	XR.postPairs({ xray_acl_enable: $j('#acl_enable')[0].checked ? '1' : '0' }, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '已保存。点「应用」后生效。', false);
		load_all();
	});
}

function render_rows(){
	var html = '';
	if (ROWS.length === 0) {
		html = '<tr><td colspan="6" style="text-align:center; color:#888;">'
		     + '还没有访问控制条目。不添加时，所有设备都走上面的分流规则。</td></tr>';
	}
	for (var i = 0; i < ROWS.length; i++) {
		var a = ROWS[i];
		var on = (a.enabled !== '0');
		html += '<tr' + (on ? '' : ' style="opacity:0.5;"') + '>'
		     + '<td style="width:44px; text-align:center;">'
		     +   '<input type="checkbox" ' + (on ? 'checked="checked"' : '')
		     +   ' onchange="toggle_row(\'' + a.id + '\', this.checked)">'
		     + '</td>'
		     + '<td style="width:150px;">' + XR.esc(a.remarks || '(无备注)') + '</td>'
		     + '<td>' + XR.esc(source_summary(a)) + '</td>'
		     + '<td style="width:210px;">' + XR.esc(outbound_label(a.outbound)) + '</td>'
		     + '<td style="width:150px;">' + XR.preproxyCell(a.preproxy) + '</td>'
		     + '<td style="width:130px; white-space:nowrap;">'
		     +   '<a class="btn btn-mini" href="Shadowsocks_ACL_Edit.asp?id=' + encodeURIComponent(a.id) + '">编辑</a> '
		     +   '<a class="btn btn-mini btn-danger" href="javascript:del_row(' + i + ')">删除</a>'
		     + '</td>'
		     + '</tr>';
	}
	$j('#acl_rows')[0].innerHTML = html;
	$j('#acl_count')[0].innerHTML = ROWS.length;
}

function source_summary(a){
	var s = (a.sources || '').split(' ').filter(function (v) { return v; });
	if (!s.length) {
		return '(空来源，已跳过)';
	}
	return s.slice(0, 3).join(', ') + (s.length > 3 ? ' 等' + s.length + '个' : '');
}

// 「遵循分流」不是引擎里的 tag，只是一个「不生成规则」的标记，显示时单独给个名字
function outbound_label(tag){
	if (tag === 'follow') {
		return '遵循分流（不单独处理）';
	}
	return XR.nodeLabel(tag);
}

function row_of(id){
	for (var i = 0; i < ROWS.length; i++) {
		if (ROWS[i].id === id) {
			return ROWS[i];
		}
	}
	return null;
}

function payload_of(obj){
	var o = {};
	for (var k in obj) {
		if (k !== 'id' && Object.prototype.hasOwnProperty.call(obj, k)) {
			o[k] = obj[k];
		}
	}
	return JSON.stringify(o);
}

function toggle_row(id, on){
	var a = row_of(id);
	if (!a) {
		return;
	}
	a.enabled = on ? '1' : '0';
	var pair = {};
	pair['xray_acl_' + id] = payload_of(a);
	XR.postPairs(pair, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '条目已' + (on ? '启用' : '停用') + '。点「应用」后生效。', false);
		render_rows();
	});
}

function del_row(idx){
	var a = ROWS[idx];
	if (!confirm('确定删除访问控制条目「' + (a.remarks || a.id) + '」？')) {
		return;
	}
	// 与规则列表同理：先摘顺序，再删键，避免留下悬空 id
	var keep = [];
	for (var i = 0; i < ROWS.length; i++) {
		if (ROWS[i].id !== a.id) {
			keep.push(ROWS[i].id);
		}
	}
	XR.postPairs({ xray_acl_order: keep.join(',') }, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.delKey('xray_acl_' + a.id, function(){
			XR.status($j('#status_line')[0], '已删除条目「' + (a.remarks || a.id) + '」。点「应用」后生效。', false);
			load_all();
		});
	});
}

function add_row(){
	var id = XR.nextAclId(X);
	location.href = 'Shadowsocks_ACL_Edit.asp?id=' + encodeURIComponent(id) + '&new=1';
}

function do_apply(){
	XR.status($j('#status_line')[0], '正在重启 xray…', true);
	XR.restart(function(msg){
		XR.status($j('#status_line')[0], msg || '已触发重启', false);
	});
}
</script>

<style>
.table-condensed td { vertical-align: middle; }
.nav-tabs > li > a { padding-right: 6px; padding-left: 6px; }
#status_line { min-height: 22px; margin: 6px 0 10px 0; font-size: 13px; }
</style>
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
                            <h2 class="box_head round_top"><#menu5_16#></h2>
                            <div class="round_bottom">
                                <div class="row-fluid">
                                    <div id="tabMenu" class="submenuBlock"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td width="26%">访问控制总开关</td>
                                            <td>
                                                <input type="checkbox" id="acl_enable" onchange="save_global()">
                                                <span id="acl_enable_state"></span>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    开启后，下面列出的设备<b>不再走分流规则</b>，直接按各自指定的出站处理。
                                                </span>
                                            </td>
                                        </tr>
                                    </table>

                                    <div id="status_line"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table table-bordered table-condensed">
                                        <thead>
                                            <tr>
                                                <th style="width:44px; text-align:center;">启用</th>
                                                <th style="width:150px;">备注</th>
                                                <th>来源设备</th>
                                                <th style="width:210px;">出站</th>
                                                <th style="width:150px;">前置代理</th>
                                                <th style="width:130px;">操作</th>
                                            </tr>
                                        </thead>
                                        <tbody id="acl_rows"></tbody>
                                    </table>

                                    <div style="font-size:13px; margin-bottom:10px;">
                                        共 <span id="acl_count">0</span> 条。条目自上而下匹配，命中第一条即停。
                                    </div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td>
                                                <input type="button" class="btn btn-primary" value="添加条目" onclick="add_row()">
                                                <input type="button" class="btn btn-success" value="应用（重启 xray）" onclick="do_apply()">
                                                <input type="button" class="btn" value="刷新" onclick="load_all()">
                                            </td>
                                        </tr>
                                    </table>

                                    <div style="border-top:1px solid #ddd; padding-top:10px; margin-top:6px; font-size:13px; color:#666;">
                                        <b>关于用 MAC 指定设备：</b>
                                        xray 的来源匹配只认 IP，不认 MAC。所以填 MAC 的条目会在每次生成配置时
                                        去 DHCP 租约（/tmp/dnsmasq.leases）和 ARP 表里查对应的 IP。
                                        设备当前不在线、或换了 IP 还没续租，就查不到 —— 这种情况该条目会被跳过，
                                        等设备联网后点一次「应用」即可生效。要让 MAC 稳定可用，
                                        建议在「DHCP 服务器」页给它绑定静态 IP。
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div id="footer"></div>
</div>
</body>
</html>
