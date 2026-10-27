#!/usr/bin/env bash
# a64pkgmut —— 证明 a64pkgtest 的判据真的能抓到缺陷
#
# 形式与 a64pkgtest.sh 不同：这里**不重跑整套** 41 项，而是每个变异只重编
# 内核镜像、跑一次模拟器、比对关键行。整套重跑要 7 ×（重编汇编器 + 链接器
# + 3M 步模拟），在沙盒里必然超时；而"整套绿"和"关键行没变"是两回事 ——
# 探针只盯那一条会变的判据，反而更不容易被别处的噪声掩盖。
#
# 每个变异只改**一条因果链**，对应的关键行必须变。变不了就说明那组断言
# 是空转的 —— 这和被测代码有缺陷一样严重。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=$ROOT/tools/a64pkg/main.s
BAK=/tmp/a64pkgmut_main.s.bak
T=/tmp/a64pkgmut_tools
W=/tmp/a64pkgmut_work
cp $SRC $BAK
restore() { cp $BAK $SRC; }
trap restore EXIT
rm -rf $W && mkdir -p $W
NMUT=0; NCATCH=0

# ── 预编译汇编器与链接器（只做一次）──
mkdir -p $T && cp lib/*.mo $T/
cp examples/a64as.mo $T/test.mo
(cd $T && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1) && cp $T/out.elf $T/a64as.elf
cp examples/a64ld.mo $T/test.mo
(cd $T && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1) && cp $T/out.elf $T/a64ld.elf
if [ ! -f $T/a64as.elf ] || [ ! -f $T/a64ld.elf ]; then
    echo "a64pkgmut: 汇编器/链接器编译失败"; exit 1
fi

# ── 用户镜像与所有包（只生成一次）──
$T/a64as.elf -r $ROOT/tools/a64pkg/user.s $W/user.o > /dev/null 2>&1
$T/a64ld.elf --base 1075838976 $W/user.elf $W/user.o > /dev/null 2>&1
python3 - "$W" <<'PY'
import sys, os
w = sys.argv[1]
def fnv(b):
    h = 2166136261
    for x in b:
        h ^= x
        h = (h * 16777619) & 0xFFFFFFFF
    return h
p = open(os.path.join(w, "user.elf"), "rb").read()
hx = p.hex()
def save(n, s): open(os.path.join(w, "%s.txt" % n), "w").write(s)
save("pkg",   "MOPK1|app|1|%d|%s|%d" % (len(p), hx, fnv(p)))
save("sum",   "MOPK1|app|1|%d|%s|%d" % (len(p), hx, fnv(p) + 1))
save("hlen",  "MOPK1|app|1|%d|%s|%d" % (len(p), hx[:-2], fnv(p)))
save("hexchar","MOPK1|app|1|%d|%s|%d" % (len(p), "zz" + hx[2:], fnv(p)))
big = b"\x00" * 2000
save("big",   "MOPK1|app|1|%d|%s|%d" % (len(big), big.hex(), fnv(big)))
PY
for f in pkg sum hlen hexchar big; do
    [ -s $W/$f.txt ] || { echo "a64pkgmut: 包 $f 生成失败"; exit 1; }
done

build() { $T/a64as.elf -r $SRC $W/main.o > /dev/null 2>&1 \
          && $T/a64ld.elf $W/kern.elf $W/main.o > /dev/null 2>&1; }
runp() { python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 \
         --initrd $W/$1.txt@0x40410000 --steps 3000000 2>/dev/null; }

mut() {  # mut <名> <探针包> <grep 表达式> <期望计数> <旧串> <新串>
    local name=$1 pk=$2 pat=$3 want=$4 old=$5 new=$6
    restore
    python3 - "$SRC" "$old" "$new" <<'PY'
import sys
p = sys.argv[1]
olds = sys.argv[2].split("@@"); news = sys.argv[3].split("@@")
s = open(p).read()
if len(olds) != len(news):
    print("MUT-FAIL 替换对不上"); sys.exit(2)
for o, n in zip(olds, news):
    if s.count(o) != 1:
        print("MUT-FAIL 锚点不唯一/不存在: %d" % s.count(o)); sys.exit(2)
    s = s.replace(o, n)
open(p, "w").write(s)
PY
    if [ $? != 0 ]; then echo "✗ $name 变异未生效"; return; fi
    if ! build; then echo "✗ $name 重编失败"; return; fi
    local got
    got=$(runp $pk | grep -c "$pat")
    NMUT=$((NMUT+1))
    if [ "$got" != "$want" ]; then
        NCATCH=$((NCATCH+1)); echo "✓ $name 被捕获（$pat 得到 $got，期望 $want）"
    else
        echo "✗ $name **未**被捕获（$pat 仍为 $got）"
    fi
}

mut "M1 不比校验和"   sum     '^BAD 5$' 1 \
'        bl      fnv
        cmp     x0, x22
        b.ne    up_sum' \
'        bl      fnv
        cmp     x0, x0
        b.ne    up_sum'

# -3 由**两道**检查共同保证：先比 hex 段长度是否 2*len，再比 hexdec 解出的
# 字节数是否等于 len。只改一道，另一道仍会把 hlen 负例拦成 -3 —— 这是
# "改了代码却没改到那条因果链"的又一个实例。
mut "M2 两道长度检查都失效" hlen '^BAD 3$' 1 \
'        cmp     x18, x21@@        cmp     x0, x19' \
'        cmp     x18, x18@@        cmp     x0, x0'

mut "M3 非法 hex 不报错" hexchar '^BAD 4$' 1 \
'hv_bad:
        mov     x0, #1
        neg     x0, x0
        ret' \
'hv_bad:
        mov     x0, #0
        ret'

# M4 不能用"把文件区挪到用户区"来变异：用户程序硬编码了 0x40430000，
# 挪走之后它读的仍是内核私有块，PF2 照样出现 —— 判据根本没变。
# 能验证"文件内容区真的隔离"的，是让内核私有块不再私有。
mut "M4 内核私有块不再私有" pkg '^PF2$' 1 \
'        mov     x9, #0x0401' \
'        mov     x9, #0x0441'

mut "M5 create 不递增计数" pkg '^1$' 1 \
'        add     x10, x10, #1
        ldaddr  x9, fs_count
        str     x10, [x9]' \
'        add     x10, x10, #0
        ldaddr  x9, fs_count
        str     x10, [x9]'

mut "M6 write 不记录长度" pkg '^5050$' 2 \
'        str     x13, [x9]
        str     x13, [sp, #0]' \
'        str     x13, [sp, #0]'

mut "M7 容量检查放宽"   big    '^BAD 6$' 1 \
'        mov     x18, #1024
        cmp     x19, x18
        b.gt    up_big' \
'        mov     x18, #4096
        cmp     x19, x18
        b.gt    up_big'

mut "M8 不清零 bss"       pkg   '^0$' 2 \
'        cmp     x20, x15' \
'        cmp     x20, x20'

restore
echo "a64pkgmut: $NCATCH / $NMUT 被捕获"
if [ "$NCATCH" != "$NMUT" ]; then exit 1; fi
exit 0
