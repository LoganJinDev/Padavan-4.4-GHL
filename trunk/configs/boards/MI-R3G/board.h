/* Xiaomi Mi R3G */

#define BOARD_PID		"MI-R3G"
#define BOARD_NAME		"MI-R3G"
#define BOARD_DESC		"Xiaomi Mi R3G Wireless Router"
#define BOARD_VENDOR_NAME	"Beijing Xiaomi Technology Co., Ltd."
#define BOARD_VENDOR_URL	"http://www.mi.com/"
#define BOARD_MODEL_URL		"http://www.mi.com/miwifir3g"
#define BOARD_BOOT_TIME		20
#define BOARD_FLASH_TIME	120

#define BOARD_HAS_5G_11AC	1
#define BOARD_NUM_ANT_5G_TX	2
#define BOARD_NUM_ANT_5G_RX	2
#define BOARD_NUM_ANT_2G_TX	2
#define BOARD_NUM_ANT_2G_RX	2
#define BOARD_NUM_ETH_LEDS	1
#define BOARD_NUM_ETH_EPHY	3
#define BOARD_HAS_EPHY_L1000	1
#define BOARD_HAS_EPHY_W1000	1
#define BOARD_NUM_UPHY_USB3	1

/* Xiaomi Mi R3G 出厂默认值。此处定义会被 defaults.h 的 #ifndef 守卫接住，
 * 只影响 MI-R3G 这一个板型；其他板型不定义这几项，自动走上游通用值。
 * 备份/恢复出厂设置后生效（nvram_restore_defaults）。*/
/* 管理地址。DHCP 池必须同网段，否则下发的是不可达网段 */
#define DEF_LAN_ADDR	"192.168.32.1"
#define DEF_LAN_DHCP_BEG	"192.168.32.100"
#define DEF_LAN_DHCP_END	"192.168.32.244"
