#!/usr/bin/env bash
# a64svctest —— 自举 aarch64 的**特权级分离**（EL1 内核 + EL0 用户 + svc）验证
#
# 判据分六层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出              抓"根本没产出 / 新助记符没被识别"
#   ② 产物里 svc/eret/msr/mrs 的**编码**真的出现
#                                  抓"助记符静默落到别的分支"
#   ③ 向量表 2KB 对齐 + 向量在 VBAR+0x400
#                                  抓"对齐没生效"（错位后跑飞却不报错）
#   ④ 端到端裸机执行 + 逐行输出     抓"指令合法但语义错"
#   ⑤ 模拟器诊断计数（svc/trap/eret/uviol）
#                                  抓"走的是别的路径、碰巧也对"
#   ⑥ 反向：关掉异常模型必须**没有输出**
#                                  抓"这些性质其实是程序自己碰巧做到的"
#
# 期望的模拟器计数不是照抄实现，而是从源码结构独立数出来的：
#   9 次 svc = 7 次 uputs + 1 次越界 write + 1 次 exit
#   3 次 trap = vbar_el1 / tpidr_el1 / esr_el1 三条特权指令
#   12 次 eret = 9 + 3（每次陷入各返回一次）
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64svctest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译汇编器与链接器（墨语言 → x86-64 ELF）──
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
./a64as.elf -r $ROOT/tools/a64svc/main.s $W/main.o > $W/as.log 2>&1
chk "汇编退出码" "$?" "0"
grep -qi "unknown\|error\|out of range" $W/as.log && {
    echo "✗ 汇编报错"; cat $W/as.log; FAILN=$((FAILN+1)); }
./a64ld.elf $W/sys.elf $W/main.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"

# ①b 新助记符 sp_el1 必须被**识别**：未知系统寄存器会 rc≠0，
#     不加这条的话"内核栈没按内核意图设置"永远测不出来。
printf '.text\n_start:\n msr sp_el1, x0\n' > $W/sp.s
./a64as.elf $W/sp.s $W/sp.elf > $W/sp.log 2>&1
chk "msr sp_el1 被识别" "$?" "0"

# ── ② 产物里每条关键指令的编码真的出现 ──
python3 - $W/main.o > $W/insn.txt <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
shoff = struct.unpack_from('<Q', d, 40)[0]
shnum = struct.unpack_from('<H', d, 60)[0]
shstr = struct.unpack_from('<H', d, 62)[0]
stro = struct.unpack_from('<Q', d, shoff+shstr*64+24)[0]
sec = {}
for i in range(shnum):
    b = shoff + i*64
    nm = d[stro+struct.unpack_from('<I', d, b)[0]:]
    nm = nm[:nm.index(0)].decode()
    sec[nm] = (struct.unpack_from('<Q', d, b+24)[0],
               struct.unpack_from('<Q', d, b+32)[0])
off, sz = sec['.text']
words = [struct.unpack_from('<I', d, off+k)[0] for k in range(0, sz, 4)]
# svc #0 = 0xD4000001；eret = 0xD69F03E0
print("svc", sum(1 for w in words if (w & 0xFFE0001F) == 0xD4000001))
print("eret", sum(1 for w in words if w == 0xD69F03E0))
# MSR (register) 底字 0xD5100000 | (sysreg<<5)：w>>20 恒为 0xD51
print("msr", sum(1 for w in words if (w >> 20) == 0xD51))
# MRS 同理恒为 0xD53
print("mrs", sum(1 for w in words if (w >> 20) == 0xD53))
# 用户态那次直写 UART 用的 strb：0x39000000 | ...（size=0, opc=0）
print("strb", sum(1 for w in words if (w & 0xFFC00000) == 0x39000000))
# 符号表：vectors 必须 2KB 对齐
soff, ssz = sec['.symtab']
stroff = struct.unpack_from('<I', d, shoff +
    [i for i in range(shnum)
     if d[stro+struct.unpack_from('<I', d, shoff+i*64)[0]:]
     .split(b'\0')[0] == b'.strtab'][0]*64 + 40)[0]
sd = d[sec['.strtab'][0]:sec['.strtab'][0]+sec['.strtab'][1]]
for o in range(0, ssz, 24):
    nm = sd[struct.unpack_from('<I', d, soff+o)[0]:].split(b'\0')[0].decode()
    if nm == 'vectors':
        print("vectors", struct.unpack_from('<Q', d, soff+o+8)[0] & 0x7FF)
        break
PY
# 期望条数是**从源码数出来的**：svc 3 处（uputs / 越界 write / exit）、
# eret 2 处（_start 落 EL0 / 异常返回）、msr 8 处、mrs 4 处、strb 3 处。
chk "svc 出现在产物里" "$(awk '$1=="svc"{print $2}' $W/insn.txt)" "3"
chk "eret 出现在产物里" "$(awk '$1=="eret"{print $2}' $W/insn.txt)" "2"
chk "msr 出现在产物里" "$(awk '$1=="msr"{print $2}' $W/insn.txt)" "8"
chk "mrs 出现在产物里" "$(awk '$1=="mrs"{print $2}' $W/insn.txt)" "4"
chk "strb 出现在产物里" "$(awk '$1=="strb"{print $2}' $W/insn.txt)" "3"

# ── ③ 向量表必须 2KB 对齐（VBAR 的硬件要求）──
chk "vectors 2KB 对齐" "$(awk '$1=="vectors"{print $2}' $W/insn.txt)" "0"

# ── ④ 端到端裸机执行 ──
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 > $W/out.txt 2> $W/diag.txt
chk "裸机运行" "$?" "0"
for line in "MO-SVC" "W OK" "P OK" "T OK" "M OK" "R OK" "U OK" "EXIT"; do
    chk "输出含 $line" "$(grep -c "^$line\$" $W/out.txt)" "1"
done
# 三条特权指令各被认出一次（vbar_el1 / tpidr_el1 / esr_el1）
chk "TRAP 出现 3 次" "$(grep -c '^TRAP$' $W/out.txt)" "3"
chk "VBAR OK 出现 3 次" "$(grep -c '^VBAR OK$' $W/out.txt)" "3"
# 越界指针被拒 → 不该打印 BAD
chk "无 BAD" "$(grep -c '^BAD\$' $W/out.txt)" "0"
# 用户直写 UART 无效：那个 'X' 会紧跟在 U OK 前面。
# 注意 EXIT 里本来就有个 X，所以不能只查"含 X 的行数"。
chk "无 XU OK（EL0 碰不到硬件）" "$(grep -c 'XU OK' $W/out.txt)" "0"
chk "X 只出现在 EXIT 里" "$(grep -c 'X' $W/out.txt)" "1"

# ── ⑤ 模拟器诊断计数 ──
get() { sed -n 's/.*'"$1"'=\([-0-9a-fx]*\).*/\1/p' $W/diag.txt | head -1; }
chk "svc 次数" "$(get ' svc')" "9"
chk "trap 次数" "$(get ' trap')" "3"
chk "eret 次数" "$(get ' eret')" "12"
chk "用户违规访问硬件次数" "$(get 'uviol')" "1"
# 内核栈与用户栈必须是**两个**栈，且相距正好一个栈（.bss 里各 4096）
python3 - $W/diag.txt > $W/stack.txt <<'PY'
import sys, re
s = open(sys.argv[1]).read()
u = int(re.search(r'usp=(0x[0-9a-f]+)', s).group(1), 16)
k = int(re.search(r'ksp=(0x[0-9a-f]+)', s).group(1), 16)
print("diff", u - k)
PY
chk "内核栈 ≠ 用户栈（相距 4096）" "$(awk '$1=="diff"{print $2}' $W/stack.txt)" "4096"

# ── ⑥ 反向：关掉异常模型必须没有输出 ──
#     没有这一条，"隔离"可能只是程序自己碰巧做到的。
timeout 120 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 0 --steps 200000 \
    > $W/out0.txt 2> /dev/null
chk "关掉异常模型则无输出" "$(wc -c < $W/out0.txt | tr -d ' ')" "0"

echo "通过 $PASS 项，失败 $FAILN 项"
[ "$FAILN" = "0" ] || { echo "--- out.txt ---"; cat $W/out.txt; echo "--- diag ---"; cat $W/diag.txt; exit 1; }
exit 0
