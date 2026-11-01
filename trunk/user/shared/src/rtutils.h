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

#ifndef _rtutils_h_
#define _rtutils_h_

extern const char* find_wlan_if_up(int is_aband);

extern int calc_phy_mode(int i_val, int is_aband);
extern int calc_fixed_tx_mode(int i_val, int is_aband, int i_phy_mode, int *p_mcs);
extern int calc_mcast_tx_mode(int i_val, int is_aband, int *p_mmcs);

extern void  nvram_wlan_set(int is_aband, const char *param, char *value);
extern void  nvram_wlan_set_int(int is_aband, const char *param, int value);
extern char* nvram_wlan_get(int is_aband, const char *param);
extern int   nvram_wlan_get_int(int is_aband, const char *param);

/* 额外 SSID 槽（idx 取 1..3，对应 nvram 键 ext1_* / ext2_* / ext3_*）
 * 返回值指向 nvram 静态轮转缓存，须立即使用或拷贝，不可跨次调用持有 */
extern char* nvram_wlan_get_ext(int is_aband, int idx, const char *param);
extern int   nvram_wlan_get_ext_int(int is_aband, int idx, const char *param);
/* 额外 SSID 槽是否应生效：启用 且 SSID 名非空 且（非开放网络时）密码长度 >= 8 */
extern int   is_ext_allowed(int is_aband, int idx);

#endif
