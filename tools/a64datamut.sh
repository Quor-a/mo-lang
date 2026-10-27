#!/usr/bin/env bash
# a64datamut —— 证明 a64datatest 真的在验东西：把实现改坏，测试必须变红。
# 每个变异都要：① 锚点命中且唯一  ② 改坏后测试失败  ③ 改回后基线仍通过。
# 开工前先自愈（反向替换），防止上一轮被强杀后源码停在变异态 —— 备份也可能
# 是污染版（本项目已在 v1.129 / v1.132 上栽过）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64datamut
rm -rf $W; mkdir -p $W/pristine
cp examples/a64as.mo $W/pristine/a64as.mo
cp examples/a64ld.mo $W/pristine/a64ld.mo

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

# 自愈：把四种变异串一律改回干净串（幂等）
heal examples/a64as.mo "NDF = NDF + 0;" "NDF = NDF + 1;"
heal examples/a64ld.mo "ROFF[k] + 8;" "ROFF[k];"
heal examples/a64ld.mo "while i < 4 {\n        store8(&DTA + p + i" "while i < 8 {\n        store8(&DTA + p + i"
heal examples/a64as.mo "while i < 4 { dbyte(0); i = i + 1; }" "while i < 8 { dbyte(0); i = i + 1; }"

CAP=0; TOT=0
run_mut() {
  name=$1; file=$2; old=$3; new=$4
  TOT=$((TOT+1))
  cp $W/pristine/$(basename $file) $file
  if ! apply "$file" "$old" "$new"; then echo "✗ $name 锚点未命中"; return 0; fi
  if bash tools/a64datatest.sh > $W/$name.log 2>&1; then
    echo "✗ $name 未被捕获（测试仍通过）"
  else
    red=$(grep -o 'a64datatest: [0-9]* 通过 / [0-9]* 失败' $W/$name.log | sed 's/.*\/ //;s/ 失败//')
    echo "✓ $name 被捕获，失败 $red 项"
    CAP=$((CAP+1))
  fi
}

run_mut M1 examples/a64as.mo "                NDF = NDF + 1;" "                NDF = NDF + 0;"
run_mut M2 examples/a64ld.mo "                let off: i64 = FDO[RFIL[k]] + ROFF[k];" "                let off: i64 = FDO[RFIL[k]] + ROFF[k] + 8;"
run_mut M3 examples/a64ld.mo "    while i < 8 {
        store8(&DTA + p + i, (v / d) % 256);" "    while i < 4 {
        store8(&DTA + p + i, (v / d) % 256);"
run_mut M4 examples/a64as.mo "            while i < 8 { dbyte(0); i = i + 1; }" "            while i < 4 { dbyte(0); i = i + 1; }"

# 还原 + 基线复验
cp $W/pristine/a64as.mo examples/a64as.mo
cp $W/pristine/a64ld.mo examples/a64ld.mo
diff -q $W/pristine/a64as.mo examples/a64as.mo > /dev/null && diff -q $W/pristine/a64ld.mo examples/a64ld.mo > /dev/null && echo "源码已还原" || echo "✗ 还原失败"
if bash tools/a64datatest.sh > $W/base.log 2>&1; then
  echo "基线复验通过"
else
  echo "✗ 基线复验失败"; tail -5 $W/base.log
fi
echo "a64datamut: $CAP / $TOT 被捕获"
