/* GHL */

#define BOARD_PID		"GHL"
#define BOARD_NAME		"GHL"
#define BOARD_DESC		"GHL Wireless Router"
#define BOARD_VENDOR_NAME	"Heaven"
#define BOARD_VENDOR_URL	"http://www.bigwc.cn/"
#define BOARD_MODEL_URL		"http://www.bigwc.cn/"
#define BOARD_BOOT_TIME		30
#define BOARD_FLASH_TIME	120

#define BOARD_HAS_5G_11AC	1
#define BOARD_NUM_ANT_5G_TX	2
#define BOARD_NUM_ANT_5G_RX	2
#define BOARD_NUM_ANT_2G_TX	2
#define BOARD_NUM_ANT_2G_RX	2
#define BOARD_NUM_ETH_LEDS	1
#define BOARD_HAS_EPHY_L1000	1
#define BOARD_HAS_EPHY_W1000	1
#define BOARD_NUM_UPHY_USB3	1
#define BOARD_USB_PORT_SWAP	0

/* GHL 出厂默认值。此处定义会被 defaults.h 的 #ifndef 守卫接住，
 * 只影响 GHL 这一个板型；其他板型不定义这几项，自动走上游通用值。
 * 备份/恢复出厂设置后生效（nvram_restore_defaults）。*/
/* 管理地址。DHCP 池必须同网段，否则下发的是不可达网段 */
#define DEF_LAN_ADDR		"192.168.9.1"
#define DEF_LAN_DHCP_BEG	"192.168.9.100"
#define DEF_LAN_DHCP_END	"192.168.9.244"
/* SSID 用纯字面量，不带 MAC 后缀（上游默认是 BOARD_PID "_%s"）。
 * rc.c 对它做 sprintf(tmp, value, lan_mac)，字面量无 %s 时等价于直接拷贝 */
#define DEF_WLAN_2G_SSID	"GHL"
#define DEF_WLAN_5G_SSID	"GHL_5G"
