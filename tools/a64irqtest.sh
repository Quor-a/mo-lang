#!/usr/bin/env bash
# a64irqtest —— 自举 aarch64 的 **抢占式多任务** + **指令中止** 验证
#
# 与 a64mmu 的差别：mmu 版只验了**取数**越界（data abort, EC=0x24）；这一版
# 补上**取指**越界（instruction abort, EC=0x20）和**被中断抢走 CPU**。
#
# 判据分八层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出                抓"根本没产出 / 新助记符没被识别"
#   ② 32 位 load 的编码              抓"ldr w 被编成 64 位"（本轮真缺陷）
#   ③ mov Xd, sp 编成 add 而非 orr   抓"栈顶变成 0"（本轮真缺陷）
#   ④ capstone 第三方反汇编核对       抓"编码自洽但不符合规范"
#   ⑤ 端到端：逐行输出 + 交织关系     抓"编码合法但语义错"
#   ⑥ 两类指令中止各恰好一次          抓"拦了但分不清是哪种错"
#   ⑦ 反向：--tick 0 必须毫无交织     抓"所谓抢占其实是 exit 后的顺序调度"
#   ⑧ 内核栈必须是内核自己登记的那个  抓"抢占用了用户栈"
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64irqtest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0; SKIP=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译汇编器与链接器 ──
cp lib/*.mo $W/
cp examples/a64as.mo $W/test.mo
cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "汇编器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64as.elf
cp $ROOT/examples/a64ld.mo $W/test.mo
rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "链接器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64ld.elf

# ── ① 汇编 + 链接 ──
./a64as.elf -r $ROOT/tools/a64irq/main.s $W/main.o > $W/as.log 2>&1
chk "汇编退出码" "$?" "0"
grep -qi "unknown\|error\|out of range\|bad register" $W/as.log && {
    echo "✗ 汇编报错"; cat $W/as.log; FAILN=$((FAILN+1)); }
./a64ld.elf $W/sys.elf $W/main.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"

# ── ② 32 位 load：`ldr w0, [x1]` 必须是 0xB9400020（size=10）──
#     编成 64 位的话，读 GIC 这类 32 位 MMIO 会顺带吞掉相邻的下一个寄存器。
printf '.text\n_start:\n ldr w0, [x1]\n str w0, [x2]\n' > $W/w.s
./a64as.elf $W/w.s $W/w.elf > $W/w.log 2>&1
chk "32 位 ldr/str 可汇编" "$?" "0"
python3 - $W/w.elf > $W/w.txt <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
words = [struct.unpack_from('<I', d, o)[0] for o in range(0, len(d) - 3, 4)]
print("ldrw", 1 if 0xB9400020 in words else 0)
print("strw", 1 if 0xB9000040 in words else 0)
PY
chk "ldr w 是 32 位编码" "$(grep '^ldrw' $W/w.txt | awk '{print $2}')" "1"
chk "str w 是 32 位编码" "$(grep '^strw' $W/w.txt | awk '{print $2}')" "1"

# ── ③ mov Xd, sp 必须编成 add（0x910003E0），不能是 orr（读 XZR）──
printf '.text\n_start:\n mov x0, sp\n' > $W/sp.s
./a64as.elf $W/sp.s $W/sp.elf > $W/sp.log 2>&1
chk "mov x0, sp 可汇编" "$?" "0"
python3 - $W/sp.elf > $W/sp.txt <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
words = [struct.unpack_from('<I', d, o)[0] for o in range(0, len(d) - 3, 4)]
print("addsp", 1 if 0x910003E0 in words else 0)
print("orr",   1 if 0xAA1F03E0 in words else 0)
PY
chk "mov x0,sp 编成 add" "$(grep '^addsp' $W/sp.txt | awk '{print $2}')" "1"
chk "mov x0,sp 不是 orr" "$(grep '^orr' $W/sp.txt | awk '{print $2}')" "0"

# ── ④ capstone 第三方反汇编核对 ──
if python3 -c "import capstone" 2>/dev/null; then
python3 - $W/main.o > $W/cap.txt <<'PY'
import struct, sys, capstone
d = open(sys.argv[1], 'rb').read()
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
txt = []
for o in range(0, len(d) - 3, 4):
    w = struct.unpack_from('<I', d, o)[0]
    for i in md.disasm(struct.pack('<I', w), 0):
        txt.append(i.mnemonic + ' ' + i.op_str)
s = '\n'.join(txt)
print("br",    1 if 'br ' in s else 0)
print("ldrw",  1 if 'ldr w' in s else 0)
print("msrsp", 1 if 'sp_el0' in s or 'sp_el1' in s else 0)
print("eret",  1 if 'eret' in s else 0)
PY
    for k in br ldrw msrsp eret; do
        v=$(grep "^$k " $W/cap.txt | awk '{print $NF}')
        [ "$v" = "1" ] && PASS=$((PASS+1)) || { echo "✗ capstone 未核对出 $k"; FAILN=$((FAILN+1)); }
    done
else
    echo "· 跳过：capstone 未安装"
    SKIP=$((SKIP+4))
fi

# ── ⑤ ⑥ 端到端（开 MMU + 定时器）──
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 --mmu 1 --tick 512 --steps 400000 > $W/on.txt 2>&1
for line in "MO-IRQ" "ALLDONE" "V OK"; do
    grep -qx "$line" $W/on.txt && PASS=$((PASS+1)) || { echo "✗ 缺输出行 '$line'"; FAILN=$((FAILN+1)); }
done
# 三个任务的每一次迭代都必须出现（少一个就说明计数被抢占弄乱了）
for i in 0 1 2 3 4; do
    grep -qx "A$i" $W/on.txt && PASS=$((PASS+1)) || { echo "✗ 缺 A$i"; FAILN=$((FAILN+1)); }
done
for i in 0 1 2 3; do
    grep -qx "B$i" $W/on.txt && PASS=$((PASS+1)) || { echo "✗ 缺 B$i"; FAILN=$((FAILN+1)); }
done
for i in 0 1; do
    grep -qx "C$i" $W/on.txt && PASS=$((PASS+1)) || { echo "✗ 缺 C$i"; FAILN=$((FAILN+1)); }
done
# 顺序必须是递增的：抢占若毁了上下文，计数会跳号或重复
aseq=$(grep -o "^A[0-9]$" $W/on.txt | tr -d 'A' | tr '\n' ' ')
chk "A 的计数序列" "$aseq" "0 1 2 3 4 "
bseq=$(grep -o "^B[0-9]$" $W/on.txt | tr -d 'B' | tr '\n' ' ')
chk "B 的计数序列" "$bseq" "0 1 2 3 "
# 两类指令中止各恰好一次：权限（跳内核私有页）与转换（跳未映射页）必须能分开
chk "IP 次数" "$(grep -cx 'IP' $W/on.txt)" "1"
chk "IT 次数" "$(grep -cx 'IT' $W/on.txt)" "1"
# 交织：B0 必须排在 A1 之前 —— 没有抢占的话 A 会一口气跑完
la1=$(grep -nx "A1" $W/on.txt | cut -d: -f1)
lb0=$(grep -nx "B0" $W/on.txt | cut -d: -f1)
if [ -n "$lb0" ] && [ -n "$la1" ] && [ "$lb0" -lt "$la1" ]; then
    PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ 没有交织（B0 不在 A1 之前）"; fi
# 栈没混：任一任务的栈标记检查失败都会打出 ?BAD
grep -q "BAD" $W/on.txt && { echo "✗ 出现栈混用 BAD"; FAILN=$((FAILN+1)); } || PASS=$((PASS+1))
# 内核栈：必须是内核自己 msr sp_el1 登记的那个（0x40401800），不是用户栈
ksp=$(grep -o "ksp=0x[0-9a-f]*" $W/on.txt | head -1 | cut -d= -f2)
chk "内核栈" "$ksp" "0x40401800"
# 诊断计数：IRQ 必须真的发生过
irqn=$(grep -o "irq=[0-9]*" $W/on.txt | head -1 | cut -d= -f2)
if [ -n "$irqn" ] && [ "$irqn" -gt 0 ]; then PASS=$((PASS+1)); else
    FAILN=$((FAILN+1)); echo "✗ irq=0（定时器没打进来）"; fi
# **只打一次不算抢占**：内核不发 EOIR 的话第一次 IRQ 之后就再也进不来了，
# 于是 A 一口气跑完、B/C 顺序接上 —— 那也满足"B0 在 A1 之前"，看着照样
# 像交织。所以还要断言 IRQ 的次数（基线 16 次）足够多。
if [ -n "$irqn" ] && [ "$irqn" -ge 8 ]; then PASS=$((PASS+1)); else
    FAILN=$((FAILN+1)); echo "✗ irq=$irqn 太少（只抢占了一次）"; fi
# 轮转间隔：A 的相邻两次迭代之间应当只隔两个任务（A B C 一轮）
la0=$(grep -nx "A0" $W/on.txt | cut -d: -f1)
gap=$((la1 - la0))
if [ "$gap" -le 4 ]; then PASS=$((PASS+1)); else
    FAILN=$((FAILN+1)); echo "✗ A0→A1 隔了 $gap 行（不是一轮轮转）"; fi

# ── ⑦ 反向：关掉定时器，必须毫无交织 ──
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 --mmu 1 --tick 0 --steps 400000 > $W/off.txt 2>&1
grep -qx "A4" $W/off.txt && PASS=$((PASS+1)) || { echo "✗ 关掉定时器后连 A4 都没有"; FAILN=$((FAILN+1)); }
# **不是断言"B0 不出现"**：没有定时器时 A 跑完 exit 后仍会顺序切到 B，
# B/C 照样会跑。判据只能是**顺序** —— A 必须一口气跑完，B0 排在 A4 之后。
# 写成"没有 B0"的话这条会失败，而失败的原因是我把判据写错了，不是代码错。
la4=$(grep -nx "A4" $W/off.txt | cut -d: -f1)
lb0=$(grep -nx "B0" $W/off.txt | cut -d: -f1)
if [ -n "$lb0" ] && [ -n "$la4" ] && [ "$lb0" -gt "$la4" ]; then
    PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ 关掉定时器后 A 仍被切走（B0 不在 A4 之后）"; fi
grep -q "V OK" $W/off.txt && PASS=$((PASS+1)) || { echo "✗ 关掉定时器后没有 V OK"; FAILN=$((FAILN+1)); }

echo "a64irqtest: $PASS 通过 / $FAILN 失败 / $SKIP 跳过"
[ $FAILN -eq 0 ]
