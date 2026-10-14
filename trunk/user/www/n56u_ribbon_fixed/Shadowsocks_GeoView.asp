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

function initial(){
	show_banner(2);
	show_menu(5,13,5);
	show_footer();
}

// 前端与 xrayctl.sh 的 valid_target() 保持一致。
// 这条命令经 SystemCmd 走的是裸 shell 执行，两边各挡一道
function ok(s){
	return /^[A-Za-z0-9._:@!\/-]+$/.test(s);
}

// 所有命令都写进同一个结果框
function do_cmd(cmd, busy_msg){
	XR.status($j('#status_line')[0], busy_msg, true);
	XR.runCmd(cmd, function(msg){
		XR.status($j('#status_line')[0], '', false);
		$j('#result').val(msg || '(无输出)');
	});
}

function do_lookup(){
	var t = XR.clean($j('#target').val());
	if (!t) {
		XR.status($j('#status_line')[0], '请先填写域名或 IP', false);
		return;
	}
	if (!ok(t)) {
		XR.status($j('#status_line')[0], '非法字符：只允许 字母 数字 . _ : @ ! / -', false);
		return;
	}
	do_cmd('/etc_ro/ss/xrayctl.sh lookup ' + t, '查询 ' + t + ' …');
}

function do_extract(){
	var t = XR.clean($j('#spec').val());
	if (!t) {
		XR.status($j('#status_line')[0], '请先填写分类，如 geosite:cn', false);
		return;
	}
	if (!ok(t)) {
		XR.status($j('#status_line')[0], '非法字符：只允许 字母 数字 . _ : @ ! / -', false);
		return;
	}
	do_cmd('/etc_ro/ss/xrayctl.sh extract ' + t, '提取 ' + t + ' …');
}

function do_list(){
	do_cmd('/etc_ro/ss/xrayctl.sh rules list', '读取已装分类…');
}

function clear_result(){
	$j('#result').val('');
	XR.status($j('#status_line')[0], '', false);
}

function check_enter(e){
	if (e && e.keyCode === 13) {
		do_lookup();
		return false;
	}
	return true;
}
</script>

<style>
#result { font-family: 'Courier New', Courier, mono; font-size: 13px; }
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
                                            <td width="20%">查询目标归属</td>
                                            <td>
                                                <input type="text" id="target" class="input" style="width:340px;"
                                                       placeholder="www.google.com 或 8.8.8.8 或 1.2.3.0/24"
                                                       onkeydown="return check_enter(event)">
                                                <input type="button" class="btn btn-primary" value="查询" onclick="do_lookup()">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    在已安装的分类里查这个域名/IP 会命中哪些分类。
                                                    判断口径与引擎一致：<br>
                                                    域名 —— domain: 按后缀、full: 按全等、keyword: 按子串；
                                                    regexp: 条目在生成配置时就已被丢弃，因此这里也不会算命中。<br>
                                                    IP —— 按 CIDR 网段归属。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>查看分类内容</td>
                                            <td>
                                                <input type="text" id="spec" class="input" style="width:340px;"
                                                       placeholder="geosite:cn 或 geoip:cn">
                                                <input type="button" class="btn" value="提取" onclick="do_extract()">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    打印指定分类的前若干条，用来确认分类里到底装了什么。
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td>已装分类</td>
                                            <td>
                                                <input type="button" class="btn" value="列出已装分类" onclick="do_list()">
                                                <span class="help-block" style="margin:2px 0 0 0;">
                                                    分类库在 /tmp（内存盘），重启后需要到「分流规则」页重新更新。
                                                </span>
                                            </td>
                                        </tr>
                                    </table>

                                    <div id="status_line"></div>

                                    <textarea id="result" rows="14" class="span12" readonly="readonly"
                                              wrap="off" placeholder="查询结果会显示在这里"></textarea>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td>
                                                <input type="button" class="btn" value="清空结果" onclick="clear_result()">
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
