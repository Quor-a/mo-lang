#!/usr/bin/env bash
# a64bssmut —— 证明 a64bsstest 真的在验东西：把实现改坏，测试必须变红。
# 每个变异都要：① 锚点命中且唯一  ② 改坏后测试失败  ③ 改回后基线仍通过。
# 开工前先自愈（反向替换），防止上一轮被强杀后源码停在变异态 —— 备份也可能
# 是污染版（本项目已在 v1.129 / v1.132 上栽过）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64bssmut
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

# 自愈：把六种变异串一律改回干净串（幂等）
heal examples/a64as.mo "wsh(shof + 192, nb - hof, 1," "wsh(shof + 192, nb - hof, 8,"
heal examples/a64as.mo "    NBB = 0;
    CURSEC = 0;
    if resolve == 0 {" "    CURSEC = 0;
    if resolve == 0 {"
heal examples/a64as.mo "fn dbyte(b: i64) -> i64 {
    store8(&DAT + ND, b);" "fn dbyte(b: i64) -> i64 {
    if CURSEC == 3 { return bbyte(); }"
heal examples/a64ld.mo "if SSEC[i] == 3 { return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i]; }" "if SSEC[i] == 3 { return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i]; }"
heal examples/a64ld.mo "return BASE + NT * 4 + FBW[SFIL[i]] + SOFF[i];" "return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i];"
heal examples/a64ld.mo "return BASE + NT * 4 + ND + SOFF[i];" "return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i];"
heal examples/a64ld.mo "    st64(104, n + 0);" "    st64(104, n + NB);"

CAP=0; TOT=0
run_mut() {
  name=$1; file=$2; old=$3; new=$4
  TOT=$((TOT+1))
  cp $W/pristine/a64as.mo examples/a64as.mo
  cp $W/pristine/a64ld.mo examples/a64ld.mo
  if ! apply "$file" "$old" "$new"; then echo "✗ $name 锚点未命中"; return 0; fi
  if timeout 900 bash tools/a64bsstest.sh > $W/$name.log 2>&1; then
    echo "✗ $name 未被捕获（测试仍通过）"
  else
    red=$(grep -o 'a64bsstest: [0-9]* 通过 / [0-9]* 失败' $W/$name.log | sed 's/.*\/ //;s/ 失败//')
    echo "✓ $name 被捕获，失败 ${red:-?} 项"
    CAP=$((CAP+1))
  fi
}

# M1 .bss 段头类型写成 SHT_PROGBITS(1)：它会在文件里真占字节
run_mut M1 examples/a64as.mo "wsh(shof + 192, nb - hof, 8," "wsh(shof + 192, nb - hof, 1,"
# M2 两遍汇编之间不复位 NBB：bss 大小翻倍（本轮真实踩到）
run_mut M2 examples/a64as.mo "    NBB = 0;
    CURSEC = 0;" "    CURSEC = 0;"
# M3 .zero 在 bss 里仍写文件字节（不派发到 bbyte）
run_mut M3 examples/a64as.mo "fn dbyte(b: i64) -> i64 {
    if CURSEC == 3 { return bbyte(); }" "fn dbyte(b: i64) -> i64 {"
# M4 bss 基址漏掉 ND：bss 落在 .data 上，填充会抹掉字符串
run_mut M4 examples/a64ld.mo "if SSEC[i] == 3 { return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i]; }" "if SSEC[i] == 3 { return BASE + NT * 4 + FBW[SFIL[i]] + SOFF[i]; }"
# M5 bss 基址漏掉 FBW：两个模块的 bss 起点相同，互相覆盖
run_mut M5 examples/a64ld.mo "if SSEC[i] == 3 { return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i]; }" "if SSEC[i] == 3 { return BASE + NT * 4 + ND + SOFF[i]; }"
# M6 memsz 不含 NB：文件里没 bss、内存里也不给 bss
run_mut M6 examples/a64ld.mo "    st64(104, n + NB);" "    st64(104, n + 0);"

# 还原 + 基线复验
cp $W/pristine/a64as.mo examples/a64as.mo
cp $W/pristine/a64ld.mo examples/a64ld.mo
if diff -q $W/pristine/a64as.mo examples/a64as.mo > /dev/null && diff -q $W/pristine/a64ld.mo examples/a64ld.mo > /dev/null; then echo "源码已还原"; else echo "✗ 还原失败"; fi
if timeout 900 bash tools/a64bsstest.sh > $W/base.log 2>&1; then
  echo "基线复验通过"
else
  echo "✗ 基线复验失败"; tail -8 $W/base.log
fi
echo "a64bssmut: $CAP / $TOT 被捕获"

[ "$CAP" = "$TOT" ]
