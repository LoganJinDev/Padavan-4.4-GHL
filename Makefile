# =====================================================
#  Padavan Firmware Build System - Top-Level Makefile
#  Author: TurBoTse (Optimized for clarity and scalability)
#  Description: Professional, modular, and scalable firmware pipeline
# =====================================================

TOPDIR          := $(CURDIR)
SOURCE_DIR      := $(TOPDIR)/trunk
TEMPLATE_DIR    := $(SOURCE_DIR)/configs/templates
CONFIG_FILE     := $(SOURCE_DIR)/.config

# Toolchain Settings
TOOLCHAIN       ?= $(or $(shell echo $$TOOLCHAIN), mipsel-linux-musl)
TOOLCHAIN_ROOT  := $(TOPDIR)/toolchain
TOOLCHAIN_PATH  := $(TOOLCHAIN_ROOT)/$(TOOLCHAIN)
# 预编译交叉工具链已自托管在本仓库 tag `toolchain` 的 Release 里。
# 原先这里的兜底指向上游 TurBoTse/padavan —— 那是一个静默单点：上游删 Release、
# 改 tag 或仓库消失，本地裸跑 `make <板型>` 就在第 1 步 404，而 CI 完全无感
# （CI 自己传 TOOLCHAIN_URL 环境变量，见 .github/workflows/custom.yml）。
# 现在兜底也指向本仓库，对上游零依赖。
#   资产要求：文件名必须精确等于 <toolchain>.tar.xz（不带版本后缀），
#   且两个都传 —— mipsel-linux-musl.tar.xz / mipsel-linux-uclibc.tar.xz，
#   因为两条 workflow 的 toolchain 下拉都给了这两个选项，只传一个选到另一个就 404。
#   换地址：设环境变量 TOOLCHAIN_URL 覆盖（优先级高于这里的兜底）。
TOOLCHAIN_URL   ?= $(or $(shell echo $$TOOLCHAIN_URL), https://github.com/LoganJinDev/Padavan-4.4-GHL/releases/download/toolchain/$(TOOLCHAIN).tar.xz)
QUEUE_H         := $(TOOLCHAIN_PATH)/$(TOOLCHAIN)/sysroot/usr/include/sys/queue.h
QUEUE_H_URL     := https://raw.githubusercontent.com/bminor/glibc/master/misc/sys/queue.h

# Auto-discovered target products
PRODUCTS        := $(notdir $(basename $(wildcard $(TEMPLATE_DIR)/*.config)))

# Phony targets
.PHONY: all build clean distclean prepare-headers $(PRODUCTS)

# Default target
all: build

build:
	@echo "\033[1;36m===> 🔎 Verifying toolchain availability...\033[0m"
	@if [ ! -d "$(TOOLCHAIN_PATH)/bin" ]; then \
		echo "\033[1;36m===> 📂 Creating toolchain directory...\033[0m"; \
		mkdir -p "$(TOOLCHAIN_PATH)"; \
		echo "\033[1;33m===> ⬇️ Downloading prebuilt toolchain...\033[0m"; \
		curl -fL --retry 3 --progress-bar "$(TOOLCHAIN_URL)" | tar -xJ -C "$(TOOLCHAIN_PATH)" || { \
			echo "\033[1;31m===> ❌ Toolchain download failed: $$? (URL: $(TOOLCHAIN_URL))\033[0m"; \
			rm -rf "$(TOOLCHAIN_PATH)"; \
			$(MAKE) -C "$(TOPDIR)/toolchain" build CT_PREFIX="$(TOOLCHAIN_PATH)" CT_TARGET="$(TOOLCHAIN)" || { \
				echo "\033[1;31m===> ❌ Toolchain source build failed\033[0m"; exit 1; }; \
		}; \
	fi
	@echo "\033[1;32m===> ✅ Toolchain ready: $(TOOLCHAIN)\033[0m"
	@$(MAKE) prepare-headers
	@echo "\033[1;36m===> 🔎 Validating firmware configuration...\033[0m"
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "\033[1;31m===> ❌ Missing .config file.\033[0m"; \
		echo "\033[1;36m===> 💡 Available build targets:\033[0m"; \
		for p in $(PRODUCTS); do echo "  - $$p"; done; \
		exit 1; \
	fi
	@echo "\033[1;32m===> 🛠️ Initiating firmware compilation...\033[0m"
	@$(MAKE) -C $(SOURCE_DIR)

# Ensure sys/queue.h exists for musl-based toolchain (required by some source files)
ifeq ($(TOOLCHAIN),mipsel-linux-musl)
prepare-headers:
	@echo "\033[1;36m===> 🔎 Checking sys/queue.h...\033[0m"
	@if [ ! -f "$(QUEUE_H)" ]; then \
		echo "\033[1;36m===> ⬇️ Installing sys/queue.h...\033[0m"; \
		curl -fL --retry 3 --progress-bar "$(QUEUE_H_URL)" -o "$(QUEUE_H)" || { \
			echo "\033[1;31m===> ❌ queue.h installation failed. Check your network or URL.\033[0m"; exit 1; }; \
		echo "\033[1;32m===> ✅ queue.h successfully installed.\033[0m"; \
	else \
		echo "\033[1;32m===> ✅ sys/queue.h already exists.\033[0m"; \
	fi
else
	@true
endif

# Device-specific firmware configuration and build
$(PRODUCTS):
	@echo "\033[1;36m===> ⚙️ Setting up configuration for target: $@...\033[0m"
	@cp -f "$(TEMPLATE_DIR)/$@.config" "$(CONFIG_FILE)"
	@echo "" >> "$(CONFIG_FILE)"
	@echo "CONFIG_CROSS_COMPILE=$(TOOLCHAIN)" >> "$(CONFIG_FILE)"
	@echo "CONFIG_CROSS_COMPILER_ROOT=$(TOOLCHAIN_PATH)" >> "$(CONFIG_FILE)"
	@echo "TOOLCHAIN_URL=$(TOOLCHAIN_URL)" >> "$(CONFIG_FILE)"
	@echo "CONFIG_CCACHE=y" >> "$(CONFIG_FILE)"
	@echo "CONFIG_CCACHE_DIR=$(TOPDIR)" >> "$(CONFIG_FILE)"
	@echo "\033[1;32m===> 📝 Configuration generated: $(CONFIG_FILE)\033[0m"
	@$(MAKE) build

clean:
	@echo "\033[1;36m===> 🧼 Cleaning build environment...\033[0m"
	@$(MAKE) -C $(SOURCE_DIR) clean
	@rm -f $(CONFIG_FILE)
	@echo "\033[1;32m===> ♻️  Clean operation completed.\033[0m"

distclean: clean
	@echo "\033[1;36m===> 🧼 Removing toolchain...\033[0m"
	@rm -rf $(TOOLCHAIN_PATH)
	@echo "\033[1;32m===> ♻️  Distclean operation completed.\033[0m"
