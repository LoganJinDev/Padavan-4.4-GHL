<!--本页面文件部分内容提取自灯大固件-->
<!DOCTYPE html>
<html>
<head>
    <title>
        <#Web_Title#> - SQM QoS
    </title>
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
<script>
var $j = jQuery.noConflict();
<% sqm_status(); %>
        $j(document).ready(function () {
            init_itoggle('sqm_enable');
            init_itoggle('sqm_active');
            init_itoggle('sqm_down_speed');
            init_itoggle('sqm_up_speed');
            init_itoggle('sqm_debug_log');
            init_itoggle('sqm_log_level');
            init_itoggle('sqm_qdisc');
            init_itoggle('sqm_script');
        });

        function initial() {
            show_banner(2);
            show_menu(5, 19);
            show_footer();
            fill_sqm_status(sqm_status());
            showTab(getHash());
            /* 按设备限速的规则表是 scripts.* 文件，非安全来源（非 LAN/VPN）不允许写，
             * 这里同步把它置灰，免得用户改完才发现保存不了。与 Advanced_frp.asp /
             * Advanced_adbyby.asp 的写法一致 */
            if (!login_safe())
                inputCtrl(document.form['scripts.lanlimit.conf'], 0);
        }

        function textarea_scripts_enabled(v) {
            inputCtrl(document.form['scripts.lanlimit.conf'], v);
        }

        function applyRule() {
        showLoading();
        document.form.action_mode.value = " Restart ";
        document.form.current_page.value = "Advanced_SQM.asp";
        document.form.next_page.value = "";
        document.form.submit();
        }
function fill_sqm_status(status_code){
    var stext = "Unknown";
    if (status_code == 0)
        stext = "<#Running#>";
    else
        stext = "<#Stopped#>";
    $("sqm_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'warning' : 'success') + '">' + stext + '</span>';
}

var arrHashes = ["cfg", "qdisc", "stats"];
function showTab(curHash){
    var obj = $('tab_sqm_'+curHash.slice(1));
    if (obj == null || obj.style.display == 'none')
        curHash = '#cfg';
    for(var i = 0; i < arrHashes.length; i++){
        if(curHash == ('#'+arrHashes[i])){
            $j('#tab_sqm_'+arrHashes[i]).parents('li').addClass('active');
            $j('#wnd_sqm_'+arrHashes[i]).show();
        }else{
            $j('#wnd_sqm_'+arrHashes[i]).hide();
            $j('#tab_sqm_'+arrHashes[i]).parents('li').removeClass('active');
        }
    }
    window.location.hash = curHash;
}

function getHash(){
    var curHash = window.location.hash.toLowerCase();
    for(var i = 0; i < arrHashes.length; i++){
        if(curHash == ('#'+arrHashes[i]))
            return curHash;
    }
    return ('#'+arrHashes[0]);
}

        function done_validating(action) {
            refreshpage();
        }

    </script>
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

        <input type="hidden" name="current_page" value="Advanced_SQM.asp">
        <input type="hidden" name="next_page" value="">
        <input type="hidden" name="next_host" value="">
        <input type="hidden" name="sid_list" value="SqmConf;">
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
                                <h2 class="box_head round_top">SQM QoS - <#menu5_37#></h2>
                                <div class="round_bottom">
                                    <div>
                            <ul class="nav nav-tabs" style="margin-bottom: 10px;">
                                
                                <li class="active">
                                    <a href="Advanced_SQM.asp">SQM QOS</a>
                                </li>
                            </ul>
                        </div>
                                    <div class="row-fluid">
                                        <div id="tabMenu" class="submenuBlock"></div>
                                        <div class="alert alert-info" style="margin: 10px;">
                          注意:SQM会自动设置相应的HWNAT规则，请勿自行调整WAN页面的HWNAT选项造成流控失效</br>
				因7621性能所限,大于500M宽带谨慎开启QOS！</br>
            通过SQM_QoS您可以：对指定接口流量整形,例如自定义5G访客网络。其他接口如5G主接口不会受到影响。</br>
                                       访客网络接口名称视机型而定，5G访客：ra1(或rai1） 2.4G访客rax1(或ra1)。
                                        </div>
                                   </div>

                                        <table width="100%" align="center" cellpadding="4" cellspacing="0" class="table" style="margin-top: 10px;">
                                            <tr style="display:none;">
                                                  <th width="50%"><#running_status#></th>
                                                <td colspan="2">
                                                    <span id="sqm_status" ></span>
                                                    <span class="label label-info" style="margin-left: 0px;"><% nvram_get_x("","sqm_qdisc"); %></span>
                                                    <span class="label label-info" style="margin-left: 20px;"><% nvram_get_x("","sqm_script"); %></span>
                                            </td>
                                            </tr>
                                            <tr>
                                                <th>启用SQM</th>
                                                <td colspan="2">
                                                    <div class="main_itoggle">
                                                        <div id="sqm_enable_on_of">
                                                            <input type="checkbox" id="sqm_enable_fake"
                                                            <% nvram_match_x("", "sqm_enable", "1", "value=1 checked"); %><% nvram_match_x("", "sqm_enable", "0", "value=0"); %>
                                                            />
                                                        </div>
                                                    </div>
                                                    <div style="position: absolute; margin-left: -10000px;">
                                                        <input type="radio" value="1" name="sqm_enable" id="sqm_enable_1" class="input" value="1" <% nvram_match_x("", "sqm_enable", "1", "checked"); %> /> Yes
                                                        <input type="radio" value="0" name="sqm_enable" id="sqm_enable_0" class="input" value="0" <% nvram_match_x("", "sqm_enable", "0", "checked"); %> /> No
                                                    </div>
                                                </td>
                                            </tr>
                                              <tr>
                                            <th>流控对象</th>
                                            <td>
                                                <select name="sqm_flag" class="input">
                                                    <option value="1" <% nvram_match_x("", "sqm_flag", "1", "selected"); %>>仅有线到外网</option>
                                                    <option value="2" <% nvram_match_x("", "sqm_flag", "2", "selected"); %>>仅无线到外网</option>
                                                    <option value="3" <% nvram_match_x("", "sqm_flag", "3", "selected"); %>>有线到外网+无线到外网</option>
                                                    <option value="4" <% nvram_match_x("", "sqm_flag", "4", "selected"); %>>自定义接口</option>
                                                </select>
                                            </td>
                                        </tr>
                                            <tr>
                                                <th>自定义接口</th>
                                                <td>
                                                    <input type="text" maxlength="10" class="input" size="10" name="sqm_active" value="<% nvram_get_x("","sqm_active"); %>"/>
                                                </td>
                                                <td>
                                                    &nbsp;<span style="color:#888;">上项菜单需选择“自定义接口“ 可填写例如:ra0</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th>队列规则</th>
                                                <td>
                                                    <select name="sqm_qdisc" class="input">
                                                        <option value="fq_codel" <% nvram_match_x("","sqm_qdisc", "fq_codel","selected"); %>>fq_codel (*)</option>
                                                        <option value="codel" <% nvram_match_x("","sqm_qdisc", "codel","selected"); %>>codel</option>
                                                        <option value="sfq" <% nvram_match_x("","sqm_qdisc", "sfq","selected"); %>>sfq</option>
                                                        <option value="cake" <% nvram_match_x("","sqm_qdisc", "cake","selected"); %>>cake</option>
                                                    </select>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th>队列脚本</th>
                                                <td>
                                                    <select name="sqm_script" class="input">
                                                        <option value="simple.qos" <% nvram_match_x("","sqm_script", "simple.qos","selected"); %>>simple (*)</option>
                                                        <option value="simplest.qos" <% nvram_match_x("","sqm_script", "simplest.qos","selected"); %>>simplest</option>
                                                        <option value="simplest_tbf.qos" <% nvram_match_x("","sqm_script", "simplest_tbf.qos","selected"); %>>simplest_tbf</option>
                                                        <option value="piece_of_cake.qos" <% nvram_match_x("","sqm_script", "piece_of_cake.qos","selected"); %>>piece_of_cake</option>
                                                        <option value="layer_cake.qos" <% nvram_match_x("","sqm_script", "layer_cake.qos","selected"); %>>layer_cake</option>
                                                    </select>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th width="32%">宽带下载速度 (<span class="label label-info">kbit/s</span>)</th>
                                                <td>
                                                    <input type="text" maxlength="10" class="input" size="10" id="sqm_down_speed" name="sqm_down_speed" value="<% nvram_get_x("","sqm_down_speed"); %>"/>
                                                </td>
                                                <td>
                                                    <a href="#bw_calc_dialog" class="btn btn-info" data-toggle="modal">速度计算器</a>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th width="32%">宽带上传速度 (<span class="label label-info">kbit/s</span>)</th>
                                                <td>
                                                    <input type="text" maxlength="10" class="input" size="10" id="sqm_up_speed" name="sqm_up_speed" value="<% nvram_get_x("","sqm_up_speed"); %>"/>
                                                </td>
                                                <td>
                                                    &nbsp;<span style="color:#888;">测速的80-95％，1 Mbps = 1024 kbit/s 需填写小于下载速度的值</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th>启用日志</th>
                                                <td>
                                                    <div class="main_itoggle">
                                                        <div id="sqm_debug_log_on_of">
                                                            <input type="checkbox" id="sqm_debug_log_fake"
                                                            <% nvram_match_x("", "sqm_debug_log", "1", "value=1 checked"); %><% nvram_match_x("", "sqm_debug_log", "0", "value=0"); %>
                                                            />
                                                        </div>
                                                    </div>
                                                    <div style="position: absolute; margin-left: -10000px;">
                                                        <input type="radio" value="1" name="sqm_debug_log" id="sqm_debug_log_1" class="input" value="1" <% nvram_match_x("", "sqm_debug_log", "1", "checked"); %> /> Yes
                                                        <input type="radio" value="0" name="sqm_debug_log" id="sqm_debug_log_0" class="input" value="0" <% nvram_match_x("", "sqm_debug_log", "0", "checked"); %> /> No
                                                    </div>
                                                </td>
                                                <td>
                                                    &nbsp;<span style="color:#888;">/var/run/sqm/<% nvram_get_x("","sqm_active"); %>.debug.log</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <th>日志等级</th>
                                                <td>
                                                    <select name="sqm_log_level" class="input">
                                                        <option value="0" <% nvram_match_x("","sqm_log_level", "0","selected"); %>>silent</option>
                                                        <option value="1" <% nvram_match_x("","sqm_log_level", "1","selected"); %>>error</option>
                                                        <option value="2" <% nvram_match_x("","sqm_log_level", "2","selected"); %>>warn</option>
                                                        <option value="5" <% nvram_match_x("","sqm_log_level", "5","selected"); %>>info (*)</option>
                                                        <option value="8" <% nvram_match_x("","sqm_log_level", "8","selected"); %>>debug</option>
                                                        <option value="10" <% nvram_match_x("","sqm_log_level", "10","selected"); %>>trace</option>
                                                    </select>
                                                </td>
                                                <td>
                                                    &nbsp;<span style="color:#888;">仅调试时启用debug/trace</span>
                                                </td>
                                            </tr>
                </table>

                                        <!-- ===== 按设备限速（lanlimit.sh）=====
                                             规则表存成 /etc/storage/lanlimit.conf，改用下面的 textarea 编辑；
                                             点页面底部的「应用」由 applydb 写盘，服务端写完立刻 reload tc 规则 -->
                                        <table width="100%" align="center" cellpadding="4" cellspacing="0" class="table" style="margin-top: 10px;">
                                            <tr>
                                                <th width="30%">按设备限速</th>
                                                <td colspan="2">
                                                    <span style="color:#666;">
                                                        每行一台设备，三个字段：<b>目标</b> <b>下行kbit</b> <b>上行kbit</b>，填 <b>0</b> 表示该方向不限。目标填 IP 或 MAC 均可，空格分隔。
                                                    </span>
                                                    <a href="javascript:spoiler_toggle('lanlimit_tip')"><i class="icon-hand-right"></i> 说明与示例</a>
                                                    <div id="lanlimit_tip" style="display:none; margin-top:8px; color:#666; line-height:1.8;">
                                                        · 下行 5M / 上行 1M：<code>192.168.9.100&nbsp;&nbsp;&nbsp;5120&nbsp;&nbsp;&nbsp;1024</code><br/>
                                                        · 只限上传 512k，按 MAC：<code>A4:5E:60:11:22:33&nbsp;&nbsp;&nbsp;0&nbsp;&nbsp;&nbsp;512</code><br/>
                                                        · <code>#</code> 开头是注释，空行忽略<br/>
                                                        · MAC 在应用时通过 DHCP 租约表 / ARP 表解析成当前 IP；设备不在线则本次跳过，等它上线后再点一次「应用」即可<br/>
                                                        · <b>要稳定生效必须关掉硬件加速</b>：把「外部网络(WAN) → 硬件加速」设为 <b>Disable</b>（等价 <code>nvram set hw_nat_mode=0</code>），SFE 同理（<code>nvram set sfe_enable=0</code>）。否则被硬件直通的长连接（下载、在线视频）不经过内核 qdisc，限速对它们无效。代价是转发性能下降<br/>
                                                        · 这里与上面的 SQM 是两套独立机制，可以同时用：SQM 管整条线路，这里只管指定的单台设备
                                                    </div>
                                                    <br/>
                                                    <textarea rows="12" wrap="off" spellcheck="false" maxlength="8192" class="span12" name="scripts.lanlimit.conf" style="font-family:'Courier New'; font-size:12px;"><% nvram_dump("scripts.lanlimit.conf",""); %></textarea>
                                                    <span style="color:#888;">改完点页面底部的「应用」即保存并立即生效；重启后由 autostart.sh 自动恢复</span>
                                                </td>
                                            </tr>
                                        </table>

                                   <table class="table">
                                            <tr>
                                                <td colspan="3" style="border-top: 0 none;">
                                                    <br/>
                                                    <center>
                                                        <input class="btn btn-primary" style="width: 219px" type="button" value="<#CTL_apply#>" onclick="applyRule()"/>
                                                    </center>
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
    </form>
    <div id="footer"></div>
</div>

<!-- foreign dns list modal -->
<div class="modal fade" id="bw_calc_dialog" style="left: 60%;width: 300px;overflow: hidden;">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">
                    <span aria-hidden="true">&times;</span>
                </button>
                <h4 class="modal-title">SQM QoS 速度计算器</h4>
            </div>
            <div class="modal-body">
                <div>
                    <span style="display: inline-block; width:68px;">带宽</span>:<input type="text" class="span2" style="margin: 1px 5px;" id="bw_in_Mbps" value="10">Mbps
                </div>
                <div>
                    <span style="display: inline-block; width:68px;">百分比</span>:<input type="text" class="span2" style="margin: 1px 5px;" id="bw_percent" value="95"> %
                </div>
                <div>
                    <span style="display: inline-block; width:68px;">结果</span>:<input type="text" readonly class="span2" style="margin: 1px 5px;" id="bw_result" value=""> kbit/s
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" id="bw_set_down_action" class="btn btn-primary">设置下载速度</button>
                <button type="button" id="bw_set_up_action" class="btn btn-primary">设置上传速度</button>
            </div>
        </div>
    </div>
</div>
<script>
    (function($) {
        //wait document ready
        $(function() {
            var update_bw_result = function(){
                var bw_val = $('#bw_in_Mbps').val() * 1024 * $('#bw_percent').val() / 100;
                bw_val = Math.ceil(bw_val);
                $('#bw_result').val(bw_val);
            };
            update_bw_result();
            $('#bw_in_Mbps').keyup(update_bw_result);
            $('#bw_percent').keyup(update_bw_result);
            $('#bw_set_down_action').click(function(){
                $('#sqm_down_speed').val($('#bw_result').val());
                $('#bw_calc_dialog').modal('hide');
            });
            $('#bw_set_up_action').click(function(){
                $('#sqm_up_speed').val($('#bw_result').val());
                $('#bw_calc_dialog').modal('hide');
            });
        });
    })(jQuery);
</script>
</body>
</html>
