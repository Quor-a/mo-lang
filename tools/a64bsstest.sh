#!/usr/bin/env bash
# a64bsstest —— 墨语言自举 AArch64 **.bss 段**的端到端验证
#
# bss 的全部意义只有一句话：**占内存、不占文件**。所以判据必须同时
# 钉住两件事，缺一个就会漏：
#   ① 文件里没有 bss 字节      → filesz 不含 NB，实际文件大小 == filesz
#   ② 内存里有 bss 字节且为零  → memsz == filesz + NB，程序能读写
# 只验 ② 的话，把 bss 当 .data 写出去也能全绿（文件变大但行为一样）；
# 只验 ① 的话，链接器压根不分配 bss 也能全绿（memsz 相同、读到的是 0）。
#
# 另有两条负例：.bss 里初始化必须报错；.bss 段类型不是 NOBITS 必须报错。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64bsstest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译汇编器与链接器（墨语言 → x86-64 ELF，无外部 as/ld）──
cp lib/*.mo $W/
cp examples/a64as.mo $W/test.mo
cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "汇编器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64as.elf
cp $ROOT/examples/a64ld.mo $W/test.mo
rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "链接器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64ld.elf

for m in lib mem buf main; do
    ./a64as.elf -r $ROOT/tools/a64bss/$m.s $W/$m.o > $W/$m.aslog 2>&1
    chk "汇编 $m.s" "$?" "0"
    grep -q "error\|cannot\|overflow" $W/$m.aslog && { echo "✗ $m.s 汇编报错"; cat $W/$m.aslog; FAILN=$((FAILN+1)); }
done

# ① 目标文件里 .bss 必须是 SHT_NOBITS(8)，且 sh_size 正确
python3 - > $W/sec.txt 2>&1 <<'PY'
import struct

def shoff_of(d): return struct.unpack_from('<Q', d, 40)[0]
def shnum_of(d): return struct.unpack_from('<H', d, 60)[0]

def secs(d):
    shoff = shoff_of(d); shnum = shnum_of(d)
    shstr = struct.unpack_from('<H', d, 62)[0]
    stro = struct.unpack_from('<Q', d, shoff + shstr * 64 + 24)[0]
    out = {}
    for i in range(shnum):
        b = shoff + i * 64
        nm = d[stro + struct.unpack_from('<I', d, b)[0]:]
        nm = nm[:nm.index(0)].decode()
        out[nm] = (struct.unpack_from('<I', d, b + 4)[0],
                   struct.unpack_from('<Q', d, b + 32)[0],
                   struct.unpack_from('<Q', d, b + 24)[0],
                   struct.unpack_from('<I', d, b + 40)[0])
    return out

def symshn(d, want):
    s = secs(d)
    symoff, symsz, lk = s['.symtab'][2], s['.symtab'][1], s['.symtab'][3]
    stro2 = struct.unpack_from('<Q', d, shoff_of(d) + lk * 64 + 24)[0]
    for k in range(1, symsz // 24):
        e = symoff + k * 24
        nm = d[stro2 + struct.unpack_from('<I', d, e)[0]:]
        nm = nm[:nm.index(0)].decode()
        if nm == want:
            return struct.unpack_from('<H', d, e + 6)[0]
    return -1

for f, exp in (('mem', 8), ('buf', 12288)):
    d = open('/tmp/a64bsstest/%s.o' % f, 'rb').read()
    s = secs(d)
    ty, sz = s.get('.bss', (-1, -1))[:2]
    print("%s_BSS_TYPE=%d" % (f.upper(), ty))
    print("%s_BSS_SIZE=%d" % (f.upper(), sz))

d = open('/tmp/a64bsstest/mem.o', 'rb').read()
print("ACC_SHNDX=%d" % symshn(d, 'acc'))
d = open('/tmp/a64bsstest/buf.o', 'rb').read()
print("BUF_SHNDX=%d" % symshn(d, 'buf'))
PY
chk "mem.o .bss 段类型 = SHT_NOBITS(8)" "$(grep 'MEM_BSS_TYPE=' $W/sec.txt)" "MEM_BSS_TYPE=8"
chk "mem.o .bss 大小 = 8" "$(grep 'MEM_BSS_SIZE=' $W/sec.txt)" "MEM_BSS_SIZE=8"
chk "buf.o .bss 段类型 = SHT_NOBITS(8)" "$(grep 'BUF_BSS_TYPE=' $W/sec.txt)" "BUF_BSS_TYPE=8"
chk "buf.o .bss 大小 = 12288" "$(grep 'BUF_BSS_SIZE=' $W/sec.txt)" "BUF_BSS_SIZE=12288"
chk "acc 符号落在 .bss(3)" "$(grep 'ACC_SHNDX=' $W/sec.txt)" "ACC_SHNDX=3"
chk "buf 符号落在 .bss(3)" "$(grep 'BUF_SHNDX=' $W/sec.txt)" "BUF_SHNDX=3"

# ── 链接 ──
./a64ld.elf $W/sys.elf $W/main.o $W/lib.o $W/mem.o $W/buf.o > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"
grep -q "undefined\|duplicate\|cannot" $W/ld.log && { echo "✗ 链接器报错"; cat $W/ld.log; FAILN=$((FAILN+1)); }

# ① filesz 不含 bss ② memsz 含 bss ③ 实际文件大小 == 120+filesz
python3 - > $W/sz.txt 2>&1 <<'PY'
import struct, os
d=open('/tmp/a64bsstest/sys.elf','rb').read()
phoff=struct.unpack_from('<Q',d,32)[0]
filesz=struct.unpack_from('<Q',d,phoff+32)[0]
memsz=struct.unpack_from('<Q',d,phoff+40)[0]
print("FILESZ=%d" % filesz)
print("MEMSZ=%d" % memsz)
print("DIFF=%d" % (memsz-filesz))
print("ONDISK=%d" % os.path.getsize('/tmp/a64bsstest/sys.elf'))
PY
BSS=$(grep -o 'bss bytes' $W/ld.log >/dev/null && python3 -c "
import re
s=open('$W/ld.log').read()
m=re.search(r'([0-9]+) bss bytes', s)
print(m.group(1) if m else -1)")
DIFF=$(grep -o 'DIFF=[0-9]*' $W/sz.txt | cut -d= -f2)
ONDISK=$(grep -o 'ONDISK=[0-9]*' $W/sz.txt | cut -d= -f2)
FILESZ=$(grep -o 'FILESZ=[0-9]*' $W/sz.txt | cut -d= -f2)
chk "链接器报告的 bss 大小 = 8 + 12288" "$BSS" "12296"
chk "memsz - filesz == bss 大小" "$DIFF" "$BSS"
chk "文件大小 == 120 + filesz（bss 不在文件里）" "$ONDISK" "$((120 + FILESZ))"

# ── 端到端执行 ──
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --steps 400000 > $W/run.txt 2>$W/run.err
OUT=$(grep -v "^---" $W/run.txt | grep -v '^$')
chk "裸机输出" "$OUT" "MO-BSS
Z OK
P OK
SUM OK
FILL OK
DATA OK
ACC OK"
# 整体比对只有一条断言，任何一条自检失败都只红一项 —— 看不出**哪一条**
# 挂了，也让变异的"红几项"失去分辨力。所以七条再逐条钉一次。
for L in "MO-BSS" "Z OK" "P OK" "SUM OK" "FILL OK" "DATA OK" "ACC OK"; do
    chk "输出含 $L" "$(printf '%s\n' "$OUT" | grep -cx "$L")" "1"
done
chk "没有 BAD 行" "$(printf '%s\n' "$OUT" | grep -cx 'BAD')" "0"

# ── 负例一：.bss 里写初始化数据必须报错（值会被丢掉，静默）──
printf '        .bss\nx:      .byte 1\n' > $W/init.s
./a64as.elf -r $W/init.s $W/init.o > $W/init.log 2>&1
chk ".bss 初始化报错" "$?" "1"
grep -q "cannot initialize .bss" $W/init.log || { echo "✗ .bss 初始化未报错"; cat $W/init.log; FAILN=$((FAILN+1)); }

# ── 负例二：.bss 段类型不是 NOBITS 时链接器必须拒绝 ──
python3 - > /dev/null 2>&1 <<'PY'
import struct
d=bytearray(open('/tmp/a64bsstest/mem.o','rb').read())
shoff=struct.unpack_from('<Q',d,40)[0]
shnum=struct.unpack_from('<H',d,60)[0]
shstr=struct.unpack_from('<H',d,62)[0]
stro=struct.unpack_from('<Q',d,shoff+shstr*64+24)[0]
for i in range(shnum):
    b=shoff+i*64
    nm=bytes(d[stro+struct.unpack_from('<I',d,b)[0]:])
    nm=nm[:nm.index(0)].decode()
    if nm=='.bss':
        struct.pack_into('<I', d, b+4, 1)   # 改成 SHT_PROGBITS
open('/tmp/a64bsstest/mem_bad.o','wb').write(bytes(d))
print("patched")
PY
./a64ld.elf $W/bad.elf $W/main.o $W/lib.o $W/mem_bad.o $W/buf.o > $W/bad.log 2>&1
chk ".bss 类型非 NOBITS 时报错" "$?" "1"
grep -q "SHT_NOBITS" $W/bad.log || { echo "✗ 未报 SHT_NOBITS"; cat $W/bad.log; FAILN=$((FAILN+1)); }

echo "a64bsstest: $PASS 通过 / $FAILN 失败"
[ "$FAILN" = "0" ]
