#!/bin/bash
# ppc64_native —— 构建 PowerPC64 原生程序（静态、无 libc）
#
#   bash tools/ppc64_native.sh app.mo [-o app] [--le]
#
# 默认构建**大端** ppc64（因为 Unicorn 的 PPC 后端只支持大端，
# 这样才能在模拟器里验证）；加 --le 构建小端 ppc64le（真机用）。
#
# 两者生成完全相同的汇编，只是链接目标字节序不同。
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
SRC=${1:-examples/s390hello.mo}
OUT=${2:-app.ppc64}
TGT_ARCH=powerpc64-linux-musl
MO_TGT=cfs-ppc64
if [ "$3" = "--le" ]; then TGT_ARCH=powerpc64le-linux-musl; MO_TGT=cfs-ppc64le; fi
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/moppc; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" $MO_TGT > $W/app.c || { echo "mo2x 失败"; exit 1; }
grep -q '"sc"' $W/app.c || { echo "PowerPC 系统调用缺失"; exit 1; }

$ZIGCC -target $TGT_ARCH -static -nostdlib -O2 -Wl,--image-base=0x10000 -o "$OUT" $W/app.c 2>&1 \
  | grep -E "error" | head -10
[ -f "$OUT" ] || { echo "编译失败"; exit 1; }

echo "ppc64: $OUT"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
# ⚠️ e_machine 的字节序取决于 EI_DATA（d[5]）：大端 ELF 用 '>H'，
# 小端 ELF 用 '<H'。固定用 '>H' 时小端产物会读出 0x1500 而不是 0x15，
# 于是 ppc64le 明明构建正确却被判成"（?）"并让 targets_test 报失败。
_end = '>' if d[5] == 2 else '<'
mach = struct.unpack(_end + 'H', d[18:20])[0]
print("   %s 机器类型 = 0x%x (%s)" % ("✓" if mach==21 else "✗", mach,
                                      "PowerPC64" if mach==21 else "?"))
print("   %s 字节序 = %s" % ("✓", "大端" if d[5]==2 else "小端"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
