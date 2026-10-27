#!/bin/bash
# aifixmut —— 证明 tools/aifix.sh **自身**有效
#
#   make aifixmut
#
# 为什么要有它
# ------------
# aifix 是"AI 修复 bug 的闭环"，它自己也是一段会写坏的代码。
# 它的四条守卫（拒绝生成物 / 唯一匹配 / 找不到就报 / 没钉住就报）
# 每一条都可以被悄悄改掉，而改掉之后 aifix **照样打印"结论：修复有效"**。
# 那就是最坏的一种失效：验证工具自己骗自己。
#
# 四个场景各配一个变异，判据是「aifix 的行为是否改变」：
#
#   M1 去掉「拒绝 src/compiler.mo」        → 场景 A 不再 exit 2
#   M2 「变异必须失败」改成恒真            → 场景 B 从 exit 1 变成 exit 0
#   M3 去掉 python 里的 NO_MATCH 检查      → 场景 D 不再 exit 2
#   M4 去掉 python 里的 MULTI_MATCH 检查   → 场景 C 不再 exit 2
#
# 场景 B 用的是**假的修复**（改一行注释）：测试本来就通过，
# 撤掉修复也通过。合格的 aifix 必须报「没被钉住」而不是「修复有效」。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SRC=tools/aifix.sh
PKG=examples/pkgv2.mo
BAK=build/aifixmut
mkdir -p "$BAK"
cp "$SRC" "$BAK/aifix.orig"
cp "$PKG" "$BAK/pkgv2.orig"
cp src/compiler.mo "$BAK/compiler.orig"

PASS=0
FAIL=0

ck() {
    if [ "$2" = "$3" ]; then
        echo "  ✓ $1 ($2)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $1 (得到 '$2' 想要 '$3')"
        FAIL=$((FAIL + 1))
    fi
}

restore_all() {
    cp "$BAK/aifix.orig" "$SRC"
    cp "$BAK/pkgv2.orig" "$PKG"
    cp "$BAK/compiler.orig" src/compiler.mo
    make bin/moc >/dev/null 2>&1
}
trap 'echo; echo "⚠ 中断 —— 还原 aifix.sh / pkgv2.mo / compiler.mo"; restore_all; exit 130' INT TERM

# 变异：精确子串替换，用 python 不用 sed（v1.137 教训）
mutate() {   # mutate <old> <new>
    python3 - "$SRC" "$1" "$2" <<'PYEOF'
import sys
p, o, n = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
if s.count(o) != 1:
    print("ANCHOR_MISS %d" % s.count(o)); sys.exit(1)
open(p, 'w', encoding='utf-8').write(s.replace(o, n))
print("OK")
PYEOF
}

# ---- 场景 A：不能把补丁打在生成物上 ----
# 锚点刻意取一行**注释**：万一"拒绝生成物"这条守卫失效，aifix 真的动手改，
# 改的也只是注释，不会让 src/compiler.mo 编不过（v1.157 第一版用
# 'fn main()' 当锚点，M1 变异下一跑就把 main 改没了，make boot 直接
# "no main function" —— 验证脚本自己污染了被验证的项目）。
scene_a() {
    bash tools/aifix.sh --file src/compiler.mo \
        --old '#  读取 .mo 源码，输出 ELF64 静态可执行文件（x86-64 / Linux）' \
        --new '#  读取 .mo 源码（aifixmut 场景 A）' \
        --test true >"$BAK/a.log" 2>&1
    local rc=$?
    cp "$BAK/compiler.orig" src/compiler.mo
    echo $rc
}
# ---- 场景 B：假修复必须被判为「没被钉住」 ----
scene_b() {
    bash tools/aifix.sh --file examples/pkgv2.mo \
        --old 'pkgv2.mo —— 真正的包管理器' --new 'pkgv2.mo —— 包管理器' \
        --test true >"$BAK/b.log" 2>&1
    echo $?
}
# ---- 场景 C：--old 出现多次必须拒绝 ----
scene_c() {
    bash tools/aifix.sh --file examples/pkgv2.mo \
        --old 'bemit(1);' --new 'bemit(1); ' --test true >"$BAK/c.log" 2>&1
    echo $?
}
# ---- 场景 D：--old 找不到必须拒绝 ----
scene_d() {
    bash tools/aifix.sh --file examples/pkgv2.mo \
        --old '这一行在 pkgv2.mo 里绝不存在 XYZ' --new 'zzz' \
        --test true >"$BAK/d.log" 2>&1
    echo $?
}

echo "=== aifixmut：证明 aifix 自己的守卫有效 ==="

# ---------------- 基线 ----------------
restore_all
A0=$(scene_a); B0=$(scene_b); C0=$(scene_c); D0=$(scene_d)
restore_all
echo
echo "基线：A=$A0 B=$B0 C=$C0 D=$D0"
ck "基线 A 拒绝生成物"   "$A0" "2"
ck "基线 B 报未被钉住"   "$B0" "1"
ck "基线 C 拒绝多处匹配" "$C0" "2"
ck "基线 D 拒绝找不到"   "$D0" "2"
grep -q "拒绝" "$BAK/a.log" && ck "基线 A 说明含'拒绝'" yes yes || ck "基线 A 说明含'拒绝'" no yes
grep -q "没被钉住" "$BAK/b.log" && ck "基线 B 说明含'没被钉住'" yes yes || ck "基线 B 说明含'没被钉住'" no yes

# ---------------- M1 ----------------
restore_all
R=$(mutate '    src/compiler.mo)
        echo "❌ 拒绝' '    xsrc/compiler.mo)
        echo "❌ 拒绝')
ck "M1 锚点" "$R" "OK"
A1=$(scene_a)
ck "M1 去掉拒绝 → A 不再 exit 2" "$([ "$A1" != "$A0" ] && echo changed || echo same)" "changed"
restore_all

# ---------------- M2 ----------------
R=$(mutate '    if [ "$RC_MUT" -ne 0 ]; then' '    if [ 1 -eq 1 ]; then')
ck "M2 锚点" "$R" "OK"
B1=$(scene_b)
ck "M2 判据恒真 → B 不再 exit 1" "$([ "$B1" != "$B0" ] && echo changed || echo same)" "changed"
restore_all

# ---------------- M3 ----------------
R=$(mutate 'if c == 0:
    print("NO_MATCH")
    sys.exit(1)' 'if c == 0:
    pass')
ck "M3 锚点" "$R" "OK"
D1=$(scene_d)
ck "M3 去掉 NO_MATCH → D 不再 exit 2" "$([ "$D1" != "$D0" ] && echo changed || echo same)" "changed"
restore_all

# ---------------- M4 ----------------
R=$(mutate 'if c > 1:
    print("MULTI_MATCH %d" % c)
    sys.exit(1)' 'if c > 1:
    pass')
ck "M4 锚点" "$R" "OK"
C1=$(scene_c)
ck "M4 去掉 MULTI_MATCH → C 不再 exit 2" "$([ "$C1" != "$C0" ] && echo changed || echo same)" "changed"
restore_all

# 收尾：保留备份副本（被强杀后源码可能停在变异态，备份不能跟着删）
echo
echo "通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
