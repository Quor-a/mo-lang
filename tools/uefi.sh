#!/bin/bash
# uefi —— 用墨语言构建 UEFI 应用（64 位 PE32+，子系统 10）
#
#   bash tools/uefi.sh app.mo [-o app.efi]
#
# 流水线：
#   墨语言 → mo2x uefi（ConOut 协议输出的 freestanding C）
#          → zig cc -target x86_64-windows-gnu（子系统 efi_application）
#
# 两个关键点：
#   1. zig 0.17 的 x86_64-uefi 目标要求 MSVC ABI 的 libc，本机取不到，
#      直接编会报 "unable to provide libc for target x86_64-uefi"。
#      而 UEFI 应用本质上就是 subsystem=10 的 PE32+，
#      所以按 Windows 目标编、但用 efi_application 子系统是等价的。
#   2. UEFI 不能用 mingw 的 crt（它会找 WinMain/main），所以 -nostdlib；
#      lld 在 efi_application 下默认入口名是 **EfiMain**（不是 efi_main）。
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
SRC=${1:-examples/uefi.mo}
OUT=${2:-app.efi}
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/mouefi; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" uefi > $W/app.c || { echo "mo2x 失败"; exit 1; }
grep -q "uefi_puts" $W/app.c || { echo "UEFI 前导缺失"; exit 1; }
grep -q "EfiMain" $W/app.c   || { echo "UEFI 入口缺失"; exit 1; }

$ZIGCC -target x86_64-windows-gnu -O2 -nostdlib \
    -Wl,--subsystem,efi_application -o "$OUT" $W/app.c 2>&1 | grep -E "error" | head -10
[ -f "$OUT" ] || { echo "编译失败"; exit 1; }

echo "uefi: $OUT"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
print("   %s DOS 头 MZ" % ("✓" if d[:2]==b'MZ' else "✗"))
pe = struct.unpack('<I', d[0x3c:0x40])[0]
print("   %s PE 签名" % ("✓" if d[pe:pe+4]==b'PE\0\0' else "✗"))
mach = struct.unpack('<H', d[pe+4:pe+6])[0]
print("   %s 机器类型 = 0x%x (%s)" % ("✓" if mach==0x8664 else "✗", mach, "x86-64" if mach==0x8664 else "?"))
sub  = struct.unpack('<H', d[pe+0x5c:pe+0x5e])[0]
print("   %s 子系统 = %d (%s)" % ("✓" if sub==10 else "✗", sub, "EFI application" if sub==10 else "?"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
echo "  运行需要 OVMF（UEFI 固件）；本机没有，所以只验证到产物结构"
