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

// 页面模型。X = db_xray 快照；ROWS = 按 xray_route_order 排好序的规则数组
var X = {};
var ROWS = [];

function initial(){
	show_banner(2);
	show_menu(5,13,3);
	show_footer();
	load_all();
}

function load_all(){
	XR.status($j('#status_line')[0], '读取中…', true);
	XR.loadAll(function(x, ss){
		X = x;
		ROWS = XR.rules(x);
		render_global();
		render_rules();
		XR.status($j('#status_line')[0], '', false);
	});
}

// ------------------------------------------------------------ 全局开关

function render_global(){
	$j('#route_enable')[0].checked = (X.xray_route_enable === '1');
	$j('#fakedns')[0].checked = (X.xray_fakedns === '1');
	$j('#remote_dns').val(X.xray_remote_dns || '');
	// 下载源：空值就显示为空，输入框的 placeholder 里写的是「留空时脚本用的内置默认地址」
	$j('#dl_prefix').val(X.xray_dl_prefix || '');
	$j('#dl_base').val(X.xray_dl_base || '');
	$j('#dl_v2r').val(X.xray_dl_v2r || '');
	$j('#dl_meta').val(X.xray_dl_meta || '');
	$j('#dl_geoip').val(X.xray_dl_geoip || '');
	$j('#route_enable_state')[0].innerHTML = (X.xray_route_enable === '1')
		? '<span class="label label-success">已启用</span>'
		: '<span class="label">已停用</span>';
}

function save_global(){
	var dns = XR.clean($j('#remote_dns').val());
	// 远程 DNS 只接受 IP 或 IP:端口。写进非法值会让整份 xray 配置加载失败，
	// 而 xray 加载失败的表现是「科学上网整个不通」，排查起来很难指向这里
	if (dns && !/^[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]{1,5})?$/.test(dns)) {
		XR.status($j('#status_line')[0], '远程 DNS 格式不对，应为 1.1.1.1 或 1.1.1.1:53', false);
		return;
	}
	XR.postPairs({
		xray_route_enable: $j('#route_enable')[0].checked ? '1' : '0',
		xray_fakedns: $j('#fakedns')[0].checked ? '1' : '0',
		xray_remote_dns: dns || '1.1.1.1'
	}, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '已保存。点「应用」后生效。', false);
		load_all();
	});
}

// ------------------------------------------------------------ 下载源

// 下载源地址的形态校验。
// ★ 不能照抄后端 valid_target() 的字符集 ^[A-Za-z0-9._:@!/-]+$ —— 它不允许 % & ? =，
//   会把带 query 的镜像源（例：https://ghproxy.net/…?token=x）全部挡掉。
// ★ 要求带 http(s):// —— 少写 scheme 是最常见的手误，curl 收到会直接失败，
//   而失败在界面上只表现为「更新分类」全部报取不到，很难指向这五个输入框。
// ★ 必须挡单引号与反斜杠：XR.clean() 会静默把它们吃掉，
//   于是用户粘的地址会被悄悄改掉一个字符却仍显示「已保存」。这里先按原始值判，报错而不是静默改。
function url_shape_ok(s){
	return /^https?:\/\/[^\s'\\]+$/i.test(s);
}

// 保存 5 个下载源。空值 = 用脚本里的内置默认值（键为空时 shell 自己回落），
// 所以空串是合法输入，不报错也不写占位内容。
function save_sources(){
	var fields = ['xray_dl_prefix', 'xray_dl_base', 'xray_dl_v2r', 'xray_dl_meta', 'xray_dl_geoip'];
	var boxes  = ['dl_prefix', 'dl_base', 'dl_v2r', 'dl_meta', 'dl_geoip'];
	var pairs  = {};
	for (var i = 0; i < fields.length; i++) {
		var raw = $j('#' + boxes[i]).val();
		// ★ 先按【原始值】校验，再 clean —— 顺序反了会漏掉被 clean 吃掉字符的那些输入
		if (raw !== '' && !url_shape_ok(raw)) {
			XR.status($j('#status_line')[0],
				'下载源「' + boxes[i] + '」格式不对：要写成 http:// 或 https:// 开头的完整地址，' +
				'且不能含空格、单引号、反斜杠；留空表示用内置默认地址。', false);
			return;
		}
		pairs[fields[i]] = XR.clean(raw);
	}
	XR.postPairs(pairs, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '下载源已保存，下次「更新分类」即用新地址。', false);
		load_all();
	});
}

// ------------------------------------------------------------ 规则列表

function render_rules(){
	var html = '';
	if (ROWS.length === 0) {
		html = '<tr><td colspan="6" style="text-align:center; color:#888;">'
		     + '还没有规则。点下面的「添加规则」，或点「载入起步模板」。</td></tr>';
	}
	for (var i = 0; i < ROWS.length; i++) {
		var r = ROWS[i];
		var on = (r.enabled !== '0');
		html += '<tr' + (on ? '' : ' style="opacity:0.5;"') + '>'
		     + '<td style="width:44px; text-align:center;">'
		     +   '<input type="checkbox" ' + (on ? 'checked="checked"' : '')
		     +   ' onchange="toggle_rule(\'' + r.id + '\', this.checked)">'
		     + '</td>'
		     + '<td style="width:150px;">' + XR.esc(r.remarks || '(无备注)') + '</td>'
		     + '<td>' + XR.esc(XR.summary(r)) + '</td>'
		     + '<td style="width:210px;">' + XR.esc(XR.nodeLabel(r.outbound)) + '</td>'
		     + '<td style="width:150px;">' + XR.preproxyCell(r.preproxy) + '</td>'
		     + '<td style="width:180px; white-space:nowrap;">'
		     +   '<a class="btn btn-mini" href="Shadowsocks_RuleEdit.asp?id=' + encodeURIComponent(r.id) + '">编辑</a> '
		     +   '<a class="btn btn-mini" href="javascript:move_rule(' + i + ',-1)">&#8593;</a> '
		     +   '<a class="btn btn-mini" href="javascript:move_rule(' + i + ',1)">&#8595;</a> '
		     +   '<a class="btn btn-mini btn-danger" href="javascript:del_rule(' + i + ')">删除</a>'
		     + '</td>'
		     + '</tr>';
	}
	$j('#rule_rows')[0].innerHTML = html;
	$j('#rule_count')[0].innerHTML = ROWS.length;
}

// 按 id 找当前内存里的规则；改一个字段时拿它当底稿，保住其余字段
function rule_of(id){
	for (var i = 0; i < ROWS.length; i++) {
		if (ROWS[i].id === id) {
			return ROWS[i];
		}
	}
	return null;
}

// id 是前端附加在对象上的，不属于规则内容，序列化前要摘掉
function payload_of(obj){
	var o = {};
	for (var k in obj) {
		if (k !== 'id' && Object.prototype.hasOwnProperty.call(obj, k)) {
			o[k] = obj[k];
		}
	}
	return JSON.stringify(o);
}

function toggle_rule(id, on){
	var r = rule_of(id);
	if (!r) {
		return;
	}
	r.enabled = on ? '1' : '0';
	var pair = {};
	pair['xray_rule_' + id] = payload_of(r);
	XR.postPairs(pair, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '规则已' + (on ? '启用' : '停用') + '。点「应用」后生效。', false);
		render_rules();
	});
}

function move_rule(idx, dir){
	var to = idx + dir;
	if (to < 0 || to >= ROWS.length) {
		return;
	}
	var tmp = ROWS[idx];
	ROWS[idx] = ROWS[to];
	ROWS[to] = tmp;
	// 顺序单独存在 xray_route_order 里。引擎按这个顺序生成规则、xray 先匹配到的先赢，
	// 所以上移/下移会实打实改变哪条规则生效
	XR.postPairs({ xray_route_order: ids_of(ROWS) }, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '顺序已保存。点「应用」后生效。', false);
		render_rules();
	});
}

function del_rule(idx){
	var r = ROWS[idx];
	if (!confirm('确定删除规则「' + (r.remarks || r.id) + '」？')) {
		return;
	}
	// 先摘掉顺序里的 id 再删规则键。反过来的话，万一顺序写失败，
	// xray_route_order 里就留下一个指向已删规则的悬空 id
	var keep = [];
	for (var i = 0; i < ROWS.length; i++) {
		if (ROWS[i].id !== r.id) {
			keep.push(ROWS[i].id);
		}
	}
	XR.postPairs({ xray_route_order: keep.join(',') }, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.delKey('xray_rule_' + r.id, function(){
			XR.status($j('#status_line')[0], '已删除规则「' + (r.remarks || r.id) + '」。点「应用」后生效。', false);
			load_all();
		});
	});
}

function ids_of(rows){
	var out = [];
	for (var i = 0; i < rows.length; i++) {
		out.push(rows[i].id);
	}
	return out.join(',');
}

// 新规则先跳到编辑页，点保存才真正落库 —— 中途退出不会留下空规则
function add_rule(){
	var id = XR.nextRuleId(X);
	location.href = 'Shadowsocks_RuleEdit.asp?id=' + encodeURIComponent(id) + '&new=1';
}

// ------------------------------------------------------------ 起步模板

// ① 精简起步：刻意只放两条，内容完全写在下面、页面上看得见。
// 两条覆盖最常见的心智模型（大陆直连 / 其余走代理），分类名也都是默认清单里有的，
// 载入即可用，不需要先去更新分类。
var TEMPLATE = [
	{
		remarks: '国内直连',
		network: 'tcp,udp',
		outbound: 'direct',
		fakedns: '0',
		domain_list: 'geosite:cn geosite:geolocation-cn',
		ip_list: 'geoip:cn geoip:private'
	},
	{
		remarks: '被墙走代理',
		network: 'tcp,udp',
		outbound: 'default',
		fakedns: '1',
		domain_list: 'geosite:gfw',
		ip_list: ''
	}
];

// ② passwall2 出厂复刻
// 取自本机 OpenWrt 上真实的 /usr/share/passwall2/0_default_config（5 条 shunt_rules）。
// 注意：网上常被引用的「上游 8 条」（DirectFront/ProxyFront/DirectGame/ProxyGame/CN/Iran/
// Russia_Block/Russia）在这个版本里已经不存在了 —— 现网只有这 5 条，按实际内容来。
//
// 三处刻意的取舍：
//   · 丢掉 #rule-set:remote: 行。那是 sing-box 的远程规则集语法，xray 不认，
//     留着只会生成一条永远不匹配的死规则。
//   · 出站一律 default。出厂文件里这 5 条都没写 node，按上游语义就是跟随全局节点。
//     唯一例外是 PrivateIP 走 direct —— 私有网段没有任何理由过代理。
//   · 勾 FakeDNS 的只有带 ip_list 的那几条。这正是本面板「按规则开 FakeDNS」的用途：
//     域名先拿假 IP，纯 IP 的 geoip 规则才能按域名分流。
//     没有 ip_list 的 PrivateIP 不勾，免得白白把假 IP 引进来。
//
// 已知缺口（页面会提示）：geosite:ir 与 geosite:ru-blocked 在上游没有文本形态，
// 取不到（见 ssrcrules_update.sh 顶部说明）—— 这两条的域名部分会展开为空，IP 部分照常。
// 而 geoip:ir / geoip:ru / geoip:ru-blocked 都不在默认清单里，得先手动装（geoip:ru 有 447KB）。
var TEMPLATE_PW2 = [
	{
		remarks: 'China',
		network: 'tcp,udp',
		outbound: 'default',
		fakedns: '1',
		domain_list: 'geosite:cn',
		ip_list: 'geoip:cn'
	},
	{
		remarks: 'Iran',
		network: 'tcp,udp',
		outbound: 'default',
		fakedns: '1',
		domain_list: 'geosite:ir',
		ip_list: 'geoip:ir'
	},
	{
		remarks: 'Russia_Block',
		network: 'tcp,udp',
		outbound: 'default',
		fakedns: '1',
		domain_list: 'geosite:ru-blocked',
		ip_list: 'geoip:ru-blocked'
	},
	{
		remarks: 'Russia',
		network: 'tcp,udp',
		outbound: 'default',
		fakedns: '1',
		domain_list: '',
		ip_list: 'geoip:ru'
	},
	{
		remarks: 'PrivateIP',
		network: 'tcp,udp',
		outbound: 'direct',
		fakedns: '0',
		domain_list: '',
		ip_list: '10.0.0.0/8 127.0.0.0/8 198.51.100.0/24 192.0.0.0/24 169.254.0.0/16 ' +
			'224.0.0.0/3 192.168.0.0/16 192.88.99.0/24 100.64.0.0/10 172.16.0.0/12 ' +
			'0.0.0.0/8 192.0.2.0/24 203.0.113.0/24'
	}
];

// 两个模板共用的落库逻辑：把 template 追加到现有规则后面，并更新排序键。
// label 只用于状态文本，便于一眼看出载入的是哪一套
function apply_template(template, label){
	if (ROWS.length > 0 && !confirm('当前已有 ' + ROWS.length + ' 条规则，模板会追加在后面。继续？')) {
		return;
	}
	var ids = XR.orderOf(X);
	var pairs = {};
	var n = parseInt(XR.nextRuleId(X).substring(1), 10);
	for (var i = 0; i < template.length; i++) {
		var id = 'r' + (n + i);
		var o = {};
		for (var k in template[i]) {
			if (Object.prototype.hasOwnProperty.call(template[i], k)) {
				o[k] = template[i][k];
			}
		}
		o.enabled = '1';
		pairs['xray_rule_' + id] = JSON.stringify(o);
		ids.push(id);
	}
	pairs.xray_route_order = ids.join(',');
	XR.postPairs(pairs, function(err){
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '已载入 ' + template.length + ' 条' + label + '规则。点「应用」后生效。', false);
		load_all();
	});
}

function load_template(){
	apply_template(TEMPLATE, '起步');
}

// passwall2 出厂那套：载入前把两个坑说在明处 —— 出站要自己改、分类要自己装。
// 不说清楚的话，用户会看到 5 条规则里 3 条完全不生效，然后来查是不是坏了
function load_template_pw2(){
	if (!confirm('载入 passwall2 出厂的 5 条分流规则？\n\n'
		+ '两点先说明：\n'
		+ '· 出站都指向「默认节点」（PrivateIP 例外，走直连）—— 载入后按需自己改。\n'
		+ '· Iran 的域名部分取不到（geosite:ir 上游无文本源）；Russia 系还要 geoip:ru /\n'
		+ '  geoip:ir / geoip:ru-blocked，默认清单里都没有，得先去下面手动更新。\n\n'
		+ '分类没装齐之前，对应规则不命中，属预期行为，不是坏了。')) {
		return;
	}
	apply_template(TEMPLATE_PW2, 'passwall2 出厂');
}

// ------------------------------------------------------------ 动作按钮

function do_apply(){
	XR.status($j('#status_line')[0], '正在重启 xray…', true);
	XR.restart(function(msg){
		XR.status($j('#status_line')[0], msg || '已触发重启', false);
	});
}

function do_rules_update(){
	if (!confirm('更新分类小文本？\n需要联网，耗时约 1-3 分钟，期间请勿断电。\n更新完成后会自动存入 flash，重启后自动恢复。')) {
		return;
	}
	XR.status($j('#status_line')[0], '正在更新分类…', true);
	XR.runCmd('/etc_ro/ss/xrayctl.sh rules update', function(msg){
		XR.status($j('#status_line')[0], msg, false);
	});
}

function do_rules_list(){
	XR.status($j('#status_line')[0], '读取中…', true);
	XR.runCmd('/etc_ro/ss/xrayctl.sh rules list', function(msg){
		XR.status($j('#status_line')[0], msg, false);
	});
}

function do_custom_update(){
	var spec = XR.clean($j('#custom_spec').val());
	if (!spec) {
		XR.status($j('#status_line')[0], '请先填写要更新的分类，如 geosite:netflix', false);
		return;
	}
	// 与 xrayctl.sh 的服务端校验保持一致。SystemCmd 那条路是裸 shell 执行，
	// 前端挡一道、后端再挡一道，两边都不能省
	if (!/^[A-Za-z0-9._:@!\/ -]+$/.test(spec)) {
		XR.status($j('#status_line')[0], '分类名里有非法字符', false);
		return;
	}
	XR.status($j('#status_line')[0], '正在更新 ' + spec + '…', true);
	XR.runCmd('/etc_ro/ss/xrayctl.sh rules update ' + spec, function(msg){
		XR.status($j('#status_line')[0], msg, false);
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
                                            <td width="26%">分流总开关</td>
                                            <td>
                                                <input type="checkbox" id="route_enable" onchange="save_global()">
                                                <span id="route_enable_state"></span>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    关闭时完全不写 routing 段，等同于没有分流功能。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>FakeDNS</td>
                                            <td>
                                                <input type="checkbox" id="fakedns" onchange="save_global()">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    规则里勾了 FakeDNS 的域名才走假 IP 解析；一条都没勾时对所有域名生效。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>远程 DNS</td>
                                            <td>
                                                <input type="text" id="remote_dns" class="input" style="width:160px;"
                                                       placeholder="1.1.1.1" onchange="save_global()">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    FakeDNS 查不到时用的上游 DNS，只能填 IP 或 IP:端口。
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
                                                <th>匹配内容</th>
                                                <th style="width:210px;">出站</th>
                                                <th style="width:150px;">前置代理</th>
                                                <th style="width:180px;">操作</th>
                                            </tr>
                                        </thead>
                                        <tbody id="rule_rows"></tbody>
                                    </table>

                                    <div style="font-size:13px; margin-bottom:10px;">
                                        共 <span id="rule_count">0</span> 条规则。
                                        规则自上而下匹配，命中第一条即停；都不命中走「默认节点」。
                                    </div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td>
                                                <input type="button" class="btn btn-primary" value="添加规则" onclick="add_rule()">
                                                <input type="button" class="btn" value="载入起步模板" onclick="load_template()">
                                                <input type="button" class="btn" value="载入 passwall2 出厂规则" onclick="load_template_pw2()">
                                                <input type="button" class="btn btn-success" value="应用（重启 xray）" onclick="do_apply()">
                                                <input type="button" class="btn" value="刷新" onclick="load_all()">
                                            </td>
                                        </tr>
                                    </table>

                                    <div style="border-top:1px solid #ddd; padding-top:10px; margin-top:6px;">
                                        <h4 style="margin-bottom:8px;">分类小文本（geosite / geoip）</h4>
                                        <div style="font-size:13px; color:#666; margin-bottom:8px;">
                                            分类库更新后会自动存入 flash（约 116 KB），重启后由开机流程自动解回内存盘，无需每次开机重新下载。<br>
                                            若 flash 余量不足导致持久化失败，状态栏会明确提示，此时重启后需要重新更新。
                                        </div>
                                        <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                            <tr>
                                                <td width="30%">更新全部默认分类</td>
                                                <td>
                                                    <input type="button" class="btn" value="更新分类" onclick="do_rules_update()">
                                                    <input type="button" class="btn" value="列出已装分类" onclick="do_rules_list()">
                                                </td>
                                            </tr>
                                            <tr>
                                                <td>只更新指定分类</td>
                                                <td>
                                                    <input type="text" id="custom_spec" class="input" style="width:340px;"
                                                           placeholder="geosite:netflix geoip:us">
                                                    <input type="button" class="btn" value="更新" onclick="do_custom_update()">
                                                    <span class="help-block" style="margin:2px 0 0 0;">
                                                        空格分隔多个，写法是 geosite:名字 或 geoip:名字。
                                                    </span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <td>下载源（可自定义）</td>
                                                <td>
                                                    <div style="margin-bottom:3px;">
                                                        <span style="display:inline-block; width:80px; color:#666;">加速前缀</span>
                                                        <input type="text" id="dl_prefix" class="input" style="width:400px;"
                                                               title="留空则直连。非空时四个源统一拼成「前缀 + 地址」，例：https://ghproxy.net/"
                                                               placeholder="留空则直连（例：https://ghproxy.net/）" onchange="save_sources()">
                                                    </div>
                                                    <div style="margin-bottom:3px;">
                                                        <span style="display:inline-block; width:80px; color:#666;">域名源①</span>
                                                        <input type="text" id="dl_base" class="input" style="width:400px;"
                                                               title="https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release"
                                                               placeholder="https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release" onchange="save_sources()">
                                                    </div>
                                                    <div style="margin-bottom:3px;">
                                                        <span style="display:inline-block; width:80px; color:#666;">域名源②</span>
                                                        <input type="text" id="dl_v2r" class="input" style="width:400px;"
                                                               title="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
                                                               placeholder="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release" onchange="save_sources()">
                                                    </div>
                                                    <div style="margin-bottom:3px;">
                                                        <span style="display:inline-block; width:80px; color:#666;">域名源③</span>
                                                        <input type="text" id="dl_meta" class="input" style="width:400px;"
                                                               title="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite"
                                                               placeholder="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite" onchange="save_sources()">
                                                    </div>
                                                    <div style="margin-bottom:3px;">
                                                        <span style="display:inline-block; width:80px; color:#666;">IP 源</span>
                                                        <input type="text" id="dl_geoip" class="input" style="width:400px;"
                                                               title="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text"
                                                               placeholder="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text" onchange="save_sources()">
                                                    </div>
                                                    <span class="help-block" style="margin:2px 0 0 0;">
                                                        <b>留空 = 用内置默认地址</b>（鼠标停在输入框上可看到完整默认值）。
                                                        域名分类按 ①②③ 顺序回退，先取到用哪个。<br>
                                                        raw.githubusercontent.com 被墙时，把「加速前缀」填成镜像地址（例 https://ghproxy.net/ ），
                                                        四个源会统一走它。改完自动保存，下次「更新分类」即用新地址。
                                                    </span>
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
    </div>
    <div id="footer"></div>
</div>
</body>
</html>
