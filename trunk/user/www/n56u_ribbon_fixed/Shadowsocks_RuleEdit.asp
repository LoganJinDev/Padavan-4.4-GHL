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

var RID = '';      // 规则 id，形如 r1
var IS_NEW = false; // 从列表页「添加规则」进来的
var X = {};

function initial(){
	show_banner(2);
	show_menu(5,13,3);
	show_footer();

	RID = query('id');
	IS_NEW = (query('new') === '1');

	// id 会参与 dbus 键名与 URL，只认 r+数字 这一种形式
	if (!/^r[0-9]+$/.test(RID)) {
		alert('规则 id 不合法');
		location.href = 'Shadowsocks_Route.asp';
		return;
	}

	$j('#rid_label')[0].innerHTML = RID + (IS_NEW ? '（新建）' : '');

	XR.loadAll(function(x, ss){
		X = x;
		XR.fillSelect($j('#outbound')[0], null);
		fill_form();
	});
}

// 极简 query 取值。不用 jQuery 的 $.query 插件 —— 那需要额外引入文件
function query(name){
	var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search);
	return m ? decodeURIComponent(m[1]) : '';
}

function fill_form(){
	var raw = IS_NEW ? null : XR.parseJson(X['xray_rule_' + RID]);
	var r = raw || {};

	$j('#remarks').val(r.remarks || '');
	$j('#enabled')[0].checked = (r.enabled !== '0');
	$j('#network').val(r.network || 'tcp,udp');
	$j('#fakedns')[0].checked = (r.fakedns === '1');
	// 列表在 dbus 里是「单行、空白分隔」，编辑时展开成一行一条，便于阅读
	$j('#domain_list').val(XR.unpackList(r.domain_list));
	$j('#ip_list').val(XR.unpackList(r.ip_list));

	// 出站下拉要等 db_ss 就绪后再填，所以放这里而不是 initial
	XR.fillSelect($j('#outbound')[0], r.outbound || 'default');
}

function save(){
	var domain = XR.packList($j('#domain_list').val());
	var ip = XR.packList($j('#ip_list').val());

	if (!domain && !ip) {
		// 引擎会跳过空规则（xrayroute.lua 的 build_routing 里 #domain>0 or #ip>0）。
		// 但「静默跳过」对用户是坏体验，这里直接拦下来
		alert('域名列表和 IP 列表不能同时为空，否则这条规则不会生效。');
		return;
	}

	var o = {
		enabled: $j('#enabled')[0].checked ? '1' : '0',
		remarks: XR.clean($j('#remarks').val()),
		network: XR.clean($j('#network').val()),
		outbound: XR.clean($j('#outbound').val()),
		fakedns: $j('#fakedns')[0].checked ? '1' : '0',
		domain_list: domain,
		ip_list: ip
	};

	var pairs = {};
	pairs['xray_rule_' + RID] = JSON.stringify(o);
	if (IS_NEW) {
		// 新建时要把 id 挂到顺序表末尾，否则列表页读不到这条规则
		var ids = XR.orderOf(X);
		if (index_of(ids, RID) < 0) {
			ids.push(RID);
		}
		pairs.xray_route_order = ids.join(',');
	}

	XR.status($j('#status_line')[0], '保存中…', true);
	$j('#btn_save').attr('disabled', 'disabled');
	XR.postPairs(pairs, function(err){
		$j('#btn_save').removeAttr('disabled');
		if (err) {
			XR.status($j('#status_line')[0], err, false);
			return;
		}
		XR.status($j('#status_line')[0], '已保存。点「返回列表」后再点「应用」生效。', false);
	});
}

function index_of(arr, v){
	for (var i = 0; i < arr.length; i++) {
		if (arr[i] === v) {
			return i;
		}
	}
	return -1;
}

function go_back(){
	location.href = 'Shadowsocks_Route.asp';
}
</script>

<style>
textarea.mono { font-family: 'Courier New', Courier, mono; font-size: 13px; }
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
                            <h2 class="box_head round_top"><#menu5_16#> - 规则编辑</h2>
                            <div class="round_bottom">
                                <div class="row-fluid">
                                    <div id="tabMenu" class="submenuBlock"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td width="20%">规则 id</td>
                                            <td><span id="rid_label"></span></td>
                                        </tr>
                                        <tr>
                                            <td>备注</td>
                                            <td>
                                                <input type="text" id="remarks" class="input" style="width:340px;"
                                                       placeholder="例如：国内直连">
                                                <span class="help-block" style="margin:2px 0 0 0;">只用于列表显示。</span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>启用</td>
                                            <td>
                                                <input type="checkbox" id="enabled">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    关掉后这条规则不参与生成，但内容会留着。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>出站</td>
                                            <td>
                                                <select id="outbound" class="input" style="width:340px;"></select>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    命中这条规则的流量走哪个节点。节点列表来自「科学上网」页已保存的节点。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>协议</td>
                                            <td>
                                                <select id="network" class="input" style="width:340px;">
                                                    <option value="tcp,udp">TCP + UDP（推荐）</option>
                                                    <option value="tcp">仅 TCP</option>
                                                    <option value="udp">仅 UDP</option>
                                                </select>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>FakeDNS</td>
                                            <td>
                                                <input type="checkbox" id="fakedns">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    勾上后，这条规则的域名由 FakeDNS 返回假 IP，用于让纯 IP 的规则也能按域名分流。<br>
                                                    只要有任意一条规则勾了，就只对这些规则的域名生效；一条都没勾时对所有域名生效。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>域名列表</td>
                                            <td>
                                                <textarea id="domain_list" rows="9" class="span12 mono"
                                                          placeholder="geosite:cn&#10;geosite:gfw&#10;domain:example.com&#10;full:exact.example.com&#10;keyword:google"></textarea>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    一行一条。# 开头或行尾的内容会被当作注释丢掉。<br>
                                                    可用写法：<b>geosite:分类名</b>（引用分类，可加 @属性 过滤，如 geosite:cn@cn）、
                                                    <b>domain:</b>后缀匹配、<b>full:</b>精确匹配、<b>keyword:</b>子串匹配。<br>
                                                    直接写裸域名等同于 domain:。<b>regexp:</b> 会被忽略 —— 引擎生成配置时要去掉反斜杠，正则会变形。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>IP 列表</td>
                                            <td>
                                                <textarea id="ip_list" rows="7" class="span12 mono"
                                                          placeholder="geoip:cn&#10;geoip:private&#10;1.2.3.0/24"></textarea>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    一行一条。可用 <b>geoip:分类名</b> 或直接写 CIDR。<br>
                                                    域名列表与 IP 列表是<b>或</b>的关系：命中任意一边即走本规则的出站。
                                                </span>
                                            </td>
                                        </tr>
                                    </table>

                                    <div id="status_line"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td>
                                                <input type="button" id="btn_save" class="btn btn-primary" value="保存" onclick="save()">
                                                <input type="button" class="btn" value="返回列表" onclick="go_back()">
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
    <div id="footer"></div>
</div>
</body>
</html>
