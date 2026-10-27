#!/bin/bash
# fenwmut —— Fenwick 树（BIT）的变异验证
#
# 只跑 make test 证明不了断言非空转：24 项全绿也可能是"断言恒真"。
# 本脚本把 lib/fenw.mo 改回**已知的缺陷状态**，要求 tests/150_fenw.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链。
#   4. 每次 apply 后**读回校验**：沙盒文件系统有写入可见性延迟，
#      否则"变异没生效"却打印全绿。
#   5. 必须有 timeout：M3 是死循环变异，没有 timeout 会把整条链拖死。
#   6. 开工前**预检源码是否已是变异态** —— 否则备份本身就是污染版，
#      后面每一轮都从污染态开始，结论全部无效。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/fenw.mo
BAKD=build/fenwmut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/fenw.mo"

restore() { cp -f "$BAKD/fenw.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot150 && mkdir -p /tmp/mot150
    cp "$HERE"/lib/*.mo /tmp/mot150/
    cp "$HERE"/tests/150_fenw.mo /tmp/mot150/test.mo
    ( cd /tmp/mot150 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot150/out.elf 2>/dev/null
    ( cd /tmp/mot150 && timeout 30 ./out.elf ) >/tmp/mot150/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new):
    s = open("lib/fenw.mo").read()
    assert old in s, "anchor not found: " + old[:70]
    s2 = s.replace(old, new, 1)
    assert s2 != s, "replace was a no-op: " + tag
    open("lib/fenw.mo", 'w').write(s2)
    assert new in open("lib/fenw.mo").read(), "mutation did not land: " + tag

# ── M1 前缀遍历：剥掉 lowbit → 逐个减 1 ───────────────────
#    值也错（Σ T[1..i] ≠ prefix(i)），且退化成 O(n)
M1 = ("        FWV = FWV + FWP[h + 1 + FWI];\n"
      "        FWI = FWI - (FWI & (0 - FWI));\n"
      "        FWSTEP = FWSTEP + 1;\n")

# ── M2 只改步数计数，值全对 ───────────────────────────────
#    ★ 本脚本最关键的一条：它证明「FWSTEP == popcount(i)」是
#      **承重**断言 —— 值断言一条都不会红，只有它能抓。
M2 = M1

# ── M3 前缀循环的终止条件 ─────────────────────────────────
M3 = ("    while FWI > 0 {\n"
      "        FWV = FWV + FWP[h + 1 + FWI];\n")

if tag == "M1":
    sub(M1,
        "        FWV = FWV + FWP[h + 1 + FWI];\n"
        "        FWI = FWI - 1;\n"
        "        FWSTEP = FWSTEP + 1;\n")
elif tag == "M2":
    sub(M2,
        "        FWV = FWV + FWP[h + 1 + FWI];\n"
        "        FWI = FWI - (FWI & (0 - FWI));\n"
        "        FWSTEP = FWSTEP + 2;\n")
elif tag == "M3":
    # FWI 归 0 后 0 - lowbit(0) == 0 ⇒ 死循环
    sub(M3,
        "    while FWI >= 0 {\n"
        "        FWV = FWV + FWP[h + 1 + FWI];\n")
elif tag == "M4":
    # 单点加的上升遍历改逐个 +1 ⇒ 更新错格子
    sub("        FWP[h + 1 + FWI] = FWP[h + 1 + FWI] + d;\n"
        "        FWI = FWI + (FWI & (0 - FWI));\n",
        "        FWP[h + 1 + FWI] = FWP[h + 1 + FWI] + d;\n"
        "        FWI = FWI + 1;\n")
elif tag == "M5":
    # lower_bound 的严格小于改小于等于 ⇒ 恰好命中时差一位
    sub("            if FWP[h + 1 + FWI] < FWW {\n",
        "            if FWP[h + 1 + FWI] <= FWW {\n")
elif tag == "M6":
    # 区间加的 B2 加权项：d*(l-1) → d*l ⇒ 少减一个 d
    sub("    fw_addb2(h, l, d * (l - 1));",
        "    fw_addb2(h, l, d * l);")
else:
    raise SystemExit("unknown mutation " + tag)
PY
}

# ── 0) 预检：源码必须处于干净态 ────────────────────────────
DIRTY=$(python3 - <<'PY'
s = open("lib/fenw.mo").read()
bad = []
for tag, needle in [
    ("M1", "        FWI = FWI - 1;\n        FWSTEP"),
    ("M2", "        FWSTEP = FWSTEP + 2;"),
    ("M3", "    while FWI >= 0 {"),
    ("M4", "        FWP[h + 1 + FWI] = FWP[h + 1 + FWI] + d;\n        FWI = FWI + 1;\n"),
    ("M5", "FWP[h + 1 + FWI] <= FWW"),
    ("M6", "    fw_addb2(h, l, d * l);"),
]:
    if needle in s:
        bad.append(tag)
print(",".join(bad))
PY
)
if [ -n "$DIRTY" ]; then
    echo "✗ 预检失败：源码已处于变异态（$DIRTY）—— 备份会跟着污染，后面结论全部无效"
    echo "  先把 lib/fenw.mo 手工还原（或从上一次 build/fenwmut_bak 取回）再跑"
    exit 1
fi

fail=0

# ── 1) 基线必须先通过 ──────────────────────────────────────
base=$(run_test)
if [ "$base" = "0" ]; then
    echo "✓ 基线通过（退出码 0）"
else
    echo "✗ 基线就没通过（退出码 $base）—— 后面的结论全部无效"
    head -20 /tmp/mot150/o.txt 2>/dev/null
    exit 1
fi

for m in M1 M2 M3 M4 M5 M6; do
    restore
    if ! apply_mut "$m"; then
        echo "✗ $m 变异未能生效（锚点没命中）"
        fail=$((fail+1))
        continue
    fi
    got=$(run_test)
    nred=$(grep -c '^FAIL' /tmp/mot150/o.txt 2>/dev/null)
    if [ "$got" != "0" ]; then
        first=$(grep -m1 '^FAIL' /tmp/mot150/o.txt 2>/dev/null)
        if [ "$got" = "124" ]; then
            echo "✓ $m 变异被捕获 → 程序挂住（timeout，exit 124，${nred} 项红）"
        else
            echo "✓ $m 变异被捕获 → ${first}（${nred} 项红，rc=$got）"
        fi
    else
        echo "✗ $m 变异**未被捕获**（150 仍全绿）"
        fail=$((fail+1))
    fi
done

restore
echo "---- 还原后复查 ----"
after=$(run_test)
if [ "$after" = "0" ]; then echo "✓ 还原后基线仍通过"; else echo "✗ 还原后基线不通过（rc=$after）"; fail=$((fail+1)); fi

echo "未捕获的变异数：$fail"
exit $fail
