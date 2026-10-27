#!/usr/bin/env bash
# a64ldmut —— 证明 a64ldtest 的判据真的能抓到东西
#
# 每个变异都刻意改在**一条因果链**上：改完代码必须让测试变红。
# 只改代码而测试仍绿的变异（M6 第一版就是）说明判据瞎，不是代码对。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64ldmut
mkdir -p $W build
PY=python3

# ── 变异表：file | 原串 | 变异串 ─────────────────────────────
M_FILE=(
  examples/a64ld.mo
  examples/a64ld.mo
  examples/a64ld.mo
  examples/a64ld.mo
  examples/a64ld.mo
  examples/a64ld.mo
  examples/a64as.mo
)
M_FROM=(
  '    if ty == 283 {'
  '            let pgp: i64 = (p / 4096) * 4096;'
  '            let pgs: i64 = (s / 4096) * 4096;'
  '        if sec == 2 { return i; }'
  '    return BASE + NT * 4 + FDO[SFIL[i]] + SOFF[i];'
  '            let lo: i64 = s - (s / 4096) * 4096;'
  '    if RELM == 1 { return 0; }'
)
M_TO=(
  '    if ty == 999 {'
  '            let pgp: i64 = p;'
  '            let pgs: i64 = s;'
  '        if sec == 2 { SSEC[i] = 2; SOFF[i] = off; SFIL[i] = fil; return i; }'
  '    return BASE + NT * 4 + FTW[SFIL[i]] + SOFF[i];'
  '            let lo: i64 = 0;'
  '    if RELM == 0 { return 0; }'
)
M_EXP=(
  cap
  cap
  ident
  cap
  cap
  cap
  cap
)
M_NAME=(
  "M1 不应用 CALL26"
  "M2 adrp 的 P 不做页对齐"
  "M7 adrp 的 S 不做页对齐（数学恒等，预期未捕获）"
  "M3 UNDEF 覆盖已定义（破坏顺序无关）"
  "M4 data 基址误用 text 基址"
  "M5 addlo 用 0 代替低 12 位"
  "M6 -r 模式仍回填 fixup（地址算两次）"
)

# ── 自愈：反向替换，确保开工时源码是干净的 ───────────────────
$PY - "${M_FILE[@]}" -- "${M_FROM[@]}" -- "${M_TO[@]}" <<'PY'
import sys
a=sys.argv[1:]
i1=a.index('--'); i2=a.index('--',i1+1)
files=a[:i1]; frm=a[i1+1:i2]; to=a[i2+1:]
n=0
for f,t,s in zip(files,to,frm):
    d=open(f).read()
    if s in d and t in d:
        d=d.replace(t,s,1); open(f,'w').write(d); n+=1
print("healed=%d" % n)
PY

for f in examples/a64ld.mo examples/a64as.mo; do cp $f build/$(basename $f).ldmut.bak; done

run_test() {
    bash tools/a64ldtest.sh > $W/t.log 2>&1
    echo $?
}

# ── 基线必须全绿 ──
RC=$(run_test)
if [ "$RC" != "0" ]; then
    echo "✗ 基线未通过，拒绝继续（源码或测试本身有问题）"; tail -20 $W/t.log; exit 1
fi
echo "基线: 通过"

i=0
NCAP=0
NMUT=${#M_NAME[@]}
while [ $i -lt $NMUT ]; do
    f=${M_FILE[$i]}; s=${M_FROM[$i]}; t=${M_TO[$i]}
    $PY - "$f" "$s" "$t" <<'PY'
import sys
f,s,t=sys.argv[1],sys.argv[2],sys.argv[3]
d=open(f).read()
assert s in d, "锚点未命中: "+f
assert d.count(s)==1, "锚点不唯一: "+f
open(f,'w').write(d.replace(s,t,1))
PY
    if [ $? != 0 ]; then echo "✗ ${M_NAME[$i]} 变异未生效"; i=$((i+1)); continue; fi
    RC=$(run_test)
    EXP=${M_EXP[$i]}
    if [ "$RC" != "0" ]; then
        NF=$(grep -c '^✗' $W/t.log)
        echo "  ${M_NAME[$i]}: 被捕获（$NF 项变红）"
        NCAP=$((NCAP+1))
        if [ "$EXP" = "ident" ]; then echo "    ↑ 与预期不符：本以为数学恒等"; fi
    else
        if [ "$EXP" = "ident" ]; then
            echo "  ${M_NAME[$i]}: 如预期未被捕获 —— 改了代码但数学上等价，"
            echo "    判据测不出它是**正确**的（imm=(S&A-pgp)/4096 在 S>pgp 时恒等于"
            echo "    正确值，因为低 12 位被整除抹掉）。保留在此，提醒别拿它当有效变异。"
            NCAP=$((NCAP+1))
        else
            echo "✗ ${M_NAME[$i]}: **未被捕获**（判据漏了这条因果链）"
        fi
    fi
    cp build/$(basename $f).ldmut.bak $f
    i=$((i+1))
done

echo "a64ldmut: $NCAP / $NMUT 被捕获"
[ "$NCAP" = "$NMUT" ]
