#!/usr/bin/env bash
# a64arithmut —— 证明 a64arithtest 的判据真的在起作用
#
# 做法：把编码器/链接器**故意改坏**，测试必须变红；还原后基线必须变绿。
# 备份放在 build/（项目内）—— /tmp 备份会在沙盒中断时蒸发，届时源码停在
# 变异态而"干净版"也没了（本项目已栽过）。
#
# 关键教训（本轮实测）：改了代码 ≠ 改到了那条因果链。设计变异时要先问
# "改完之后程序行为会变吗"，否则会出现"测试全绿 → 认定未捕获"的假阳性。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
BAK_AS=build/a64as.mo.bak
BAK_LD=build/a64ld.mo.bak
cp examples/a64as.mo $BAK_AS
cp examples/a64ld.mo $BAK_LD
PASS=0; FAILN=0
restore_all() { cp $BAK_AS examples/a64as.mo; cp $BAK_LD examples/a64ld.mo; }

apply() {  # apply <文件> <旧串> <新串>
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()
n = s.count(old)
if n != 1:
    sys.stderr.write("锚点命中 %d 次（应为 1）—— 变异未生效，后续结论无意义\n" % n)
    sys.exit(3)
open(path, 'w', encoding='utf-8').write(s.replace(old, new))
PY
    if [ $? != 0 ]; then echo "✗ 变异未生效: $2"; FAILN=$((FAILN+1)); return 1; fi
    return 0
}

run_mut() {  # run_mut <名字> <文件> <旧串> <新串>
    restore_all
    apply "$2" "$3" "$4" || { restore_all; return; }
    if bash tools/a64arithtest.sh > /tmp/a64arithmut.log 2>&1; then
        echo "✗ $1 未被捕获（测试仍然全绿）"
        FAILN=$((FAILN+1))
    else
        echo "✓ $1 被捕获: $(grep -o '通过 [0-9]* 项，失败 [0-9]* 项' /tmp/a64arithmut.log | tail -1)"
        PASS=$((PASS+1))
    fi
    restore_all
}

# ── 汇编器侧 ──
run_mut "M1 udiv 的 Rn/Rm 互换（12345/100 → 100/12345）" examples/a64as.mo \
    'emit(0x9AC00800 | (rm * 65536) | (rn * 32) | rd);' \
    'emit(0x9AC00800 | (rn * 65536) | (rm * 32) | rd);'

run_mut "M2 msub 的 Ra 字段位置 1024→32" examples/a64as.mo \
    'emit(0x9B008000 | (rm * 65536) | (ra * 1024) | (rn * 32) | rd);' \
    'emit(0x9B008000 | (rm * 65536) | (ra * 32) | (rn * 32) | rd);'

run_mut "M3 lsr 套用 lsl 的 immr 公式" examples/a64as.mo \
    'emit(0xD3400000 | (sh * 65536) | (63 * 1024) | (rn * 32) | rd);' \
    'emit(0xD3400000 | ((64 - sh) % 64 * 65536) | (63 * 1024) | (rn * 32) | rd);'

run_mut "M4 csel 的 cond 字段位置 4096→32" examples/a64as.mo \
    'emit(0x9A800000 | (rm * 65536) | (cd * 4096) | (rn * 32) | rd);' \
    'emit(0x9A800000 | (rm * 65536) | (cd * 32) | (rn * 32) | rd);'

# ── 链接器侧：CONDBR19 的 bit4..0 语义 ──
run_mut "M5 链接器 CONDBR19 只保留低 4 位（cbz x26 → cbz x10）" examples/a64ld.mo \
    'TXT[idx] = (w & 4278190080) | (imm * 32) | (w & 31);' \
    'TXT[idx] = (w & 4278190080) | (imm * 32) | (w & 15);'

# ── 重定位分类：漏了 cbz/cbnz 两个字 ──
run_mut "M6 reltype 不分类 cbz（0xB4）" examples/a64as.mo \
    '    if (w & 4278190080) == 3019898880 { return 280; }' \
    '    if (w & 4278190080) == 3028287487 { return 280; }'

# ── 还原后基线必须变绿 ──
restore_all
if bash tools/a64arithtest.sh > /tmp/a64arithmut.log 2>&1; then
    echo "✓ 还原后基线通过: $(grep -o '通过 [0-9]* 项，失败 [0-9]* 项' /tmp/a64arithmut.log | tail -1)"
    PASS=$((PASS+1))
else
    echo "✗ 还原后基线仍然失败（源码没被正确还原）"; FAILN=$((FAILN+1))
    tail -20 /tmp/a64arithmut.log
fi

echo "变异 $PASS 个被捕获 / $FAILN 个失败"
[ "$FAILN" = "0" ] || exit 1
exit 0
