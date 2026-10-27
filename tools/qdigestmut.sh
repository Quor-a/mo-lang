#!/bin/bash
# qdigestmut —— Q-digest 的变异验证
#
# 只跑 make test 证明不了断言非空转：21 项全绿也可能是"断言恒真"。
# 本脚本把 lib/qdigest.mo 改回**已知的缺陷状态**，要求 tests/149_qdigest.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链（M6 第一版就改错了地方，恒未捕获）。
#   4. 每次 apply 后**读回校验**：沙盒文件系统有写入可见性延迟，
#      否则"变异没生效"却打印全绿。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/qdigest.mo
BAKD=build/qdigestmut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/qdigest.mo"

restore() { cp -f "$BAKD/qdigest.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot149 && mkdir -p /tmp/mot149
    cp "$HERE"/lib/*.mo /tmp/mot149/
    cp "$HERE"/tests/149_qdigest.mo /tmp/mot149/test.mo
    ( cd /tmp/mot149 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot149/out.elf 2>/dev/null
    ( cd /tmp/mot149 && ./out.elf ) >/tmp/mot149/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new, cnt=1):
    s = open("lib/qdigest.mo").read()
    assert old in s, "anchor not found: " + old[:70]
    s2 = s.replace(old, new, cnt)
    assert s2 != s, "replace was a no-op: " + tag
    open("lib/qdigest.mo", 'w').write(s2)
    chk = open("lib/qdigest.mo").read()
    assert new in chk, "mutation did not land: " + tag

# ── 压缩核心：父 += 左 + 右，孩子清零 ──────────────────────
MERGE3 = ("        if QK + QV + QW <= k {\n"
          "            QDP[h + 2 + QI] = QK + QV + QW;\n"
          "            QDP[h + 2 + QI * 2] = 0;\n"
          "            QDP[h + 2 + QI * 2 + 1] = 0;\n"
          "        }\n")

if tag == "M1":
    # 只清零孩子、不把计数加到父节点 ⇒ 质量凭空消失
    sub(MERGE3,
        "        if QK + QV + QW <= k {\n"
        "            QDP[h + 2 + QI * 2] = 0;\n"
        "            QDP[h + 2 + QI * 2 + 1] = 0;\n"
        "        }\n")
elif tag == "M2":
    # 加到父节点但不清零孩子 ⇒ 同一份质量被数两次
    sub(MERGE3,
        "        if QK + QV + QW <= k {\n"
        "            QDP[h + 2 + QI] = QK + QV + QW;\n"
        "        }\n")
elif tag == "M3":
    # 查询的累计判据 >= 改 >  ⇒ 差一
    sub("        if QV >= r { return QI; }",
        "        if QV > r { return QI; }")
elif tag == "M4":
    # 压缩改成自顶向下 ⇒ 只有最上面几层生效，节点数几乎不降
    sub("    QI = QD_SIG - 1;\n"
        "    while QI >= 1 {\n"
        "        QV = QDP[h + 2 + QI * 2];",
        "    QI = 1;\n"
        "    while QI <= QD_SIG - 1 {\n"
        "        QV = QDP[h + 2 + QI * 2];")
    sub("        QI = QI - 1;\n"
        "    }\n"
        "    return 0;\n"
        "}\n"
        "\n"
        "# ── 查询",
        "        QI = QI + 1;\n"
        "    }\n"
        "    return 0;\n"
        "}\n"
        "\n"
        "# ── 查询")
elif tag == "M5":
    # 合并改成逐节点取 max ⇒ 总量不再是 Na + Nb
    sub("        QDP[c + 2 + QI] = QDP[a + 2 + QI] + QDP[b + 2 + QI];",
        "        QDP[c + 2 + QI] = QDP[a + 2 + QI];\n"
        "        if QDP[b + 2 + QI] > QDP[c + 2 + QI] { QDP[c + 2 + QI] = QDP[b + 2 + QI]; }")
else:
    raise SystemExit("unknown mutation " + tag)
PY
}

fail=0

# ── 0) 基线必须先通过 ──────────────────────────────────────
base=$(run_test)
if [ "$base" = "0" ]; then
    echo "✓ 基线通过（退出码 0）"
else
    echo "✗ 基线就没通过（退出码 $base）—— 后面的结论全部无效"
    cat /tmp/mot149/o.txt 2>/dev/null | head -20
    exit 1
fi

for m in M1 M2 M3 M4 M5; do
    restore
    if ! apply_mut "$m"; then
        echo "✗ $m 变异未能生效（锚点没命中）"
        fail=$((fail+1))
        continue
    fi
    got=$(run_test)
    nred=$(grep -c '^FAIL' /tmp/mot149/o.txt 2>/dev/null)
    if [ "$got" != "0" ]; then
        echo "✓ $m 变异被捕获 → $(grep -m1 '^FAIL' /tmp/mot149/o.txt 2>/dev/null)（${nred} 项红，rc=$got）"
    else
        echo "✗ $m 变异**未被捕获**（149 仍全绿）"
        fail=$((fail+1))
    fi
done

restore
echo "---- 还原后复查 ----"
after=$(run_test)
if [ "$after" = "0" ]; then echo "✓ 还原后基线仍通过"; else echo "✗ 还原后基线不通过（rc=$after）"; fail=$((fail+1)); fi

echo "未捕获的变异数：$fail"
exit $fail
