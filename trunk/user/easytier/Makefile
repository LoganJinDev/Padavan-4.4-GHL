#
# EasyTier —— Padavan 移植版
#
# 上游是 Rust 写的预编译静态二进制（mipsel，core 6.4 MiB + cli 2.6 MiB），
# 所以这里不编译任何源码，只做两件事：
#   ① 把控制脚本装进 /usr/bin（约 20 KiB，三个机型都装）
#   ② 按 CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN 决定要不要把 8.94 MiB 的
#      二进制一起编进固件（只有大闪存机型才开）
#
# GHL 根分区 29 MB、余量仅 1.19 MiB，装不下二进制 ⇒ 走「首次使用时由
# easytier_download.sh 从 GitHub 下载到 /tmp」这条路。
# MI-R3G（余量 48.88 MiB）/ MI-R3P（余量 96.60 MiB）⇒ 直接编进固件。
#
# 与官方 OpenWrt 包 build 规则的差异：
#   * 官方 Build/Prepare 里 `wget --no-check-certificate` ⇒ 这里不关证书校验
#   * 官方下载完不做任何校验 ⇒ 这里验整包 sha256，再逐个验二进制
#
THISDIR := $(shell pwd)

EASYTIER_TAG  := v2.6.4
EASYTIER_ARCH := mipsel

# ★ zip 文件名与 zip 内层目录名不是一回事，别合并成一个变量：
#     zip 文件: easytier-linux-mipsel-v2.6.4.zip
#     内层目录: easytier-linux-mipsel/
EASYTIER_ZIP  := easytier-linux-$(EASYTIER_ARCH)-$(EASYTIER_TAG).zip
EASYTIER_DIR  := easytier-linux-$(EASYTIER_ARCH)
EASYTIER_URL  := https://github.com/EasyTier/EasyTier/releases/download/$(EASYTIER_TAG)/$(EASYTIER_ZIP)

# 三重指纹：整包 + 两个二进制。
# ★ 必须与 easytier_download.sh 里那三个值逐字一致 —— 设备侧和构建侧
#   钉的是同一份字节，任何一边改了另一边也得改。
EASYTIER_ZIP_SHA256  := 7c93bcc9e9276f102b5299b0773941db7fd1d99ad04bac42b479a0d979ef5220
EASYTIER_CORE_SHA256 := 2ae281fb79b9026a00a4c9e5bfce6c007f155d919881d64c2a91795011d3a245
EASYTIER_CLI_SHA256  := b99664c7c956d5a16d708a32f9928955c0ed777ae7e1d9eeda986b623ff27de4

# 构建机上的 sha256 工具名：Linux 用 sha256sum，macOS 只有 shasum
SHA256 := $(shell if command -v sha256sum >/dev/null 2>&1; then echo sha256sum; else echo "shasum -a 256"; fi)

# 关掉二进制开关时，整条下载/解压链都不该跑 —— 8.94 MiB 白拉。
# ★ 用 make 变量做条件依赖，比在 recipe 里写 if 干净：依赖为空时
#   这两个目标根本不进入构建图，make 连看都不看。
ifeq ($(CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN),y)
BIN_TARGETS := download_test extra_test
else
BIN_TARGETS :=
endif

all: $(BIN_TARGETS)
	@echo "easytier build done!"

# 下载 + 整包校验。已存在就跳过（照 frp/Makefile 的先例，重建不重拉）。
download_test:
	( if [ ! -f $(EASYTIER_ZIP) ]; then \
		curl -fL --connect-timeout 15 --retry 3 -o $(EASYTIER_ZIP) $(EASYTIER_URL) \
		|| wget -t 5 --timeout=20 -O $(EASYTIER_ZIP) $(EASYTIER_URL); \
	fi )
	( if [ ! -f $(EASYTIER_ZIP) ]; then echo "!! $(EASYTIER_ZIP) 下载失败"; exit 1; fi )
	@echo "$(EASYTIER_ZIP_SHA256)  $(EASYTIER_ZIP)" | $(SHA256) -c - \
		|| { rm -f $(EASYTIER_ZIP); echo "!! $(EASYTIER_ZIP) 整包校验失败"; exit 1; }

# 解压 + 逐个二进制校验。
# ★ 不用官方那句 `easytier-core -h | wc -l > 3` 当判据 —— 那是存在性检查
#   不是完整性校验，任何能打印三行的东西都能过关。
extra_test: download_test
	( if [ ! -d $(EASYTIER_DIR) ]; then unzip -q -o $(EASYTIER_ZIP); fi )
	@echo "$(EASYTIER_CORE_SHA256)  $(EASYTIER_DIR)/easytier-core" | $(SHA256) -c - \
		|| { rm -rf $(EASYTIER_DIR); echo "!! easytier-core 校验失败"; exit 1; }
	@echo "$(EASYTIER_CLI_SHA256)  $(EASYTIER_DIR)/easytier-cli" | $(SHA256) -c - \
		|| { rm -rf $(EASYTIER_DIR); echo "!! easytier-cli 校验失败"; exit 1; }

clean:
	@# 与 frp/Makefile 一致：刻意不删下载物，避免每次重建都重拉 8.94 MiB
	@# rm -rf $(EASYTIER_ZIP) $(EASYTIER_DIR)
	@true

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/easytier.sh /usr/bin/easytier.sh
	$(ROMFSINST) -p +x $(THISDIR)/easytier_download.sh /usr/bin/easytier_download.sh
ifeq ($(CONFIG_FIRMWARE_INCLUDE_EASYTIER_BIN),y)
	$(ROMFSINST) -p +x $(THISDIR)/$(EASYTIER_DIR)/easytier-core /usr/bin/easytier-core
	$(ROMFSINST) -p +x $(THISDIR)/$(EASYTIER_DIR)/easytier-cli  /usr/bin/easytier-cli
endif
