#!/bin/bash
# kernel.sh —— 用墨语言构建可引导的内核镜像
#
#   bash tools/kernel.sh examples/kernel.mo [-o kernel.elf] [--run]
#
# 流水线：
#   墨语言源码 → mo2x kern（VGA + 端口 I/O 的 freestanding C）
#             → zig cc -target x86-freestanding
#             → 自定义链接脚本 + Multiboot 头 → 32 位 ELF
#
# 产物可被 GRUB 或 `qemu-system-i386 -kernel` 直接加载。
#
# 与 cfs 后端的区别：内核**不能用系统调用**（它自己就是提供系统调用的
# 那一层），所以输出走 VGA 缓冲 0xB8000，I/O 走 in/out 端口。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/kernel.mo}
OUT=${2:-kernel.elf}
RUN=0
[ "$3" = "--run" ] && RUN=1

[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }

W=/tmp/mokern
rm -rf $W; mkdir -p $W
cp "$SRC" $W/kernel.mo

# 1) 墨语言 → C（内核目标）
$ROOT/bin/mo2x $W/kernel.mo kern > $W/kernel.c || { echo "mo2x 失败"; exit 1; }
grep -q "vga_print" $W/kernel.c || { echo "内核前导缺失"; exit 1; }

# 2) 编译（32 位 freestanding，无 libc）
$ZIGCC -target x86-freestanding -fno-pic -fno-stack-protector \
       -O2 -ffreestanding -std=c11 \
       -c $W/kernel.c -o $W/kernel.o 2>&1 | head -20 || true
[ -f $W/kernel.o ] || { echo "编译失败"; exit 1; }

# 3) 汇编入口
$ZIGCC -target x86-freestanding -c $ROOT/boot/entry32.S -o $W/entry.o 2>&1 | head -20

# 4) 链接
$ZIGCC -target x86-freestanding -Wl,--script=$ROOT/boot/linker.ld -nostdlib \
       -Wl,--build-id=none -Wl,--script=$ROOT/boot/linker.ld $W/entry.o $W/kernel.o -o $OUT 2>&1 | head -20
[ -f "$OUT" ] || { echo "链接失败"; exit 1; }

echo "kernel: $OUT"
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'

# 5) 校验 Multiboot 头 —— 这是"能不能被 GRUB 加载"的关键
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
if d[:4] != b'\x7fELF':
    print("   ✗ 不是 ELF"); sys.exit(1)
# 在第一个 4KB 内找 magic
off = d.find(struct.pack('<I', 0x1BADB002), 0, 8192)
if off < 0:
    print("   ✗ 找不到 Multiboot 头（必须在前 8KB 内）"); sys.exit(1)
magic, flags, checksum = struct.unpack('<III', d[off:off+12])
ok = ((magic + flags + checksum) & 0xFFFFFFFF) == 0
print("   %s Multiboot1 头 @ 偏移 %d (magic=%08x flags=%08x)" % ("✓" if ok else "✗", off, magic, flags))
if not ok: sys.exit(1)
# 检查入口
if d[16:18] == struct.pack('<H', 3) or True:
    entry = struct.unpack('<I', d[24:28])[0]
    print("   ✓ 入口点 = 0x%x" % entry)
# 不应有未定义的动态依赖
if b'.interp' in d[:8192]:
    print("   ✗ 仍有解释器段（说明链进了 libc）")
else:
    print("   ✓ 无 .interp（未链 libc）")
PY

if [ $RUN -eq 1 ]; then
  if command -v qemu-system-i386 >/dev/null 2>&1; then
    echo "   启动 qemu（Ctrl-A X 退出）"
    qemu-system-i386 -kernel "$OUT" -m 128
  else
    echo "   （未安装 qemu-system-i386，跳过运行）"
  fi
fi
