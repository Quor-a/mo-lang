#!/bin/bash
# kmod —— 用墨语言写 Linux 内核模块（.ko）
#
#   bash tools/kmod.sh module.mo <模块名> [--build]
#
# 原理：墨语言的 C 后端产出普通 C，再套一层 module_init/exit 包装，
# 用内核头文件编译成 .ko。这样"墨语言能写 Linux 内核"就不是口号。
#
# 注意：真正编译需要本机装有当前内核的头文件
#   （/lib/modules/$(uname -r)/build）。
# 没有头文件时脚本会**明确报错**并告诉你装什么，而不是假装成功。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/khello.mo}
MOD=${2:-momod}
BUILD=0
[ "$3" = "--build" ] && BUILD=1

[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/mokmod/$MOD; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" c > $W/core.c || { echo "mo2x 失败"; exit 1; }
# 内核里没有 libc：把 print 重定向到 printk
cat > $W/${MOD}.c <<'HDR'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
HDR
# 把生成的 C 里对 stdio 的依赖去掉（内核无法用）
sed -e '/#include <unistd.h>/d' \
    -e '/#include <sys\/syscall.h>/d' \
    -e '/#include <stdio.h>/d' \
    -e 's/\bprint\b/mo_printk/g' \
    -e 's/\bprint_nl\b/mo_printk_nl/g' \
    -e 's/\bprint_i64\b/mo_printk_i64/g' \
    $W/core.c >> $W/${MOD}.c
cat >> $W/${MOD}.c <<'TAIL'

/* 内核环境适配：墨语言的 print 家族在这里落到 printk */
static void mo_printk(const unsigned char* s){ printk(KERN_INFO "%s", (const char*)s); }
static void mo_printk_nl(void){ printk(KERN_INFO "\n"); }
static void mo_printk_i64(long v){ printk(KERN_INFO "%ld", (long)v); }

static int __init mo_mod_init(void){
    long r = mo_main();
    printk(KERN_INFO "mo module init: mo_main returned %ld\n", r);
    return 0;
}
static void __exit mo_mod_exit(void){
    printk(KERN_INFO "mo module exit\n");
}
module_init(mo_mod_init);
module_exit(mo_mod_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("mo");
MODULE_DESCRIPTION("a Linux kernel module written in the Mo language");
TAIL
cat > $W/Makefile <<'MK'
obj-m += MODNAME.o
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
MK
sed -i "s/MODNAME/$MOD/g" $W/Makefile

echo "kmod: $W/${MOD}.c 已生成（$(wc -l < $W/${MOD}.c) 行）"
echo "  Makefile 就绪"

if [ $BUILD -eq 1 ]; then
  KDIR=/lib/modules/$(uname -r)/build
  if [ ! -d "$KDIR" ]; then
    echo
    echo "  ✗ 缺少内核头文件：$KDIR"
    echo "    安装： apt install linux-headers-\$(uname -r)"
    echo "    本工具已生成可直接编译的 C 与 Makefile，装好头文件后："
    echo "      cd $W && make"
    exit 3
  fi
  ( cd $W && make 2>&1 | tail -6 )
fi
