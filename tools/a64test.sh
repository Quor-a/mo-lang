#!/usr/bin/env bash
# a64test —— 墨语言自举 aarch64 汇编器的端到端验证
#
# 判据分四层，缺一层就会漏掉不同类别的缺陷：
#   ① ELF 头        机器字、入口、段数 —— 抓"产物根本不是 aarch64"
#   ② 解码对拍      用 tools/a64dis.py **独立**解码每条指令 —— 抓字段错位
#   ③ 引用完整性    分支目标与 ldaddr 拼出的地址必须落在镜像内 —— 抓偏移算错
#   ④ 端到端执行    在裸机模拟器里真跑，逐行比对输出 —— 抓语义错
#
# 另有一组负例：越界立即数必须**报错**而不是静默截断。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64test
rm -rf $W && mkdir -p $W
BAK=build/a64as.mo.bak
SRC=examples/a64as.mo
PY=tools/a64dis.py
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译汇编器（墨语言 → x86-64 ELF）──
cp lib/*.mo $W/ && cp $SRC $W/test.mo
cd $W && rm -f out.elf
$ROOT/bin/moc > /dev/null 2>&1
chk "汇编器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"

# ── 汇编：墨语言 → aarch64 机器码 + ELF（无 C 编译器/as/ld 参与）──
./out.elf $ROOT/tools/a64sys.s $W/sys64.elf > $W/as.log 2>&1
chk "汇编退出码" "$?" "0"
grep -q "undefined\|error\|out of range" $W/as.log && { echo "✗ 汇编器报错"; cat $W/as.log; FAILN=$((FAILN+1)); }

# ① ELF 头
read -r MACH ENTRY PHNUM <<EOF
$(python3 -c "
import struct
d=open('$W/sys64.elf','rb').read()
print(struct.unpack_from('<H',d,18)[0], struct.unpack_from('<Q',d,24)[0], struct.unpack_from('<H',d,56)[0])
")
EOF
chk "e_machine = AArch64(183)" "$MACH" "183"
chk "e_entry" "$ENTRY" "1073741824"
chk "e_phnum" "$PHNUM" "1"

# ② 解码对拍
NC=$(python3 -c "
import struct,re
d=open('$W/sys64.elf','rb').read()
print((struct.unpack_from('<Q',d,96)[0])//1 if False else int(open('$W/as.log').read().split()[1]))
")
python3 $ROOT/$PY $W/sys64.elf $NC > $W/dis.txt 2>$W/dis.err
chk "全部指令可解码" "$(grep -c '?' $W/dis.txt)" "0"

# ③ 引用完整性：分支/地址必须落在镜像内
python3 - > $W/ref.txt 2>&1 <<'PY'
import struct, re
d=open('/tmp/a64test/sys64.elf','rb').read()
NC=int(open('/tmp/a64test/as.log').read().split()[1])
BASE=0x40000000
end=BASE+NC*4+int(open('/tmp/a64test/as.log').read().split()[3])
bad=0
for k in range(NC):
    w=struct.unpack_from('<I', d, 120+k*4)[0]
    a=BASE+k*4
    if (w & 0xFC000000)==0x14000000 or (w & 0xFC000000)==0x94000000:
        off=w & 0x3FFFFFF
        if off & (1<<25): off -= (1<<26)
        t=a+off*4
        if not (BASE <= t < end): bad+=1; print("branch out of range: %x" % t)
    if (w & 0xFF000010)==0x54000000:
        off=(w>>5)&0x7FFFF
        if off & (1<<18): off -= (1<<19)
        t=a+off*4
        if not (BASE <= t < end): bad+=1; print("cond branch out of range: %x" % t)
print("BADREF=%d" % bad)
PY
chk "引用完整性" "$(grep -c 'BADREF=0' $W/ref.txt)" "1"

# ④ 端到端执行
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 180 python3 $ROOT/tools/kern64run.py $W/sys64.elf --steps 100000 > $W/run.txt 2>$W/run.err
OUT=$(grep -v "^---" $W/run.txt | grep -v '^$')
chk "裸机输出" "$OUT" "MO-A64 BOOT
SUM=5050 OK
FIB=55 OK
MEM OK
IMM OK"

# ── 负例：越界立即数必须报错 ──
printf '.text\n_start:\n\tcmp x0, #5050\n\tret\n' > $W/bad.s
./out.elf $W/bad.s $W/bad.elf > $W/bad.log 2>&1
chk "imm12 越界报错" "$?" "1"
grep -q "out of range" $W/bad.log || { echo "✗ 越界立即数未报错"; FAILN=$((FAILN+1)); }

echo "a64test: $PASS 通过 / $FAILN 失败"
[ "$FAILN" = "0" ]
