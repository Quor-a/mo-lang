#!/usr/bin/env bash
# a64mut —— 证明 a64test 的四层判据真的在起作用
#
# 做法：把编码器**故意改坏**，测试必须变红；还原后基线必须变绿。
# 备份放在 build/（项目内）—— /tmp 备份会在沙盒中断时蒸发，
# 届时源码停在变异态而"干净版"也没了（本项目已栽过）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=examples/a64as.mo
BAK=build/a64as.mo.bak
cp $SRC $BAK
PASS=0; FAILN=0

apply() {  # apply <名字> <旧串> <新串>
    python3 - "$2" "$3" <<'PY'
import sys
old, new = sys.argv[1], sys.argv[2]
p = 'examples/a64as.mo'
s = open(p).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("锚点命中 %d 次（应为 1）—— 变异未生效，后续结论无意义\n" % n)
    sys.exit(3)
open(p,'w').write(s.replace(old, new))
PY
    if [ $? != 0 ]; then echo "✗ $1 变异未生效"; FAILN=$((FAILN+1)); return 1; fi
    return 0
}

run_mut() {  # run_mut <名字> <旧串> <新串>
    cp $BAK $SRC
    apply "$1" "$2" "$3" || { cp $BAK $SRC; return; }
    if bash tools/a64test.sh > /tmp/a64mut.log 2>&1; then
        echo "✗ $1 未被捕获（测试仍然全绿）"
        FAILN=$((FAILN+1))
    else
        echo "✓ $1 被捕获: $(grep -o '[0-9]* 通过 / [0-9]* 失败' /tmp/a64mut.log | tail -1)"
        PASS=$((PASS+1))
    fi
    cp $BAK $SRC
}

run_mut "M1 movz 的 imm16 移位 32→16" \
    'emit(0xD2800000 | (hw * 2097152) | (im * 32) | rd);' \
    'emit(0xD2800000 | (hw * 2097152) | (im * 16) | rd);'
run_mut "M2 ldr 偏移不做 8 字节缩放" \
    'emit(0xF9400000 | ((off / 8) * 1024) | (rn * 32) | rd);' \
    'emit(0xF9400000 | (off * 1024) | (rn * 32) | rd);'
run_mut "M3 b.cond 的 imm19 移位写错" \
    'CODE[ci] = CODE[ci] | ((d & 524287) * 32);' \
    'CODE[ci] = CODE[ci] | ((d & 524287) * 1024);'
run_mut "M4 去掉 imm12 越界检查" \
    'if v > 4095 { fail("immediate out of range (imm12: 0..4095)"); return 0; }' \
    'if v > 4095000 { fail("immediate out of range (imm12: 0..4095)"); return 0; }'

cp $BAK $SRC
echo "--- 基线 ---"
if bash tools/a64test.sh > /tmp/a64mut.log 2>&1; then
    echo "✓ 基线通过: $(grep -o '[0-9]* 通过 / [0-9]* 失败' /tmp/a64mut.log | tail -1)"
    PASS=$((PASS+1))
else
    echo "✗ 基线未通过（源码可能停在变异态）"; cat /tmp/a64mut.log | tail -5; FAILN=$((FAILN+1))
fi
echo "a64mut: $PASS 捕获 / $FAILN 未捕获"
[ "$FAILN" = "0" ]
