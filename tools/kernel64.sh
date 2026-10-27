#!/bin/bash
# kernel64.sh —— 用墨语言构建 **ARM64 裸机内核镜像**
#
#   bash tools/kernel64.sh examples/kernel64.mo /tmp/mokern64.elf
#
# 流水线（与 kernel.sh 对标，只有目标架构和入口不同）：
#   墨语言源码 → mo2x kern-aarch64（PL011 UART MMIO 的 freestanding C）
#             → zig cc -target aarch64-freestanding
#             → boot/entry64.S + boot/linker64.ld → 64 位裸机 ELF
#
# 产物可被 `qemu-system-aarch64 -M virt -kernel xxx.elf` 直接加载，
# 也可由 tools/kern64run.py 在 CPU 模拟器里执行验证。
#
# 关键差别：ARM64 **没有 I/O 地址空间**，所以内核后端把 inb/outb 退化成
# MMIO 字节读写；输出一律走 0x09000000 的 PL011 UART。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
cd "$ROOT"
SRC=${1:-examples/kernel64.mo}
OUT=${2:-kernel64.elf}

[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }

W=/tmp/mokern64
rm -rf $W; mkdir -p $W
cp "$SRC" $W/kernel.mo

# 1) 墨语言 → C（ARM64 内核目标）
$ROOT/bin/mo2x $W/kernel.mo kern-aarch64 > $W/kernel.c || { echo "mo2x 失败"; exit 1; }
# 确认拿到的是 **ARM64** 前导而不是 x86 的 VGA 版 —— 两者函数名不同，
# 拿错了后面照样能编出来，只是跑起来往错误地址写（静默）。
grep -q "uart_print" $W/kernel.c || { echo "ARM64 内核前导缺失"; exit 1; }
if grep -q "0xB8000" $W/kernel.c; then echo "错误：落到了 x86 VGA 前导"; exit 1; fi

# 2) 编译（aarch64 freestanding，无 libc）
$ZIGCC -target aarch64-freestanding -fno-pic -fno-stack-protector \
       -O2 -ffreestanding -std=c11 -mgeneral-regs-only \
       -c $W/kernel.c -o $W/kernel.o 2>&1 | head -20 || true
[ -f $W/kernel.o ] || { echo "编译失败"; exit 1; }

# 3) 汇编入口
$ZIGCC -target aarch64-freestanding -c $ROOT/boot/entry64.S -o $W/entry.o 2>&1 | head -20
[ -f $W/entry.o ] || { echo "入口汇编失败"; exit 1; }

# 4) 链接
$ZIGCC -target aarch64-freestanding -Wl,--script=$ROOT/boot/linker64.ld -nostdlib \
       -Wl,--build-id=none $W/entry.o $W/kernel.o -o "$OUT" 2>&1 | head -20
[ -f "$OUT" ] || { echo "链接失败"; exit 1; }

echo "kernel64: $OUT"
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
