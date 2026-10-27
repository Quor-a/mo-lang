#!/bin/bash
# motools_test —— 墨语言版工具链脚本与其取代的 Python 版交叉验证
#
# 为什么要有这个脚本：
#   两个版本是**独立实现**（Mo 版自己解析 ELF、自己解码指令；Python 版
#   借 readelf + objdump）。独立实现给出一致结论，两边才都可信。
#   而两边给出**不一致**结论时，必须能说清谁对 —— 所以每条断言都写死了
#   "为什么正确的那个是它"。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1
F=0

ck() { # ck <说明> <实际> <期望>
  if [ "$2" = "$3" ]; then echo "  OK  $1 ($2)"
  else echo "  ✗   $1 (实际 $2, 期望 $3)"; F=$((F+1)); fi
}

echo "== seedalign： Mo 版 vs Python 版 =="
mkdir -p build
./bin/moc tools/seedalign.mo build/seedalign.elf || { echo "编译失败"; exit 1; }
MO_S=$(./build/seedalign.elf . | sed -n 's/.*seed=\([0-9]*\).*/\1/p')
PY_S=$(python3 tools/seedalign.py | sed -n 's/.*seed=\([0-9]*\).*/\1/p')
ck "两边数出的 dquad 数量一致" "$MO_S" "$PY_S"

echo "== codecompose： Mo 版 vs Python 版 =="
./bin/moc tools/codecompose.mo build/codecompose.elf || { echo "编译失败"; exit 1; }
./build/codecompose.elf bin/moc > build/cc_mo.txt
python3 tools/codecompose.py bin/moc > build/cc_py.txt

MO_TOT=$(sed -n 's/^代码段 \([0-9]*\) 字节.*/\1/p' build/cc_mo.txt)
PY_TOT=$(sed -n 's/^代码段 \([0-9]*\) 字节.*/\1/p' build/cc_py.txt)
MO_PUSH=$(awk '$1=="push"{print $4}' build/cc_mo.txt)
PY_PUSH=$(awk '$1=="push"{print $4}' build/cc_py.txt)
MO_POP=$(awk '$1=="pop"{print $4}' build/cc_mo.txt)
PY_POP=$(awk '$1=="pop"{print $4}' build/cc_py.txt)

ck "push 条数一致（两边都靠外部/自己解码，结论必须相同）" "$MO_PUSH" "$PY_PUSH"
ck "pop 条数一致" "$MO_POP" "$PY_POP"

# movabs 不变量：0xB8+r 带 REX.W 就是 10 字节（1 操作码 + 8 立即数）
MV_B=$(awk '$1=="movabs"{print $2}' build/cc_mo.txt)
MV_N=$(awk '$1=="movabs"{print $4}' build/cc_mo.txt)
# 少了这条，上一条断言会在"根本没有 movabs"时空转成 0==0 通过
ck "bin/moc 里确实有 movabs（否则上一条是空转）" "$((MV_N > 0))" "1"
ck "movabs 每条都是 10 字节" "$((MV_B))" "$((MV_N * 10))"

# Python 版会漏：objdump 一行最多打印 7 字节，movabs 的 10 字节被截断，
# 于是每条只算 7 字节。所以 Mo 版的总字节数必然更大。
if [ "$MO_TOT" -gt "$PY_TOT" ]; then
  echo "  OK  Mo 版总字节数更大（Python 版漏了 objdump 折行的 $((MO_TOT-PY_TOT)) 字节）"
else
  echo "  ✗   Mo 版总字节数($MO_TOT) 未大于 Python 版($PY_TOT)"; F=$((F+1))
fi

# 解码正确性：Mo 版逐条解码，指令边界必须精确落在代码段末尾（工具内部断言，
# 返回非 0 即失败）。这是 Python 版做不到的校验。
./build/codecompose.elf bin/moc > /dev/null 2>&1
ck "线性扫描边界精确落在末尾（解码器自校验）" "$?" "0"

echo
if [ "$F" = "0" ]; then echo "motools: 通过"; else echo "motools: 失败 $F 项"; fi
exit $F
