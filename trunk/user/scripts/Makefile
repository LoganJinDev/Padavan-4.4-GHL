include $(ROOTDIR)/rules.mk

PKG_NAME:=scripts

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	$(CP) ./files $(PKG_BUILD_DIR)/
	mkdir -p $(PKG_BUILD_DIR)/files/usr/share/terminfo
	tar -xzf ./terminfo.tar.gz -C $(PKG_BUILD_DIR)/files/usr/share
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackage,scripts))

romfs:
	fakeroot ./makedevlinks $(ROMFSDIR)
	$(CP) $(PKG_BUILD_DIR)/files/* $(ROMFSDIR)/
# $(CP) 是整目录拷贝，会把工作区里的源码备份目录 auto_baks/ 一并带进镜像。
# CI 从 git 克隆不受影响（auto_baks 已 gitignore），但本地编译会；这里统一清掉，避免刷进无用文件。
	rm -rf $(ROMFSDIR)/sbin/auto_baks $(ROMFSDIR)/usr/bin/auto_baks $(ROMFSDIR)/etc_ro/auto_baks
ifneq ($(STORAGE_ENABLED),y)
	rm -f $(ROMFSDIR)/sbin/automount.sh
endif
ifndef CONFIG_BLK_DEV_SD
	rm -f $(ROMFSDIR)/sbin/hddtune.sh
	rm -f $(ROMFSDIR)/sbin/spindown.sh
endif
ifndef CONFIG_MTD_UBI
	rm -f $(ROMFSDIR)/sbin/rwfs2ubi.sh
endif
