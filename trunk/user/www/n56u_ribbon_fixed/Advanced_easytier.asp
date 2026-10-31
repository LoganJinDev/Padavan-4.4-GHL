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

function et_syscmd(cmd){
	// 走 SystemCmd 通道执行一条命令，把回显写进状态格。
	// ★ 两段式：POST /apply.cgi 只是把命令【登记】进 sys_script，
	//   紧接着的 GET /console_response.asp 才是真正的执行扳机。
	//   少了第二段，命令永远不会跑（而且不报任何错）。
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
				success: function(t){ $j("#et_bin_state").text($j.trim(t)); },
				error: function(){ $j("#et_bin_state").text("命令通道无响应"); }
			});
		},
		error: function(){ $j("#et_bin_state").text("命令提交失败"); }
	});
}

function easytier_dl(){
	$j("#et_bin_state").text("正在下载…");
	et_syscmd("easytier.sh dl");
}

function easytier_state(){
	et_syscmd("easytier.sh state");
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
										<th>二进制状态</th>
				<td>
					<span id="et_bin_state" style="margin-right: 12px;"><% nvram_get_x("","easytier_bin_state"); %></span>
					<input class="btn" type="button" value="下载 / 校验二进制" onclick="easytier_dl()" />
					<input class="btn" type="button" value="刷新状态" onclick="easytier_state()" style="margin-left: 8px;" />
					<div style="margin-top: 6px; color: #888;">约 8.9 MiB，后台下载；小闪存机型固件不含二进制，须先下载到 /tmp。</div>
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

