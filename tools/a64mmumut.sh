#!/usr/bin/env bash
# a64mmumut —— 证明 a64mmutest 真的能抓到缺陷（6 个变异，各自改一条因果链）
#
# 每个变异改的是**一条具体的因果链**：
#   M1 用户自己的块也设成 AP=00      → 用户连自己的内存都写不了
#   M2 只读块改成可写                → 写不被拦，值还被改掉
#   M3 内核私有块改成用户可访问      → 隔离失效，秘密值被改
#   M4 未映射块补上映射              → 转换错误变成权限错误（TR3→PF3）
#   M5 模拟器一律给全权限            → 不隔离，V BAD
#   M6 模拟器不区分转换/权限错误      → TR3 变 PF3（内核拿到错的原因）
#
# 变异脚本自己也会失效，所以每次开工前先跑**基线**（必须 0 红），收尾再跑一次
# 确认还原干净 —— 备份取自被污染的源码是本项目栽过多次的老坑。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64mmutest
SRC=$ROOT/tools/a64mmu/main.s
SIM=$ROOT/tools/kern64run.py

[ -f $W/a64as.elf ] || bash tools/a64mmutest.sh > /dev/null 2>&1
cd $W

build() {   # 重新汇编 + 链接
    ./a64as.elf -r $SRC main.o > /dev/null 2>&1 || return 1
    ./a64ld.elf sys.elf main.o > /dev/null 2>&1 || return 1
}

# 判据：与 a64mmutest ④⑥ 同一组，红数 = 不满足的条数
judge() {
    timeout 300 python3 $SIM $W/sys.elf --exc 1 --mmu 1 > $W/m.txt 2>&1
    red=0
    for line in "MO-MMU" "U OK" "R OK" "PF1" "TR3" "UDONE" "DONE" "V OK" "N4"; do
        grep -qx "$line" $W/m.txt || red=$((red+1))
    done
    [ "$(grep -cx 'PF2' $W/m.txt)" = "2" ] || red=$((red+1))
    grep -q "V BAD" $W/m.txt && red=$((red+1))
    [ "$(grep -o 'eret=[0-9]*' $W/m.txt | head -1 | cut -d= -f2)" = "8" ] || red=$((red+1))
    return 0
}

cp $SRC $W/main.s.bak
cp $SIM $W/kern64run.py.bak

build
judge
BASE=$red
echo "基线红数: $BASE"
[ "$BASE" = "0" ] || { echo "✗ 基线就没过，变异结果不可信"; exit 1; }

py() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
assert s.count(old) == 1, "锚点命中 %d 次（应为 1）：%s" % (s.count(old), old[:40])
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
}

run_mut() {   # $1 = 名字，$2..：判据前的准备由调用方做
    name=$1
    build
    judge
    if [ "$red" -gt 0 ]; then
        echo "  $name 被捕获（$red 项红）"; CAP=$((CAP+1))
    else
        echo "  $name **未被捕获**（0 项红）—— 判据有洞"; MISS=$((MISS+1))
    fi
}

CAP=0; MISS=0

# ── M1：用户块 AP=01 → 00 ──
py $SRC '        mov     x9, #0x0441' '        mov     x9, #0x0401'
run_mut "M1 用户块不可访问"
cp $W/main.s.bak $SRC

# ── M2：只读块 AP=11 → 01 ──
py $SRC '        mov     x9, #0x04C1' '        mov     x9, #0x0441'
run_mut "M2 只读块可写"
cp $W/main.s.bak $SRC

# ── M3：内核私有块 AP=00 → 01 ──
py $SRC '        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4040, lsl #32' '        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4040, lsl #32'
run_mut "M3 内核私有块可访问"
cp $W/main.s.bak $SRC

# ── M4：未映射块补上映射（AP=00）──
py $SRC '        str     x9, [x14, #16]' '        str     x9, [x14, #16]
        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4060, lsl #32
        movk    x9, #0x0040, lsl #48
        str     x9, [x14, #24]'
run_mut "M4 未映射块补映射"
cp $W/main.s.bak $SRC

# ── M5：模拟器一律给全权限 ──
py $SIM '            prot.append(pr)' '            prot.append(UC_PROT_ALL)'
run_mut "M5 模拟器不隔离"
cp $W/kern64run.py.bak $SIM

# ── M6：不区分转换错误与权限错误 ──
py $SIM '                dfsc = DFSC_TRANS + lvl' '                dfsc = DFSC_PERM + lvl'
run_mut "M6 故障原因不区分"
cp $W/kern64run.py.bak $SIM

# ── 还原自检：源码与模拟器都必须回到基线 ──
cmp -s $SRC $W/main.s.bak && echo "  还原自检: main.s 干净" || { echo "✗ main.s 未还原"; MISS=$((MISS+2)); }
cmp -s $SIM $W/kern64run.py.bak && echo "  还原自检: kern64run.py 干净" || { echo "✗ kern64run.py 未还原"; MISS=$((MISS+2)); }
build
judge
echo "还原后基线红数: $red"
[ "$red" = "0" ] || { echo "✗ 还原后基线不为 0"; MISS=$((MISS+2)); }

echo "a64mmumut: $CAP 被捕获 / $MISS 未捕获（共 6 个变异）"
[ $MISS -eq 0 ] && [ $CAP -eq 6 ]
