#!/usr/bin/env bash
# a64armut —— 证明 a64artest 真的在验东西：把实现改坏，测试必须变红。
# 每个变异都要：① 锚点命中且唯一  ② 改坏后测试失败  ③ 改回后基线仍通过。
#
# 六个变异分别打在六条**不同**的因果链上：
#   M1 不做按需（全抽）    → 未使用成员进产物，产物变大且含 ZZ-UNUSED
#   M2 抽取循环不迭代      → 传递依赖 fnb 缺失，链接直接失败
#   M3 链接器不做偶数对齐  → 第二个成员头错位
#   M4 归档器不做偶数对齐  → 同上，但错在写的一侧
#   M5 归档器 fmag 写错    → 格式本身坏掉（只被格式判据抓到）
#   M6 probe 恒为 0        → 一个成员都抽不出来，fna 未定义
#
# 开工前先自愈（反向替换），防止上一轮被强杀后源码停在变异态 —— 备份也可能
# 是污染版（本项目已在 v1.129 / v1.132 / v1.146 上栽过）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64armut
rm -rf $W; mkdir -p $W/pristine
cp examples/a64ld.mo $W/pristine/a64ld.mo
cp examples/a64ar.mo $W/pristine/a64ar.mo

apply() {
python3 - "$1" "$2" "$3" <<'PY'
import sys
p,old,new=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p,encoding='utf-8').read()
n=s.count(old)
if n!=1: sys.exit("ANCHOR ERROR in %s: %r count=%d"%(p,old[:70],n))
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY
}
heal() {
python3 - "$1" "$2" "$3" <<'PY'
import sys
p,mut,clean=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(s.replace(mut,clean))
PY
}

# 自愈（幂等）：把六种变异串一律改回干净串
heal examples/a64ld.mo "if 1 == 1 {
                            AMUSED[m] = 1;" "if arprobe(m) == 1 {
                            AMUSED[m] = 1;"
heal examples/a64ld.mo "                            fil = fil + 1;
                            changed = 0;" "                            fil = fil + 1;
                            changed = 1;"
heal examples/a64ld.mo "if 0 == 1 { o = o + 1; }" "if sz % 2 == 1 { o = o + 1; }"
heal examples/a64ld.mo "if SSEC[j] == 999 { return 1; }" "if SSEC[j] == 2 { return 1; }"
heal examples/a64ar.mo "if 0 == 1 {
            store8(&OUT + NO, 10);" "if INL % 2 == 1 {
            store8(&OUT + NO, 10);"
heal examples/a64ar.mo "        store8(&OUT + NO, 88);" "        store8(&OUT + NO, 96);"

# ── 基线：干净源码必须通过 ──
cp $W/pristine/a64ld.mo examples/a64ld.mo
cp $W/pristine/a64ar.mo examples/a64ar.mo
if ! timeout 900 bash tools/a64artest.sh > $W/base.log 2>&1; then
    echo "✗ 基线未通过（源码可能停在变异态）"; tail -20 $W/base.log; exit 1
fi
echo "✓ 基线通过 $(grep -o 'a64artest: [0-9]* 通过 / [0-9]* 失败' $W/base.log)"

CAP=0; TOT=0
run_mut() {
  name=$1; file=$2; old=$3; new=$4
  TOT=$((TOT+1))
  cp $W/pristine/a64ld.mo examples/a64ld.mo
  cp $W/pristine/a64ar.mo examples/a64ar.mo
  if ! apply "$file" "$old" "$new"; then echo "✗ $name 锚点未命中"; return 0; fi
  if timeout 900 bash tools/a64artest.sh > $W/$name.log 2>&1; then
    echo "✗ $name 未被捕获（测试仍通过）"
  else
    red=$(grep -o 'a64artest: [0-9]* 通过 / [0-9]* 失败' $W/$name.log | sed 's/.*\/ //;s/ 失败//')
    echo "✓ $name 被捕获，失败 ${red:-?} 项"
    CAP=$((CAP+1))
  fi
  cp $W/pristine/a64ld.mo examples/a64ld.mo
  cp $W/pristine/a64ar.mo examples/a64ar.mo
}

run_mut M1 examples/a64ld.mo "if arprobe(m) == 1 {
                            AMUSED[m] = 1;" "if 1 == 1 {
                            AMUSED[m] = 1;"
run_mut M2 examples/a64ld.mo "                            fil = fil + 1;
                            changed = 1;" "                            fil = fil + 1;
                            changed = 0;"
run_mut M3 examples/a64ld.mo "if sz % 2 == 1 { o = o + 1; }" "if 0 == 1 { o = o + 1; }"
run_mut M4 examples/a64ar.mo "if INL % 2 == 1 {
            store8(&OUT + NO, 10);" "if 0 == 1 {
            store8(&OUT + NO, 10);"
run_mut M5 examples/a64ar.mo "        store8(&OUT + NO, 96);" "        store8(&OUT + NO, 88);"
run_mut M6 examples/a64ld.mo "if SSEC[j] == 2 { return 1; }" "if SSEC[j] == 999 { return 1; }"

# ── 收尾：还原后基线必须仍然通过 ──
cp $W/pristine/a64ld.mo examples/a64ld.mo
cp $W/pristine/a64ar.mo examples/a64ar.mo
if timeout 900 bash tools/a64artest.sh > $W/final.log 2>&1; then
    echo "✓ 还原后基线仍通过"
else
    echo "✗ 还原后基线失败"; tail -20 $W/final.log
fi

echo "a64armut: $CAP / $TOT 被捕获"
[ "$CAP" = "$TOT" ]
