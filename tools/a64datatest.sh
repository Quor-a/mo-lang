#!/usr/bin/env bash
# a64datatest —— 自举 AArch64 工具链的「数据段重定位」端到端验证
#
# 判据分五层，缺一层就漏掉不同类别的缺陷：
#   ① .o 里有 .rela.data、类型是规范的 257   抓"用了私有编号/根本没产出"
#   ② 链接**前**跳转表字节必须是 0           抓"汇编器自己算好了地址，没走重定位"
#   ③ 链接**后** 8 字节 == 独立算出的地址     抓"算错但程序仍能跑"（用外部算的期望值）
#   ④ 端到端执行                             抓"地址写进去了但 blr 到了别处"
#   ⑤ 缺模块时必须因**数据段**里的未定义符号报错 抓"数据段重定位没参与符号解析"
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64datatest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

cp lib/*.mo $W/
cp examples/a64as.mo $W/test.mo
cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "汇编器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64as.elf
cp $ROOT/examples/a64ld.mo $W/test.mo
rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "链接器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64ld.elf

./a64as.elf -r $ROOT/tools/a64data/main.s $W/main.o > /dev/null 2>&1
chk "汇编 main.s" "$?" "0"
./a64as.elf -r $ROOT/tools/a64data/handlers.s $W/handlers.o > /dev/null 2>&1
chk "汇编 handlers.s" "$?" "0"

# ① + ②：用独立解析器读 .o（不依赖被测程序的日志）
python3 - > $W/obj.txt 2>&1 <<'PY'
import struct
def load(p):
    return open(p,'rb').read()
def secs(d):
    shoff=struct.unpack_from('<Q',d,40)[0]; shnum=struct.unpack_from('<H',d,60)[0]
    shstr=struct.unpack_from('<H',d,62)[0]
    stro=struct.unpack_from('<Q',d,shoff+shstr*64+24)[0]
    out={}
    for i in range(shnum):
        b=shoff+i*64
        nm=d[stro+struct.unpack_from('<I',d,b)[0]:]
        nm=nm[:nm.index(0)].decode()
        out[nm]=dict(off=struct.unpack_from('<Q',d,b+24)[0],
                     size=struct.unpack_from('<Q',d,b+32)[0],
                     link=struct.unpack_from('<I',d,b+40)[0])
    return out
def syms(d,s):
    shoff=struct.unpack_from('<Q',d,40)[0]
    stro=struct.unpack_from('<Q',d,shoff+s['.symtab']['link']*64+24)[0]
    out={}
    for k in range(1, s['.symtab']['size']//24):
        e=s['.symtab']['off']+k*24
        nm=d[stro+struct.unpack_from('<I',d,e)[0]:]
        nm=nm[:nm.index(0)].decode()
        out[nm]=(struct.unpack_from('<H',d,e+6)[0], struct.unpack_from('<Q',d,e+8)[0])
    return out
def relas(d,s,key):
    out=[]
    for k in range(s[key]['size']//24):
        e=s[key]['off']+k*24
        info=struct.unpack_from('<Q',d,e+8)[0]
        out.append((struct.unpack_from('<Q',d,e)[0], info & 0xFFFFFFFF))
    return out

BASE=0x40000000
dm=load('/tmp/a64datatest/main.o'); dh=load('/tmp/a64datatest/handlers.o')
sm=secs(dm); sh=secs(dh)
print("HAS_RELADATA=%d" % (1 if '.rela.data' in sm else 0))
rd=relas(dm,sm,'.rela.data')
print("N_RELADATA=%d" % len(rd))
print("TYPES=%s" % ",".join(str(t) for t in sorted(set(t for _,t in rd))))
sym=syms(dm,sm)
print("H0_SHNDX=%d" % sym['h0'][0])
print("H1_SHNDX=%d" % sym['h1'][0])       # 在 main.o 里必须是 UNDEF(0)
print("JT_SHNDX=%d" % sym['jt'][0])
print("H0_VAL=%d" % sym['h0'][1])
print("JT_VAL=%d" % sym['jt'][1])
# 链接前：跳转表这 16 个字节必须是 0（地址还没人填）
off=sm['.data']['off']+sym['jt'][1]
print("PRE_ZERO=%d" % (1 if dm[off:off+16]==b'\0'*16 else 0))
print("MAIN_TSZ=%d" % sm['.text']['size'])
print("H1_VAL=%d" % syms(dh,sh)['h1'][1])
PY
chk "main.o 有 .rela.data" "$(grep 'HAS_RELADATA=' $W/obj.txt)" "HAS_RELADATA=1"
chk ".rela.data 条数 = 2" "$(grep 'N_RELADATA=' $W/obj.txt)" "N_RELADATA=2"
chk "类型是规范值 257(ABS64)" "$(grep 'TYPES=' $W/obj.txt)" "TYPES=257"
chk "h0 在 main.o 的 .text(1)" "$(grep 'H0_SHNDX=' $W/obj.txt)" "H0_SHNDX=1"
chk "h1 在 main.o 里是 UNDEF(0)" "$(grep 'H1_SHNDX=' $W/obj.txt)" "H1_SHNDX=0"
chk "jt 在 .data(2)" "$(grep 'JT_SHNDX=' $W/obj.txt)" "JT_SHNDX=2"
chk "链接前跳转表字节全 0" "$(grep 'PRE_ZERO=' $W/obj.txt)" "PRE_ZERO=1"

# ── 链接 ──
./a64ld.elf $W/sys.elf $W/main.o $W/handlers.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"

# ③ 链接后的 8 字节 == **独立**算出的地址（不信任链接器日志）
python3 - > $W/chk.txt 2>&1 <<'PY'
import struct
BASE=0x40000000
d=open('/tmp/a64datatest/sys.elf','rb').read()
def gv(n):
    return int(open('/tmp/a64datatest/obj.txt').read().split(n+'=')[1].split()[0])
main_tsz=gv('MAIN_TSZ'); jt=gv('JT_VAL'); h0=gv('H0_VAL'); h1=gv('H1_VAL')
nt=(main_tsz+3)//4  # 占位，真实 NT 由链接器日志不可信 → 用 data 起点反推
# 数据起点 = 120 + NT*4；用 ELF 程序头的 filesz 与已知 data 长度定位：
#  这里直接按「main.o 的 .data 在链接后位于 data 区开头」算文件偏移
ph=struct.unpack_from('<Q',d,32)[0]
filesz=struct.unpack_from('<Q',d,96)[0]
ptxt=struct.unpack_from('<Q',d,72)[0]
nt=(filesz-4147)//4   # 4147 = 数据字节数（由 .o 累加，独立于链接器）
doff=120+nt*4+jt
v0=struct.unpack_from('<Q',d,doff)[0]
v1=struct.unpack_from('<Q',d,doff+8)[0]
e0=BASE+h0
e1=BASE+main_tsz+h1
print("GOT0=%d WANT0=%d" % (v0,e0))
print("GOT1=%d WANT1=%d" % (v1,e1))
PY
chk "jt[0] = h0 地址" "$(grep -o 'GOT0=[0-9]* WANT0=[0-9]*' $W/chk.txt | awk '{split($1,a,"=");split($2,b,"="); print (a[2]==b[2])?"same":"diff"}')" "same"
chk "jt[1] = h1 地址" "$(grep -o 'GOT1=[0-9]* WANT1=[0-9]*' $W/chk.txt | awk '{split($1,a,"=");split($2,b,"="); print (a[2]==b[2])?"same":"diff"}')" "same"

# ④ 端到端
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 180 python3 $ROOT/tools/kern64run.py $W/sys.elf --steps 200000 > $W/run.txt 2>&1
OUT=$(grep -v "^---" $W/run.txt | grep -v '^$')
chk "裸机输出" "$OUT" "MO-SYS
A
B
SYS OK"

# ⑤ 链接顺序无关
./a64ld.elf $W/sys2.elf $W/handlers.o $W/main.o > $W/ld2.log 2>&1
chk "换序链接退出码" "$?" "0"
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 180 python3 $ROOT/tools/kern64run.py $W/sys2.elf --steps 200000 > $W/run2.txt 2>&1
chk "换序后输出一致" "$(grep -v "^---" $W/run2.txt | grep -v '^$')" "$OUT"

# ⑤b 负例：只补上 puts、仍缺 h1 —— 此时**唯一**未定义的符号只出现在
#     .rela.data 里。它能被报出来，才说明数据段重定位真的参与了符号解析。
cat > $W/onlyputs.s <<'EOS'
        .text
        .globl puts
puts:
        mov     x2, #0
        movk    x2, #0x0900, lsl #16
puts_loop:
        ldrb    w3, [x0]
        cmp     w3, #0
        b.eq    puts_done
        strb    w3, [x2]
        add     x0, x0, #1
        b       puts_loop
puts_done:
        ret
EOS
./a64as.elf -r $W/onlyputs.s $W/onlyputs.o > /dev/null 2>&1
./a64ld.elf $W/bad.elf $W/main.o $W/onlyputs.o > $W/bad.log 2>&1
chk "缺 h1 时报错" "$?" "1"
grep -q "undefined symbol: h1" $W/bad.log || { echo "✗ 未报 h1 未定义（数据段重定位没参与解析）"; cat $W/bad.log; FAILN=$((FAILN+1)); }
chk "缺 h1 时不产出文件" "$([ -f $W/bad.elf ] && echo yes || echo no)" "no"

# ⑤c 负例：连 puts 都没有 → 任何一个未定义符号都要拦住，不能静默产出
./a64ld.elf $W/bad2.elf $W/main.o > $W/bad2.log 2>&1
chk "缺 handlers.o 时报错" "$?" "1"
chk "缺 handlers.o 时不产出文件" "$([ -f $W/bad2.elf ] && echo yes || echo no)" "no"

echo "a64datatest: $PASS 通过 / $FAILN 失败"
[ "$FAILN" = "0" ]
