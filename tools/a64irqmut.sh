#!/usr/bin/env bash
# a64irqmut —— 证明 a64irq 的判据真的能抓到缺陷
#
# 每个变异只改 main.s 的一处（精确子串替换），然后重跑端到端。
# **判据不复用 a64irqtest 的全套**（那要重新编译汇编器/链接器，一个变异
# 一两分钟、六个就跑不完），而是只跑端到端 + 那几条与因果链直接相关的断言：
#   交织 · A 的计数序列 · IP 恰好一次 · IT 恰好一次 · 无栈混用 · ALLDONE
#
# 判据只写"必须失败"，不写"必须失败几项" —— 后者会把"改了代码但没改到
# 因果链"误判成通过，也会在断言增减时莫名其妙地红。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=$ROOT/tools/a64irq/main.s
W=/tmp/a64irqmut
rm -rf $W && mkdir -p $W
BAK=$W/main.s.bak
cp $SRC $BAK
# 自愈：开工前先按"变异→干净"方向反向替换一遍，万一上一轮的还原没跑完
python3 - $BAK <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
fix = [("        # 不写 EOIR\n", ""),
       ("        mov     x9, x9\n", "        add     x9, x9, #1\n"),
       ("        mov     x18, #128\n", "        mov     x18, #248\n"),
       ("        # 不切用户栈\n", "        msr     sp_el0, x14\n"),
       ("        b       iabt_perm\n", "        b.ge    iabt_perm\n"),
       ("        # 不杀任务\n", "        bl      kill_cur\n")]
for a, b in fix:
    if a in s:
        s = s.replace(a, b)
open(p, 'w').write(s)
PY
cp $BAK $SRC

# ── 只编译一次汇编器/链接器 ──
cp lib/*.mo $W/
cp examples/a64as.mo $W/test.mo
cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
cp out.elf $W/a64as.elf
cp $ROOT/examples/a64ld.mo $W/test.mo
rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
cp out.elf $W/a64ld.elf

run_one() {
    rm -f $W/main.o $W/sys.elf
    ./a64as.elf -r $SRC $W/main.o > /dev/null 2>&1 || { echo "ASFAIL"; return; }
    ./a64ld.elf $W/sys.elf $W/main.o > /dev/null 2>&1 || { echo "LDFAIL"; return; }
    timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 --mmu 1 \
        --tick 512 --steps 400000 > $W/out.txt 2>&1
    python3 - $W/out.txt <<'PY'
import sys, re
t = open(sys.argv[1]).read()
lines = t.split('\n')
def ln(x):
    for i, l in enumerate(lines):
        if l == x: return i
    return -1
bad = 0
a = [l[1:] for l in lines if re.fullmatch(r'A[0-9]', l)]
if a != ['0', '1', '2', '3', '4']: bad += 1
b = [l[1:] for l in lines if re.fullmatch(r'B[0-9]', l)]
if b != ['0', '1', '2', '3']: bad += 1
if not (0 <= ln('B0') < ln('A1')): bad += 1
if not (0 < ln('A1') - ln('A0') <= 4): bad += 1
m = re.search(r'irq=(\d+)', t)
if not (m and int(m.group(1)) >= 8): bad += 1
if sum(1 for l in lines if l == 'IP') != 1: bad += 1
if sum(1 for l in lines if l == 'IT') != 1: bad += 1
if 'BAD' in t: bad += 1
if 'ALLDONE' not in t: bad += 1
if 'V OK' not in t: bad += 1
print(bad)
PY
}

echo "== 基线 =="
BAD0=$(run_one)
if [ "$BAD0" = "0" ]; then echo "基线通过"; else echo "✗ 基线就红了（$BAD0 项）——先修好再谈变异"; cp $BAK $SRC; exit 1; fi

apply() {
python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
assert old in s, "锚点没命中: %r" % old[:40]
s = s.replace(old, new, 1)
open(path, 'w').write(s)
PY
}

MUT=0; CAUGHT=0
try() {
    name=$1; old=$2; new=$3
    cp $BAK $SRC
    if ! apply $SRC "$old" "$new"; then echo "✗ $name 锚点没命中"; cp $BAK $SRC; return; fi
    # 确认真的改到了（写回后读一遍，沙盒文件系统偶有写入可见性延迟）
    if ! grep -qF "$new" $SRC; then echo "✗ $name 改完没生效"; cp $BAK $SRC; return; fi
    MUT=$((MUT+1))
    n=$(run_one)
    if [ "$n" = "0" ]; then
        echo "✗ M$MUT $name 未被捕获（判据全绿）"
    else
        CAUGHT=$((CAUGHT+1)); echo "· M$MUT $name 被捕获（$n 项红）"
    fi
    cp $BAK $SRC
}

try "IRQ 不应答 EOIR" "        str     w10, [x9]" "        # 不写 EOIR"
try "调度器不推进 cur" "        add     x9, x9, #1" "        mov     x9, x9"
try "只保存前 16 个寄存器" "        mov     x18, #248               # 31 个寄存器 × 8" "        mov     x18, #128"
try "切换时不换用户栈" "        msr     sp_el0, x14" "        # 不切用户栈"
try "两类中止不分（只报权限）" "        b.ge    iabt_perm" "        b       iabt_perm"
try "中止后不杀任务" "        bl      kill_cur" "        # 不杀任务"

cp $BAK $SRC
echo "a64irqmut: $CAUGHT / $MUT 被捕获"
[ "$CAUGHT" -eq "$MUT" ]
