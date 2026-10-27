#!/bin/env bash
# floatlitmut —— 端到端变异验证：证明浮点字面量的检查不是空转
#
# 为什么必须有这个脚本：
#   "常量对上了"有两种可能：解析器真的正确舍入，或者**根本没检查到**。
#   区分它们的唯一办法是故意把解析器弄坏，看检查是否报红。
#
# 弄坏的方式是**还原历史 bug**：lex_number 里把小数位预算从 sig 改回 8，
#   0.693147180559945  →  0.69314718
# 这正是 v1.115 之前的行为 —— 不报错、不崩溃，只是静默给一个看起来合理的数。
#
# 两层检查分别验：
#   tests/127 是**手挑**的 20 个常量（含 π、ln2、log10(2) 这类数学常量）
#   tools/floattest.sh 是**随机** 340 个字面量与 Python 逐位比对
# 两层都要报红。只改手挑的那批，说明覆盖面依赖挑样本的眼光。
#
# 安全：任何退出路径都还原 src/compiler.mo（trap EXIT），
#   且还原后**核对变异串确实不在源码里**（1.102 的教训：备份被删掉后
#   第二次还原是空操作，脚本照样打印全绿）。
set -u
HERE="$(cd "$(dirname "$0")" && cd .. && pwd)"
SRC="$HERE/src/compiler.mo"
BAK=/tmp/floatlitmut_backup.mo
OLD="                budget = sig;"
NEW="                budget = 8;"

# --- 0) 开工前先验源码干净：被污染的源码会让"变异被抓到"变成假阳性 ---
if grep -q "budget = 8;" "$SRC"; then
    echo "✗ 源码里已经存在变异串 —— 上一次运行没还原干净，先手动恢复"
    exit 1
fi

cp "$SRC" "$BAK" || { echo "✗ 备份失败"; exit 1; }
restore() { cp "$BAK" "$SRC"; }
trap restore EXIT

W=/tmp/floatlitmut; rm -rf $W; mkdir -p $W/t1 $W/t2 $W/build

# --- 1) 基线：正常编译器必须两项都全绿 ---
cp "$HERE"/lib/*.mo $W/t1/
cp "$HERE/tests/127_float_literal.mo" $W/t1/test.mo
( cd $W/t1 && "$HERE/bin/moc" >/dev/null 2>&1 )
if [ ! -f $W/t1/out.elf ]; then echo "✗ 基线编译失败"; exit 1; fi
( cd $W/t1 && ./out.elf >/dev/null 2>&1 ); brc=$?
if [ "$brc" -ne 0 ]; then
    echo "✗ 基线就没过（退出码 $brc）—— 先修正常情况，变异验证没有意义"; exit 1
fi
echo "== 基线 =="
echo "  tests/127  通过"
if ! bash "$HERE/tools/floattest.sh" > $W/base_rand.txt 2>&1; then
    echo "✗ 基线随机比对就没过 —— 见 $W/base_rand.txt"; cat $W/base_rand.txt; exit 1
fi
echo "  floattest  $(head -1 $W/base_rand.txt)"

# --- 2) 变异 ---
python3 - "$SRC" "$OLD" "$NEW" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    print("✗ 定位串出现 %d 次（期望 1）—— 编译器源码结构变了，本脚本要跟着改" % s.count(old))
    sys.exit(1)
open(p, 'w').write(s.replace(old, new, 1))
PY
if [ $? -ne 0 ]; then exit 1; fi
if ! grep -q "budget = 8;" "$SRC"; then echo "✗ 变异没写进去"; exit 1; fi
echo "== 变异：小数位预算 18 → 8（还原历史 bug）=="

# --- 3) 用**未变异**的 moc 造出变异编译器 ---
cp "$SRC" $W/build/test.mo
cp "$HERE"/lib/*.mo $W/build/ 2>/dev/null
( cd $W/build && "$HERE/bin/moc" >/dev/null 2>&1 )
if [ ! -f $W/build/out.elf ]; then echo "✗ 变异编译器构建失败"; exit 1; fi
cp $W/build/out.elf $W/moc_mut && chmod +x $W/moc_mut

# --- 4) 手挑常量必须报红 ---
cp "$HERE"/lib/*.mo $W/t2/
cp "$HERE/tests/127_float_literal.mo" $W/t2/test.mo
( cd $W/t2 && $W/moc_mut >/dev/null 2>&1 )
if [ ! -f $W/t2/out.elf ]; then echo "✗ 变异体编译失败"; exit 1; fi
( cd $W/t2 && ./out.elf > $W/mut.txt 2>&1 ); mrc=$?
echo "  tests/127  退出码 $mrc（应非 0）"
grep "FAIL" $W/mut.txt | head -3 | sed 's/^/    /'

# --- 5) 随机批必须报红 ---
bash "$HERE/tools/floattest.sh" $W/moc_mut > $W/mut_rand.txt 2>&1; rrc=$?
echo "  floattest  退出码 $rrc（应非 0）"
head -3 $W/mut_rand.txt | sed 's/^/    /'

FAILN=0
[ "$mrc" -eq 0 ] && { echo "✗ 手挑常量批次竟然全过 —— 检查是空转"; FAILN=$((FAILN+1)); }
[ "$rrc" -eq 0 ] && { echo "✗ 随机批次竟然全过 —— 检查是空转"; FAILN=$((FAILN+1)); }
if [ "$FAILN" -ne 0 ]; then exit 1; fi
echo "✓ 两层均被捕获（浮点字面量的检查非空转）"
exit 0
