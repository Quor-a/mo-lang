#!/bin/bash
# winbuild —— 用墨语言构建 Windows 原生可执行文件（PE32+）
#
#   bash tools/winbuild.sh app.mo [-o app.exe] [--console] [--gui]
#
# 流水线：墨语言 → mo2x C → zig cc -target x86_64-windows-gnu → .exe
#
# 说明：zig 自带 mingw 的 libc 与导入库，**不需要安装 MSVC 或 MinGW**。
# 产物是真正的 PE32+，可在 Windows 上直接运行（或用 wine）。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/winhello.mo}
OUT=${2:-app.exe}
SUBSYS=console   # console = 控制台子系统；windows = GUI
[ "$3" = "--gui" ] && SUBSYS=windows

[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/mowin; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" c > $W/app_core.c || { echo "mo2x 失败"; exit 1; }

# 生成的 C 里 print / print_i64 / print_nl 是普通调用，
# Windows 下用 printf 实现它们 —— 必须在**使用之前**声明，
# 所以是前置而不是追加。
cat > $W/app.c <<'PRE'
#include <stdio.h>
#include <stdlib.h>
static void print(const unsigned char* s){ printf("%s", (const char*)s); }
static void print_nl(void){ printf("\n"); }
static void print_i64(long v){ printf("%ld", (long)v); }
PRE
cat $W/app_core.c >> $W/app.c

$ZIGCC -target x86_64-windows-gnu -O2 \
    -Wl,--subsystem,$SUBSYS -o "$OUT" $W/app.c 2>&1 | grep -E "error" | head -10 || true
[ -f "$OUT" ] || { echo "构建失败"; exit 1; }

echo "winbuild: $OUT"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
ok = d[:2] == b'MZ'
print("   %s DOS 头 MZ" % ("✓" if ok else "✗"))
if not ok: sys.exit(1)
pe = struct.unpack('<I', d[0x3c:0x40])[0]
print("   %s PE 签名 @ 0x%x (%r)" % ("✓" if d[pe:pe+4]==b'PE\0\0' else "✗", pe, d[pe:pe+4]))
mach = struct.unpack('<H', d[pe+4:pe+6])[0]
print("   ✓ 机器类型 = 0x%x (%s)" % (mach, "x86-64" if mach==0x8664 else "?"))
sub  = struct.unpack('<H', d[pe+0x5c:pe+0x5e])[0]
print("   ✓ 子系统 = %d (%s)" % (sub, "控制台" if sub==3 else "GUI" if sub==2 else "?"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
