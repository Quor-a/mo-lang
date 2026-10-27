#!/usr/bin/env bash
# a64execmut —— 证明 a64exectest 的判据真的能抓到缺陷
#
# 形式与 a64exectest.sh 不同：这里**不重跑整套** 43 项，而是每个变异只重编
# 内核镜像、跑一次模拟器、比对关键行。整套重跑要 6 ×（重编汇编器 + 链接器
# + 3M 步模拟），在沙盒里必然超时；而"整套绿"和"关键行没变"是两回事 ——
# 探针只盯那一条会变的判据，反而更不容易被别处的噪声掩盖。
#
# 每个变异只改**一条因果链**，对应的关键行必须变。变不了就说明那组断言
# 是空转的 —— 这和被测代码有缺陷一样严重。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=$ROOT/tools/a64exec/main.s
BAK=/tmp/a64execmut_main.s.bak
T=/tmp/a64execmut_tools
W=/tmp/a64execmut_work
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
    echo "a64execmut: 汇编器/链接器编译失败"; exit 1
fi

# ── 用户镜像与负例镜像（只生成一次）──
$T/a64as.elf -r $ROOT/tools/a64exec/user.s $W/user.o > /dev/null 2>&1
$T/a64ld.elf --base 1075838976 $W/user.elf $W/user.o > /dev/null 2>&1
python3 - "$W" <<'PY'
import sys, os, struct
w = sys.argv[1]
e = bytearray(open(os.path.join(w, "user.elf"), "rb").read())
# 入口改成 +0x14：跳过前 5 条指令，直接从求和开始
b = bytearray(e); struct.pack_into("<Q", b, 24, 0x40200014)
open(os.path.join(w, "user_entry.elf"), "wb").write(bytes(b))
# 负例：机器类型改成 x86-64 / 段 memsz 放大到 16MB
a = bytearray(e); struct.pack_into("<H", a, 18, 62)
open(os.path.join(w, "bad_mach.elf"), "wb").write(bytes(a))
a = bytearray(e)
off = struct.unpack_from("<Q", a, 32)[0]
struct.pack_into("<Q", a, off + 40, 0x1000000)
open(os.path.join(w, "bad_seg.elf"), "wb").write(bytes(a))
PY

build() {  # 重编内核镜像
    $T/a64as.elf -r $SRC $W/main.o > /dev/null 2>&1
    $T/a64ld.elf $W/kern.elf $W/main.o > /dev/null 2>&1
}
gout() {  # gout <elf> —— 跑一次并回显输出
    python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 \
        --initrd "$1"@0x40410000 --steps 3000000 2>/dev/null
}
has() { [ "$(printf '%s\n' "$1" | grep -c "^$2\$")" != "0" ]; }

# ── 基线 ──
build
BASE=$(gout $W/user.elf)
BASE_MACH=$(gout $W/bad_mach.elf)
BASE_SEG=$(gout $W/bad_seg.elf)
BASE_ENTRY=$(gout $W/user_entry.elf)
chk_base() {
    if has "$BASE" "$1"; then :; else echo "✗ 基线缺少 '$1'"; fi
    if has "$BASE_MACH" "E-3"; then :; else echo "✗ 基线负例 mach 不是 E-3"; fi
    if has "$BASE_SEG" "E-7"; then :; else echo "✗ 基线负例 seg 不是 E-7"; fi
    if has "$BASE_ENTRY" "5050"; then :; else echo "✗ 基线改入口后没算出 5050"; fi
}
BASEOK=$(chk_base "U1"; chk_base "0"; chk_base "5050")
if [ -n "$BASEOK" ]; then echo "$BASEOK"; echo "a64execmut: 基线本身不成立"; exit 1; fi

mut() {  # mut <name> <old@@@new> <elf> <判据: 期望出现|期望不出现>
    local name="$1" code="$2" elf="$3" want="$4" mode="$5"
    cp $BAK $SRC
    python3 - "$SRC" "$code" <<'PY'
import sys
path, code = sys.argv[1], sys.argv[2]
s = open(path).read()
old, new = code.split("@@@")
if old not in s:
    sys.stderr.write("锚点未命中\n"); sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
    if [ $? != 0 ]; then
        echo "✗ $name: 锚点未命中（变异未生效）"; NMUT=$((NMUT+1)); return
    fi
    NMUT=$((NMUT+1))
    build
    local o; o=$(gout $elf)
    local got=no
    if has "$o" "$want"; then got=yes; fi
    if [ "$got" = "$mode" ]; then
        NCATCH=$((NCATCH+1)); echo "✓ $name: 被捕获"
    else
        echo "✗ $name: 未被捕获（期望'$want' $mode，实际 $got）"
    fi
}

# M1 不校验 e_machine：x86-64 的 ELF 会被当成 aarch64 加载
mut "M1 不校验 machine" \
'        b.ne    le_mach
@@@        b.ne    le_phes
' $W/bad_mach.elf "E-3" no

# M2 不清零 bss：用户读到的是内核污染留下的 0xA5A5A5A5
mut "M2 不清零 bss" \
'le_zero:
        cmp     x20, x15
@@@le_zero:
        b       le_next2
        cmp     x20, x15
' $W/user.elf "0" no

# M3 不复制 PT_LOAD：用户区只剩清零过的字节
mut "M3 不复制段" \
'le_copy:
        cmp     x20, x14
@@@le_copy:
        b       le_zero
        cmp     x20, x14
' $W/user.elf "U1" no

# M4 用户区设成 AP=00：用户一取指就被拦
mut "M4 用户区不可执行" \
'        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4020, lsl #32
@@@        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4020, lsl #32
' $W/user.elf "U1" no

# M5 不校验段越界：锚点必须是 **b.gt**（越过上界）那条 —— 越界负例改的是
# memsz，走的是上界分支；改下界的 b.lt 完全不起作用，第一版就选错了。
mut "M5 不校验段越界" \
'        b.gt    le_seg
@@@        nop
' $W/bad_seg.elf "E-7" no

# M6 入口写死：改 ELF 头的 e_entry 不再起作用
mut "M6 入口写死" \
'        mov     x0, x27
        ret
@@@        mov     x0, #0
        movk    x0, #0x4020, lsl #16
        ret
' $W/user_entry.elf "U1" yes

restore
echo "a64execmut: $NCATCH / $NMUT 被捕获"
if [ "$NCATCH" != "$NMUT" ]; then exit 1; fi
exit 0
