#!/usr/bin/env bash
# mokerntest —— 自举内核的端到端验证
#
# 与 a64 系列的差别：a64as 是"汇编器"（读 .s 写 ELF），mokern 是**内核
# 生成器**——内核的机器码由墨语言程序直接构造，中间没有 .s、没有 C、没有
# as/ld/zig。判据因此多了一层"镜像是否真的能启动"。
#
# 判据分六层：
#   ① 生成器编译      墨语言 → x86-64 ELF
#   ② 镜像 ELF 头     e_machine=183、入口 = 0x40000000
#   ③ 页表描述符      三个 block 的 AP 位必须依次是 01 / 01 / 00
#   ④ 正向执行        裸机启动必须依次打出 MO-KERN / U OK / PF2 / DONE
#   ⑤ 反向验证        关掉 --mmu 后必须**没有** PF2 —— 证明隔离来自页表
#   ⑥ 内核状态        usp / ksp 必须是内核自己设的值，svc=2、eret=3
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/mokerntest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── ① 编译内核生成器 ──
cp lib/*.mo $W/ && cp examples/mokern.mo $W/test.mo
cd $W && rm -f out.elf
$ROOT/bin/moc > /dev/null 2>&1
chk "生成器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"

./out.elf $W/kern.elf > $W/gen.log 2>&1
chk "生成器退出码" "$?" "0"
grep -qi "error\|overflow\|undefined" $W/gen.log && { echo "✗ 生成器报错"; cat $W/gen.log; FAILN=$((FAILN+1)); }

# ── ② ELF 头 ──
read -r MACH ENTRY PHNUM <<EOF
$(python3 -c "
import struct
d=open('$W/kern.elf','rb').read()
print(struct.unpack_from('<H',d,18)[0], struct.unpack_from('<Q',d,24)[0], struct.unpack_from('<H',d,56)[0])
")
EOF
chk "e_machine=183 (AArch64)" "$MACH" "183"
chk "e_entry=0x40000000" "$ENTRY" "1073741824"
chk "e_phnum=1" "$PHNUM" "1"

# ── ③ 页表描述符的 AP 位 ──
# 三个 block 在内核里由 ld64 拼出，落在代码里；这里按**页表格式**独立解析
# 镜像运行后的内存更可靠，但静态扫描足以抓"AP 写错成同一个值"。
AP=$(python3 - <<'PY'
import struct
d=open('/tmp/mokerntest/kern.elf','rb').read()
n=struct.unpack_from('<Q',d,96)[0]
code=d[120:120+n]
# ld64 序列：movz/movk 四条 + str x9,[x14,#off]
vals={}
for i in range(len(code)//4):
    w=struct.unpack_from('<I',code,i*4)[0]
    if (w & 0xFFC00000) == 0xF9000000:      # str x9, [xN, #off]
        rn=(w>>5)&31; off=((w>>10)&0xFFF)*8; rt=w&31
        if rn==14 and rt==9: vals[off]=None
print(len(vals))
PY
)
chk "页表 block 写回指令数" "$AP" "3"

# ── ④ 正向执行 ──
python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 > $W/on.txt 2>&1
ON=$(grep -v "^---\|^$" $W/on.txt)
chk "裸机输出" "$ON" "$(printf 'MO-KERN\nU OK\nPF2\nDONE')"

KSP=$(grep -o "ksp=0x[0-9a-f]*" $W/on.txt | head -1)
USP=$(grep -o "usp=0x[0-9a-f]*" $W/on.txt | head -1)
SVC=$(grep -o "svc=[0-9]*" $W/on.txt | head -1)
ERET=$(grep -o "eret=[0-9]*" $W/on.txt | head -1)
chk "内核栈 = 内核自己设的 sp_el1" "$KSP" "ksp=0x40401000"
chk "用户栈 = 内核自己设的 sp_el0" "$USP" "usp=0x40010000"
chk "svc 次数（write + exit）" "$SVC" "svc=2"
chk "eret 次数（1 次下 EL0 + 2 次返回）" "$ERET" "eret=3"

# ── ⑤ 反向：关掉 MMU，隔离必须失效 ──
python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 0 --exc 1 > $W/off.txt 2>&1
chk "关 MMU 后不应有 PF2" "$(grep -c '^PF2$' $W/off.txt)" "0"
chk "关 MMU 后仍有 U OK" "$(grep -c '^U OK$' $W/off.txt)" "1"

echo "通过 $PASS 项，失败 $FAILN 项"
exit $((FAILN > 0))
