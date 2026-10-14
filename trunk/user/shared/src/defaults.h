/*
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#ifndef _defaults_h_
#define _defaults_h_

#include <ralink_board.h>

#define SYS_SHELL		"/bin/sh"
#define SYS_EXEC_PATH		"/usr/sbin:/usr/bin:/sbin:/bin"
#define SYS_EXEC_PATH_OPT	"/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin"
#define SYS_HOME_PATH_ROOT	"/home/admin"

#define SYS_USER_ROOT		"admin"
#define SYS_GROUP_ROOT		"root"
#define SYS_USER_NOBODY		"nobody"
#define SYS_GROUP_NOGROUP	"nogroup"

/* 本文件被所有板型共用，所以这里不写死任何型号专属值。
 * 型号定制值放在 configs/boards/<PID>/board.h —— configure 会把它拷成
 * user/shared/src/include/ralink_board.h（本文件开头已 include），
 * 于是板型专属定义在这里已经可见。板型没定义时回落到上游通用值。
 * 改某个板型的默认地址/SSID，只动那个板型的 board.h，不影响其他型号。*/
#ifndef DEF_LAN_ADDR
#define DEF_LAN_ADDR		"192.168.2.1"
#endif
/* DHCP 池必须与 LAN 网段保持一致，否则下发的是不可达网段 */
#ifndef DEF_LAN_DHCP_BEG
#define DEF_LAN_DHCP_BEG	"192.168.2.100"
#endif
#ifndef DEF_LAN_DHCP_END
#define DEF_LAN_DHCP_END	"192.168.2.244"
#endif
#ifndef DEF_LAN_MASK
#define DEF_LAN_MASK		"255.255.255.0"
#endif

#define DEF_WLAN_2G_CC		"CN"
#define DEF_WLAN_5G_CC		"CN"
/* 回落值里的 %s 由 rc.c 的 nvram_restore_defaults() 用 lan_mac 做 sprintf 填充，
 * 所以默认 SSID 是带 MAC 后缀的。板型若覆盖成不含 %s 的字面量，sprintf 退化成
 * 普通拷贝，同样安全 */
#ifndef DEF_WLAN_2G_SSID
#define DEF_WLAN_2G_SSID	BOARD_PID "_%s"
#endif
#ifndef DEF_WLAN_5G_SSID
#define DEF_WLAN_5G_SSID	BOARD_PID "_5G_%s"
#endif
#define DEF_WLAN_2G_GSSID	BOARD_PID "_GUEST_%s"
#define DEF_WLAN_5G_GSSID	BOARD_PID "_GUEST_5G_%s"
#define DEF_WLAN_2G_PSK		"1234567890"
#define DEF_WLAN_5G_PSK		"1234567890"

#define DEF_ROOT_PASSWORD	"admin"
#define DEF_SMB_WORKGROUP	"WORKGROUP"
#define DEF_TIMEZONE		"CST-8"
#define DEF_NTP_SERVER0		"ntp1.aliyun.com"
#define DEF_NTP_SERVER1		"time1.cloud.tencent.com"
#ifdef SUPPORT_OPENSSL_EC
#define DEF_HTTPS_CIPH_LIST	"ECDH+CHACHA20:ECDH+AESGCM:DH+AESGCM:DH+AES256:DH+AES:DH+3DES:RSA+AES:RSA+3DES:!ADH:!MD5:!DSS"
#else
#define DEF_HTTPS_CIPH_LIST	"DH+AESGCM:DH+AES256:DH+AES:DH+3DES:RSA+AES:RSA+3DES:!ADH:!MD5:!DSS"
#endif
#define DEF_OVPNS_CIPH_LIST	"CHACHA20-POLY1305:AES-256-GCM:AES-128-GCM"
#define DEF_OVPNC_CIPH_LIST	"CHACHA20-POLY1305:AES-256-GCM:AES-128-GCM"

#endif
