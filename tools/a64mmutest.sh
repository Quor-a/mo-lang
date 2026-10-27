#!/usr/bin/env bash
# a64mmutest —— 自举 aarch64 的 **MMU** 验证：隔离由页表说了算
#
# 与 a64svc 的差别：svc 版里"用户碰不到内核"是**模拟器的约定**；这一版由
# 页表描述符的 AP[2:1] / UXN 决定，用户越界会真的触发 data abort（EC=0x24）。
#
# 判据分七层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出                  抓"根本没产出 / 新助记符没被识别"
#   ② 新增系统寄存器与屏障的**编码**真的出现在产物里
#                                      抓"助记符静默落到别的分支"
#   ③ capstone 第三方反汇编核对        抓"编码自洽但不符合规范"
#   ④ 端到端裸机执行：逐行输出          抓"编码合法但语义错"
#   ⑤ 模拟器诊断计数（svc/eret）        抓"走的是别的路径、碰巧也对"
#   ⑥ 退出前校验三处内存**没被改掉**    抓"拦了但值还是被写了"
#   ⑦ 反向：关掉 MMU 必须出现 V BAD     抓"这些性质其实是程序自己碰巧做到的"
#
# 期望的计数不是照抄实现，而是从源码结构独立数出来的：
#   4 次 svc = U OK + R OK + UDONE + exit
#   8 次 eret = 4 次 svc 返回 + 4 次 abort 返回（PF1/PF2/PF2/TR3）
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64mmutest
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
./a64as.elf -r $ROOT/tools/a64mmu/main.s $W/main.o > $W/as.log 2>&1
chk "汇编退出码" "$?" "0"
grep -qi "unknown\|error\|out of range\|bad register" $W/as.log && {
    echo "✗ 汇编报错"; cat $W/as.log; FAILN=$((FAILN+1)); }
./a64ld.elf $W/sys.elf $W/main.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"

# ①b 新系统寄存器必须被**识别**：不认会 rc≠0。少了这条，"页表根本没建成"
#     和"页表建了但模拟器没看"就分不开。
printf '.text\n_start:\n msr ttbr0_el1, x0\n msr tcr_el1, x1\n msr mair_el1, x2\n msr sctlr_el1, x3\n dsb\n isb\n' > $W/sr.s
./a64as.elf $W/sr.s $W/sr.elf > $W/sr.log 2>&1
chk "MMU 系统寄存器被识别" "$?" "0"

# ── ② 产物里每条关键编码真的出现 ──
python3 - $W/main.o > $W/insn.txt <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
words = [struct.unpack_from('<I', d, o)[0] for o in range(0, len(d) - 3, 4)]
def has(lo, hi):
    return any(lo <= w <= hi for w in words)
print("ttbr0", 1 if has(0xD5182000, 0xD518201F) else 0)
print("tcr",   1 if has(0xD5182040, 0xD518205F) else 0)
print("mair",  1 if has(0xD518A200, 0xD518A21F) else 0)
print("sctlr", 1 if has(0xD5181000, 0xD518101F) else 0)
print("dsb",   1 if 0xD5033F9F in words else 0)
print("isb",   1 if 0xD5033FDF in words else 0)
PY
grep -q "^ttbr0 1" $W/insn.txt || { echo "✗ 产物里没有 msr ttbr0_el1"; FAILN=$((FAILN+1)); }
grep -q "^tcr 1"   $W/insn.txt || { echo "✗ 产物里没有 msr tcr_el1";   FAILN=$((FAILN+1)); }
grep -q "^mair 1"  $W/insn.txt || { echo "✗ 产物里没有 msr mair_el1";  FAILN=$((FAILN+1)); }
grep -q "^sctlr 1" $W/insn.txt || { echo "✗ 产物里没有 msr sctlr_el1"; FAILN=$((FAILN+1)); }
grep -q "^dsb 1"   $W/insn.txt || { echo "✗ 产物里没有 dsb";           FAILN=$((FAILN+1)); }
grep -q "^isb 1"   $W/insn.txt || { echo "✗ 产物里没有 isb";           FAILN=$((FAILN+1)); }
[ $FAILN -eq 0 ] && PASS=$((PASS+6))

# ── ③ capstone 第三方反汇编核对（缺库则记为跳过，不假装通过）──
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
for name in ("ttbr0_el1", "tcr_el1", "mair_el1", "sctlr_el1", "dsb sy", "isb"):
    print(name, 1 if name in s else 0)
PY
    for k in ttbr0_el1 tcr_el1 mair_el1 sctlr_el1 "dsb sy" isb; do
        # 用 $NF 而不是 $2：助记符里带空格时（"dsb sy"）字段会错位，
        # 错位后取到的是助记符本身，判定恒为"没核对出"—— 假失败。
        v=$(grep "^$k " $W/cap.txt | awk '{print $NF}')
        [ "$v" = "1" ] && PASS=$((PASS+1)) || { echo "✗ capstone 未核对出 $k"; FAILN=$((FAILN+1)); }
    done
else
    echo "· 跳过：capstone 未安装，未做第三方反汇编核对"
    SKIP=$((SKIP+6))
fi

# ── ④ ⑤ ⑥ 端到端（开 MMU）──
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 --mmu 1 > $W/on.txt 2>&1
for line in "MO-MMU" "U OK" "R OK" "PF1" "TR3" "UDONE" "DONE" "V OK" "N4"; do
    grep -qx "$line" $W/on.txt && PASS=$((PASS+1)) || { echo "✗ 缺输出行 '$line'"; FAILN=$((FAILN+1)); }
done
# PF2 必须**恰好两次**：只读页写一次、内核私有页读写两次里的两次
c=$(grep -cx "PF2" $W/on.txt)
chk "PF2 次数" "$c" "2"
# 关键反向：V BAD 绝不能出现（出现说明拦了但值还是被改掉）
grep -q "V BAD" $W/on.txt && { echo "✗ 出现 V BAD（内存被改掉）"; FAILN=$((FAILN+1)); } || PASS=$((PASS+1))
# 诊断计数
svc=$(grep -o "svc=[0-9]*" $W/on.txt | head -1 | cut -d= -f2)
chk "svc 次数" "$svc" "4"
eret=$(grep -o "eret=[0-9]*" $W/on.txt | head -1 | cut -d= -f2)
chk "eret 次数" "$eret" "8"

# ── ⑦ 反向：关掉 MMU，用户写入必须真的生效（V BAD 必须出现）──
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --exc 1 --mmu 0 > $W/off.txt 2>&1
grep -q "V BAD" $W/off.txt && PASS=$((PASS+1)) || { echo "✗ 关掉 MMU 后没有 V BAD（隔离其实来自别处）"; FAILN=$((FAILN+1)); }
grep -q "PF1" $W/off.txt && { echo "✗ 关掉 MMU 后仍有 PF1"; FAILN=$((FAILN+1)); } || PASS=$((PASS+1))
grep -qx "U OK" $W/off.txt && PASS=$((PASS+1)) || { echo "✗ 关掉 MMU 后连 U OK 都没了"; FAILN=$((FAILN+1)); }

echo "a64mmutest: $PASS 通过 / $FAILN 失败 / $SKIP 跳过"
[ $FAILN -eq 0 ]
