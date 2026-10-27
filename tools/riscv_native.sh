#!/bin/bash
# riscv_native —— 构建 RISC-V 64 原生程序（静态、无 libc）
#
#   bash tools/riscv_native.sh app.mo [-o app.rv64]
#
# 与 android_native.sh 同一套思路：mo2x 的 freestanding 后端发出
# 直接陷入内核的 C（RISC-V 上是 ecall，调用号在 a7），再用 zig 交叉编译。
#
# 产物能在任何 RISC-V Linux 上跑（开发板、QEMU、未来的 RISC-V 手机）。
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
SRC=${1:-examples/andromo.mo}
OUT=${2:-app.rv64}
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/morv; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" cfs-riscv64 > $W/app.c || { echo "mo2x 失败"; exit 1; }
grep -q "ecall" $W/app.c || { echo "RISC-V 系统调用缺失"; exit 1; }

$ZIGCC -target riscv64-linux-musl -static -nostdlib -O2 -o "$OUT" $W/app.c 2>&1 \
  | grep -E "error" | head -10
[ -f "$OUT" ] || { echo "编译失败"; exit 1; }

echo "riscv: $OUT"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
mach = struct.unpack('<H', d[18:20])[0]
print("   %s 机器类型 = 0x%x (%s)" % ("✓" if mach==0xf3 else "✗", mach,
                                      "RISC-V" if mach==0xf3 else "?"))
# 静态：没有 .interp 段
print("   %s 无 .interp（静态）" % ("✓" if b'.interp' not in d[:4096] else "✗"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
