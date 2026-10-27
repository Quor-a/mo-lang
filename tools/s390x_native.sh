#!/bin/bash
# s390x_native —— 构建 s390x（大端）原生程序（静态、无 libc）
#
#   bash tools/s390x_native.sh app.mo [-o app.s390x]
#
# s390x 有两个特殊之处，脚本里都体现出来了：
#   1. **大端**：Unicorn 模拟必须用 UC_MODE_BIG_ENDIAN
#   2. **自己的 syscall 号表**：write=4、exit=1，不是 asm-generic 的 64/93
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
SRC=${1:-examples/andromo.mo}
OUT=${2:-app.s390x}
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/mos390; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" cfs-s390x > $W/app.c || { echo "mo2x 失败"; exit 1; }
grep -q "svc 0" $W/app.c || { echo "s390x 系统调用缺失"; exit 1; }

# --image-base=0x10000 是关键：Unicorn 模拟 s390x 时**只可靠访问低位内存**。
# 默认链接到 0x1000000 时代码能执行，但数据段写入会静默失败，
# 程序表现为卡住不动。真机运行不受影响（ELF 仍是正常位置无关的静态可执行文件）。
$ZIGCC -target s390x-linux-musl -static -nostdlib -O2 -Wl,--image-base=0x10000 -o "$OUT" $W/app.c 2>&1 \
  | grep -E "error" | head -10
[ -f "$OUT" ] || { echo "编译失败"; exit 1; }

echo "s390x: $OUT"
python3 - "$OUT" <<'PY'
import struct, sys
d = open(sys.argv[1],'rb').read()
mach = struct.unpack('>H', d[18:20])[0]
print("   %s 机器类型 = 0x%x (%s)" % ("✓" if mach==22 else "✗", mach,
                                      "s390x" if mach==22 else "?"))
print("   %s 字节序 = %s" % ("✓" if d[5]==2 else "✗", "大端" if d[5]==2 else "小端"))
PY
ls -l "$OUT" | awk '{print "  大小: "$5" 字节"}'
