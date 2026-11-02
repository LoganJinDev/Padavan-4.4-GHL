include $(ROOTDIR)/rules.mk

PKG_NAME := lzma
PKG_VERSION := 2602
PKG_SOURCE := $(PKG_NAME)$(PKG_VERSION).7z
# 双源：www.7-zip.org 是唯一官方源，但云编译实测出现过
#   "curl: (6) Could not resolve host: www.7-zip.org"（DNS 瞬时故障）
# 它一挂整个构建就失败，而 download.pl 内置的三个 OpenWrt 备用镜像
# 对 lzma2602.7z 永久 404（那是 7-Zip 自己的命名，OpenWrt 镜像上只有
# tukaani 的 lzma-<ver>.tar.xz，根本不是同一个文件）。
# SourceForge 的 sevenzip 项目就是 7-Zip 官方项目，同版本 lzma2602.7z
# 逐字节相同（SHA-256 与下方 PKG_HASH 一致）⇒ 追加为第二源，无需改 hash。
# download.pl 按 @mirrors 顺序回退（download.pl:351-361），7-zip.org 仍是首选。
PKG_SOURCE_URL := https://www.7-zip.org/a/ \
	https://downloads.sourceforge.net/project/sevenzip/LZMA%20SDK/
PKG_HASH := 2878c85f5f43a4a4e0952b1fd4e5fe097c1c143997a8047c7e1e788892aa9357
PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	@echo "==> Extracting $(PKG_SOURCE)..."
	@7z x -bd -y $(DL_DIR)/$(PKG_SOURCE) -o$(PKG_BUILD_DIR) > /dev/null
endef

define Build/Compile
	@echo "==> Compiling $(PKG_NAME)..."
	+$(MAKE) -C $(PKG_BUILD_DIR)/CPP/7zip/Bundles/LzmaCon -f makefile.gcc

	@echo "==> Installing $(PKG_NAME) to tools/lzma..."
	$(INSTALL_DIR) $(ROOTDIR)/tools/lzma
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/CPP/7zip/Bundles/LzmaCon/_o/lzma $(ROOTDIR)/tools/lzma/
endef

$(eval $(call BuildPackage,lzma))
