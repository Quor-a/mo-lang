#!/bin/bash
# android_native —— 用墨语言构建**安卓原生可执行文件**（无需 NDK）
#
#   bash tools/android_native.sh app.mo [-o app]
#
# 原理：Android 的内核就是 Linux 内核，系统调用号与 ARM64 Linux 一致。
# 所以用 cfs-aarch64 后端（freestanding、不链接 libc、内联汇编 svc）
# 编出的静态 ARM64 ELF，可以直接 adb push 到手机上跑。
#
#   adb push app /data/local/tmp/app && adb shell chmod +x /data/local/tmp/app
#   adb shell /data/local/tmp/app
#
# 与 NDK 路径的区别：NDK 走 JNI + .so + APK，适合做带界面的 App；
# 这条路径做的是**命令行原生程序**（Termux / root shell / init 脚本），
# 不需要 Android SDK，不需要 Java。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/andromo.mo}
OUT=${2:-app_arm64}
ARCH=${ARCH:-aarch64}
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
# 🔴 输出目录不存在时 zig 报的是 "unable to open output directory ...:
# FileNotFound"，接着由本脚本打印 "构建失败" —— 而失败原因是**路径没建**，
# 不是源码有问题。真机上的典型触发：`android_native.sh app.mo out/app`，
# out/ 没建就必现。v1.180 实测。
mkdir -p "$(dirname "$OUT")" 2>/dev/null
W=/tmp/moand; rm -rf $W; mkdir -p $W

if [ "$ARCH" = "aarch64" ]; then
  $ROOT/bin/mo2x "$SRC" cfs-aarch64 > $W/app.c
  ZT=aarch64-linux-musl
elif [ "$ARCH" = "x86_64" ]; then
  $ROOT/bin/mo2x "$SRC" cfs > $W/app.c
  ZT=x86_64-linux-musl
else
  echo "ARCH 只支持 aarch64 / x86_64"; exit 2
fi

# zig 与 gcc 的参数面不同：zig 要 -target <triplet>，gcc 系交叉编译器
# 本身就是 triplet 前缀（aarch64-linux-gnu-gcc），不认 -target。
ZIGCC=$(bash "$ROOT/tools/zigcc.sh" "$ZT") || exit 1
if echo "$ZIGCC" | grep -q ziglang; then
    ZARGS="-target $ZT"
else
    ZARGS=""
fi

# 后端自带 _start（自己发 exit 系统调用），与 musl 的 crt 冲突。
# 因为产物完全不依赖 libc，直接不要 crt 更干净。
# -fno-builtin：不让编译器把手写循环替换成 strlen/memset/memcpy 等库函数调用。
# freestanding 产物不链 libc，被换出来的调用在链接期就是 undefined symbol；
# 而且它是**静默发生的** —— 源码里一行都没写过 strlen，报错却指向链接。
# mo2x 的 fs_header 已经提供了这些符号（双保险），这里再从编译器侧关掉。
# -Wno-int-conversion：墨语言里 i64 与 ptr **是同一个 64 位字**（load8(i64) 合法、
# 指针可以当整数算），不存在"整数不能当指针用"这回事。C 后端把它表达成
# long long / unsigned char* 两种类型，于是同一份合法源码在那里被判
# "incompatible pointer to integer conversion" —— 那是**表达介质的差异**，
# 不是源码缺陷（v1.177 交叉编译 a64as.mo 时撞上，14 处全在 lib/str.mo、vec.mo）。
#
# 真正该被抓的是"数算错了"，而那由数字判据负责，不由 C 的类型系统负责。
# 待 lib/ 把 ptr 标注补齐后可去掉这一项。
# -fno-lto -fno-strict-aliasing：MO_ARGC / MO_ARGV 只被 _start 的 naked 内联汇编引用，
# C 代码里没有任何一处读它们。LTO 做全局可达性分析时看不见 asm 里的引用，
# 判定"只写不读"，于是把变量整段删掉 —— 链接期报
# "undefined symbol: MO_ARGC"，而源码、mo2x 产物、汇编里都明明白白写着它。
# 真机实测（Android ARM64，2026-10-24）：不加 -fno-lto -fno-strict-aliasing 必现，加了即过。
# 这也是为什么那两个变量必须**非 static**（static 在 -O2 下同样会被删）。
# libc 依赖自动检测：程序里 extern 了 pthread_* 等 libc 线程/网络符号时，
# freestanding（-nostdlib）链不出来 —— pthread 需要完整 libc 运行时（TLS、
# 进程共享状态）。这时切到「libc 模式」：
#   1. 生成 C 里自带的 naked _start 与 crt1.o 冲突 → 改名 MO_START_X，
#      mo_start 改名为 main，naked 体里的 `b mo_start` 改 `b main`，
#      让 crt1 正常接管进程启动（ argc/argv 由 crt 填，我们的 mo_start
#      逻辑原样作为 main 运行）；
#   2. 去掉 -nostdlib，链 libc + pthread。
# 纯 syscall 程序（andromo/wc/pkgarm 等）仍走 freestanding，零依赖单文件。
LIBC_NEEDED=$(grep -cE '^(int|long long) (pthread_|dlopen|printf|fprintf|malloc|free)' $W/app.c || true)
if [ "$LIBC_NEEDED" -gt 0 ]; then
  sed -e 's/void _start(void)/void MO_START_X(void)/' \
      -e 's/void mo_start(void)/int mo_main_(void)/' \
      -e 's/asm volatile("b mo_start");/asm volatile("b main");/' \
      -e 's/^long long abort() {/long long mo_abort() {/' \
      -e 's/^long long abort();/long long mo_abort();/' \
      -e 's/__atomic_load_8(/__atomic_load_n(/g' \
      -e 's/__atomic_store_8(/__atomic_store_n(/g' \
      -e 's/__atomic_compare_exchange_8(/__atomic_compare_exchange_n(/g' \
      -e 's/__atomic_add_fetch_8(/__atomic_fetch_add(/g' \
      -e 's/\batomic_cas(/__mo_acas_(/g' \
      -e '/^#include <stddef.h>/a\
static long long __mo_acas_(long long* p, long long e, long long d){ long long o=e; long ok=__atomic_compare_exchange_n(p,&o,d,0,5,5); return ok?1:0; }' \
      -e 's/__sync_val_compare_and_swap_8(/__sync_val_compare_and_swap(/g' \
      -e 's/long long lf_load(unsigned char\* p)/long long lf_load(long long* p)/' \
      -e 's/long long lf_store(unsigned char\* p, long long v)/long long lf_store(long long* p, long long v)/' \
      -e 's/long long lf_cas(long long tid, unsigned char\* p, long long exp, long long des)/long long lf_cas(long long tid, long long* p, long long exp, long long des)/' \
      -e 's/\blmalloc(/heap_lmalloc(/g' \
      -e 's/\bmalloc(/heap_malloc(/g' \
      -e 's/\bcalloc(/heap_calloc(/g' \
      -e 's/\brealloc(/heap_realloc(/g' \
      -e 's/\bfree(/heap_free(/g' \
      -e '/extern __attribute__((noreturn)) void exit/d' \
      -e '/long long __atomic_load_n(/d' \
      -e '/long long __atomic_store_n(/d' \
      -e '/int __atomic_compare_exchange_n(/d' \
      -e '/long long __atomic_fetch_add(/d' \
      $W/app.c > $W/app_libc.c
  cat >> $W/app_libc.c <<'EOF'

int mo_main_(void);
int main(int c, char** v) {
    MO_ARGC = c;
    MO_ARGV = (unsigned char**)v;
    return mo_main_();
}
EOF
  LIBC_FLAGS="-lpthread"
  $ZIGCC $ZARGS -static -fno-builtin -O2 -fno-lto -fno-strict-aliasing -Wno-int-conversion -o "$OUT" $W/app_libc.c $LIBC_FLAGS 2>&1 | grep -E "error" | head -10 || true
else
  $ZIGCC $ZARGS -static -nostdlib -fno-builtin -O2 -fno-lto -fno-strict-aliasing -Wno-int-conversion -o "$OUT" $W/app.c 2>&1 | grep -E "error" | head -10 || true
fi
[ -f "$OUT" ] || { echo "构建失败"; exit 1; }

echo "android_native: $OUT ($ARCH，静态、无 libc)"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
assert d[:4]==b'\x7fELF', "不是 ELF"
mach = struct.unpack('<H', d[18:20])[0]
names = {0xb7:'AArch64 (ARM64)', 0x3e:'x86-64'}
print("   ✓ ELF 机器类型 = 0x%x (%s)" % (mach, names.get(mach,'?')))
print("   %s 静态链接（无 .interp）" % ("✓" if b'.interp' not in d[:4096] else "✗"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
echo "  部署: adb push $OUT /data/local/tmp/ && adb shell /data/local/tmp/$OUT"
