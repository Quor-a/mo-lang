#!/usr/bin/env bash
# a64artest —— 墨语言自举 AArch64 **ar 归档 + 按需抽取**的端到端验证
#
# 归档的全部意义只有一句话：**没用到的成员不进产物**。
# 所以判据必须同时钉住两件事，缺一个就会漏：
#   ① 用到的必须进来        → 端到端跑出 A / B / MO-AR / SYS OK
#                             （B 靠的是**传递抽取**，见下）
#   ② 没用到的必须不进来    → 产物里搜不到 "ZZ-UNUSED"
# 只验 ① 的话，"把归档里所有成员都塞进去"也能全绿 —— 那等于没做按需，
# 而且产物更大、把没用到的代码也带进了裸机镜像，是个真缺陷。
#
# ── 传递抽取是这里最硬的一条 ────────────────────────────────
#   main → fna（在 a.o）→ fnb（在 b.o）
#   第一轮遍历时 fnb 还不是 UNDEF（fna 都没进来），probe(b.o) 必然返回 0。
#   只有抽出 a.o 之后 fnb 才变成 UNDEF，必须**再转一轮**才能把 b.o 拉进来。
#   只做一遍的实现会在 fnb 上报未定义，症状看起来像"归档里少放了一个文件"，
#   其实是抽取循环少了一轮。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64artest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译三个工具（墨语言 → x86-64 ELF，无外部 as/ld）──
cp lib/*.mo $W/
for t in a64as a64ld a64ar; do
    cp $ROOT/examples/$t.mo $W/test.mo
    ( cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1 )
    chk "编译 $t" "$([ -f $W/out.elf ] && echo yes || echo no)" "yes"
    cp $W/out.elf $W/$t.elf
done
cd $W

# ── 汇编五个模块 ──
for m in lib a b unused main; do
    ./a64as.elf -r $ROOT/tools/a64ar/$m.s $W/$m.o > $W/$m.aslog 2>&1
    chk "汇编 $m.s" "$?" "0"
    grep -q "error\|cannot\|overflow" $W/$m.aslog && { echo "✗ $m.s 汇编报错"; cat $W/$m.aslog; FAILN=$((FAILN+1)); }
done

# ── ① 归档：ar 头的每个字段都要对 ────────────────────────────
# 成员顺序**刻意是 b 在前、a 在后**（依赖方向与归档顺序相反）：
#   第一轮遍历时 fnb 还不是 UNDEF，b.o 被跳过；抽出 a.o 之后 fnb 才变成
#   UNDEF，只有**再转一轮**才能把 b.o 拉进来。
#   若按 a、b 顺序归档，第一轮内 a→b 恰好顺着遍历方向，"抽取循环不迭代"
#   这个缺陷会被完全掩盖 —— 改坏了代码测试照样全绿（实测确认）。
#   所以**样本顺序**本身就是覆盖的一部分，不只是样本数量。
./a64ar.elf $W/libx.a $W/b.o $W/a.o $W/unused.o > $W/ar.log 2>&1
chk "归档退出码" "$?" "0"
grep -q "3 members" $W/ar.log || { echo "✗ 成员数不对"; cat $W/ar.log; FAILN=$((FAILN+1)); }

python3 - > $W/ar.txt 2>&1 <<'PY'
d = open('/tmp/a64artest/libx.a', 'rb').read()
print("MAGIC=%d" % (1 if d[:8] == b'!<arch>\n' else 0))
# 逐个成员走一遍头：size 字段必须是十进制、且能走到下一个成员头
o = 8
n = 0
sizes = []
ok = 1
while o + 60 <= len(d):
    hdr = d[o:o + 60]
    if hdr[58:60] != b'`\n':
        ok = 0
        break
    sz = int(hdr[48:58].decode().strip())
    sizes.append(sz)
    if o + 60 + sz > len(d):
        ok = 0
        break
    o = o + 60 + sz
    if sz % 2 == 1:
        o = o + 1
    n = n + 1
print("WALK_OK=%d" % ok)
print("NMEM=%d" % n)
print("SIZES=%s" % ",".join(str(x) for x in sizes))
# 成员 0 必须真的是一个 ET_REL aarch64 目标文件。
# 偏移 68 = magic(8) + 成员头(60)，**不是** 60 —— 头前面还有 magic，
# 写成 60 的话取到的是头的尾巴，ET_REL 与 machine 都是 0，
# 而 WALK_OK 仍然自洽（两者用的是不同的偏移来源），不会互相暴露。
m0 = d[68:68 + sizes[0]]
print("M0_ETREL=%d" % (1 if int.from_bytes(m0[16:18], 'little') == 1 else 0))
print("M0_ARCH=%d" % int.from_bytes(m0[18:20], 'little'))
PY
chk "ar magic"                 "$(grep -o 'MAGIC=[0-9]*' $W/ar.txt | cut -d= -f2)" "1"
chk "成员头走查（对齐+size 正确）" "$(grep -o 'WALK_OK=[0-9]*' $W/ar.txt | cut -d= -f2)" "1"
chk "成员数 = 3"                "$(grep -o 'NMEM=[0-9]*' $W/ar.txt | cut -d= -f2)" "3"
chk "成员 0 是 ET_REL"          "$(grep -o 'M0_ETREL=[0-9]*' $W/ar.txt | cut -d= -f2)" "1"
chk "成员 0 是 aarch64(183)"    "$(grep -o 'M0_ARCH=[0-9]*' $W/ar.txt | cut -d= -f2)" "183"

# ── ② 链接：main.o + lib.o + libx.a ──
./a64ld.elf $W/sys.elf $W/main.o $W/lib.o $W/libx.a > $W/ld.log 2>&1
chk "链接退出码" "$?" "0"
grep -q "undefined\|duplicate\|cannot" $W/ld.log && { echo "✗ 链接器报错"; cat $W/ld.log; FAILN=$((FAILN+1)); }
NEX=$(python3 -c "
import re
m=re.search(r'([0-9]+) archive members', open('$W/ld.log').read())
print(m.group(1) if m else -1)")
chk "抽取成员数 = 2（a 与 b，不是 3）" "$NEX" "2"

# ── ③ 按需：产物里不能有未使用成员的东西 ─────────────────────
chk "产物不含 ZZ-UNUSED（按需生效）" "$(grep -q "ZZ-UNUSED" $W/sys.elf && echo yes || echo no)" "no"
SZ_AR=$(stat -c %s $W/sys.elf)

# ── ④ 对照：全量链接（把三个 .o 直接列出）必须更大且含 ZZ-UNUSED ──
#    没有这个对照，"产物里搜不到"可能只是因为字符串恰好没写进去。
./a64ld.elf $W/full.elf $W/main.o $W/lib.o $W/a.o $W/b.o $W/unused.o > $W/full.log 2>&1
chk "全量链接退出码" "$?" "0"
chk "全量产物含 ZZ-UNUSED" "$(grep -q "ZZ-UNUSED" $W/full.elf && echo yes || echo no)" "yes"
SZ_FULL=$(stat -c %s $W/full.elf)
chk "按需产物比全量小" "$([ "$SZ_AR" -lt "$SZ_FULL" ] && echo yes || echo no)" "yes"

# ── ⑤ 端到端执行（模拟器里跑裸机，下面没有 Linux/libc）──
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} timeout 300 python3 $ROOT/tools/kern64run.py $W/sys.elf --steps 400000 > $W/run.txt 2>$W/run.err
OUT=$(grep -v "^---" $W/run.txt | grep -v '^$')
chk "裸机输出" "$OUT" "A
B
MO-AR
SYS OK"
for L in "A" "B" "MO-AR" "SYS OK"; do
    chk "输出含 $L" "$(printf '%s\n' "$OUT" | grep -cx "$L")" "1"
done

# ── 负例一：不给归档 → fna 必须未定义 ───────────────────────
./a64ld.elf $W/noa.elf $W/main.o $W/lib.o > $W/noa.log 2>&1
chk "缺归档时报错" "$?" "1"
grep -q "undefined symbol" $W/noa.log || { echo "✗ 未报 undefined symbol"; cat $W/noa.log; FAILN=$((FAILN+1)); }
grep -q "fna" $W/noa.log || { echo "✗ 未点名 fna"; cat $W/noa.log; FAILN=$((FAILN+1)); }

# ── 负例二：归档 magic 被破坏 → 必须报错，不能当 .o 处理 ───────
python3 -c "
d = bytearray(open('/tmp/a64artest/libx.a','rb').read())
d[0:8] = b'XXXXXXXX'
open('/tmp/a64artest/bad.a','wb').write(bytes(d))"
./a64ld.elf $W/bad.elf $W/main.o $W/lib.o $W/bad.a > $W/bad.log 2>&1
chk "magic 破坏时报错" "$?" "1"

echo "a64artest: $PASS 通过 / $FAILN 失败"
[ "$FAILN" = "0" ]
