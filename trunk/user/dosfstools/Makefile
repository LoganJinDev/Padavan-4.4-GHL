SRC_NAME=dosfstools-4.2
SRC_URL=https://github.com/dosfstools/dosfstools/releases/download/v4.2/dosfstools-4.2.tar.gz

CFLAGS+=$(COPT) -ffunction-sections -fdata-sections -fvisibility=hidden
LDFLAGS += -Wl,--gc-sections

#all: download_test extract_test config_test
# ---------------------------------------------------------------------------
# 修 mtime：dosfstools-4.2 的源树是随仓库一起提交的（vendored），而 git 不保存 mtime。
#
# git 检出时每个文件取当前时间，写入顺序按索引里的路径字节序。aclocal.m4 排在
# configure.ac 之前，于是 configure.ac 的 mtime 更新，Makefile.in 里那条维护者规则
#     $(ACLOCAL_M4): $(am__aclocal_m4_deps)        # 即 aclocal.m4: configure.ac
# 就每次都会触发，去执行 configure 里写死的 `missing --run aclocal-1.16`。
# 老 runner（Ubuntu 24.04，automake 1.16）里该命令存在，规则能跑通，看不出问题；
# 新 runner（Ubuntu 26.04，automake 1.18）里 aclocal-1.16 已被移除，于是
#     make[5]: *** [Makefile:383: aclocal.m4] Error 127
# 注意 configure 里钉死版本的是 aclocal / automake-1.16，autoconf 反而没带版本号。
#
# 这里理顺时间戳，而不是跑 autoreconf：上游发布用的就是 automake 1.16，用 1.18 重新
# 生成 aclocal.m4 / configure / Makefile.in 会得到与上游发布物不同的构建脚本，属于没
# 必要的风险。理顺规则是「输入钉到 T-1，所有产物钉到同一个 T」——产物之间时间戳相等
# 时 make 认为不比依赖旧，于是三条维护者规则（aclocal.m4、configure、Makefile.in）
# 同时沉默，上游产物原样保留。
#
# 放在 all 的配方第一行，而不是做成 all 的独立前置：all 的前置在 -j 下可能与 config_test
# 并发，写在配方里则一定在 ./configure 之后、内层 make 之前串行执行。此时
# Makefile / config.status 是刚生成的（真实时间），比 2000 年新，不会反过来触发重建。
# ---------------------------------------------------------------------------
all: config_test
	( cd $(SRC_NAME) ; \
		find . -type f \( -name configure.ac -o -name configure.in -o -name Makefile.am \
			-o -name acinclude.m4 -o -name '*.m4' \) -exec touch -t 200001010000 {} + ; \
		find . -type f \( -name Makefile.in -o -name aclocal.m4 -o -name configure \
			-o -name config.h.in \) -exec touch -t 200001010001 {} + ; \
	)
	$(MAKE) -j$(HOST_NCPU) -C $(SRC_NAME)

download_test:
	( if [ ! -f $(SRC_NAME).tar.gz ]; then \
		wget -t5 --timeout=20 --no-check-certificate -O $(SRC_NAME).tar.gz $(SRC_URL); \
	fi )

extract_test:
	( if [ ! -d $(SRC_NAME) ]; then \
		tar xzf $(SRC_NAME).tar.gz; \
	fi )

config_test:
	( if [ -f ./config_done ]; then \
		echo "the same configuration"; \
	else \
		make configure && touch config_done; \
	fi )

configure:
	( cd $(SRC_NAME) ;\
	./configure \
		--enable-compat-symlinks \
		--exec-prefix=/ \
		--without-udev \
		--host=$(HOST_TARGET) \
		--build=$(HOST_BUILD) ; \
	)

clean:
	if [ -f $(SRC_NAME)/Makefile ] ; then \
		$(MAKE) -C $(SRC_NAME) distclean; \
	fi ; \
	rm -f config_done

romfs:
	$(ROMFSINST) $(SRC_NAME)/src/fsck.fat /sbin/dosfsck
