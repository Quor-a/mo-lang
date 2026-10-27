#!/usr/bin/env bash
# floattest —— 浮点字面量的**跨实现逐位比对**
#
# 为什么单独做：tests/127 里那 20 个常量是**手挑**的，只能证明"这几个对"。
# 而精度 bug 的特征是"大部分对、个别差得很远"—— 手挑的样本很容易恰好避开。
#
# 做法：随机生成一批字面量，墨语言的 fbits 与 Python struct 的位模式逐个比对。
# Python 是**独立实现**（它自己有正确的 strtod），两边一致才说明真的对。
#
# 生成范围遵循实现契约（见 docs/float_literal.md）：
#   有效数字 <= 17 位 且 小数点后总位数 <= 26 位 → 必须 0 ulp
#
# 用法：bash tools/floattest.sh [编译器]
#   默认 bin/moc；传别的编译器是为了**变异验证**——
#   tools/floatlitmut.sh 会传一个"小数位回退到 8 位"的变异编译器进来，
#   那时本脚本必须报不一致。不接受参数的话就只能验默认编译器，
#   变异验证会退化成"改了编译器却没重编"，等于空转。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC=${1:-$ROOT/bin/moc}
CC="$(cd "$(dirname "$CC")" && pwd)/$(basename "$CC")"
W=/tmp/mofloat; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

python3 - "$W" <<'PY'
import random, sys, os
W=sys.argv[1]
random.seed(20261012)
vals=[]
for e in range(0,19):
    for _ in range(10):
        ip=random.randint(0,10**min(e,18)-1) if e>0 else 0
        nd=random.randint(1,16)
        fd=''.join(random.choice('0123456789') for _ in range(nd))
        vals.append(f"{ip}.{fd}")
for z in range(0,25):
    for _ in range(6):
        nd=random.randint(1,min(16,26-z))
        fd='0'*z+''.join(random.choice('0123456789') for _ in range(nd))
        vals.append("0."+fd)
open(W+'/vals.txt','w').write('\n'.join(vals))
L=['import "io.mo";','fn main() -> i64 {']
for s in vals: L.append(f'    print_hex(fbits({s})); print("\\n");')
L.append('    return 0;\n}')
open(W+'/test.mo','w',encoding='utf-8').write('\n'.join(L))
PY

( cd $W && rm -f out.elf && timeout 300 "$CC" >/dev/null 2>&1 )
if [ ! -f $W/out.elf ]; then echo "floattest: ✗ 编译失败"; exit 1; fi
( cd $W && timeout 60 ./out.elf > $W/got.txt 2>&1 )

python3 - "$W" <<'PY'
import struct, sys
W=sys.argv[1]
vals=[l.strip() for l in open(W+'/vals.txt') if l.strip()]
got=[int(l.strip(),16) for l in open(W+'/got.txt') if l.strip()]
# 🔴 必须核对条数：程序若崩在半路，got.txt 会短一截，
#    而 zip() 只比到较短的那个 —— 结果是"总数 340 不一致 0"的**假通过**。
#    静默少报正是本项目反复踩的模式，这里显式钉死。
if len(got) != len(vals):
    print("✗ 输出条数不足：期望 %d 实得 %d（程序提前退出？）" % (len(vals), len(got)))
    sys.exit(1)
bad=[]
for s,g in zip(vals,got):
    w=struct.unpack('<Q',struct.pack('<d',float(s)))[0]
    if w!=g: bad.append((s,w,g,g-w))
print("总数",len(vals),"不一致",len(bad))
for s,w,g,d in bad[:10]: print("  %-34s want %016x got %016x  %+d ulp"%(s,w,g,d))
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then echo "floattest: OK（与 Python 逐位一致）"; exit 0; fi
echo "floattest: FAILED"; exit 1
