#!/usr/bin/env bash
# a64ldtest —— 墨语言自举 AArch64 **链接器**的端到端验证
#
# 判据分六层，缺一层就漏掉不同类别的缺陷：
#   ① 目标文件是 ET_REL          抓"根本没产出可重定位文件"
#   ② 符号表含 SHN_UNDEF         抓"外部引用没被登记"
#   ③ 重定位类型是真规范值       抓"用了私有编号，别人按规范读不懂"
#   ④ 链接产物的重定位已被应用   抓"链接器什么都没做，却假装成功"
#   ⑤ 链接顺序无关               抓"符号解析依赖输入次序"
#   ⑥ 端到端执行 + 负例          抓"算错但产物仍可执行"
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64ldtest
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

# ── 汇编三个独立模块 ──
for m in lib calc main; do
    ./a64as.elf -r $ROOT/tools/a64ld/$m.s $W/$m.o > $W/$m.aslog 2>&1
    chk "汇编 $m.s" "$?" "0"
done

# ① 目标文件是 ET_REL
ETYPE=$(python3 -c "
import struct
d=open('$W/lib.o','rb').read()
print(struct.unpack_from('<H',d,16)[0])
")
chk "e_type = ET_REL(1)" "$ETYPE" "1"

# ② / ③ 用独立解析器读符号表与重定位表
python3 - > $W/obj.txt 2>&1 <<'PY'
import struct
def secs(d):
    shoff=struct.unpack_from('<Q',d,40)[0]
    shnum=struct.unpack_from('<H',d,60)[0]
    shstr=struct.unpack_from('<H',d,62)[0]
    stro=struct.unpack_from('<Q',d,shoff+shstr*64+24)[0]
    out={}
    for i in range(shnum):
        b=shoff+i*64
        nm=d[stro+struct.unpack_from('<I',d,b)[0]:]
        nm=nm[:nm.index(0)].decode()
        out[nm]=dict(type=struct.unpack_from('<I',d,b+4)[0],
                     off=struct.unpack_from('<Q',d,b+24)[0],
                     size=struct.unpack_from('<Q',d,b+32)[0],
                     link=struct.unpack_from('<I',d,b+40)[0])
    return out,d

def syms(d,s):
    strb=d if False else None
    shoff=struct.unpack_from('<Q',d,40)[0]
    stro=struct.unpack_from('<Q',d,shoff+s['.symtab']['link']*64+24)[0]
    out=[]
    for k in range(1, s['.symtab']['size']//24):
        e=s['.symtab']['off']+k*24
        nmoff=struct.unpack_from('<I',d,e)[0]
        nm=d[stro+nmoff:]
        nm=nm[:nm.index(0)].decode()
        out.append((nm, struct.unpack_from('<H',d,e+6)[0]))
    return out

def relas(d,s):
    out=[]
    for k in range(s['.rela.text']['size']//24):
        e=s['.rela.text']['off']+k*24
        info=struct.unpack_from('<Q',d,e+8)[0]
        out.append(info & 0xFFFFFFFF)
    return out

d=open('/tmp/a64ldtest/lib.o','rb').read(); s,_=secs(d)
print("LIB_UNDEF=%d" % sum(1 for n,sh in syms(d,s) if sh==0))
print("LIB_PUTS_SHNDX=%d" % [sh for n,sh in syms(d,s) if n=='puts'][0])
d=open('/tmp/a64ldtest/main.o','rb').read(); s,_=secs(d)
sy=dict((n,sh) for n,sh in syms(d,s))
print("MAIN_PUTS_UNDEF=%d" % (1 if sy.get('puts')==0 else 0))
print("MAIN_START_SHNDX=%d" % sy.get('_start',-1))
print("MAIN_RELTYPES=%s" % ",".join(str(t) for t in sorted(set(relas(d,s)))))
d=open('/tmp/a64ldtest/calc.o','rb').read(); s,_=secs(d)
print("CALC_RELTYPES=%s" % ",".join(str(t) for t in sorted(set(relas(d,s)))))
PY
chk "lib.o 无未定义符号" "$(grep -c 'LIB_UNDEF=0' $W/obj.txt)" "1"
chk "lib.o 中 puts 在 .text(1)" "$(grep 'LIB_PUTS_SHNDX=' $W/obj.txt)" "LIB_PUTS_SHNDX=1"
chk "main.o 中 puts 是 UNDEF" "$(grep 'MAIN_PUTS_UNDEF=' $W/obj.txt)" "MAIN_PUTS_UNDEF=1"
chk "main.o 中 _start 在 .text" "$(grep 'MAIN_START_SHNDX=' $W/obj.txt)" "MAIN_START_SHNDX=1"
# 275 ADR_PREL_PG_HI21 · 277 ADD_ABS_LO12_NC · 280 CONDBR19 · 283 CALL26
chk "main.o 重定位类型" "$(grep 'MAIN_RELTYPES=' $W/obj.txt)" "MAIN_RELTYPES=275,277,280,282,283"
chk "calc.o 重定位类型" "$(grep 'CALC_RELTYPES=' $W/obj.txt)" "CALC_RELTYPES=275,277,280"

# ── 链接 ──
./a64ld.elf $W/sys.elf $W/main.o $W/lib.o $W/calc.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"
grep -q "undefined\|duplicate\|cannot" $W/ld.log && { echo "✗ 链接器报错"; cat $W/ld.log; FAILN=$((FAILN+1)); }
NR=$(grep -o '[0-9]* relocs' $W/ld.log | cut -d' ' -f1)
chk "重定位条数 > 0" "$([ "${NR:-0}" -gt 0 ] && echo yes || echo no)" "yes"

# ELF 头
read -r ET EM EN <<EOF
$(python3 -c "
import struct
d=open('$W/sys.elf','rb').read()
print(struct.unpack_from('<H',d,16)[0], struct.unpack_from('<H',d,18)[0], struct.unpack_from('<Q',d,24)[0])
")
EOF
chk "e_type = ET_EXEC(2)" "$ET" "2"
chk "e_machine = AArch64(183)" "$EM" "183"
# _start 在 main.o 的 text 开头，main.o 是第一个输入 → 入口应为 BASE
chk "e_entry = _start" "$EN" "1073741824"

# ④ 重定位**确实被应用了**：所有 bl 的 imm26 不得为 0
python3 - > $W/rel.txt 2>&1 <<'PY'
import struct
d=open('/tmp/a64ldtest/sys.elf','rb').read()
n=(struct.unpack_from('<Q',d,96)[0]-0)//1
ph=struct.unpack_from('<Q',d,96)[0]
base=struct.unpack_from('<Q',d,88)[0]
cnt=(ph)//4
zero=0; bad=0
for k in range(cnt):
    w=struct.unpack_from('<I',d,120+k*4)[0]
    if (w & 0xFC000000)==0x94000000:
        if (w & 0x3FFFFFF)==0: zero+=1
print("ZERO_BL=%d" % zero)
PY
chk "无未回填的 bl" "$(grep 'ZERO_BL=' $W/rel.txt)" "ZERO_BL=0"

# ④b 跨页场景真的进入了：若所有 adrp 的页偏移都是 0，说明 text 与 data
#    挤在同一页，"页对齐写错"这类变异根本走不到被测路径 —— 测试全绿
#    却一条都没验到（本项目已在 SAM/CMS 上栽过两次，这里必须显式钉住）。
python3 - > $W/pg.txt 2>&1 <<'PYEOF'
import struct
d=open('/tmp/a64ldtest/sys.elf','rb').read()
ph=struct.unpack_from('<Q',d,96)[0]
cnt=ph//4
nz=0
for k in range(cnt):
    w=struct.unpack_from('<I',d,120+k*4)[0]
    if (w & 0x9F000000)==0x90000000:
        imm=(((w>>5)&0x7FFFF)<<2)|((w>>29)&3)
        if imm & (1<<20): imm -= (1<<21)
        if imm != 0: nz+=1
print("ADRP_NONZERO=%d" % nz)
PYEOF
chk "adrp 页偏移非 0（跨页已生效）" "$([ "$(grep -o '[0-9]*' $W/pg.txt | tail -1)" -ge 1 ] && echo yes || echo no)" "yes"

# ⑥ 端到端执行
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 180 python3 $ROOT/tools/kern64run.py $W/sys.elf --steps 200000 > $W/run.txt 2>$W/run.err
OUT=$(grep -v "^---" $W/run.txt | grep -v '^$')
chk "裸机输出" "$OUT" "MO-LD BOOT
SUM=5050 OK
CALC"

# ⑤ 链接顺序无关：换个次序，输出必须一致
./a64ld.elf $W/sys2.elf $W/calc.o $W/lib.o $W/main.o > $W/ld2.log 2>&1
chk "换序链接退出码" "$?" "0"
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 180 python3 $ROOT/tools/kern64run.py $W/sys2.elf --steps 200000 > $W/run2.txt 2>$W/run2.err
OUT2=$(grep -v "^---" $W/run2.txt | grep -v '^$')
chk "换序后输出一致" "$OUT2" "$OUT"
# 换序后入口应跟着 _start 所在模块走（main.o 现在是最后一个输入）
EN2=$(python3 -c "
import struct
d=open('$W/sys2.elf','rb').read()
print(struct.unpack_from('<Q',d,24)[0])
")
chk "换序后入口 != BASE" "$([ "$EN2" != "1073741824" ] && echo yes || echo no)" "yes"

# ── 负例一：缺一个模块 → 未定义符号必须报错，不能静默产出 ──
./a64ld.elf $W/bad1.elf $W/main.o $W/calc.o > $W/bad1.log 2>&1
chk "缺模块时报错" "$?" "1"
grep -q "undefined symbol: puts" $W/bad1.log || { echo "✗ 缺模块未报 undefined"; cat $W/bad1.log; FAILN=$((FAILN+1)); }
chk "缺模块时不产出文件" "$([ -f $W/bad1.elf ] && echo yes || echo no)" "no"

# ── 负例二：同名重复定义 → 必须报错 ──
printf '        .text\n        .globl puts\nputs:\n        ret\n' > $W/dup.s
./a64as.elf -r $W/dup.s $W/dup.o > $W/dup.log 2>&1
./a64ld.elf $W/bad2.elf $W/main.o $W/lib.o $W/calc.o $W/dup.o > $W/bad2.log 2>&1
chk "重复定义报错" "$?" "1"
grep -q "duplicate symbol" $W/bad2.log || { echo "✗ 重复定义未报"; cat $W/bad2.log; FAILN=$((FAILN+1)); }

echo "a64ldtest: $PASS 通过 / $FAILN 失败"
[ "$FAILN" = "0" ]
