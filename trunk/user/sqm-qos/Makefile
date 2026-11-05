include $(ROOTDIR)/rules.mk

PKG_NAME:=sqm-qos

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackage,sqm-qos))

romfs:
	$(CP) ./files/* $(ROMFSDIR)/
# $(CP) 是整目录拷贝，会把工作区里的源码备份目录 auto_baks/ 一并带进镜像。
# CI 从 git 克隆不受影响（auto_baks 已 gitignore），但本地编译会；这里统一清掉，避免刷进无用文件。
	rm -rf $(ROMFSDIR)/usr/lib/sqm/auto_baks
