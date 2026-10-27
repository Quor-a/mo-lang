#!/usr/bin/env bash
# a64arithtest —— 自举 aarch64 汇编器**第二批指令**（算术 / 条件）的验证
#
# 判据分五层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出            抓"根本没产出"
#   ② 产物里每条新指令都要出现    抓"助记符没被识别、静默落到别的分支"
#                                （样本充分 ≠ 覆盖充分：源码里写了不等于编出来了）
#   ③ cbz/cbnz 的重定位是真规范值  抓"reltype 漏分类 / 用了私有编号"
#   ④ 链接产物的重定位已被应用    抓"链接器什么都没做却假装成功"
#   ⑤ 端到端裸机执行 + 逐项数字   抓"字段错位但指令仍合法"
#
# 期望值由 Python **独立**按 AArch64 语义算出（不是照抄汇编器的编码），
# 否则"汇编器说对就对"等于没验证。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64arithtest
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

# ── ① 汇编两个模块 + 链接 ──
for m in io main; do
    ./a64as.elf -r $ROOT/tools/a64arith/$m.s $W/$m.o > $W/$m.aslog 2>&1
    chk "汇编 $m.s" "$?" "0"
    grep -qi "undefined\|error\|out of range\|cannot classify" $W/$m.aslog && {
        echo "✗ 汇编 $m.s 报错"; cat $W/$m.aslog; FAILN=$((FAILN+1)); }
done
./a64ld.elf $W/sys.elf $W/main.o $W/io.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"

# ── ② 产物里每条新指令都必须真的出现 ──
#   只查源码里有没有写是不够的：助记符若没被识别，会静默当成未知指令跳过，
#   程序照跑、退出码照旧 —— 这是本项目反复出现的"样本充分 ≠ 覆盖充分"。
python3 - $W/main.o $W/io.o > $W/insn.txt <<'PY'
import struct,sys
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
        out[nm]=(struct.unpack_from('<Q',d,b+24)[0], struct.unpack_from('<Q',d,b+32)[0])
    return out
cnt={}
for path in sys.argv[1:]:
    d=open(path,'rb').read()
    s=secs(d)
    off,size=s['.text']
    for k in range(size//4):
        w=struct.unpack_from('<I',d,off+k*4)[0]
        rn=(w>>5)&31; imms=(w>>10)&63
        if (w & 0xFFC0FC00)==0x9AC00800: cnt['udiv']=cnt.get('udiv',0)+1
        if (w & 0xFFC0FC00)==0x9AC00C00: cnt['sdiv']=cnt.get('sdiv',0)+1
        if (w & 0xFFE0FC00)==0x9B008000: cnt['msub']=cnt.get('msub',0)+1
        if (w & 0xFF800000)==0xD3000000 and imms==63: cnt['lsr']=cnt.get('lsr',0)+1
        if (w & 0xFF800000)==0x93000000: cnt['asr']=cnt.get('asr',0)+1
        if (w & 0xFF000000)==0xCB000000 and rn==31: cnt['neg']=cnt.get('neg',0)+1
        if (w & 0xFF200000)==0x8A200000: cnt['bic']=cnt.get('bic',0)+1
        if (w & 0xFF200000)==0xAA200000 and rn==31: cnt['mvn']=cnt.get('mvn',0)+1
        if (w & 0xFFC00C00)==0x9A800000: cnt['csel']=cnt.get('csel',0)+1
        if (w & 0xFF000000)==0xB4000000: cnt['cbz']=cnt.get('cbz',0)+1
        if (w & 0xFF000000)==0xB5000000: cnt['cbnz']=cnt.get('cbnz',0)+1
        if (w & 0xFF000000)==0xF1000000 and (w&31)!=31: cnt['subs_i']=cnt.get('subs_i',0)+1
        if (w & 0xFF000000)==0xEB000000 and (w&31)!=31: cnt['subs_r']=cnt.get('subs_r',0)+1
        if (w & 0xFF000000)==0xB1000000: cnt['adds_i']=cnt.get('adds_i',0)+1
        if (w & 0xFFC00000)==0x79000000: cnt['strh']=cnt.get('strh',0)+1
        if (w & 0xFFC00000)==0x79400000: cnt['ldrh']=cnt.get('ldrh',0)+1
for k in sorted(cnt): print(k, cnt[k])
PY
for k in udiv sdiv msub lsr asr neg bic mvn csel cbz cbnz subs_i subs_r adds_i strh ldrh; do
    n=$(awk -v k="$k" '$1==k{print $2; found=1} END{if(!found) print 0}' $W/insn.txt)
    [ "${n:-0}" -ge 1 ] && PASS=$((PASS+1)) || { FAILN=$((FAILN+1)); echo "✗ 产物缺少 $k 指令（覆盖为空）"; }
done

# ── ③ cbz / cbnz 的重定位必须是 R_AARCH64_CONDBR19 = 280 ──
python3 - $W/main.o > $W/rel.txt <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
shoff=struct.unpack_from('<Q',d,40)[0]
shnum=struct.unpack_from('<H',d,60)[0]
shstr=struct.unpack_from('<H',d,62)[0]
stro=struct.unpack_from('<Q',d,shoff+shstr*64+24)[0]
S={}
for i in range(shnum):
    b=shoff+i*64
    nm=d[stro+struct.unpack_from('<I',d,b)[0]:]
    nm=nm[:nm.index(0)].decode()
    S[nm]=(struct.unpack_from('<Q',d,b+24)[0], struct.unpack_from('<Q',d,b+32)[0])
to,ts=S['.text']
ro,rs=S['.rela.text']
rel={}
for k in range(rs//24):
    e=ro+k*24
    off=struct.unpack_from('<Q',d,e)[0]
    info=struct.unpack_from('<Q',d,e+8)[0]
    rel[off]=info & 0xFFFFFFFF
n_cb=0; bad=0
for k in range(ts//4):
    w=struct.unpack_from('<I',d,to+k*4)[0]
    if (w & 0xFF000000) in (0xB4000000,0xB5000000):
        n_cb=n_cb+1
        if rel.get(k*4) != 280: bad=bad+1
print("cbz_or_cbnz", n_cb)
print("bad_rel", bad)
PY
chk "cbz/cbnz 条数 >= 2" "$(awk '$1=="cbz_or_cbnz"{print ($2>=2)?"yes":"no"}' $W/rel.txt)" "yes"
chk "cbz/cbnz 重定位全为 CONDBR19(280)" "$(awk '$1=="bad_rel"{print $2}' $W/rel.txt)" "0"

# ── ④ 链接后重定位已被应用：跳转目标不再是 0 ──
python3 - $W/sys.elf > $W/link.txt <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
shoff=struct.unpack_from('<Q',d,40)[0]
shnum=struct.unpack_from('<H',d,60)[0]
S={}
for i in range(shnum):
    b=shoff+i*64
    S[struct.unpack_from('<I',d,b)[0]]=(struct.unpack_from('<Q',d,b+24)[0],struct.unpack_from('<Q',d,b+32)[0])
# 可执行产物：直接从 e_entry 之后扫文本，找 cbz/cbnz 且 imm19 != 0
to,ts=S[1] if 1 in S else (120,len(d)-120)
nz=0; tot=0
for k in range(ts//4):
    w=struct.unpack_from('<I',d,to+k*4)[0]
    if (w & 0xFF000000) in (0xB4000000,0xB5000000):
        tot=tot+1
        if (w>>5)&0x7FFFF != 0: nz=nz+1
print("linked_cb", tot)
print("linked_nonzero", nz)
PY
chk "链接后 cbz/cbnz 条数 >= 2" "$(awk '$1=="linked_cb"{print ($2>=2)?"yes":"no"}' $W/link.txt)" "yes"
chk "链接后 cbz/cbnz 偏移已回填" "$(awk '$1=="linked_cb"{a=$2} $1=="linked_nonzero"{b=$2} END{print (a>0 && a==b)?"yes":"no"}' $W/link.txt)" "yes"

# ── ⑤ 端到端执行：裸机（无 Linux / libc / 安卓），只有 CPU + UART ──
timeout 120 python3 $ROOT/tools/kern64run.py $W/sys.elf > $W/out.txt 2>$W/err.txt
# 裸机的"停机"是 wfi 空转，模拟器以"步数用尽"结束，退出码非 0 属正常。
# 判据因此不能看退出码，而要看程序有没有真的走到 DONE：
# 只看退出码会把"跑飞后卡死"和"正常停机"混为一谈。
grep -q "模拟器异常" $W/err.txt && { echo "✗ 模拟器异常"; head -5 $W/err.txt; FAILN=$((FAILN+1)); }
chk "未出现模拟器异常" "$(grep -c '模拟器异常' $W/err.txt)" "0"

# 期望值：独立按 AArch64 语义算（sdiv 向零取整、asr 算术右移、lsr 逻辑右移）
python3 - $W/out.txt > $W/exp.txt <<'PY'
import sys
M=(1<<64)-1
def s64(v):
    v&=M
    return v-M-1 if v>>63 else v
def sdiv(a,b):
    q=abs(a)//abs(b)
    return -q if (a<0)!=(b<0) else q
exp=[
 ("U=", 12345//100),
 ("R=", 12345-(12345//100)*100),
 ("S=", sdiv(-12345,100)),
 ("S2=", sdiv(12345,-100)),
 ("L=", (1<<63)>>63),
 ("A=", s64(s64(1<<63)>>63)),
 ("A2=", s64(-16)>>2),
 ("N=", -42),
 ("B=", 0xFF & ~0x0F),
 ("V=", s64(~0 & M)),
 ("C=", 7),
 ("C2=", 3),
 ("Z=", sum(range(1,11))),
 ("NZ=", sum(range(1,11))),
 ("SU=", sum(range(1,6))),
 ("AD=", 1),
 ("H=", 0x1234),
]
txt=open(sys.argv[1],encoding='utf-8',errors='replace').read()
import re
# 逐项按序取值：每个标签后面紧跟的数字
pos=0; bad=0
for tag,want in exp:
    i=txt.find(tag,pos)
    if i<0:
        print("MISSING", tag, want); bad=bad+1; continue
    j=i+len(tag)
    m=re.match(r'-?\d+', txt[j:])
    got=int(m.group(0)) if m else -99999
    if got!=want:
        print("MISMATCH", tag, "got",got,"want",want); bad=bad+1
    pos=j
print("bad", bad)
print("total", len(exp))
PY
chk "逐项数字全对" "$(awk '$1=="bad"{print $2}' $W/exp.txt)" "0"
chk "期望项数" "$(awk '$1=="total"{print $2}' $W/exp.txt)" "17"
chk "输出含 DONE" "$(grep -c 'DONE' $W/out.txt)" "1"
grep -q "MISMATCH\|MISSING" $W/exp.txt && { echo "--- 实际输出 ---"; cat $W/out.txt; }

# ── 负例：越界立即数必须报错，不能静默截断 ──
cat > $W/bad.s <<'EOF'
        .text
_start:
        mov     x0, #1
        lsr     x0, x0, #64
EOF
./a64as.elf $W/bad.s $W/bad.elf > $W/bad.log 2>&1
chk "lsr #64 报错" "$([ $? -ne 0 ] && echo yes || echo no)" "yes"

echo "通过 $PASS 项，失败 $FAILN 项"
[ "$FAILN" = "0" ] || { echo "--- out.txt ---"; cat $W/out.txt; exit 1; }
exit 0
