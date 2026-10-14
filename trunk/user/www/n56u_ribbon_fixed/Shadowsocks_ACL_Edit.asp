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

var RID = '';
var IS_NEW = false;
var X = {};

// 「遵循分流」不是引擎认识的出站 tag，它只是一个「本条目不生成规则」的标记。
// 因此不能出现在 XR.nodes() 里（那是引擎真实 tag 空间），只能作为额外选项附加
var FOLLOW = { tag: 'follow', label: '遵循分流（该设备按上面的规则处理）' };

function initial(){
	show_banner(2);
	show_menu(5,13,4);
	show_footer();

	RID = query('id');
	IS_NEW = (query('new') === '1');

	if (!/^a[0-9]+$/.test(RID)) {
		alert('条目 id 不合法');
		location.href = 'Shadowsocks_ACL.asp';
		return;
	}

	$j('#rid_label')[0].innerHTML = RID + (IS_NEW ? '（新建）' : '');

	XR.loadAll(function(x, ss){
		X = x;
		fill_form();
	});
}

function query(name){
	var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search);
	return m ? decodeURIComponent(m[1]) : '';
}

function fill_form(){
	var a = IS_NEW ? null : XR.parseJson(X['xray_acl_' + RID]);
	a = a || {};

	$j('#remarks').val(a.remarks || '');
	$j('#enabled')[0].checked = (a.enabled !== '0');
	$j('#sources').val(XR.unpackList(a.sources));

	// 新条目默认「默认节点」而不是「遵循分流」：
	// 一条什么都不做的条目只会让人困惑，默认值应该是个有实际效果的选择
	XR.fillSelect($j('#outbound')[0], a.outbound || 'default', [FOLLOW]);
}

// 单个来源是否合法：MAC 或 IP/CIDR
function valid_source(s){
	if (/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(s)) {
		return 'mac';
	}
	if (/^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/.test(s)) {
		return 'ip';
	}
	return '';
}

function save(){
	var src = XR.packList($j('#sources').val());

	if (!src) {
		alert('来源设备不能为空。');
		return;
	}

	// 逐个校验并报出具体是哪一个不合法 —— 这些值会进 xray 配置的 source 字段，
	// 写错了 xray 会直接拒绝加载整份配置，表现是整个科学上网不通，很难指向这里
	var list = src.split(' ');
	for (var i = 0; i < list.length; i++) {
		if (!valid_source(list[i])) {
			alert('来源「' + list[i] + '」格式不对。\n只支持 MAC（如 AA:BB:CC:DD:EE:FF）或 IP/CIDR（如 192.168.66.100 或 192.168.66.0/24）。');
			return;
		}
	}

	var o = {
		enabled: $j('#enabled')[0].checked ? '1' : '0',
		remarks: XR.clean($j('#remarks').val()),
		sources: src,
		outbound: XR.clean($j('#outbound').val())
	};

	var pairs = {};
	pairs['xray_acl_' + RID] = JSON.stringify(o);
	if (IS_NEW) {
		var ids = XR.orderOf(X);
		if (index_of(ids, RID) < 0) {
			ids.push(RID);
		}
		// 顺序键是 xray_acl_order，不是规则的 xray_route_order
		pairs.xray_acl_order = ids.join(',');
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
	location.href = 'Shadowsocks_ACL.asp';
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
                            <h2 class="box_head round_top"><#menu5_16#> - 访问控制条目</h2>
                            <div class="round_bottom">
                                <div class="row-fluid">
                                    <div id="tabMenu" class="submenuBlock"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td width="20%">条目 id</td>
                                            <td><span id="rid_label"></span></td>
                                        </tr>
                                        <tr>
                                            <td>备注</td>
                                            <td>
                                                <input type="text" id="remarks" class="input" style="width:340px;"
                                                       placeholder="例如：客厅电视不走代理">
                                                <span class="help-block" style="margin:2px 0 0 0;">只用于列表显示。</span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>启用</td>
                                            <td>
                                                <input type="checkbox" id="enabled">
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>出站</td>
                                            <td>
                                                <select id="outbound" class="input" style="width:340px;"></select>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    命中本条目来源的流量直接走这个出站，<b>不再看上面的分流规则</b>。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>来源设备</td>
                                            <td>
                                                <textarea id="sources" rows="8" class="span12 mono"
                                                          placeholder="AA:BB:CC:DD:EE:FF&#10;192.168.66.100&#10;192.168.66.0/24"></textarea>
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    一行一个，可以是 <b>MAC</b> 或 <b>IP / CIDR</b>，两者可混填。<br>
                                                    xray 的来源匹配只认 IP，所以 MAC 需要在生成配置时查 DHCP 租约和 ARP 表换成 IP；
                                                    设备不在线时查不到，该条目会被跳过，等设备联网后点「应用」即可。
                                                    建议在「DHCP 服务器」页给常用设备绑定静态 IP，比填 MAC 稳。
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
