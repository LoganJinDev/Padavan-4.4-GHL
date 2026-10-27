<!DOCTYPE html>
<html>
<head>
	<title>
		<#Web_Title#> - <#menu5_16#>
	</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<meta http-equiv="Pragma" content="no-cache">
	<meta http-equiv="Expires" content="-1">
	<link rel="shortcut icon" href="images/favicon.ico">
	<link rel="icon" href="images/favicon.png">
	<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
	<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap-table.min.css">
	<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">
	<link rel="stylesheet" type="text/css" href="/bootstrap/css/engage.itoggle.css">
	<script type="text/javascript" src="/jquery.js?random=<% uptime(); %>"></script>
	<!-- URL 测速的探测地址要从 dbus 回填，所以在这里同步取一次 dbconf。
	     ★ 必须是【同步】的 <script src>，不能等页面 ready 后再 ajax：
	       dbconf 的响应体就是 `var db_urltest=(function(){var o={};...return o;})();`，
	       同步加载 ⇒ window.db_urltest 在本页任何 JS 跑之前就已就绪。
	     ★ 前缀必须是 urltest_ 而不是 ss：/dbconf?p=X 是【前缀匹配】，任何 ss 开头的
	       键都会落进 window.db_ss，而本页对 db_ss 每个键无保护地 JSON.parse
	       ⇒ 节点下拉框多一个垃圾项、主表多一行垃圾。 -->
	<script type="text/javascript" src="/dbconf?p=urltest&v=<% uptime(); %>"></script>
	<script type="text/javascript" src="/bootstrap/js/bootstrap.min.js"></script>
	<script type="text/javascript" src="/bootstrap/js/bootstrap-table.min.js"></script>
	<script type="text/javascript" src="/bootstrap/js/bootstrap-table-zh-CN.min.js"></script>
	<script type="text/javascript" src="/bootstrap/js/engage.itoggle.min.js"></script>
	<script type="text/javascript" src="/state.js"></script>
	<script type="text/javascript" src="/general.js"></script>
	<script type="text/javascript" src="/itoggle.js"></script>
	<script type="text/javascript" src="/popup.js"></script>
	<script type="text/javascript" src="/help.js"></script>
	<script type="text/javascript" src="/validator.js"></script>
	<script>
		var node_global_max = 0;
		var ss_all_nodes = [];  // F1：db_ss 解析后的全部节点（过滤前的全集），供 showMRULESList/ss_filter_nodes 用
		<% shadowsocks_status(); %>
		<% dns2tcp_status(); %>
		<% dnsproxy_status(); %>
		<% rules_count(); %>
		node_global_max = 0;
		editing_ss_id = 0;
		var $j = jQuery.noConflict();
		$j(document).ready(function () {
			init_itoggle('ss_enable');
			init_itoggle('switch_enable_x_0');
			init_itoggle('ss_chdns');
			init_itoggle('ss_router_proxy', change_ss_watchcat_display);
			init_itoggle('ss_cgroups');
			init_itoggle('ss_watchcat');
			init_itoggle('ss_update_chnroute');
			init_itoggle('ss_update_gfwlist');
			init_itoggle('ss_adblock');
			init_itoggle('ss_adblock_url');
			init_itoggle('socks5_enable');
			init_itoggle('ss_schedule_enable', change_on);
			// 探测地址回填：把 dbus 里的 urltest_url 反映到下拉框 / 自定义输入框上。
			// 放在 ready 里是因为要操作 DOM；读的是 <head> 里同步加载的 db_urltest。
			urltest_url_init();
			$j("#tab_ss_cfg, #tab_ss_add, #tab_ss_dlink, #tab_ss_ssl, #tab_ss_cli, #tab_ss_log, #tab_ss_help").click(
				function () {
					var newHash = $j(this).attr('href').toLowerCase();
					showTab(newHash);
					return false;
				});
			$j("#close_add").click(function () {
				$j("#vpnc_settings").fadeOut(200);
			});
			$j("#btn_add_link").click(function () {
				initSSParams();
				editing_ss_id = 0;
				document.getElementById("ss_setting_title").innerHTML = "添加节点";
				$j("#vpnc_settings").fadeIn(200);
			});
			$j("#btn_del_link").click(function () {
				del_dlink();
			});
			$j("#btn_ping_link").click(function () {
				ping_dlink();
			});
			$j("#btn_aping_link").click(function () {
				aping_dlink();
			});
			// URL 测延迟：与 ping 并列的第二套测速方案，走 urltest.sh。
			$j("#btn_urltest_link").click(function () {
				urltest_dlink();
			});
			$j("#s5_aut").change(function() { 
			if($j("#s5_aut").is(':checked')){
			document.getElementById('s5_aut').value=1;
			}else{
			document.getElementById('s5_aut').value=0;
			}
			}); 
			$j("#v2_tls").change(function() {
			if(document.getElementById('v2_tls').value != '0'){
			showhide_div('row_tj_tls_host', 1);
			}else{
			showhide_div('row_tj_tls_host', 0);
			}
			toggle_reality_rows();
			});
			// Reality 的四个字段只在「TLS/Reality」选 Reality（值为 2）时才有意义。
			// 它们是 xray 的硬性要求，缺任何一项整份配置都加载不了，
			// 所以只在真用得上的时候显示，避免在别的协议下被误填
			function toggle_reality_rows() {
			var on = (document.getElementById('v2_tls').value == '2') ? 1 : 0;
			showhide_div('row_v2_reality_pbk', on);
			showhide_div('row_v2_reality_sid', on);
			showhide_div('row_v2_reality_fp', on);
			showhide_div('row_v2_reality_spx', on);
			}
			$j("#v2_mux").change(function() { 
			if($j("#v2_mux").is(':checked')){
			document.getElementById('v2_mux').value=1;
			}else{
			document.getElementById('v2_mux').value=0;
			}
			});
			$j("#ssp_insecure").change(function() { 
			if($j("#ssp_insecure").is(':checked')){
			document.getElementById('ssp_insecure').value=1;
			}else{
			document.getElementById('ssp_insecure').value=0;
			}
			});
		});
function ClearssrplusLog(){
	var $j = jQuery.noConflict();
	$j.post('/apply.cgi',
	{
		'action_mode': ' ClearssrplusLog ',
	});
}
function ctime() {
var t=0;
c=null;
document.getElementById('btn_ctime').value='正在运行脚本:0s';
document.getElementById('btn_ctime').style.display="inline";
		c=setInterval(function(){
		t=t+1
        //document.getElementById("ctime").value=t + "秒";
		document.getElementById('btn_ctime').value='正在运行脚本:' + t +"s";
    },1000);
}
function dtime() {
clearInterval(c);
document.getElementById('btn_ctime').value='脚本运行完成!';
setTimeout('document.getElementById("btn_ctime").style.display="none";',1000);
}
		function initial() {
			show_banner(2);
			// show_menu(L1, L2, L3)：L1=主菜单下标，L2=二级菜单下标，L3=当前 tab 下标。
			// tab 数组实际取 tabtitle[L2-1]，故 L2=13 对应 tabtitle[12]（科学上网 tab 组）。
			// L3 是渲染开关而非“默认高亮”：L3 为 0/假值时整个 tab 条不渲染，
			// 会导致 分流规则/访问控制/Geo查询 等子页面无入口，故必须传 1（本页=主要设置）。
			// L1 原为 13，超出 menuL1_title 长度（有效 1..7），主菜单静默失去高亮，统一为 5。
			show_menu(5, 13, 1);
			show_footer();
			fill_ss_status(shadowsocks_status());
			fill_dns2tcp_status(dns2tcp_status());
			fill_dnsproxy_status(dnsproxy_status());
			var wan0_dns = '<% nvram_get_x("","wan0_dns"); %>';
			// use local DNS
			if (wan0_dns.length > 0){
					$j("select[name='china_dns']").prepend($j('<option value="'+wan0_dns+'" selected>本地DNS ' + wan0_dns + '</option>'));
			}
			$("chnroute_count").innerHTML = '<#menu5_17_3#>' + chnroute_count();
			$("gfwlist_count").innerHTML = '<#menu5_17_3#>' + gfwlist_count();
			switch_ss_type();
			showTab(getHash());
			showMRULESList();
			switch_dns();
			var o2 = document.form.lan_con;
			var o3 = document.form.ss_threads;
			var o4 = document.form.china_dns;
			var o5 = document.form.pdnsd_enable;
			//var o6 = document.form.socks5_enable;
			var o7 = document.form.tunnel_forward;
			o2.value = '<% nvram_get_x("","lan_con"); %>';
			o3.value = '<% nvram_get_x("","ss_threads"); %>';
			o4.value = '<% nvram_get_x("","china_dns"); %>';
			o5.value = '<% nvram_get_x("","pdnsd_enable"); %>';
			//o6.value = '<% nvram_get_x("","socks5_enable"); %>';
			o7.value = '<% nvram_get_x("","tunnel_forward"); %>';
			switch_dns();
			if (ss_schedule_support) {
				document.form.ss_date_x_Sun.checked = getDateCheck(document.form.ss_schedule.value, 0);
				document.form.ss_date_x_Mon.checked = getDateCheck(document.form.ss_schedule.value, 1);
				document.form.ss_date_x_Tue.checked = getDateCheck(document.form.ss_schedule.value, 2);
				document.form.ss_date_x_Wed.checked = getDateCheck(document.form.ss_schedule.value, 3);
				document.form.ss_date_x_Thu.checked = getDateCheck(document.form.ss_schedule.value, 4);
				document.form.ss_date_x_Fri.checked = getDateCheck(document.form.ss_schedule.value, 5);
				document.form.ss_date_x_Sat.checked = getDateCheck(document.form.ss_schedule.value, 6);
				document.form.ss_time_x_hour.value = getrebootTimeRange(document.form.ss_schedule.value, 0);
				document.form.ss_time_x_min.value = getrebootTimeRange(document.form.ss_schedule.value, 1);
				document.getElementById('ss_schedule_enable_tr').style.display = "";
				change_on();
			} else {
				document.getElementById('ss_schedule_enable_tr').style.display = "none";
				document.getElementById('ss_schedule_date_tr').style.display = "none";
				document.getElementById('ss_schedule_time_tr').style.display = "none";
			}
		}
		function textarea_scripts_enabled(v) {
			//inputCtrl(document.form['scripts.ss.dom.sh'], v);
			//inputCtrl(document.form['scripts.ss.ip.sh'], v);
		}
		function change_on() {
			var v = document.form.ss_schedule_enable_x.value;
			showhide_div('ss_schedule_date_tr', v);
			showhide_div('ss_schedule_time_tr', v);
			if (v == 1)
				check_Timefield_checkbox();
		}
		function validForm() {
			if (ss_schedule_support) {
				if (!document.form.ss_date_x_Sun.checked && !document.form.ss_date_x_Mon.checked &&
					!document.form.ss_date_x_Tue.checked && !document.form.ss_date_x_Wed.checked &&
					!document.form.ss_date_x_Thu.checked && !document.form.ss_date_x_Fri.checked &&
					!document.form.ss_date_x_Sat.checked && document.form.ss_schedule_enable_x[0].checked) {
					alert(Untranslated.filter_lw_date_valid);
					document.form.ss_date_x_Sun.focus();
					return false;
				}
			}
			return true;
		}
		function switch_ss_type() {
			showhide_div('row_quic_header', 0);
			showhide_div('row_quic_key', 0);
			showhide_div('row_quic_security', 0);
			showhide_div('row_s5_password', 0);
			showhide_div('row_s5_username', 0);
			showhide_div('row_ss_method', 0);
			showhide_div('row_ss_obfs_para', 0);
			showhide_div('row_ss_obfs', 0);
			showhide_div('row_ss_password', 0);
			showhide_div('row_ss_plugin_opts', 0);
			showhide_div('row_ss_plugin', 0);
			showhide_div('row_ss_protocol_para', 0);
			showhide_div('row_ss_protocol', 0);
			showhide_div('row_ssp_insecure', 0);
			showhide_div('row_tj_tls_host', 0);
			showhide_div('row_v2_aid', 0);
			showhide_div('row_v2_http2_host', 0);
			showhide_div('row_v2_http2_path', 0);
			showhide_div('row_v2_mkcp_congestion', 0);
			showhide_div('row_v2_mkcp_downlink', 0);
			showhide_div('row_v2_mkcp_mtu', 0);
			showhide_div('row_v2_mkcp_readbu', 0);
			showhide_div('row_v2_mkcp_tti', 0);
			showhide_div('row_v2_mkcp_uplink', 0);
			showhide_div('row_v2_mkcp_writebu', 0);
			showhide_div('row_v2_mux', 0);
			showhide_div('row_v2_net', 0);
			showhide_div('row_v2_security', 0);
			showhide_div('row_v2_tls', 0);
			showhide_div('row_v2_flow', 0);
			showhide_div('row_v2_reality_pbk', 0);
			showhide_div('row_v2_reality_sid', 0);
			showhide_div('row_v2_reality_fp', 0);
			showhide_div('row_v2_reality_spx', 0);
			showhide_div('row_v2_type_tcp', 0);
			showhide_div('row_v2_type', 0);
			showhide_div('row_v2_vid', 0);
			showhide_div('row_v2_webs_host', 0);
			showhide_div('row_v2_webs_path', 0);
			showhide_div('row_v2_grpc_path', 0);
			showhide_div('row_s5_enable', 0);
			showhide_div('row_s5_username', 0);
			showhide_div('row_s5_password', 0);
			showhide_div('row_v2_http_host', 0);
			showhide_div('row_v2_http_path', 0);
			showhide_div('row_v2_httpupgrade_host', 0);
			showhide_div('row_v2_httpupgrade_path', 0);
			showhide_div('row_v2_splithttp_host', 0);
			showhide_div('row_v2_splithttp_path', 0);
			var b = document.form.ssp_type.value;
			if (b == "ss") {
				showhide_div('row_ss_password', 1);
				showhide_div('row_ss_method', 1);
				showhide_div('row_ss_plugin', 1);
				showhide_div('row_ss_plugin_opts', 1);
			} else if (b == "ssr") {
				showhide_div('row_ss_protocol', 1);
				showhide_div('row_ss_protocol_para', 1);
				showhide_div('row_ss_obfs', 1);
				showhide_div('row_ss_obfs_para', 1);
				showhide_div('row_ss_password', 1);
				showhide_div('row_ss_method', 1);
			} else if (b == "trojan") {
				showhide_div('row_ss_password', 1);
				//showhide_div('row_v2_tls', 1);
				showhide_div('row_tj_tls_host', 1);
				showhide_div('row_ssp_insecure', 1);
			} else if (b == "v2ray" || b == "xray") {
				switch_v2_type();
				showhide_div('row_v2_aid', 1);
				showhide_div('row_v2_vid', 1);
				showhide_div('row_v2_security', 1);
				showhide_div('row_v2_net', 1);
				showhide_div('row_v2_type', 1);
				showhide_div('row_v2_tls', 1);
				showhide_div('row_v2_flow', 1);
				showhide_div('row_v2_mux', 1);
				showhide_div('row_tj_tls_host', 1);
				showhide_div('row_ssp_insecure', 1);
				toggle_reality_rows();
			} else if (b == "socks5") {
				showhide_div('row_s5_enable', 1);
				showhide_div('row_s5_username', 1);
				showhide_div('row_s5_password', 1);
			}
		}
		function switch_v2_type() {
			showhide_div('row_quic_header', 0);
			showhide_div('row_quic_key', 0);
			showhide_div('row_quic_security', 0);
			showhide_div('row_v2_http_host', 0);
			showhide_div('row_v2_http_path', 0);
			showhide_div('row_v2_http2_host', 0);
			showhide_div('row_v2_http2_path', 0);
			showhide_div('row_v2_mkcp_congestion', 0);
			showhide_div('row_v2_mkcp_downlink', 0);
			showhide_div('row_v2_mkcp_mtu', 0);
			showhide_div('row_v2_mkcp_readbu', 0);
			showhide_div('row_v2_mkcp_tti', 0);
			showhide_div('row_v2_mkcp_uplink', 0);
			showhide_div('row_v2_mkcp_writebu', 0);
			showhide_div('row_v2_type_tcp', 0);
			showhide_div('row_v2_type', 0);
			showhide_div('row_v2_webs_host', 0);
			showhide_div('row_v2_webs_path', 0);
			showhide_div('v2_kcp_guise', 0);
			showhide_div('v2_tcp_guise', 0);
			showhide_div('row_v2_httpupgrade_host', 0);
			showhide_div('row_v2_httpupgrade_path', 0);
			showhide_div('row_v2_splithttp_host', 0);
			showhide_div('row_v2_splithttp_path', 0);
			var b = document.form.v2_transport.value;
			if (b == "tcp") {
				showhide_div('row_v2_type', 1);
				showhide_div('v2_tcp_guise', 1);
				showhide_div('row_v2_http_host', 1);
				showhide_div('row_v2_http_path', 1);
			} else if (b == "kcp") {
				showhide_div('row_v2_type', 1);
				showhide_div('v2_kcp_guise', 1);
				showhide_div('row_v2_mkcp_mtu', 1);
				showhide_div('row_v2_mkcp_tti', 1);
				showhide_div('row_v2_mkcp_uplink', 1);
				showhide_div('row_v2_mkcp_downlink', 1);
				showhide_div('row_v2_mkcp_readbu', 1);
				showhide_div('row_v2_mkcp_writebu', 1);
				showhide_div('row_v2_mkcp_congestion', 1);
			} else if (b == "ws") {
				showhide_div('row_v2_webs_host', 1);
				showhide_div('row_v2_webs_path', 1);
			} else if (b == "grpc") {
				showhide_div('row_v2_grpc_path', 1);
			} else if (b == "h2") {
				showhide_div('row_v2_http2_host', 1);
				showhide_div('row_v2_http2_path', 1);
			} else if (b == "quic") {
				showhide_div('row_quic_security', 1);
				showhide_div('row_quic_key', 1);
				showhide_div('row_quic_header', 1);
			}else if (b == "httpupgrade") {
				showhide_div('row_v2_httpupgrade_host', 1);
				showhide_div('row_v2_httpupgrade_path', 1);
			}else if (b == "splithttp") {
				showhide_div('row_v2_splithttp_host', 1);
				showhide_div('row_v2_splithttp_path', 1);
			}
		}
		function switch_dns() {
			var b = document.form.pdnsd_enable.value;
			if (b == "0" || b == "1") { 
				showhide_div('row_china_dns', 1);
				showhide_div('row_tunnel_forward', 1);
				showhide_div('row_ssp_dns_ip', 0);
				showhide_div('row_ssp_dns_port', 0);
			} else if (b == "2") {
				showhide_div('row_china_dns', 0);
				showhide_div('row_tunnel_forward', 0);
				showhide_div('row_ssp_dns_ip', 0);
				showhide_div('row_ssp_dns_port', 0);
			}
		}
		function applyRule() {
			if (validForm()) {
				if (ss_schedule_support) {
					updateDateTime();
				}
			}
			showLoading();
			showsdlinkList();
			showsudlinkList();
			shows5dlinkList();
			document.form.action_mode.value = " Restart ";
			document.form.current_page.value = "Shadowsocks.asp";
			document.form.next_page.value = "";
			document.form.submit();
		}
		function submitInternet(v) {
			showLoading();
			$j.ajax({
				type: "POST",
				url: "/Shadowsocks_action.asp",
				data: {
					connect_action: v,
				},
				dataType: "json",
				success: function (response) {
					alert("脚本执行成功...")
				},
				complete: function(xhr, ts) {
					hideLoading();
				}
			});
		}
		function change_ss_watchcat_display() {
			var v = document.form.ss_router_proxy[0].checked;
			showhide_div('ss_wathcat_option', v);
		}
		function fill_ss_status(status_code) {
			var stext = "Unknown";
			if (status_code == 0)
				stext = "<#Stopped#>";
			else if (status_code == 1)
				stext = "<#Running#>";
			$("ss_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' + stext + '</span>';
			$("domestic_ip").innerHTML = '<iframe src="http://ip.3322.net" height="30" scrolling="no" frameborder="0" marginheight="0" marginwidth="0"></iframe>';
			$("foreign_ip").innerHTML = '<iframe src="https://ifconfig.me/ip" height="30" scrolling="no" frameborder="0" marginheight="0" marginwidth="0"></iframe>';
			$("gg_status").innerHTML = '<span><img alt="无法访问" src="https://www.google.com/favicon.ico?' + new Date().getTime() + '" /></span>';
		}
		function fill_dns2tcp_status(status_code) {
			var stext = "Unknown";
			if (status_code == 0)
				stext = "<#Stopped#>";
			else if (status_code == 1)
				stext = "<#Running#>";
			$("dns2tcp_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' +
				stext + '</span>';
		}
		function fill_dnsproxy_status(status_code) {
			var stext = "Unknown";
			if (status_code == 0)
				stext = "<#Stopped#>";
			else if (status_code == 1)
				stext = "<#Running#>";
			$("dnsproxy_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' +
				stext + '</span>';
		}
		var arrHashes = ["cfg", "add", "ssl", "cli", "log", "help"];
		function showTab(curHash) {
			var obj = $('tab_ss_' + curHash.slice(1));
			if (obj == null || obj.style.display == 'none')
				curHash = '#cfg';
			for (var i = 0; i < arrHashes.length; i++) {
				if (curHash == ('#' + arrHashes[i])) {
					$j('#tab_ss_' + arrHashes[i]).parents('li').addClass('active');
					$j('#wnd_ss_' + arrHashes[i]).show();
				} else {
					$j('#wnd_ss_' + arrHashes[i]).hide();
					$j('#tab_ss_' + arrHashes[i]).parents('li').removeClass('active');
				}
			}
			window.location.hash = curHash;
		}
		function getHash() {
			var curHash = window.location.hash.toLowerCase();
			for (var i = 0; i < arrHashes.length; i++) {
				if (curHash == ('#' + arrHashes[i]))
					return curHash;
			}
			return ('#' + arrHashes[0]);
		}
		function markGroupRULES(o, c, b) {
			document.form.group_id.value = "SspList";
			if (b == " Add ") {
				if (document.form.ssp_staticnum_x_0.value >= c) {
					alert("<#JS_itemlimit1#> " + c + " <#JS_itemlimit2#>");
					return false;
				}
			}
			pageChanged = 0;
			document.form.action_mode.value = b;
			document.form.current_page.value = "Shadowsocks.asp#add";
			return true;
		}
		//订阅节点
		function dlink() {
		ctime();
			var ns = {};
			ns[1] = "dlink";
			document.getElementById("btn_update_link").value="正在更新";
			$j.ajax({
				url: "/applydb.cgi?usedlink=1&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("脚本执行失败！！！")
				},
				success: function (response) {
					setTimeout("dtime();$j('#table99').bootstrapTable('refresh');document.getElementById('btn_update_link').value='手动更新订阅';",1000);
				}
			});
		}
		//清空节点
		function ddlink() {
		ctime();
			var ns = {};
			ns[1] = "ddlink";
			document.getElementById("btn_rest_link").value="正在清空";
			$j.ajax({
				url: "/applydb.cgi?useddlink=1&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("脚本执行失败！！！")
				},
				success: function (response) {
					node_global_max=0;
					setTimeout("dtime();$j('#table99').bootstrapTable('refresh');document.getElementById('btn_rest_link').value='清空节点';",1000);
				}
			});
		}

		// ================= F1：节点分组（订阅 / 手动）=================
		//
		// 判据是节点 JSON 里【有没有 grouphashkey】，不是有没有 coustom：
		//   grouphashkey = md5(订阅URL)，只有 dlink.lua:498 写 ⇒「有」= 来自订阅，忠实。
		//   coustom:"1" 只有本页的 add_ss()（:1527 那个 DataObj）写 ⇒「有」= 走的手动入口；
		//   而 dlink.lua:644 对【无 coustom 的老节点】只记一行日志、并不删除 ⇒「无 coustom」
		//   既可能是手动节点、也可能是历史遗留节点，反推不出来。
		function ss_node_is_sub(o) {
				return !!(o && typeof (o.grouphashkey) != "undefined" && o.grouphashkey !== "");
		}

		// 按 #ss_list_mode 的当前值过滤 ss_all_nodes。
		//   a = 全部节点 / d = 自定义节点（手动）/ c = 订阅节点
		// ★ 节点下拉框与主表都调本函数 ⇒ 两处口径不可能分叉。
		function ss_filter_nodes() {
				if (!ss_all_nodes || ss_all_nodes.length === 0) {
						return [];
				}
				var sel = document.getElementById("ss_list_mode");
				var mode = sel ? sel.value : "a";
				if (mode != "c" && mode != "d") {
						return ss_all_nodes;
				}
				var out = [];
				for (var i = 0; i < ss_all_nodes.length; i++) {
						var isSub = ss_node_is_sub(ss_all_nodes[i]);
						if ((mode == "c" && isSub) || (mode == "d" && !isSub)) {
								out.push(ss_all_nodes[i]);
						}
				}
				return out;
		}

		// 切换筛选条件：数据没变、只是显示口径变了 ⇒ 本地重算，不重新发请求。
		function ss_apply_filter() {
				if (!ss_all_nodes || ss_all_nodes.length === 0) {
						// 页面还没拉到节点（或真没节点）：让 bootstrapTable 走它自己的 ajax 重新拉一遍
						$j('#table99').bootstrapTable('refresh');
						return;
				}
				ss_fill_node_lists();
				$j('#table99').bootstrapTable('load', ss_filter_nodes());
		}

		// 重建三个节点下拉框（TCP / UDP / SOCKS5）。
		function ss_fill_node_lists() {
				var nodeList = document.getElementById("nodeList"); // 获取TCP节点
				var unodeList = document.getElementById("u_nodeList"); // 获取UDP节点
				var s5nodeList = document.getElementById("s5_nodeList"); // 获取SOCK5节点
				if (!nodeList || !unodeList || !s5nodeList) {
						return;
				}
				nodeList.options.length = 1; // 清除TCP旧节点，准备获取新列表信息
				unodeList.options.length = 1; // 清除UDP旧节点，准备获取新列表信息
				s5nodeList.options.length = 1; // 清除SOCK5旧节点，准备获取新列表信息
				var view = ss_filter_nodes();
				for (var i = 0; i < view.length; i++) {
						var o = view[i];
						// 判断下怕获取失败 ，括号是运算的问题
						var text = '[ ' + (o.type ? o.type : "类型获取失败") + ' ] ' + (o.alias ? o.alias : "名字获取失败");
						nodeList.options.add(new Option(text, o.ids)); // 通过 replace 把不要的字符去掉
						unodeList.options.add(new Option(text, o.ids));
						s5nodeList.options.add(new Option(text, o.ids));
				}
				// ★ 原来这段排序+默认选中写在 for 循环体内（每个节点重排一遍，O(n²)）。
				//   移出循环行为完全一致（排序幂等、选中只认第一个），只是不再重复做无用功。
				ss_sort_node_list('#nodeList');
				ss_sort_node_list('#u_nodeList');
				ss_sort_node_list('#s5_nodeList');
				document.form.global_server.value = '<% nvram_get_x("","global_server"); %>';
				document.form.udp_relay_server.value = '<% nvram_get_x("","udp_relay_server"); %>';
				document.form.socks5_enable.value = '<% nvram_get_x("","socks5_enable"); %>';
		}

		// 节点号从大到小排 + 默认选中第一项（与原逻辑逐字一致）。
		// ★ 选择器用的是「直接子代」（>option）：一旦给下拉框加 <optgroup>，这里会静默地
		//   匹配到 0 个元素（不报错、不排序、不设 selected）—— 所以「来源」分组信息
		//   走表格的列，不走进 <optgroup>。
		function ss_sort_node_list(sel) {
				$j(sel + '>option').sort(function (a, b) {
						var aText = $j(a).val() * 1;
						var bText = $j(b).val() * 1;
						if (aText > bText) return -1;
						if (aText < bText) return 1;
						return 0;
				}).appendTo(sel);
				$j(sel + '>option').eq(0).attr("selected", "selected");
		}

		// 子分组：grouphashkey → 订阅显示名。
		//
		// ★ 为什么能靠【顺序】对应、不需要在 JS 里算 md5：
		//   dlink.lua:494 的外层循环是 for k, url in ipairs(subscribe_url)，节点 id（ssrindex）
		//   按订阅顺序递增 ⇒「每组最小节点 id 的升序」=「订阅 URL 的行序」。
		//   update_dlink.sh:14 的 grep -v '^#' | grep -v "^$" 与 dlink.lua 读 /tmp/dlist.txt
		//   同序同过滤 ⇒ 本页 textarea 里看到的行序就是 dlink.lua 看到的顺序。
		// ★ 数量对不上就【全部】回落「订阅N」，绝不能错位贴名 —— 错位的名字比没有名字更坏。
		function ss_sub_names() {
				var seen = {}, groups = [];
				for (var i = 0; i < ss_all_nodes.length; i++) {
						var o = ss_all_nodes[i];
						if (!ss_node_is_sub(o)) {
								continue;
						}
						var h = String(o.grouphashkey);
						var id = parseInt(o.ids, 10);
						if (!(h in seen)) {
								seen[h] = { key: h, min: id };
								groups.push(seen[h]);
						} else if (id < seen[h].min) {
								seen[h].min = id;
						}
				}
				groups.sort(function (a, b) { return a.min - b.min; });

				// 订阅 URL 列表就在本 tab 的 textarea 里（服务端 nvram_dump 已经渲染进去了，
				// tab 藏着也仍在 DOM 里）。★ 本函数只从 showMRULESList 的 ajax 回调里调 ——
				// 写在脚本顶层时这个 textarea 还没被解析出来。
				var ta = document.getElementsByName("scripts.ss_dlink.sh")[0];
				var urls = [];
				if (ta) {
						var rows = String(ta.value).split(/\r?\n/);
						for (var j = 0; j < rows.length; j++) {
								var t = rows[j].replace(/^\s+|\s+$/g, '');
								// 与 update_dlink.sh:14 同款过滤：空行与 # 开头的注释行都不算一个源
								if (t && t.charAt(0) != '#') {
										urls.push(t);
								}
						}
				}

				var ok = (urls.length === groups.length);
				var names = {};
				for (var g = 0; g < groups.length; g++) {
						names[groups[g].key] = ok ? ss_sub_label(urls[g], g + 1) : ('订阅' + (g + 1));
				}
				return names;
		}

		// 订阅显示名：主机名 + 末段路径，截断到 24 字符；解析不出来回落「订阅N」。
		// 手写正则而不用 new URL()：本页跑在路由器上的老 WebKit + jQuery 1.x 环境，
		// 不假设 URL 构造器存在。
		function ss_sub_label(url, n) {
				var fallback = '订阅' + n;
				var m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?#]+)([^?#]*)/.exec(url);
				if (!m) {
						return fallback;
				}
				var host = m[1].replace(/^[^@]*@/, '').replace(/:\d+$/, '');
				var seg = m[2].replace(/\/+$/, '').split('/');
				var last = seg[seg.length - 1];
				var name = last ? (host + '/' + last) : host;
				if (name.length > 24) {
						name = name.substring(0, 23) + '…';
				}
				return name || fallback;
		}


		function showMRULESList() {
					$j('#table99').bootstrapTable({
						//data: myss,
						striped: true,
						pageNumber: 1,
						pagination: true,
						sortable: true,
						sortName: 'ids',
						sortOrder: "desc",
						sidePagination: 'client',
						pageSize: 25,
						pageList: [15, 25, 35, 50], // 分页显示记录数
						uniqueId: "ids",
						ajax:function(request) {
						$j.ajax({
						  url:"/dbconf?p=ss&v=<% uptime(); %>",
						  type:"get",
						  success:function(data){
							request.success({
							  row : data
							});
					//显示节点下拉列表 by 花妆男
					// 渲染父节点  obj 需要渲染的数据 keyStr key需要去除的字符串
					// ★ F1：先把 db_ss 解析成一份节点数组，下面两处（节点下拉框、主表）都从它取数。
					//   只认 ssconf_basic_json_<数字> 这种键：/dbconf?p=ss 是【前缀匹配】，
					//   将来若有别的 ss 开头的键混进来，这里会把它挡在节点列表之外
					//   （实测当前 41 个键全是节点，这层过滤是防御性的，与 xrayroute.js 的 nodes() 同款）。
					// ★ node_global_max 必须对【全部】节点求最大 id，不能只对过滤后的结果求 ——
					//   否则「添加节点」会算出一个已存在的 id 并覆盖掉真实节点（:1533 的 node_global_max += 1）。
					var keyStr = "ssconf_basic_json_";
					ss_all_nodes = [];
					for (var key in db_ss) { // 遍历对象
										if (key.indexOf(keyStr) !== 0) {
															continue;
										}
										var node_id = key.replace(keyStr, '');
										if (!/^\d+$/.test(node_id)) {
															continue;
										}
										var dbss = JSON.parse(db_ss[key]); // 字符串转为对象
										dbss.ids = node_id;
										ss_all_nodes.push(dbss);
										var node_i = parseInt(node_id, 10);
										if (node_i > node_global_max) {
															node_global_max = node_i;
										}
					}
					// F1 子分组：给每个节点贴上「来源」显示名，供表格的「来源」列用。
					var subNames = ss_sub_names();
					for (var ni = 0; ni < ss_all_nodes.length; ni++) {
										if (ss_node_is_sub(ss_all_nodes[ni])) {
															ss_all_nodes[ni].src_name = subNames[String(ss_all_nodes[ni].grouphashkey)] || '订阅';
										} else {
															ss_all_nodes[ni].src_name = '手动';
										}
					}
					// 三个节点下拉框与主表共用同一个过滤口径（ss_filter_nodes），口径不会分叉
					ss_fill_node_lists();
					$j('#table99').bootstrapTable('load', ss_filter_nodes());
						  },
						  error:function(error){
							console.log(error);
						  }
						})
					  },
						columns: [{
							field: 'delete',
							title: '删除',
							checkbox: true,
							width: '30px'
						}, {
							field: 'ids',
							title: '序号',
							width: '30px',
							align: 'center',
							valign: 'middle',
							sortable: true
						}, {
							field: 'type',
							title: '类型',
							align: 'center',
							valign: 'middle',
							width: '10px'
						}, {
							field: 'alias',
							cellStyle: formatTableUnit,
							formatter: paramsMatter,
							title: '别名',
							align: 'center',
							valign: 'middle',
							width: '230px'
						}, {
							field: 'server',
							cellStyle: formatTableUnit,
							formatter: paramsMatter,
							title: '服务器地址',
							align: 'center',
							valign: 'middle',
							width: '150px'
						}, {
												field: 'src_name',
												title: '来源',
												align: 'center',
												valign: 'middle',
												width: '90px'

						}, {
							field: 'ping',
							title: 'ping',
							align: 'center',
							valign: 'middle',
							width: '50px',
							cellStyle: cellStylesales,
							formatter: actionFormatter2,
							sortable: true
						}, {
							field: 'lost',
							title: '丢包',
							align: 'center',
							valign: 'middle',
							width: '50px'
						}, {
												field: 'urltest',
												title: 'URL延迟',
												cellStyle: urlTestCellStyle,
												formatter: urlTestFormatter,
												// 与 ping 列同款：sortable 让「URL延迟」表头可点击排序。
												// 不加自定义 sorter，走 bootstrap-table 默认排序器 —— 两个值
												// 都是数字时按数值比，其余回落到字符串比较。urltest 的取值
												// 形态与 ping 完全一致（数字=毫秒 / "failed"=失败 / 缺字段=
												// 没测过），所以排序行为与 ping 列逐字一致：
												//   升序 = 没测过 → 最快 → 最慢 → failed
												//   降序 = failed → 最慢 → 最快 → 没测过
												sortable: true,
												align: 'center',
												valign: 'middle',
												width: '60px'

						}, {
							field: 'operate',
							title: '操作',
							width: '200px',
							align: 'center',
							valign: 'middle',
							events: window.operateEvents,
							formatter: actionFormatter
						}]
					});
		}
		function cellStylesales(value, row, index) {
			var ping = row.ping
			if (typeof (ping) == "undefined") {
				return ""
			} else if (ping < 100) {
				return {
					css: {
						background: '#04B404',
						color: '#000'
					}
				};
			} else if (ping < 300) {
				return {
					css: {
						background: '#ffeb3b',
						color: '#000'
					}
				};
			} else {
				return {
					css: {
						background: '#f44336',
						color: '#000'
					}
				};
			}
		}
		function actionFormatter2(value, row, index) {
			var ping = row.ping
			var result = "";
			if (typeof (ping) == "undefined") {
				result += "-";
			} else if (ping != "failed") {
				result += ping + "ms";
			} else {
				result += ping
			}
			return result;
		}

		// F2：URL 测延迟的单元格底色。
		// ★ 档位与 ping 的 cellStylesales 刻意不同（1000/2000 而不是 100/300）：
		//   ping 量的是到服务器的往返（几十 ms 量级），URL 测的是「经这个节点完整跑一次 HTTP」，
		//   含 DNS + TCP + TLS + 首字节，正常值本来就在几百 ms ⇒ 套 ping 的档位会全屏飘红。
		function urlTestCellStyle(value, row, index) {
				if (typeof (value) == "undefined" || value === null || value === "") { return "" }
				// ★ 必须显式判 "failed"：失败时 urltest_write.lua 写的是【字符串】，
				//   而 value * 1 会得到 NaN，落到下面 isNaN 分支也返回空 —— 那就把「测过且失败」
				//   显示成了「还没测」，恰好把最该看见的信号藏起来。
				if (value === "failed") { return { css: { background: '#f44336', color: '#000' } }; }
				var v = value * 1;
				if (isNaN(v)) { return "" }
				if (v < 1000) { return { css: { background: '#04B404', color: '#000' } }; }
				if (v < 2000) { return { css: { background: '#ffeb3b', color: '#000' } }; }
				return { css: { background: '#f44336', color: '#000' } };
		}
		// F2：URL 测延迟的单元格文本。
		function urlTestFormatter(value, row, index) {
				if (typeof (value) == "undefined" || value === null || value === "") { return "-" }
				if (value === "failed") { return "failed" }
				var v = value * 1;
				if (isNaN(v)) { return "-" }
				return v + "ms";
		}

		function actionFormatter(value, row, index) {
			return [
				'<a class="edit_ss" href="javascript:void(0)" title="编辑">编辑</a>',
				'<a class="copy_ss" href="javascript:void(0)" title="复制">复制</a>',
				'<a class="del_ss" href="javascript:void(0)" title="删除">删除</a>'
			].join(' | ');
		}
		window.operateEvents = {
			'click .edit_ss': function (e, value, row, index) {
				editing_ss_id = row.ids;
				document.getElementById("ss_setting_title").innerHTML = "编辑节点";
				showSSEditor(row);
			},
			'click .copy_ss': function (e, value, row, index) {
				editing_ss_id = 0;
				document.getElementById("ss_setting_title").innerHTML = "复制节点";
				showSSEditor(row);
			},
			'click .del_ss': function (e, value, row, index) {
				if (confirm('确认删除' + row.alias + '吗？')) {
					del(row.ids);
				}
			}
		}
		function initSSParams() {
			//ss
			document.getElementById('ssp_type').value = 'ss';
			document.getElementById('ssp_name').value = '';
			document.getElementById('ssp_server').value = '';
			document.getElementById('ssp_prot').value = '';
			document.getElementById("ss_password").value = '';
			//ssr
			document.getElementById("ss_method").value = 'rc4-md5';
			document.getElementById("ss_plugin").value = '';
			document.getElementById("ss_plugin_opts").value = '';
			document.getElementById("ss_protocol").value = 'origin';
			document.getElementById("ss_protocol_param").value = '';
			document.getElementById("ss_obfs").value = 'plain';
			document.getElementById("ss_obfs_param").value = '';
			//v2
			document.getElementById("ssp_insecure").value = 0;
			document.getElementById("ssp_insecure").checked = false;
			document.getElementById("v2_mux").value = 0;
			document.getElementById("v2_mux").checked = false;
			document.getElementById("v2_security").value = 'none';
			document.getElementById("v2_vmess_id").value = '';
			document.getElementById("v2_alter_id").value = '';
			document.getElementById("v2_transport").value = 'tcp';
			document.getElementById("v2_tcp_guise").value = 'none';
			document.getElementById("v2_tls").value = '0';
			document.getElementById("v2_flow").value = '0';
			document.getElementById("v2_http_host").value = '';
			document.getElementById("v2_http_path").value = '/';
			//document.getElementById("v2_tls").checked = false;
			document.getElementById("ssp_tls_host").value = '';
			//"v2 tcp"
			document.getElementById("v2_kcp_guise").value = 'none';
			document.getElementById("v2_mtu").value = '';
			document.getElementById("v2_tti").value = '';
			document.getElementById("v2_uplink_capacity").value = '';
			document.getElementById("v2_downlink_capacity").value = '';
			document.getElementById("v2_read_buffer_size").value = '';
			document.getElementById("v2_write_buffer_size").value = '';
			//v2 ws
			document.getElementById("v2_ws_host").value = '';
			document.getElementById("v2_ws_path").value = '';
			//v2 grpc
			document.getElementById("v2_grpc_path").value = '';
			//v2 h2
			document.getElementById("v2_h2_host").value = '';
			document.getElementById("v2_h2_path").value = '';
			//v2 quic
			document.getElementById("v2_quic_key").value = '';
			document.getElementById("v2_quic_guise").value = 'none';
			document.getElementById("v2_quic_security").value = 'none';
			//v2 httpupgrade
			document.getElementById("v2_httpupgrade_host").value = '';
			document.getElementById("v2_httpupgrade_path").value = '';
			//v2 splithttp
			document.getElementById("v2_splithttp_host").value = '';
			document.getElementById("v2_splithttp_path").value = '';
			//sock5
			document.getElementById("s5_password").value = '';
			document.getElementById("s5_username").value = '';
			switch_ss_type();
		}
		//编辑节点
		function showSSEditor(ss) {
			function getProperty(obj, prop, defVal) {
				return obj && obj.hasOwnProperty(prop) ? obj[prop] : defVal;
			}
			var type = getProperty(ss, 'type', 'ss');
			document.getElementById('ssp_type').value = type;
			document.getElementById('ssp_name').value = getProperty(ss, 'alias', '');
			document.getElementById('ssp_server').value = getProperty(ss, 'server', '');
			document.getElementById('ssp_prot').value = getProperty(ss, 'server_port', '');
			document.getElementById("ss_password").value = getProperty(ss, 'password', '');
			if (type == 'ss') {
				document.getElementById("ss_method").value = getProperty(ss, 'encrypt_method_ss', 'none'),
				document.getElementById("ss_plugin").value = getProperty(ss, 'plugin', ''),
				document.getElementById("ss_plugin_opts").value = getProperty(ss, 'plugin_opts', '');
			} else if (type == "ssr") {
				document.getElementById("ss_protocol").value = getProperty(ss, 'protocol', 'origin');
				document.getElementById("ss_protocol_param").value = getProperty(ss, 'protocol_param', '');
				document.getElementById("ss_method").value = getProperty(ss, 'encrypt_method', 'none');
				document.getElementById("ss_obfs").value = getProperty(ss, 'obfs', 'plain');
				document.getElementById("ss_obfs_param").value = getProperty(ss, 'obfs_param', '');
			} else if (type == "v2ray" || type == "xray") {
				var transport = getProperty(ss, 'transport', 'tcp');
				document.getElementById("ssp_insecure").value = getProperty(ss, 'insecure', 0);
				document.getElementById("ssp_insecure").checked = document.getElementById("ssp_insecure").value != 0;
				document.getElementById("v2_mux").value = getProperty(ss, 'mux', 0);
				document.getElementById("v2_mux").checked = document.getElementById("v2_mux").value != 0;
				document.getElementById("v2_security").value = getProperty(ss, 'security', 'auto');
				document.getElementById("v2_vmess_id").value = getProperty(ss, 'vmess_id', '');
				document.getElementById("v2_alter_id").value = getProperty(ss, 'alter_id', '');
				document.getElementById("v2_transport").value = transport;
				document.getElementById("v2_tcp_guise").value = getProperty(ss, 'tcp_guise', 'none');
				document.getElementById("v2_http_host").value = getProperty(ss, 'http_host', '');
				document.getElementById("v2_http_path").value = getProperty(ss, 'http_path', '');
				document.getElementById("v2_tls").value = getProperty(ss, 'tls', '0');
				document.getElementById("v2_flow").value = getProperty(ss, 'flow', '0');
				//document.getElementById("v2_tls").checked =  document.getElementById("v2_tls").value != 0;
				document.getElementById("ssp_tls_host").value = getProperty(ss, 'tls_host', '');
				document.getElementById("v2_reality_pbk").value = getProperty(ss, 'reality_public_key', '');
				document.getElementById("v2_reality_sid").value = getProperty(ss, 'reality_short_id', '');
				document.getElementById("v2_reality_fp").value = getProperty(ss, 'reality_fingerprint', 'chrome');
				document.getElementById("v2_reality_spx").value = getProperty(ss, 'reality_spider_x', '');
				// 回填完才知道要不要显示：这几个字段的可见性取决于 v2_tls 的值
				toggle_reality_rows();
				if (transport == "kcp") {
					document.getElementById("v2_kcp_guise").value = getProperty(ss, 'kcp_guise', 'none');
					document.getElementById("v2_mtu").value = getProperty(ss, 'mtu', '');
					document.getElementById("v2_tti").value = getProperty(ss, 'tti', '');
					document.getElementById("v2_uplink_capacity").value = getProperty(ss, 'uplink_capacity', '');
					document.getElementById("v2_downlink_capacity").value = getProperty(ss, 'downlink_capacity', '');
					document.getElementById("v2_read_buffer_size").value = getProperty(ss, 'read_buffer_size', '');
					document.getElementById("v2_write_buffer_size").value = getProperty(ss, 'write_buffer_size', '');
				} else if (transport == "ws") {
					document.getElementById("v2_ws_host").value = getProperty(ss, 'ws_host', '');
					document.getElementById("v2_ws_path").value = getProperty(ss, 'ws_path', '');
				} else if (transport == "grpc") {
					document.getElementById("v2_grpc_path").value = getProperty(ss, 'grpc_path', '');
				} else if (transport == "h2") {
					document.getElementById("v2_h2_host").value = getProperty(ss, 'h2_host', '');
					document.getElementById("v2_h2_path").value = getProperty(ss, 'h2_path', '');
				} else if (transport == "quic") {
					document.getElementById("v2_quic_guise").value = getProperty(ss, 'quic_guise', 'none');
					document.getElementById("v2_quic_key").value = getProperty(ss, 'quic_key', '');
					document.getElementById("v2_quic_security").value = getProperty(ss, 'quic_security', 'none');
				}else if (transport == "httpupgrade") {
					document.getElementById("v2_httpupgrade_host").value = getProperty(ss, 'httpupgrade_host', '');
					document.getElementById("v2_httpupgrade_path").value = getProperty(ss, 'httpupgrade_path', '');
				}else if (transport == "wsplithttp") {
					document.getElementById("v2_splithttp_host").value = getProperty(ss, 'splithttp_host', '');
					document.getElementById("v2_splithttp_path").value = getProperty(ss, 'splithttp_path', '');
				}
			} else if (type == "trojan") {
				document.getElementById("ssp_insecure").value = getProperty(ss, 'insecure', 0);
				document.getElementById("ssp_insecure").checked = document.getElementById("ssp_insecure").value != 0;
				document.getElementById("v2_tls").value = 1;
				//document.getElementById("v2_tls").checked = document.getElementById("v2_tls") != 0;
				document.getElementById("ssp_tls_host").value = getProperty(ss, 'tls_host', '');
			} else if (type == "socks5") {
				//
			}
			switch_ss_type();
			$j("#vpnc_settings").fadeIn(200);
		}
		//单项删除
		function del(id) {
		ctime();
			var p = "ssconf_basic";
			var ns = {};
			ns[p + "_json_" + id] = "deleting";
			$j.ajax({
				url: "/applydb.cgi?userm1=del&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("删除失败,请重试！")
				},
				success: function (response) {
				dtime();
					$j('#table99').bootstrapTable('refresh');
				}
			});
		}
		//批量删除
		function del_dlink() {
		ctime();
			var row = $j("#table99").bootstrapTable('getSelections');
			var p = "ssconf_basic";
			var ns = {};
			for (var key in row) {
				ns[p + "_json_" + row[key].ids] = "deleting";
			}
			//console.log(ns)
			document.getElementById("btn_del_link").value="正在删除节点";
			$j.ajax({
				url: "/applydb.cgi?userm1=del&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("删除失败,请重试！")
				},
				success: function (response) {
					setTimeout("dtime();$j('#table99').bootstrapTable('refresh');document.getElementById('btn_del_link').value='删除节点';",1000);
				}
			});
		}
		//ping节点
		function ping_dlink() {
		ctime();
			var row = $j("#table99").bootstrapTable('getSelections');
			var p = "ssconf_basic";
			var ns = {};
			for (var key in row) {
				ns[row[key].ids] = "ping";
			}
			//showLoading();
			document.getElementById("btn_ping_link").value="正在ping节点";
			$j.ajax({
				url: "/applydb.cgi?useping=1&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("脚本执行失败！！！")
				},
				success: function (response) {
					setTimeout("dtime();$j('#table99').bootstrapTable('refresh');document.getElementById('btn_ping_link').value='ping节点';",2000);
				}
			});
		}
		//ping全部节点
		function aping_dlink() {
		ctime();
			var ns = {};
			ns[1] = "allping";
			document.getElementById("btn_aping_link").value="正在ping节点";
			$j.ajax({
				url: "/applydb.cgi?useping=1&p=ss",
				type: 'POST',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(ns),
				error: function (xhr) {
					alert("脚本执行失败！！！")
				},
				success: function (response) {
					setTimeout("dtime();$j('#table99').bootstrapTable('refresh');document.getElementById('btn_aping_link').value='ping全部';",2000);
				}
			});
		}

		// ================= F2：真实 URL 测延迟 =================
		//
		// 与 ping 的区别：ping 量的是「到节点服务器的 ICMP/TCP 可达性」，本功能量的是
		// 「经这个节点自己的 socks 出口跑一次完整 HTTP 请求要多久」—— 后者才是用户真正
		// 感知到的「打开网页快不快」。
		//
		// ★ 探测地址下拉框（内置 7 个 generate_204 端点 + 「自定义…」）。
		//   选中值存 dbus 键 urltest_url，urltest.sh 自己 dbus get 它，为空则用它的内置默认。
		//   ★ URL 绝不能走 argv：web_ex.c 的 SystemCmd[128] 会静默截断到 127 字节。
		var URLTEST_URLS = [
				"http://www.gstatic.com/generate_204",
				"http://www.google.com/generate_204",
				"http://connectivitycheck.gstatic.com/generate_204",
				"http://cp.cloudflare.com/generate_204",
				"http://www.msftconnecttest.com/connecttest.txt",
				"http://detectportal.firefox.com/success.txt",
				"http://www.baidu.com/"
		];

		// 回填：把 dbus 里的 urltest_url 反映到下拉框 / 自定义输入框上。
		// 读的是 <head> 里【同步加载】的 window.db_urltest（不是 ajax）。
		// ★ 这里只切显示、不写 dbus —— 否则每开一次页面都会往 flash 写一次。
		function urltest_url_init() {
				var sel = document.getElementById("urltest_url_sel");
				if (!sel) {
						return;
				}
				var cur = "";
				if (typeof (window.db_urltest) != "undefined" && db_urltest &&
						typeof (db_urltest.urltest_url) != "undefined") {
						cur = String(db_urltest.urltest_url);
				}
				sel.options.length = 0;
				var hit = -1;
				for (var i = 0; i < URLTEST_URLS.length; i++) {
						sel.options.add(new Option(URLTEST_URLS[i], URLTEST_URLS[i]));
						if (URLTEST_URLS[i] === cur) {
								hit = i;
						}
				}
				sel.options.add(new Option("自定义…", "__custom__"));
				if (cur === "") {
						// dbus 里没存过 ⇒ 显示内置默认（与 urltest.sh 的 DEFAULT_URL 一致）
						sel.selectedIndex = 0;
				} else if (hit >= 0) {
						sel.selectedIndex = hit;
				} else {
						// 存的是清单外的值 ⇒ 落到「自定义」并把值填进输入框
						sel.selectedIndex = URLTEST_URLS.length;
						var inp = document.getElementById("urltest_url_custom");
						if (inp) {
								inp.value = cur;
						}
				}
				urltest_url_toggle();
				// 上次运行的结果也一并回显，免得状态栏空着
				var st = document.getElementById("urltest_status_txt");
				if (st && typeof (window.db_urltest) != "undefined" && db_urltest &&
						typeof (db_urltest.urltest_status) != "undefined") {
						st.innerHTML = String(db_urltest.urltest_status);
				}
		}

		// 只切「自定义输入框」的显隐，不写 dbus。
		function urltest_url_toggle() {
				var sel = document.getElementById("urltest_url_sel");
				var inp = document.getElementById("urltest_url_custom");
				if (!sel || !inp) {
						return;
				}
				inp.style.display = (sel.value === "__custom__") ? "" : "none";
		}

		// 下拉框改变：切显示 + 把预设值写回 dbus。
		function urltest_url_change() {
				urltest_url_toggle();
				var sel = document.getElementById("urltest_url_sel");
				if (sel && sel.value !== "__custom__") {
						urltest_url_post(sel.value);
				}
		}

		// 自定义输入框改变：形态守卫 + 写回 dbus。
		function urltest_url_save() {
				var inp = document.getElementById("urltest_url_custom");
				if (!inp) {
						return;
				}
				var v = inp.value.replace(/^\s+|\s+$/g, '');
				// ★ 形态守卫：值最终会进 urltest.sh 里 curl 的参数列表。
				//   光加引号挡不住 —— "curl -o/etc/storage/x" 是【合法 argv】，一个空格就能另起
				//   一个选项（同「订阅内容 = 未受信输入」的既有教训：对无引号裸拼接点，
				//   一个空格就能另起命令）。所以这里挡的是「形态」，不是「引号」。
				//   留空 = 用内置默认，是合法状态，不拦。
				if (v !== "" && !/^https?:\/\/[^\s]+$/i.test(v)) {
						alert("探测地址不合法：必须以 http:// 或 https:// 开头，且不能含空格等空白字符。");
						return;
				}
				inp.value = v;
				urltest_url_post(v);
		}

		// 写 dbus 键 urltest_url。
		// 走 /applydb.cgi?p=urltest ⇒ applydb_store 落到最后的 else 分支 dbclient_bulk
		// （值不过 shell，没有引号/长度问题），applydb_cgi 随后自动 mtd_storage.sh save 落 flash。
		function urltest_url_post(v) {
				var o = {};
				o.urltest_url = v;
				$j.ajax({
						url: "/applydb.cgi?p=urltest",
						type: 'POST',
						contentType: "application/x-www-form-urlencoded",
						dataType: 'text',
						data: $j.param(o),
						error: function (xhr) {
								alert("探测地址保存失败！");
						},
						success: function (response) {
								if (typeof (window.db_urltest) == "undefined" || !db_urltest) {
										window.db_urltest = {};
								}
								// 本地缓存同步：同一次会话里再选别的值时才不会拿旧值去比
								db_urltest.urltest_url = v;
						}
				});
		}

		// URL 测延迟（真实 URL，经节点自己的 socks 出口）。
		// ★ 与 ping_dlink() 的唯一区别是 POST body 里的【值】：值决定 web_ex.c 的
		//   applydb_store 走哪个动词（"ping" → ping.sh，"urltest" → urltest.sh）。
		//   query 里的 useping=1 / p=ss 对 POST 都是装饰性的 —— httpd.c:945 的 strsep
		//   在 handler 之前就把 query 切掉了，触发只认 POST body 里的值。
		//   ★ 不能改成 ?useurltest=1 而把值留成 "ping"：那会去调 ping.sh，
		//     症状是「点了 URL 测试，结果列填的却是 ICMP 延迟」。
		function urltest_dlink() {
				var row = $j("#table99").bootstrapTable('getSelections');
				if (!row || row.length === 0) {
						alert("请先勾选要测试的节点。");
						return;
				}
				var ns = {};
				for (var key in row) {
						ns[row[key].ids] = "urltest";
				}
				// ★ 不用 ctime()/dtime()：urltest.sh 自己后台脱离，success 回调会在毫秒级触发，
				//   那对客户端计时器会立刻打出「脚本运行完成!」，而测试其实刚开跑。
				//   进度改为轮询 dbus 的 urltest_run / urltest_status。
				document.getElementById("btn_urltest_link").value = "URL测试中…";
				$j.ajax({
						url: "/applydb.cgi?useping=1&p=ss",
						type: 'POST',
						contentType: "application/x-www-form-urlencoded",
						dataType: 'text',
						data: $j.param(ns),
						error: function (xhr) {
								alert("脚本执行失败！！！");
								document.getElementById("btn_urltest_link").value = "URL测试";
						},
						success: function (response) {
								urltest_poll(0);
						}
				});
		}

		// 轮询 dbus 的 urltest_run / urltest_status，直到 run != 1 或到上限。
		// ★ 上限不能省：重启后残留的 urltest_run=1 会让按钮永远卡在「测试中…」。
		//   1500ms × 80 ≈ 2 分钟 —— 41 个节点 4 路并发约 1~2 分钟。
		// ★ 只读 /dbconf?p=urltest（键很少）。不要带 ss：那会把 41 个节点的 JSON
		//   每 1.5 秒重解析一遍。
		function urltest_poll(n) {
				var left = (typeof (n) == "undefined") ? 0 : n;
				var st = document.getElementById("urltest_status_txt");
				$j.ajax({
						url: "/dbconf?p=urltest&_=" + (new Date()).getTime(),
						type: 'get',
						dataType: 'script',
						cache: false,
						success: function () {
								var run = "0", status = "";
								if (typeof (window.db_urltest) != "undefined" && db_urltest) {
										if (typeof (db_urltest.urltest_run) != "undefined") {
												run = String(db_urltest.urltest_run);
										}
										if (typeof (db_urltest.urltest_status) != "undefined") {
												status = String(db_urltest.urltest_status);
										}
								}
								if (st) {
										st.innerHTML = status;
								}
								if (run === "1" && left < 80) {
										setTimeout(function () { urltest_poll(left + 1); }, 1500);
										return;
								}
								urltest_done();
						},
						error: function () {
								// 读失败不该把界面永久卡在「测试中…」，但也不能无限重试
								if (left < 80) {
										setTimeout(function () { urltest_poll(left + 1); }, 1500);
										return;
								}
								urltest_done();
						}
				});
		}

		// 收尾：恢复按钮 + 刷新表格把新结果读进来。
		// ★ refresh 会走 bootstrapTable 的 options.ajax（本表初始化时就给了自定义 loader），
		//   那条 loader 重新 GET /dbconf?p=ss 并再跑一遍 showMRULESList 里的那段 ⇒ 新值进表、
		//   过滤口径也一并重新应用。ping_dlink() 用的就是这个收尾方式。
		function urltest_done() {
				var btn = document.getElementById("btn_urltest_link");
				if (btn) {
						btn.value = "URL测试";
				}
				$j('#table99').bootstrapTable('refresh');
		}

		function paramsMatter(value, row, index) {
			var span = document.createElement("span");
			span.setAttribute("title", value);
			span.innerHTML = value;
			return span.outerHTML;
		}
		//td宽度以及内容超过宽度隐藏
		function formatTableUnit(value, row, index) {
			return {
				css: {
					"white-space": "nowrap",
					"text-overflow": "ellipsis",
					"overflow": "hidden",
					"max-width": "60px"
				}
			}
		}
		//-----------导入链接开始
		function padright(str, cnt, pad) {
			return str + Array(cnt + 1).join(pad);
		}
		function b64EncodeUnicode(str) {
			return btoa(encodeURIComponent(str).replace(/%([0-9A-F]{2})/g, function (match, p1) {
				return String.fromCharCode('0x' + p1);
			}));
		}
		function b64encutf8safe(str) {
			return b64EncodeUnicode(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, '');
		}
		function b64DecodeUnicode(str) {
			return decodeURIComponent(Array.prototype.map.call(atob(str), function (c) {
				return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
			}).join(''));
		}
		function b64decutf8safe(str) {
			var l;
			str = str.replace(/-/g, "+").replace(/_/g, "/");
			l = str.length;
			l = (4 - l % 4) % 4;
			if (l)
				str = padright(str, l, "=");
			return b64DecodeUnicode(str);
		}
		function b64encsafe(str) {
			return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, '')
		}
		function b64decsafe(str) {
			var l;
			str = str.replace(/-/g, "+").replace(/_/g, "/");
			l = str.length;
			l = (4 - l % 4) % 4;
			if (l)
				str = padright(str, l, "=");
			return atob(str);
		}
		function dictvalue(d, key) {
			var v = d[key];
			if (typeof (v) == 'undefined' || v == '')
				return '';
			return b64decsafe(v);
		}
		function import_ssr_url(btn, urlname, sid) {
			var s = document.getElementById(urlname + '-status');
			if (!s)
				return false;
			var ssrurl = prompt("在这里粘贴配置链接 ssr:// | ss:// | vmess:// | vless:// | trojan://", "");
			if (ssrurl == null || ssrurl == "") {
				s.innerHTML = "<font color='red'>用户取消</font>";
				return false;
			}
			initSSParams();
			s.innerHTML = "";
			//var ssu = ssrurl.match(/ssr:\/\/([A-Za-z0-9_-]+)/i);
			var ssu = ssrurl.split('://');
			//console.log(ssu.length);
			if ((ssu[0] != "ssr" && ssu[0] != "ss" && ssu[0] != "vmess" && ssu[0] != "vless" && ssu[0] != "trojan") || ssu[1] == "") {
				s.innerHTML = "<font color='red'>无效格式</font>";
				return false;
			}
			var event = document.createEvent("HTMLEvents");
			event.initEvent("change", true, true);
			initSSParams();
			if (ssu[0] == "ssr") {
				var sstr = b64decsafe(ssu[1]);
				var ploc = sstr.indexOf("/?");
				document.getElementById('ssp_type').value = "ssr";
				document.getElementById('ssp_type').dispatchEvent(event);
				var url0, param = "";
				if (ploc > 0) {
					url0 = sstr.substr(0, ploc);
					param = sstr.substr(ploc + 2);
				}
				var ssm = url0.match(/^(.+):([^:]+):([^:]*):([^:]+):([^:]*):([^:]+)/);
				if (!ssm || ssm.length < 7)
					return false;
				var pdict = {};
				if (param.length > 2) {
					var a = param.split('&');
					for (var i = 0; i < a.length; i++) {
						var b = a[i].split('=');
						pdict[decodeURIComponent(b[0])] = decodeURIComponent(b[1] || '');
					}
				}
				document.getElementById('ssp_server').value = ssm[1];
				document.getElementById('ssp_prot').value = ssm[2];
				document.getElementById('ss_protocol').value = ssm[3];
				document.getElementById('ss_method').value = ssm[4];
				document.getElementById('ss_obfs').value = ssm[5];
				document.getElementById('ss_password').value = b64decsafe(ssm[6]);
				document.getElementById('ss_obfs_param').value = dictvalue(pdict, 'obfsparam');
				document.getElementById('ss_protocol_param').value = dictvalue(pdict, 'protoparam');
				var rem = pdict['remarks'];
				if (typeof (rem) != 'undefined' && rem != '' && rem.length > 0)
					document.getElementById('ssp_name').value = b64decutf8safe(rem);
				s.innerHTML = "<font color='green'>导入ShadowsocksR配置信息成功</font>";
				return false;
			} else if (ssu[0] == "ss") {
				var url0, param = "";
				var sipIndex = ssu[1].indexOf("@");
				var ploc = ssu[1].indexOf("#");
				if (ploc > 0) {
					url0 = ssu[1].substr(0, ploc);
					param = ssu[1].substr(ploc + 1);
				} else {
					url0 = ssu[1]
				}
				if (sipIndex != -1) {
				var userInfo = b64decsafe(url0.substr(0, sipIndex));
				var temp = url0.substr(sipIndex + 1).split("/?");
				var serverInfo = temp[0].split(":");
				var server = serverInfo[0];
				var port = serverInfo[1].replace("/","");
				var method, password, plugin, pluginOpts;
				if (temp[1]) {
					var pluginInfo = decodeURIComponent(temp[1]);
					var pluginIndex = pluginInfo.indexOf(";");
					var pluginNameInfo = pluginInfo.substr(0, pluginIndex);
					plugin = pluginNameInfo.substr(pluginNameInfo.indexOf("=") + 1);
					pluginOpts = pluginInfo.substr(pluginIndex + 1);
				}
				var userInfoSplitIndex = userInfo.indexOf(":");
				if (userInfoSplitIndex != -1) {
					method = userInfo.substr(0, userInfoSplitIndex);
					password = userInfo.substr(userInfoSplitIndex + 1);
				}
				document.getElementById('ssp_type').value = "ss";
				document.getElementById('ssp_type').dispatchEvent(event);
				document.getElementById('ssp_server').value = server;
				document.getElementById('ssp_prot').value = port;
				document.getElementById('ss_password').value = password || "";
				document.getElementById('ss_method').value = method || "";
				document.getElementById('ss_plugin').value = plugin || "";
				if (plugin != undefined && plugin != "") {
				document.getElementById('ss_plugin_opts').value = pluginOpts || "";
				}
				if (param != undefined) {
				document.getElementById('ssp_name').value = decodeURI(param);
				}				
				s.innerHTML = "<font color='green'>导入Shadowsocks配置信息成功</font>";
				}
			 else {
				var sstr = b64decsafe(url0);
				document.getElementById('ssp_type').value = "ss";
				document.getElementById('ssp_type').dispatchEvent(event);
				var team = sstr.split('@');
				console.log(param);
				var part1 = team[0].split(':');
				var part2 = team[1].split(':');
				document.getElementById('ssp_server').value = part2[0];
				document.getElementById('ssp_prot').value = part2[1];
				document.getElementById('ss_password').value = part1[1];
				document.getElementById('ss_method').value = part1[0];
				s.innerHTML = "<font color='green'>导入Shadowsocks配置信息成功</font>";
				}
				if (param != undefined) {
					document.getElementById('ssp_name').value = decodeURI(param);
				}
				return false;
			} else if (ssu[0] == "trojan") {
				var url0, param = "";
				var ploc = ssu[1].indexOf("#");
				if (ploc > 0) {
					url0 = ssu[1].substr(0, ploc);
					param = ssu[1].substr(ploc + 1);
				} else {
					url0 = ssu[1]
				}
				var sstr = url0;
				document.getElementById('ssp_type').value = "trojan";
				document.getElementById('ssp_type').dispatchEvent(event);
				var team = sstr.split('@');
				var password = team[0]
				var serverPart = team[1].split(':');
				var others = serverPart[1].split('?');
				var port = parseInt(others[0]);
				var queryParam = {}
				if (others.length > 1) {
					var queryParams = others[1]
					var queryArray = queryParams.split('&');
					for (i = 0; i < queryArray.length; i++) {
						var params = queryArray[i].split('=');
						queryParam[decodeURIComponent(params[0])] = decodeURIComponent(params[1] || '');
					}
				}
				document.getElementById('ssp_server').value = serverPart[0];
				document.getElementById('ssp_prot').value = port || '443';;
				document.getElementById('ss_password').value = password;
				document.getElementById('v2_tls').value = '1';
				document.getElementById('ssp_tls_host').value = queryParam.sni || '';
				if (param != undefined) {
					document.getElementById('ssp_name').value = decodeURI(param);
				}
				s.innerHTML = "<font color='green'>导入Trojan配置信息成功</font>";
				return false;
			} else if (ssu[0] == "vmess") {
				var sstr = b64DecodeUnicode(ssu[1]);
				console.log(sstr);
				var ploc = sstr.indexOf("/?");
				document.getElementById('ssp_type').value = "v2ray";
				document.getElementById('ssp_type').dispatchEvent(event);
				var url0, param = "";
				if (ploc > 0) {
					url0 = sstr.substr(0, ploc);
					param = sstr.substr(ploc + 2);
				}
				var ssm = JSON.parse(sstr);
				document.getElementById('ssp_name').value = ssm.ps;
				document.getElementById('ssp_server').value = ssm.add;
				document.getElementById('ssp_prot').value = ssm.port;
				document.getElementById('v2_alter_id').value = ssm.aid;
				document.getElementById('v2_vmess_id').value = ssm.id;
				document.getElementById('v2_transport').value = ssm.net;
				document.getElementById('v2_transport').dispatchEvent(event);
				if (ssm.net == "tcp") {
					if (ssm.type && ssm.type != "http") {
						ssm.type = "none"
					}
					document.getElementById('v2_tcp_guise').value = ssm.type;
					document.getElementById('v2_http_host').value = ssm.host;
					if (ssm.path != undefined){
						document.getElementById('v2_http_path').value = ssm.path;
					}
					else {
						document.getElementById('v2_http_path').value = '/';
					}
				} 
				if (ssm.net == "ws") {
					document.getElementById('v2_ws_host').value = ssm.host;
					document.getElementById('v2_ws_path').value = ssm.path;
				}
				if (ssm.net == "grpc") {
					document.getElementById('v2_grpc_path').value = ssm.path;
				}
				if (ssm.net == "h2") {
					document.getElementById('v2_h2_host').value = ssm.host;
					document.getElementById('v2_h2_path').value = ssm.path;
				}
				if (ssm.net == "httpupgrade") {
					document.getElementById('v2_httpupgrade_host').value = ssm.host;
					document.getElementById('v2_httpupgrade_path').value = ssm.path;
				}
				if (ssm.net == "splithttp") {
					document.getElementById('v2_splithttp_host').value = ssm.host;
					document.getElementById('v2_splithttp_path').value = ssm.path;
				}
				if (ssm.tls == "tls") {
					document.getElementById('v2_tls').value = '1';
					//document.getElementById('v2_tls').checked = true;
					document.getElementById('ssp_insecure').value = 1;
					document.getElementById('ssp_insecure').checked = true;
					document.getElementById('ssp_tls_host').value = ssm.host;
				}
				s.innerHTML = "<font color='green'>导入V2ray配置信息成功</font>";
				return false;
			} else if (ssu[0] == "vless") {
				var url0, param = "";
				var ploc = ssu[1].indexOf("#");
				if (ploc > 0) {
					url0 = ssu[1].substr(0, ploc);
					param = ssu[1].substr(ploc + 1);
				} else {
					url0 = ssu[1]
				}
				if (param != undefined) {
					document.getElementById('ssp_name').value = decodeURI(param);
				}
				var sstr = url0;
				var team = sstr.split('@');
				var password = team[0]
				var serverPart = team[1].split(':');
				var others = serverPart[1].split('?');
				var port = others[0]
				var queryParam = {}
				if (others.length > 1) {
				var queryParams = others[1]
				var queryArray = queryParams.split('&');
				for (i = 0; i < queryArray.length; i++) {
					var params = queryArray[i].split('=');
					queryParam[decodeURIComponent(params[0])] = decodeURIComponent(params[1] || '');
									}
							}
				document.getElementById('ssp_server').value = serverPart[0];
				document.getElementById('ssp_prot').value = port;
				document.getElementById('v2_vmess_id').value = password;
				document.getElementById('v2_alter_id').value = "0";
				document.getElementById('ssp_type').value = "xray";
				document.getElementById('ssp_type').dispatchEvent(event);
				document.getElementById('v2_security').value = queryParam.encryption || "none";
				document.getElementById('v2_transport').value = queryParam.type || "tcp";
				document.getElementById('v2_transport').dispatchEvent(event);

				if (queryParam.security == "tls") {
					document.getElementById('v2_tls').value = '1';
					document.getElementById('v2_flow').value = '0';
					//document.getElementById('v2_tls').checked = true;
					document.getElementById('ssp_insecure').value = 0;
					document.getElementById('ssp_insecure').checked = false;
					document.getElementById('ssp_tls_host').value = queryParam.sni || serverPart[0];
				}

				if (queryParam.type == "ws") {
					document.getElementById('v2_ws_host').value = queryParam.host;
					document.getElementById('v2_ws_path').value = queryParam.path;
				}
				if (queryParam.type == "grpc") {
					document.getElementById('v2_grpc_path').value =  queryParam.serviceName;
				}
				if (queryParam.type == "h2") {
					document.getElementById('v2_h2_host').value = queryParam.host;
					document.getElementById('v2_h2_path').value = queryParam.path;
				}
				if (queryParam.type == "httpupgrade") {
					document.getElementById('v2_httpupgrade_host').value = queryParam.host;
					document.getElementById('v2_httpupgrade_path').value =  queryParam.path;
				}
				if (queryParam.type == "splithttp") {
					document.getElementById('v2_splithttp_host').value = queryParam.host;
					document.getElementById('v2_splithttp_path').value =  queryParam.path;
				}
				if (queryParam.security == "reality") {
					document.getElementById('v2_tls').value = '2';
					if (queryParam.flow != undefined) {
					    if(queryParam.flow == 'xtls-rprx-vision'){
					    	document.getElementById('v2_flow').value = '1';
					    }
					    else if(queryParam.flow == 'xtls-rprx-vision-udp443'){
					    	document.getElementById('v2_flow').value = '2';
					    }
					    else
					    {
					    	document.getElementById('v2_flow').value = '0';
					    }
					}
					else
					{
					    document.getElementById('v2_flow').value = '1';
					}
					//document.getElementById('v2_tls').checked = true;
					document.getElementById('ssp_insecure').value = 0;
					document.getElementById('ssp_insecure').checked = false;
					document.getElementById('ssp_tls_host').value = queryParam.sni || serverPart[0];
					// 链接里的 pbk / sid / fp / spx 就是 xray 要的
					// publicKey / shortId / fingerprint / spiderX。
					// 不带过来的话导入完还得手抄一遍，漏一个 xray 就起不来
					document.getElementById('v2_reality_pbk').value = queryParam.pbk || '';
					document.getElementById('v2_reality_sid').value = queryParam.sid || '';
					document.getElementById('v2_reality_fp').value = queryParam.fp || 'chrome';
					document.getElementById('v2_reality_spx').value = queryParam.spx || '/';
					toggle_reality_rows();
				}
				s.innerHTML = "<font color='green'>导入Xray配置信息成功</font>";
				return false;
			}
		}
		//-----------导入链接结束
		function check_Timefield_checkbox() {
			if (document.form.ss_date_x_Sun.checked == true ||
				document.form.ss_date_x_Mon.checked == true ||
				document.form.ss_date_x_Tue.checked == true ||
				document.form.ss_date_x_Wed.checked == true ||
				document.form.ss_date_x_Thu.checked == true ||
				document.form.ss_date_x_Fri.checked == true ||
				document.form.ss_date_x_Sat.checked == true) {
				inputCtrl(document.form.ss_time_x_hour, 1);
				inputCtrl(document.form.ss_time_x_min, 1);
				document.form.ss_schedule.disabled = false;
			} else {
				inputCtrl(document.form.ss_time_x_hour, 0);
				inputCtrl(document.form.ss_time_x_min, 0);
				document.form.ss_schedule.disabled = true;
				document.getElementById('ss_schedule_time_tr').style.display = "";
			}
		}
		function getrebootTimeRange(str, pos) {
			if (pos == 0)
				return str.substring(7, 9);
			else if (pos == 1)
				return str.substring(9, 11);
		}
		function setrebootTimeRange(rd, rh, rm) {
			return (rd.value + rh.value + rm.value);
		}
		function updateDateTime() {
			if (document.form.ss_schedule_enable_x[0].checked) {
				document.form.ss_schedule_enable.value = "1";
				document.form.ss_schedule.disabled = false;
				document.form.ss_schedule.value = setDateCheck(
					document.form.ss_date_x_Sun,
					document.form.ss_date_x_Mon,
					document.form.ss_date_x_Tue,
					document.form.ss_date_x_Wed,
					document.form.ss_date_x_Thu,
					document.form.ss_date_x_Fri,
					document.form.ss_date_x_Sat);
				document.form.ss_schedule.value = setrebootTimeRange(
					document.form.ss_schedule,
					document.form.ss_time_x_hour,
					document.form.ss_time_x_min);
			} else
				document.form.ss_schedule_enable.value = "0";
		}
		//点击保存节点按钮
		function showNodeData(idName, obj) {
			var nodeData = document.getElementById(idName);
			//console.log(nodeData);
			for (var key in obj) {
				var tr = document.createElement("tr");
				var td = document.createElement("td");
				var td2 = document.createElement("td");
				var input = document.createElement("input");
				td.innerText = obj[key];
				tr.appendChild(td);
				input.name = key;
				td2.appendChild(input);
				tr.appendChild(td2);
				nodeData.appendChild(tr);
			}
		}
		function add_ss() {
			showhide_div('vpnc_settings', 0);
			var type = document.getElementById("ssp_type").value;
			if (type == "ss") {
				var DataObj = {
					type: document.getElementById("ssp_type").value,
					alias: document.getElementById("ssp_name").value,
					server: document.getElementById("ssp_server").value,
					server_port: document.getElementById("ssp_prot").value,
					password: document.getElementById("ss_password").value,
					encrypt_method_ss: document.getElementById("ss_method").value,
					plugin: document.getElementById("ss_plugin").value,
					plugin_opts: document.getElementById("ss_plugin_opts").value,
					coustom: "1",
				}
			} else if (type == "ssr") {
				var DataObj = {
					type: document.getElementById("ssp_type").value,
					alias: document.getElementById("ssp_name").value,
					server: document.getElementById("ssp_server").value,
					server_port: document.getElementById("ssp_prot").value,
					protocol: document.getElementById("ss_protocol").value,
					protocol_param: document.getElementById("ss_protocol_param").value,
					encrypt_method: document.getElementById("ss_method").value,
					obfs: document.getElementById("ss_obfs").value,
					obfs_param: document.getElementById("ss_obfs_param").value,
					password: document.getElementById("ss_password").value,
					coustom: "1",
				}
			} else if (type == "v2ray" || type == "xray") {
				var http_pathnew = document.getElementById("v2_http_path").value;
				if (http_pathnew == '') { document.getElementById("v2_http_path").value='/';}
				var DataObj = {
					type: document.getElementById("ssp_type").value,
					alias: document.getElementById("ssp_name").value,
					server: document.getElementById("ssp_server").value,
					server_port: document.getElementById("ssp_prot").value,
					insecure: document.getElementById("ssp_insecure").value,
					mux: document.getElementById("v2_mux").value,
					security: document.getElementById("v2_security").value,
					vmess_id: document.getElementById("v2_vmess_id").value,
					alter_id: document.getElementById("v2_alter_id").value,
					transport: document.getElementById("v2_transport").value,
					tcp_guise: document.getElementById("v2_tcp_guise").value,
					http_host: document.getElementById("v2_http_host").value,
					http_path: document.getElementById("v2_http_path").value,
					tls: document.getElementById("v2_tls").value,
					flow: document.getElementById("v2_flow").value,
					tls_host: document.getElementById("ssp_tls_host").value,
					reality_public_key: document.getElementById("v2_reality_pbk").value,
					reality_short_id: document.getElementById("v2_reality_sid").value,
					reality_fingerprint: document.getElementById("v2_reality_fp").value || 'chrome',
					// spiderX 留空时 xray 收到空串会走它自己的默认值，但显式给 / 更稳
					reality_spider_x: document.getElementById("v2_reality_spx").value || '/',
					coustom: "1",
				}
				if (document.getElementById("v2_transport").value == "kcp") {
					DataObj.kcp_guise = document.getElementById("v2_kcp_guise").value;
					DataObj.mtu = document.getElementById("v2_mtu").value;
					DataObj.tti = document.getElementById("v2_tti").value;
					DataObj.uplink_capacity = document.getElementById("v2_uplink_capacity").value;
					DataObj.downlink_capacity = document.getElementById("v2_downlink_capacity").value;
					DataObj.read_buffer_size = document.getElementById("v2_read_buffer_size").value;
					DataObj.write_buffer_size = document.getElementById("v2_write_buffer_size").value;
				} else if (document.getElementById("v2_transport").value == "ws") {
					DataObj.ws_host = document.getElementById("v2_ws_host").value;
					DataObj.ws_path = document.getElementById("v2_ws_path").value;
				} else if (document.getElementById("v2_transport").value == "grpc") {
					DataObj.grpc_path = document.getElementById("v2_grpc_path").value;
				} else if (document.getElementById("v2_transport").value == "h2") {
					DataObj.h2_host = document.getElementById("v2_h2_host").value;
					DataObj.h2_path = document.getElementById("v2_h2_path").value;
				} else if (document.getElementById("v2_transport").value == "quic") {
					DataObj.quic_guise = document.getElementById("v2_quic_guise").value;
					DataObj.quic_key = document.getElementById("v2_quic_key").value;
					DataObj.quic_security = document.getElementById("v2_quic_security").value;
				} else if (document.getElementById("v2_transport").value == "httpupgrade") {
					DataObj.httpupgrade_host = document.getElementById("v2_httpupgrade_host").value;
					DataObj.httpupgrade_path = document.getElementById("v2_httpupgrade_path").value;
				} else if (document.getElementById("v2_transport").value == "splithttp") {
					DataObj.splithttp_host = document.getElementById("v2_splithttp_host").value;
					DataObj.splithttp_path = document.getElementById("v2_splithttp_path").value;
				}
			} else if (type == "trojan") {
				var DataObj = {
					type: document.getElementById("ssp_type").value,
					alias: document.getElementById("ssp_name").value,
					server: document.getElementById("ssp_server").value,
					server_port: document.getElementById("ssp_prot").value,
					password: document.getElementById("ss_password").value,
					insecure: document.getElementById("ssp_insecure").value,
					tls: document.getElementById("v2_tls").value,
					tls_host: document.getElementById("ssp_tls_host").value,
					coustom: "1",
				}
			} else if (type == "socks5") {
				var DataObj = {
					type: document.getElementById("ssp_type").value,
					alias: document.getElementById("ssp_name").value,
					server: document.getElementById("ssp_server").value,
					server_port: document.getElementById("ssp_prot").value,
					server_user: document.getElementById("s5_username").value,
					server_pwd: document.getElementById("s5_password").value,
					coustom: "1",
				}
			}
			var post_dbus = JSON.stringify(DataObj)
			var ids;
			if (editing_ss_id == 0) {  
				node_global_max += 1;
				ids = node_global_max;
			} else {
				ids = editing_ss_id;
			}
			var ns = {};
			ns["ssconf_basic_json_" + ids] = post_dbus;
			push_data(ns);
			console.log(DataObj)
		}
		//post数据到后台处理
		function push_data(obj) {
			ctime();
			$j.ajax({
				type: "POST",
				url: '/applydb.cgi?p=ss',
				contentType: "application/x-www-form-urlencoded",
				dataType: 'text',
				data: $j.param(obj),
				success: function (response) {
				//hideLoading();
					$j("#vpnc_settings").fadeOut(200);
					dtime();
					$j('#table99').bootstrapTable('refresh');
				}
			});
		}
		function showsdlinkList() {
			var value = document.getElementById("nodeList").value;
			if (value >0){
			var key = "ssconf_basic_json_" + value;		
			var result = JSON.parse(db_ss[key]);
			document.getElementById("d_type").value = result.type;}
		}
		function showsudlinkList() {
			var value = document.getElementById("u_nodeList").value;
			if (value >0){
			var key = "ssconf_basic_json_" + value;
			var result = JSON.parse(db_ss[key]);
			document.getElementById("ud_type").value = result.type;}
		}
		function shows5dlinkList() {
			var value = document.getElementById("s5_nodeList").value;
			if (value >0){
			var key = "ssconf_basic_json_" + value
			var result = JSON.parse(db_ss[key]);
			document.getElementById("s5_type").value = result.type;}
		}
	</script>
	<style>
		.nav-tabs>li>a {
			padding-right: 6px;
			padding-left: 6px;
		}
		.contentM_qis {
			position: absolute;
			-webkit-border-radius: 5px;
			-moz-border-radius: 5px;
			border-radius: 5px;
			z-index: 200;
			background-color: #ffffff;
			margin-left: 15px;
			top: 80px;
			width: 650px;
			height: auto;
			box-shadow: 3px 3px 10px #000;
			display: none;
		}
	</style>
</head>

<body onload="initial();" onunLoad="return unload_body();">
	<div class="wrapper">
		<div class="container-fluid" style="padding-right: 0px">
			<div class="row-fluid">
				<div class="span3">
					<center>
						<div id="logo"></div>
					</center>
				</div>
				<div class="span9">
					<div id="TopBanner"></div>
				</div>
			</div>
		</div>
		<div id="Loading" class="popup_bg"></div>
		<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
		<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">
			<input type="hidden" name="current_page" value="Shadowsocks.asp">
			<input type="hidden" name="next_page" value="">
			<input type="hidden" name="next_host" value="">
			<input type="hidden" name="sid_list" value="ShadowsocksConf;">
			<input type="hidden" name="group_id" value="SspList">
			<input type="hidden" name="action_mode" value="">
			<input type="hidden" name="action_script" value="">
			<input type="hidden" name="ssp_staticnum_x_0" value="<% nvram_get_x("SspList", "ssp_staticnum_x"); %>" readonly="1" />
			<input type="hidden" id="d_type" name="d_type" value="<% nvram_get_x("","d_type"); %>">
			<input type="hidden" id="ud_type" name="ud_type" value="<% nvram_get_x("","ud_type"); %>">
			<input type="hidden" id="s5_type" name="s5_type" value="<% nvram_get_x("","s5_type"); %>">
			<input type="hidden" name="ss_schedule" value="<% nvram_get_x("", "ss_schedule"); %>" disabled>
			<input type="hidden" name="ss_schedule_enable" value="<% nvram_get_x("", "ss_schedule_enable"); %>">
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
									<h2 class="box_head round_top"><#menu5_16#> - ShadowSocksR Plus+</h2>
									<div class="round_bottom">
										<div>
											<ul class="nav nav-tabs" style="margin-bottom: 10px;">
												<li class="active"><a id="tab_ss_cfg" href="#cfg">客户端</a></li>
												<li><a id="tab_ss_add" href="#add">节点管理</a></li>
												<li><a id="tab_ss_ssl" href="#ssl">高级设置</a></li>
												<li><a id="tab_ss_cli" href="#cli">规则管理</a></li>
												<li><a id="tab_ss_log" href="#log">运行日志</a></li>
												<li><a id="tab_ss_help" href="#help">帮助文档</a></li>
											</ul>
										</div>
										<div class="row-fluid">
											<div id="tabMenu" class="submenuBlock"></div>
											<div id="wnd_ss_cfg">
												<div class="alert alert-info" style="margin: 10px;">一个兼容Shadowsocks、ShadowsocksR 、Vmess、Vless、Trojan、Sock5协议的游戏加速工具。
													<div><span style="color:#E53333;">注意:</span></div>
													<div><span style="color:#E53333;">若被编辑的节点正在运行使用，请完成后点击“应用设置”更新节点信息并"重连"</span></div>
													<div><span style="color:#E53333;">运行状态不会实时更新，启动程序后需等待一段时间后点击"刷新"获取运行状态</span></div>
												</div>
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<th width="50%"><#Main_Switch#></th>
														<td>
															<div class="main_itoggle">
																<div id="ss_enable_on_of">
																	<input type="checkbox" id="ss_enable_fake" <% nvram_match_x("", "ss_enable", "1", "value=1 checked"); %><% nvram_match_x("", "ss_enable", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_enable" id="ss_enable_1" <% nvram_match_x("", "ss_enable", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_enable" id="ss_enable_0" <% nvram_match_x("", "ss_enable", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th width="50%"><#InetControl#></th>
														<td>
															<input type="button" id="btn_reconnect" class="btn btn-info" value="<#Connect#>" onclick="submitInternet('Reconnect');">
														</td>
													</tr>
													<tr>
														<th width="50%"><#Client#> <#running_status#>：</th>
														<td id="ss_status"></td>
													</tr>
													<tr id="row_pdnsd_run">
														<th width="50%"><#Dns2tcp#> <#running_status#>：</th>
														<td id="dns2tcp_status"></td>
													</tr>
													<tr id="row_dnsproxy_run">
														<th width="50%">dnsproxy <#running_status#>：</th>
														<td id="dnsproxy_status"></td>
													</tr>
													<tr>
														<th width="50%">Google 访问状态：</th>
														<td id="gg_status"></td>
													</tr>
													<tr>
														<th width="50%">国内IP：</th>
														<td id="domestic_ip"></td>
													</tr>
													<tr>
														<th width="50%">国外IP：</th>
														<td id="foreign_ip"></td>
													</tr>
													<tr>
														<th width="50%">主服务器：</th>
														<td>
															<select name="global_server" id="nodeList" style="width: 200px;" onchange="showsdlinkList()">
																<option value="nil">停用</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">游戏UDP中继服务器：</th>
														<td>
															<select name="udp_relay_server" id="u_nodeList" style="width: 200px;" onchange="showsudlinkList()">
																<option value="nil">停用</option>
																<option value="same">与主服务相同</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">多线程并发转发：</th>
														<td>
															<select name="ss_threads" class="input" style="width: 200px;">
																<option value="0">自动（CPU线程数）</option>
																<option value="1">单线程</option>
																<option value="2">2 线程</option>
																<option value="4">4 线程</option>
																<option value="8">8 线程</option>
																<option value="16">16 线程</option>
																<option value="24">24 线程</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">运行模式：</th>
														<td>
															<select name="ss_run_mode" id="ss_run_mode" class="input" style="width: 200px;">
																<option value="gfw" <% nvram_match_x("","ss_run_mode", "gfw","selected"); %>>gfw列表模式</option>
																<option value="router" <% nvram_match_x("","ss_run_mode", "router","selected"); %>>绕过大陆IP模式</option>
																<option value="all" <% nvram_match_x("","ss_run_mode", "all","selected"); %>>全局模式</option>
																<option value="oversea" <% nvram_match_x("","ss_run_mode", "oversea","selected"); %>>海外用户回国模式</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">需要代理的端口：</th>
														<td>
															<select name="s_dports" class="input" style="width: 200px;">
																<option value="0" <% nvram_match_x("","s_dports", "0","selected"); %>>所有端口（默认）</option>
																<option value="1" <% nvram_match_x("","s_dports", "1","selected"); %>>仅常用端口(不走P2P流量到代理)</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">内网IP控制：</th>
														<td>
															<select name="lan_con" class="input" style="width: 200px;">
																<option value="0">全部走代理</option>
																<option value="1">指定IP走代理</option>
															</select>
															<span class="help-block" style="margin: 4px 0 0 0;">
																「指定IP走代理」的名单在「<b>规则管理</b>」标签页的「<b>强制走SS代理的LAN IP</b>」里填，一行一个 IP 或网段。<br>
																「全部走代理」时，「规则管理」里的「<b>不走SS代理的LAN IP</b>」是例外名单，写进去的 IP 不走代理。
															</span>
														</td>
													</tr>
													<tr id="row_pdnsd_enable">
														<th width="50%">DNS代理解析方式：(推荐dnsproxy)</th>
														<td>
															<select name="pdnsd_enable" id="pdnsd_enable" class="input" style="width: 200px;" onchange="switch_dns()">
																<option value="0">使用dnsproxy查询</option>
																<option value="1">使用dns2tcp查询</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">加载chinadns-ng：(仅绕过模式生效)</th>
														<td>
															<div class="main_itoggle">
																<div id="ss_chdns_on_of">
																	<input type="checkbox" id="ss_chdns_fake" <% nvram_match_x("", "ss_chdns", "1", "value=1 checked"); %><% nvram_match_x("", "ss_chdns", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_chdns" id="ss_chdns_1" <% nvram_match_x("", "ss_chdns", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_chdns" id="ss_chdns_0" <% nvram_match_x("", "ss_chdns", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr id="row_china_dns" style="display:none;">
														<th width="50%">国内DNS：(仅chinadns-ng生效)</th>
														<td>
															<select name="china_dns" class="input" style="width: 200px;">
																<option value="1.2.4.8#53">CNNIC DNS (1.2.4.8)</option>
																<option value="223.5.5.5#53">Ali DNS (223.5.5.5)</option>
																<option value="117.50.11.11#53">One DNS (117.50.11.11)</option>
																<option value="180.76.76.76#53">Baidu DNS (180.76.76.76)</option>
																<option value="119.29.29.29#53">DNSPOD DNS (119.29.29.29)</option>
																<option value="114.114.114.114#53">114 DNS (114.114.114.114)</option>
															</select>
														</td>
													</tr>
													<tr id="row_tunnel_forward" style="display:none;">
														<th width="50%">国外DNS：</th>
														<td>
															<select name="tunnel_forward" class="input" style="width: 200px;">
																<option value="1.1.1.1#53">Cloudflare DNS (1.1.1.1)</option>
																<option value="1.0.0.1#53">Cloudflare DNS (1.0.0.1)</option>
																<option value="4.2.2.1#53">Level 3 Public DNS (4.2.2.1)</option>
																<option value="4.2.2.2#53">Level 3 Public DNS (4.2.2.2)</option>
																<option value="4.2.2.3#53">Level 3 Public DNS (4.2.2.3)</option>
																<option value="4.2.2.4#53">Level 3 Public DNS (4.2.2.4)</option>
																<option value="8.8.4.4#53">Google Public DNS (8.8.4.4)</option>
																<option value="8.8.8.8#53">Google Public DNS (8.8.8.8)</option>
																<option value="208.67.222.222#53">OpenDNS (208.67.222.222)</option>
																<option value="208.67.220.220#53">OpenDNS (208.67.220.220)</option>
																<option value="209.244.0.3#53">Level 3 Public DNS (209.244.0.3)</option>
																<option value="209.244.0.4#53">Level 3 Public DNS (209.244.0.4)</option>
																<option value="114.114.114.114#53">Oversea Mode DNS(114.114.114.114)</option>
																<option value="114.114.115.115#53">Oversea Mode DNS(114.114.115.115)</option>
															</select>
														</td>
													</tr>
													<!--
													<tr id="row_ssp_dns_ip" style="display:none;">
														<th width="50%">SmartDNS加载方式:</th>
														<td>
															<select name="ssp_dns_ip" class="input" style="width: 200px">
																<input type="radio" value="2" name="ssp_dns_ip" id="ssp_dns_ip_2" <% nvram_match_x("", "ssp_dns_ip", "2", "checked"); %>>自动配置
																<input type="radio" value="1" name="ssp_dns_ip" id="ssp_dns_ip_1" <% nvram_match_x("", "ssp_dns_ip", "1", "checked"); %>>手动配置
															</select>
														</td>
													</tr>-->
												</table>
												<table class="table">
													<tr>
														<td style="border: 0 none; padding: 0px;">
															<center><input name="button" type="button" class="btn btn-primary" style="width: 200px" onclick="applyRule();" value="<#CTL_apply#>" /></center>
														</td>
													</tr>
												</table>
											</div>
											<!--节点列表-->
											<div id="wnd_ss_add">
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<div class="alert alert-info" style="margin: 10px;"> 添加或修改订阅地址后，请先点下方的 “保存并应用”（等同于右上角的 “应用”）保存，再点 “手动更新订阅” 拉取节点。</div>
													<tr>
														<td colspan="3">
															<i class="icon-hand-right"></i> <a href="javascript:spoiler_toggle('script7')"><span>点击输入节点订阅地址：(一行一个地址)</span></a>
															<div id="script7" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_dlink.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_dlink.sh",""); %></textarea>
															</div>
																<div style="margin-top: 6px;">
																	<input type="button" class="btn btn-primary" value="保存并应用" onclick="applyRule();">
																	<span class="help-block" style="margin: 4px 0 0 0;">
																		保存本页全部设置（含上面的订阅地址）并重启科学上网服务，等同于右上角的「应用」按钮。<br>
																		改完订阅地址先点这里保存，再点「手动更新订阅」拉取节点。
																	</span>
																</div>
														</td>
													</tr>
													<tr id="ss_schedule_enable_tr">
														<th width="50%" style="border-top: 0 none;"><#ss_schedule_enable_tr#></th>
														<td>
															<div class="main_itoggle">
																<div id="ss_schedule_enable_on_of">
																	<input type="checkbox" id="ss_schedule_enable_fake" <% nvram_match_x("", "ss_schedule_enable", "1", "value=1 checked"); %><% nvram_match_x("", "ss_schedule_enable", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" name="ss_schedule_enable_x" id="ss_schedule_enable_1" class="input" value="1" <% nvram_match_x("", "ss_schedule_enable", "1", "checked"); %>/><#checkbox_Yes#>
																<input type="radio" name="ss_schedule_enable_x" id="ss_schedule_enable_0" class="input" value="0" <% nvram_match_x("", "ss_schedule_enable", "0", "checked"); %>/><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr id="ss_schedule_date_tr">
														<th width="50%"><#ss_schedule_date_tr#></th>
														<td>
															<div class="controls">
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Mon" onChange="check_Timefield_checkbox();"/><#DAY_Mon#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Tue" onChange="check_Timefield_checkbox();"/><#DAY_Tue#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Wed" onChange="check_Timefield_checkbox();"/><#DAY_Wed#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Thu" onChange="check_Timefield_checkbox();"/><#DAY_Thu#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Fri" onChange="check_Timefield_checkbox();"/><#DAY_Fri#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Sat" onChange="check_Timefield_checkbox();"/><#DAY_Sat#></label>
																<label class="checkbox inline"><input type="checkbox" class="input" name="ss_date_x_Sun" onChange="check_Timefield_checkbox();"/><#DAY_Sun#></label>
															</div>
														</td>
													</tr>
													<tr id="ss_schedule_time_tr">
														<th style="border-top: 0 none;"><#ss_schedule_time_tr#></th>
														<td>
															<input type="text" maxlength="2" style="width: 20px;" size="2" name="ss_time_x_hour" onKeyPress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 0);" autocorrect="off" autocapitalize="off"><#Hour#>:
															<input type="text" maxlength="2" style="width: 20px;" size="2" name="ss_time_x_min" onKeyPress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off"><#Minute#>
														</td>
													</tr>
													<tr><th width="50%"><#Keyword_filter#></th>
														<td>
															<input type="input" name="ss_keyword" id="ss_keyword" value="<% nvram_get_x("", "ss_keyword"); %>" >
															<br> 命中关键字的节点将被丢弃，多个关键字用 / 分隔
														</td>
													</tr>
												</table>
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<th colspan="2">
															<select name="ss_list_mode" id="ss_list_mode" class="input" style="width: 100px;" onchange="ss_apply_filter();">
																														<option value="a">全部节点</option>
																														<option value="d">自定义节点</option>
																														<option value="c">订阅节点</option>
															</select>
															<input type="button" id="btn_add_link" class="btn btn-info" value="添加/导入">
															<input type="button" id="btn_update_link" class="btn btn-info" value="手动更新订阅" onclick="dlink();">
															<input type="button" id="btn_ping_link" class="btn btn-info" value="ping所选">
															<input type="button" id="btn_aping_link" class="btn btn-info" value="ping全部">
															<input type="button" id="btn_urltest_link" class="btn btn-info" value="URL测试">
															<input type="button" id="btn_del_link" class="btn btn-danger" value="删除节点">
															<input type="button" id="btn_rest_link" class="btn btn-danger" value="清空节点" onclick="ddlink();">
															<input type="button" id="btn_ctime" style="display:none;" class="btn btn-good" value="正在运行脚本:0s" onclick="">
															<!-- F2：URL 测试的探测地址。选中值存 dbus 键 urltest_url，urltest.sh 自己 dbus get 它。 -->
															<div style="margin-top: 6px;">
																														<span>URL 测试探测地址：</span>
																														<select id="urltest_url_sel" class="input" style="width: 300px;" onchange="urltest_url_change();"></select>
																														<input type="text" id="urltest_url_custom" class="input" style="width: 300px; display: none;" maxlength="200" placeholder="http://example.com/generate_204" onchange="urltest_url_save();">
																														<span id="urltest_status_txt" style="margin-left: 8px; color: #666;"></span>
															</div>
														</th>
													</tr>
												</table>
												<table id="table99"></table>
												<div id="vpnc_settings" class="contentM_qis" style="z-index:9999; box-shadow: 3px 3px 10px #000;margin-top: 0px;">
													<table width="100%" cellpadding="4" cellspacing="0" class="table" id="sslist">
														<tr>
															<th id="ss_setting_title" colspan="2" style="background-color: #E3E3E3;">添加/删除/编辑节点</th>
														</tr>
														<tr>
															<th width="50%">导入节点信息：</th>
															<td>
																<input type="button" class="btn btn-primary" value="点击输入节点URL" onclick="return import_ssr_url(this, '<%=self.option%>', '<%=self.value%>')" /><span id="<%=self.option%>-status"></span>
															</td>
														</tr>
														<tr>
															<th width="50%">服务器节点类型：</th>
															<td>
																<select name="ssp_type" id="ssp_type" class="input" style="width: 200px;" onchange="switch_ss_type()">
																	<option value="ss">SS</option>
																	<option value="ssr">SSR</option>
																	<option value="trojan">Trojan</option>
																	<option value="v2ray">Vmess</option>
																	<option value="xray">VLess</option>
																	<option value="socks5">SOCKS5</option>
																</select>
															</td>
														</tr>
														<tr>
															<th width="50%">别名：（可选）</th>
															<td>
																<input type="text" class="input" size="15" name="ssp_name" id="ssp_name" style="width: 200px" value="" />
															</td>
														</tr>
														<tr>
															<th width="50%">服务器IP地址：</th>
															<td>
																<input type="text" class="input" size="15" name="ssp_server" id="ssp_server" style="width: 200px" value="" />
															</td>
														</tr>
														<tr>
															<th width="50%">服务器端口：</th>
															<td>
																<input type="text" class="input" size="15" name="ssp_prot" id="ssp_prot" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_ss_password" style="display:none;">
															<th width="50%">服务器密码：</th>
															<td>
																<input type="password" class="input" size="32" name="ss_password" id="ss_password" style="width: 200px" value="" />
																<button style="margin-left: -5px;" class="btn" type="button" onclick="passwordShowHide('ss_password')"><i class="icon-eye-close"></i></button>
															</td>
														</tr>
														<tr id="row_ss_method" style="display:none;">
															<th width="50%">加密方式：</th>
															<td>
																<select name="ss_method" id="ss_method" class="input" style="width: 200px;">
																	<option value="none">none (ssr only)</option>
																	<option value="rc4">rc4</option>
																	<option value="rc4-md5">rc4-md5</option>
																	<option value="aes-128-cfb">aes-128-cfb</option>
																	<option value="aes-192-cfb">aes-192-cfb</option>
																	<option value="aes-256-cfb">aes-256-cfb</option>
																	<option value="aes-128-ctr">aes-128-ctr</option>
																	<option value="aes-192-ctr">aes-192-ctr</option>
																	<option value="aes-256-ctr">aes-256-ctr</option>
																	<option value="camellia-128-cfb">camellia-128-cfb</option>
																	<option value="camellia-192-cfb">camellia-192-cfb</option>
																	<option value="camellia-256-cfb">camellia-256-cfb</option>
																	<option value="bf-cfb">bf-cfb</option>
																	<option value="salsa20">salsa20</option>
																	<option value="chacha20">chacha20</option>
																	<option value="chacha20-ietf">chacha20-ietf</option>
																	<option value="aes-128-gcm">aes-128-gcm (ss only)</option>
																	<option value="aes-192-gcm">aes-192-gcm (ss only)</option>
																	<option value="aes-256-gcm">aes-256-gcm (ss only)</option>
																	<option value="chacha20-ietf-poly1305">chacha20-ietf-poly1305 (ss only)</option>
																	<option value="xchacha20-ietf-poly1305">xchacha20-ietf-poly1305 (ss only)</option>
																</select>
															</td>
														</tr>
														<tr id="row_ss_protocol" style="display:none;">
															<th width="50%">协议：</th>
															<td>
																<select name="ss_protocol" id="ss_protocol" class="input" style="width: 200px;">
																	<option value="origin">origin</option>
																	<option value="auth_sha1">auth_sha1</option>
																	<option value="auth_sha1_v2">auth_sha1_v2</option>
																	<option value="auth_sha1_v4">auth_sha1_v4</option>
																	<option value="auth_aes128_md5">auth_aes128_md5</option>
																	<option value="auth_aes128_sha1">auth_aes128_sha1</option>
																	<option value="auth_chain_a">auth_chain_a</option>
																	<option value="auth_chain_b">auth_chain_b</option>
																</select>
															</td>
														</tr>
														<tr id="row_ss_plugin" style="display:none;">
															<th width="50%">插件：</th>
															<td>
																<input type="text" class="input" size="15" name="ss_plugin" id="ss_plugin" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_ss_plugin_opts" style="display:none;">
															<th width="50%">插件参数：</th>
															<td>
																<input type="text" class="input" size="15" name="ss_plugin_opts" id="ss_plugin_opts" style="width: 200px" value="" />
															</td>
														</tr>
														<!--SS参数结束--SSR参数开始-->
														<tr id="row_ss_protocol_para" style="display:none;">
															<th width="50%">传输协议参数：（可选）</th>
															<td>
																<input type="text" class="input" size="15" name="ss_protocol_param" id="ss_protocol_param" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_ss_obfs" style="display:none;">
															<th width="50%">混淆：</th>
															<td>
																<select name="ss_obfs" id="ss_obfs" class="input" style="width: 200px;">
																	<option value="plain">plain</option>
																	<option value="http_simple">http_simple</option>
																	<option value="http_post">http_post</option>
																	<option value="tls1.2_ticket_auth">tls1.2_ticket_auth</option>
																	<option value="tls1.tls1.2_ticket_fastauth">tls1.tls1.2_ticket_fastauth</option>
																</select>
															</td>
														</tr>
														<tr id="row_ss_obfs_para" style="display:none;">
															<th width="50%">混淆参数：（可选）</th>
															<td>
																<input type="text" class="input" size="15" name="ss_obfs_param" id="ss_obfs_param" style="width: 200px" value="" />
															</td>
														</tr>
														<!--SSR参数结束-->
														<tr id="row_s5_enable" style="display:none;">
															<th width="50%">启用用户名/密码认证：</th>
															<td>
																<input type="checkbox" name="s5_aut" id="s5_aut" value="0" >
															</td>
														</tr>
														<tr id="row_s5_username" style="display:none;">
															<th width="50%">用户名：</th>
															<td>
																<input type="password" class="input" size="32" name="s5_username" id="s5_username" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_s5_password" style="display:none;">
															<th width="50%">密码：</th>
															<td>
																<input type="password" class="input" size="32" name="s5_password" id="s5_password" style="width: 200px" value="" />
																<button style="margin-left: -5px;" class="btn" type="button" onclick="passwordShowHide('s5_password')"><i class="icon-eye-close"></i></button>
															</td>
														</tr>
														<!--V2RAY-->
														<tr id="row_v2_aid" style="display:none;">
															<th width="50%">AlterId(Level)</th>
															<td>
																<input type="text" class="input" size="15" name="v2_alter_id" id="v2_alter_id" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_v2_vid" style="display:none;">
															<th width="50%">VmessId/VlessId (UUID)</th>
															<td>
																<input type="text" class="input" size="15" name="v2_vmess_id" id="v2_vmess_id" style="width: 200px" value="<% nvram_get_x("","v2_vid_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_security" style="display:none;">
															<th width="50%">加密：</th>
															<td>
																<select name="v2_security" id="v2_security" class="input" style="width: 200px;">
																	<option value="auto">AUTO</option>
																	<option value="none">NONE</option>
																	<option value="aes-128-gcm">AES-128-GCM</option>
																	<option value="zero">ZERO</option>
																	<option value="chacha20-poly1305">CHACHA20-POLY1305</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_net" style="display:none;">
															<th width="50%">传输方式：</th>
															<td>
																<select name="v2_transport" id="v2_transport" class="input" style="width: 200px;" onchange="switch_v2_type()">
																	<option value="tcp">TCP</option>
																	<option value="kcp">mKCP</option>
																	<option value="ws">WebSocket</option>
																	<option value="grpc">GRPC</option>
																	<option value="h2">HTTP/2</option>
																	<option value="quic">QUIC</option>
																	<option value="httpupgrade">HTTPUpgrade</option>
																	<option value="splithttp">SplitHTTP</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_type" style="display:none;">
															<th width="50%">伪装类型：</th>
															<td>
																<select id="v2_tcp_guise" name="v2_tcp_guise" class="input" style="width: 200px;display:none;">
																	<option value="none">未配置</option>
																	<option value="http">HTTP</option>
																</select>
																<select id="v2_kcp_guise" name="v2_kcp_guise" class="input" style="width: 200px;display:none;">
																	<option value="none">未配置</option>
																	<option value="srtp">VideoCall (SRTP)</option>
																	<option value="utp">BitTorrent (uTP)</option>
																	<option value="wechat-video">WechatVideo</option>
																	<option value="dtls">DTLS 1.2</option>
																	<option value="wireguard">WireGuard</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_http_host" style="display:none;">
															<th width="50%">HTTP Host</th>
															<td>
																<input type="text" class="input" size="15" name="v2_http_host" id="v2_http_host" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_v2_http_path" style="display:none;">
															<th width="50%">HTTP Path</th>
															<td>
																<input type="text" class="input" size="15" name="v2_http_path" id="v2_http_path" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_mtu" style="display:none;">
															<th width="50%">MTU</th>
															<td>
																<input type="text" class="input" size="15" name="v2_mtu" id="v2_mtu" style="width: 200px" value="1350" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_tti" style="display:none;">
															<th width="50%">TTI</th>
															<td>
																<input type="text" class="input" size="15" name="v2_tti" id="v2_tti" style="width: 200px" value="50" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_uplink" style="display:none;">
															<th width="50%">Uplink Capacity</th>
															<td>
																<input type="text" class="input" size="15" name="v2_uplink_capacity" id="v2_uplink_capacity" style="width: 200px" value="5" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_downlink" style="display:none;">
															<th width="50%">Downlink Capacity</th>
															<td>
																<input type="text" class="input" size="15" name="v2_downlink_capacity" id="v2_downlink_capacity" style="width: 200px" value="20" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_readbu" style="display:none;">
															<th width="50%">Read Buffer Size</th>
															<td>
																<input type="text" class="input" size="15" name="v2_read_buffer_size" id="v2_read_buffer_size" style="width: 200px" value="2" />
															</td>
														</tr>
														<tr id="row_v2_mkcp_writebu" style="display:none;">
															<th width="50%">Write Buffer Size</th>
															<td>
																<input type="text" class="input" size="15" name="v2_write_buffer_size" id="v2_write_buffer_size" style="width: 200px" value="2" />
															</td>
														</tr>
														<tr id="row_v2_webs_host" style="display:none;">
															<th width="50%">WebSocket Host</th>
															<td>
																<input type="text" class="input" size="15" name="v2_ws_host" id="v2_ws_host" style="width: 200px" value="<% nvram_get_x("","v2_webs_host_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_webs_path" style="display:none;">
															<th width="50%">WebSocket Path</th>
															<td>
																<input type="text" class="input" size="15" name="v2_ws_path" id="v2_ws_path" style="width: 200px" value="<% nvram_get_x("","v2_webs_path_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_grpc_path" style="display:none;">
															<th width="50%">GRPC Path (serviceName)</th>
															<td>
																<input type="text" class="input" size="15" name="v2_grpc_path" id="v2_grpc_path" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_v2_http2_host" style="display:none;">
															<th width="50%">HTTP/2 Host</th>
															<td>
																<input type="text" class="input" size="15" name="v2_h2_host" id="v2_h2_host" style="width: 200px"value="<% nvram_get_x("","v2_http2_host_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_http2_path" style="display:none;">
															<th width="50%">HTTP/2 Path</th>
															<td>
																<input type="text" class="input" size="15" name="v2_h2_path" id="v2_h2_path" style="width: 200px" value="<% nvram_get_x("","v2_http2_path_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_quic_security" style="display:none;">
															<th width="50%">QUIC Security</th>
															<td>
																<select name="v2_quic_security" id="v2_quic_security" class="input" style="width: 200px;">
																	<option value="none">未配置</option>
																	<option value="aes-128-gcm">aes-128-gcm</option>
																	<option value="chacha20-ietf-poly1305">chacha20-ietf-poly1305</option>
																</select>
															</td>
														</tr>
														<tr id="row_quic_key" style="display:none;">
															<th width="50%">QUIC Key</th>
															<td>
																<input type="text" class="input" size="15" name="v2_quic_key" id="v2_quic_key" style="width: 200px" value="" />
															</td>
														</tr>
														<tr id="row_quic_header" style="display:none;">
															<th width="50%">QUIC Header</th>
															<td>
																<select name="v2_quic_guise" id="v2_quic_guise" class="input" style="width: 200px;">
																	<option value="none">未配置</option>
																	<option value="srtp">VideoCall (SRTP)</option>
																	<option value="utp">BitTorrent (uTP)</option>
																	<option value="wechat-video">WechatVideo</option>
																	<option value="dtls">DTLS 1.2</option>
																	<option value="wireguard">WireGuard</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_httpupgrade_host" style="display:none;">
															<th width="50%">HTTPUpgrade Host</th>
															<td>
																<input type="text" class="input" size="15" name="v2_httpupgrade_host" id="v2_httpupgrade_host" style="width: 200px" value="<% nvram_get_x("","v2_httpupgrade_host_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_httpupgrade_path" style="display:none;">
															<th width="50%">HTTPUpgrade Path</th>
															<td>
																<input type="text" class="input" size="15" name="v2_httpupgrade_path" id="v2_httpupgrade_path" style="width: 200px" value="<% nvram_get_x("","v2_httpupgrade_path_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_splithttp_host" style="display:none;">
															<th width="50%">SplitHTTP Host</th>
															<td>
																<input type="text" class="input" size="15" name="v2_splithttp_host" id="v2_splithttp_host" style="width: 200px" value="<% nvram_get_x("","v2_splithttp_host_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_v2_splithttp_path" style="display:none;">
															<th width="50%">SplitHTTP Path</th>
															<td>
																<input type="text" class="input" size="15" name="v2_splithttp_path" id="v2_splithttp_path" style="width: 200px" value="<% nvram_get_x("","v2_splithttp_path_x_0"); %>" />
															</td>
														</tr>
														<tr id="row_ssp_insecure" style="display:none;">
															<th width="50%">allowInsecure</th>
															<td>
																<input type="checkbox" name="ssp_insecure" id="ssp_insecure" >
															</td>
														</tr>
														<tr id="row_v2_tls" style="display:none;">
															<th width="50%">TLS/Reality</th>
															<td>
																<select name="v2_tls" id="v2_tls" class="input" style="width: 200px;">
																	<option value="0">未配置</option>
																	<option value="1">tls</option>
																	<option value="2">Reality</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_flow" style="display:none;">
															<th width="50%">Reality flow</th>
															<td>
																<select name="v2_flow" id="v2_flow" class="input" style="width: 200px;">
																	<option value="0">未配置</option>
																	<option value="1">xtls-rprx-vision</option>
																	<option value="2">xtls-rprx-vision-udp443</option>
																</select>
															</td>
														</tr>
														<tr id="row_tj_tls_host" style="display:none;">
															<th width="50%">TLS Host</th>
															<td>
																<input type="text" class="input" size="15" name="ssp_tls_host" id="ssp_tls_host" style="width: 200px" value="">
															</td>
														</tr>
														<tr id="row_v2_reality_pbk" style="display:none;">
															<th width="50%">Reality 公钥</th>
															<td>
																<input type="text" class="input" size="15" name="v2_reality_pbk" id="v2_reality_pbk" style="width: 200px" value="">
																<div style="font-size:12px; color:#999; margin-top:2px;">
																	以下四项只在「TLS/Reality」选 <b>Reality</b> 时才需要填。<br>
																	公钥（publicKey）和 Short ID 由服务端提供。<br>
																	<b>少填任何一项 xray 都会拒绝启动</b>，表现是整个科学上网不通，排查时很难指向这里。<br>
																	从分享链接导入时会自动带上，手填的话照着服务端抄。
																</div>
															</td>
														</tr>
														<tr id="row_v2_reality_sid" style="display:none;">
															<th width="50%">Reality Short ID</th>
															<td>
																<input type="text" class="input" size="15" name="v2_reality_sid" id="v2_reality_sid" style="width: 200px" value="">
															</td>
														</tr>
														<tr id="row_v2_reality_fp" style="display:none;">
															<th width="50%">Reality 指纹</th>
															<td>
																<select name="v2_reality_fp" id="v2_reality_fp" class="input" style="width: 200px;">
																	<option value="chrome">chrome</option>
																	<option value="firefox">firefox</option>
																	<option value="safari">safari</option>
																	<option value="ios">ios</option>
																	<option value="android">android</option>
																	<option value="edge">edge</option>
																	<option value="360">360</option>
																	<option value="qq">qq</option>
																	<option value="random">random</option>
																	<option value="randomized">randomized</option>
																</select>
															</td>
														</tr>
														<tr id="row_v2_reality_spx" style="display:none;">
															<th width="50%">Reality SpiderX</th>
															<td>
																<input type="text" class="input" size="15" name="v2_reality_spx" id="v2_reality_spx" style="width: 200px" value="" placeholder="/">
																<div style="font-size:12px; color:#999; margin-top:2px;">留空按 / 处理。</div>
															</td>
														</tr>
														<tr id="row_v2_mux" style="display:none;">
															<th width="50%">MUX</th>
															<td>
																<input type="checkbox" name="v2_mux" id="v2_mux">
															</td>
														</tr>
														<!--
														<tr>
															<th width="50%">自动切换类型：</th>
															<td>
																<div class="main_itoggle">
																<div id="switch_enable_x_0_on_of">
																	<input type="checkbox" id="switch_enable_x_0_fake" <% nvram_match_x("", "switch_enable_x_0", "1", "value=1 checked"); %><% nvram_match_x("", "switch_enable_x_0", "0", "value=0"); %>>
																</div>
																</div>
																<div style="position: absolute; margin-left: -10000px;">
																	<input type="radio" value="1" name="switch_enable_x_0" id="switch_enable_x_0_1" <% nvram_match_x("", "switch_enable_x_0", "1", "checked"); %>><#checkbox_Yes#>
																	<input type="radio" value="0" name="switch_enable_x_0" id="switch_enable_x_0_0" <% nvram_match_x("", "switch_enable_x_0", "0", "checked"); %>><#checkbox_No#>
																</div>
															</td>
														</tr>-->
														<tr>
															<td>
																<center><input name="ManualRULESList2" id="ManualRULESList2" type="button" class="btn btn-primary" onclick="add_ss();" style="width: 219px" value="保存节点" /></center>
															</td>
															<td>
																<center><input name="button" type="button" class="btn btn-primary" id="close_add" style="width: 219px" value="取消" /></center>
															</td>
														</tr>
													</table>
												</div>
											</div>
											<div id="wnd_ss_ssl" style="display:none">
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<th colspan="2" style="background-color: #E3E3E3;">进程资源限制</th>
													</tr>
													<tr>
														<th width="50%">启用进程资源限制：</th>
														<td>
															<div class="main_itoggle">
																<div id="ss_cgroups_on_of">
																	<input type="checkbox" id="ss_cgroups_fake" <% nvram_match_x("", "ss_cgroups", "1", "value=1 checked"); %><% nvram_match_x("", "ss_cgroups", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_cgroups" id="ss_cgroups_1"<% nvram_match_x("", "ss_cgroups", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_cgroups" id="ss_cgroups_0"<% nvram_match_x("", "ss_cgroups", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th width="50%">CPU 限制：</th>
														<td>
															<input type="text" class="input" size="15" name="ss_cgoups_cpu_s" style="width: 200px" value="<% nvram_get_x("","ss_cgoups_cpu_s"); %>" />
														</td>
													</tr>
													<tr>
														<th width="50%">内存限制：</th>
														<td>
															<input type="text" class="input" size="15" name="ss_cgoups_mem_s" style="width: 200px" value="<% nvram_get_x("","ss_cgoups_mem_s"); %>" />
														</td>
													</tr>
													<tr>
														<th width="50%">进程守护：</th>
														<td>
															<div class="main_itoggle">
																<div id="ss_watchcat_on_of">
																	<input type="checkbox" id="ss_watchcat_fake"<% nvram_match_x("", "ss_watchcat", "1", "value=1 checked"); %><% nvram_match_x("", "ss_watchcat", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_watchcat" id="ss_watchcat_1"<% nvram_match_x("", "ss_watchcat", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_watchcat" id="ss_watchcat_0"<% nvram_match_x("", "ss_watchcat", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th colspan="2" style="background-color: #E3E3E3;">SOCKS5代理</th>
													</tr>
													<tr>
														<th width="50%">服务器：</th>
														<td>
															<select name="socks5_enable" id="s5_nodeList" style="width: 200px;" onchange="shows5dlinkList()">
																<option value="nil">停用</option>
																<option value="same">与主服务相同</option>
															</select>
														</td>
													</tr>
													<tr>
														<th width="50%">本地端口：</th>
														<td>
															<input type="text" class="input" size="15" name="socks5_port" style="width: 200px" value="<% nvram_get_x("", "socks5_port"); %>">
														</td>
													</tr>
												</table>
												<table class="table">
													<tr>
														<td style="border: 0 none; padding: 0px;">
															<center><input name="button" type="button" class="btn btn-primary" style="width: 200px" onclick="applyRule();" value="<#CTL_apply#>" /></center>
														</td>
													</tr>
												</table>
											</div>
											<div id="wnd_ss_cli" style="display:none">
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<th width="50%"><#Ad_filter#></th>
														<td>
															<div class="main_itoggle">
																<div id="ss_adblock_on_of">
																	<input type="checkbox" id="ss_adblock_fake"<% nvram_match_x("", "ss_adblock", "1", "value=1 checked"); %><% nvram_match_x("", "ss_adblock", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_adblock" id="ss_adblock_1"<% nvram_match_x("", "ss_adblock", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_adblock" id="ss_adblock_0"<% nvram_match_x("", "ss_adblock", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th width="50%"><#Filter_file#></th>
														<td>
															<input type="text" class="input" size="15" name="ss_adblock_url" style="width: 280px"  value="<% nvram_get_x("","ss_adblock_url"); %>" />
														</td>
													</tr>
													<tr>
														<th width="50%"><#Filter_file#></th>
														<td style="border-top: 0 none;" colspan="2">
															<input type="button" id="btn_connect_5" class="btn btn-info" value="<#menu5_17_2#>" onclick="submitInternet('Update_adblock');">
														</td>
													</tr>
													<tr>
														<th width="50%"><#Chnroute#> <#Address#></th>
														<td>
															<input type="text" class="input" size="15" name="ss_chnroute_url" style="width: 280px"  value="<% nvram_get_x("","ss_chnroute_url"); %>" />
														</td>
													</tr>
													<tr>
														<th width="50%"><#Chnroute#>&nbsp;&nbsp;&nbsp;&nbsp;<span class="label label-info" style="padding: 5px 5px 5px 5px;" id="chnroute_count"></span></th>
														<td style="border-top: 0 none;" colspan="2">
															<input type="button" id="btn_connect_3" class="btn btn-info" value="<#menu5_17_2#>" onclick="submitInternet('Update_chnroute');">
														</td>
													</tr>
													<tr>
														<th width="50%"><#menu5_16_19#></th>
														<td>
															<div class="main_itoggle">
																<div id="ss_update_chnroute_on_of">
																	<input type="checkbox" id="ss_update_chnroute_fake"<% nvram_match_x("", "ss_update_chnroute", "1", "value=1 checked"); %><% nvram_match_x("", "ss_update_chnroute", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_update_chnroute" id="ss_update_chnroute_1"<% nvram_match_x("", "ss_update_chnroute", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_update_chnroute" id="ss_update_chnroute_0"<% nvram_match_x("", "ss_update_chnroute", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th width="50%"><#Gfwlist#> <#Address#></th>
														<td>
															<input type="text" class="input" size="15" name="ss_gfwlist_url" style="width: 280px"  value="<% nvram_get_x("","ss_gfwlist_url"); %>" />
														</td>
													</tr>
													<tr>
														<th width="50%"><#Gfwlist#>&nbsp;&nbsp;&nbsp;&nbsp;<span class="label label-info" style="padding: 5px 5px 5px 5px;" id="gfwlist_count"></span></th>
														<td style="border-top: 0 none;" colspan="2">
															<input type="button" id="btn_connect_4" class="btn btn-info" value="<#menu5_17_2#>" onclick="submitInternet('Update_gfwlist');">
														</td>
													</tr>
													<tr>
														<th width="50%"><#menu5_16_19#></th>
														<td>
															<div class="main_itoggle">
																<div id="ss_update_gfwlist_on_of">
																	<input type="checkbox" id="ss_update_gfwlist_fake"<% nvram_match_x("", "ss_update_gfwlist", "1", "value=1 checked"); %><% nvram_match_x("", "ss_update_gfwlist", "0", "value=0"); %>>
																</div>
															</div>
															<div style="position: absolute; margin-left: -10000px;">
																<input type="radio" value="1" name="ss_update_gfwlist" id="ss_update_gfwlist_1"<% nvram_match_x("", "ss_update_gfwlist", "1", "checked"); %>><#checkbox_Yes#>
																<input type="radio" value="0" name="ss_update_gfwlist" id="ss_update_gfwlist_0"<% nvram_match_x("", "ss_update_gfwlist", "0", "checked"); %>><#checkbox_No#>
															</div>
														</td>
													</tr>
													<tr>
														<th colspan="2" style="background-color: #E3E3E3;">游戏模式客户端UDP所有端口,TCP跟随主服务器端口模式,强制走绕过大陆模式</th>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script8')"><i class="icon-chevron-right"></i> <span>游戏模式LAN IP:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script8" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_lan_gmip.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_lan_gmip.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
													<th colspan="3" style="background-color: #E3E3E3;">代理规则名单（一行一个 IP / 网段 / 域名）</th>
												</tr>
												<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script9')"><i class="icon-chevron-right"></i> <span>不走SS代理的LAN IP:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script9" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_lan_ip.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_lan_ip.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script10')"><i class="icon-chevron-right"></i> <span>强制走SS代理的LAN IP:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script10" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_lan_bip.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_lan_bip.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script11')"><i class="icon-chevron-right"></i> <span>不走SS代理的WAN IP:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script11" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_wan_ip.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_wan_ip.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script12')"><i class="icon-chevron-right"></i> <span>强制走SS代理的WAN IP:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script12" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_ip.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_ip.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script13')"><i class="icon-chevron-right"></i> <span>不走SS代理的域名:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script13" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.uss_dom.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.uss_dom.sh",""); %></textarea>
															</div>
														</td>
													</tr>
													<tr>
														<td colspan="3"><a href="javascript:spoiler_toggle('script14')"><i class="icon-chevron-right"></i> <span>强制走SS代理的域名:</span> <small style="color:#999;">（点击收起/展开）</small></a>
															<div id="script14" style="display: none">
																<textarea rows="8" wrap="off" spellcheck="false" maxlength="314571" class="span12" name="scripts.ss_dom.sh" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.ss_dom.sh",""); %></textarea>
															</div>
														</td>
													</tr>
												</table>
												<table class="table">
													<tr>
														<td style="border: 0 none; padding: 0px;">
															<center><input name="button" type="button" class="btn btn-primary" style="width: 200px" onclick="applyRule();" value="<#CTL_apply#>" /></center>
														</td>
													</tr>
												</table>
											</div>
											<div id="wnd_ss_log" style="display:none">
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<td colspan="3" style="border-top: 0 none; padding-bottom: 0px;">
															<textarea rows="21" class="span12" style="height:377px; font-family:'Courier New', Courier, mono; font-size:13px;" readonly="readonly" wrap="off" id="textarea"><% nvram_dump("ssrplus.log",""); %></textarea>
														</td>
													</tr>
													<tr>
														<td>
															<center>
																<input type="button" id="btn_ClearssrplusLog" class="btn btn-info" style="width: 200px" value=<#CTL_clear#> onClick="ClearssrplusLog();">
																<input type="button" class="btn btn-info" style="width: 200px" value=<#CTL_refresh#> onClick="parent.location.reload();">
															</center>
														</td>
													</tr>
												</table>
											</div>
											<div id="wnd_ss_help" style="display:none">
												<table width="100%" cellpadding="4" cellspacing="0" class="table">
													<tr>
														<th colspan="2" style="background-color: #E3E3E3;">chinadns-ng说明:</th>
													</tr>
													<tr>
														<th width="100%">绕过大陆模式启用chinadns会加载CDN域名规则来分流常用网站跑国内DNS,加载gfwlist列表来分流到国外DNS</th>
													</tr>
													<tr>
														<th width="100%">此模式会占用一部分内存资源,内存少的机器请谨慎开启。</th>
													</tr>
													<tr>
														<th colspan="2" style="background-color: #E3E3E3;">进程资源限制说明: 此功能底层使用 <a href="https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/cgroups.html">cgroups</a></th>
													</tr>
													<tr>
														<th width="100%">进程资源限制是为了防止进程占用过多资源导致路由器卡顿或重启,如果你的路由器配置足够,可以适当调高限制值。</th>
													</tr>
													<tr>
														<th width="100%">CPU 限制值为一个大于 2 小于 1024 的整数，表示可以使用的 CPU 百分比，如 512 表示 50%;内存限制值需要带上 M 作为单位,<br/> 如 20M 表示可以使用 20M 内存，超出会被内核 OOM Killer 自动 kill。</th>
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
	<form method="post" name="Shadowsocks_action" action="">
		<input type="hidden" name="connect_action" value="">
	</form>
</body>
</html>
