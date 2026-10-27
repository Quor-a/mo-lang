#!/bin/bash
# bitmut —— Fenwick 树的变异验证
#
# 只跑 make test 证明不了断言非空转：30 项全绿也可能是"断言恒真"。
# 本脚本把 lib/bit.mo 改回**已知的缺陷状态**，要求 tests/150_bit.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链。
#   4. 每次 apply 后**读回校验**：沙盒文件系统有写入可见性延迟，
#      否则"变异没生效"却打印全绿。
#   5. 锚点必须带足够上下文（含换行），否则短串会命中无关位置
#      （v1.141 的 importasmut 就栽过：12 空格是 16 空格那行的后缀）。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/bit.mo
BAKD=build/bitmut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/bit.mo"

restore() { cp -f "$BAKD/bit.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot150 && mkdir -p /tmp/mot150
    cp "$HERE"/lib/*.mo /tmp/mot150/
    cp "$HERE"/tests/150_bit.mo /tmp/mot150/test.mo
    ( cd /tmp/mot150 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot150/out.elf 2>/dev/null
    ( cd /tmp/mot150 && ./out.elf ) >/tmp/mot150/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new, cnt=1):
    s = open("lib/bit.mo").read()
    assert old in s, "anchor not found: " + old[:70]
    s2 = s.replace(old, new, cnt)
    assert s2 != s, "replace was a no-op: " + tag
    open("lib/bit.mo", 'w').write(s2)
    chk = open("lib/bit.mo").read()
    assert new in chk, "mutation did not land: " + tag

if tag == "M1":
    # O(n) 建树读错一格（本轮真实踩到的缺陷）：
    #   total 恰好差 SRC[n]−SRC[0]，不报错不崩溃，所有前缀和看着都合理
    sub("        BITPOOL[h + BI] = BITPOOL[h + BI] + load64(src + BI * 8);",
        "        BITPOOL[h + BI] = BITPOOL[h + BI] + load64(src + (BI - 1) * 8);")
elif tag == "M2":
    # 单点加的步进改成 +1 ⇒ 退化成线性且覆盖错误的节点
    sub("        BJ = BJ + lowbit(BJ);",
        "        BJ = BJ + 1;")
elif tag == "M3":
    # 前缀和的步进改成 -1 ⇒ 退化为线性扫描且漏掉部分节点
    sub("        BJ = BJ - lowbit(BJ);",
        "        BJ = BJ - 1;")
elif tag == "M4":
    # lower_bound 的判据 < 改 <= ⇒ 差一（答案偏左一格）
    sub("            if BITPOOL[h + BQ] < BK {",
        "            if BITPOOL[h + BQ] <= BK {")
elif tag == "M5":
    # 二分提升的起始步长不放大到最大 2 的幂 ⇒ 只跳一步，答案偏左
    sub("    BG = 1;\n"
        "    while BG * 2 <= n {\n"
        "        BG = BG * 2;\n"
        "    }\n",
        "    BG = 1;\n")
elif tag == "M6":
    # 合并改成逐格取 max（CBF 的合并是 max，但 BIT 必须是相加）
    sub("        BITPOOL[a + BI] = BITPOOL[a + BI] + BITPOOL[b + BI];",
        "        if BITPOOL[b + BI] > BITPOOL[a + BI] {\n"
        "            BITPOOL[a + BI] = BITPOOL[b + BI];\n"
        "        }")
elif tag == "M7":
    # 拆分变成空操作 ⇒ merge 不再可逆
    sub("        BITPOOL[a + BI] = BITPOOL[a + BI] - BITPOOL[b + BI];",
        "        BITPOOL[a + BI] = BITPOOL[a + BI];")
elif tag == "M8":
    # lowbit 算错：x & (x-1) 清掉的是最低置位，不是取最低置位
    sub("fn lowbit(x: i64) -> i64 {\n    return x & (0 - x);\n}",
        "fn lowbit(x: i64) -> i64 {\n    return x & (x - 1);\n}")
else:
    raise SystemExit("unknown mutation " + tag)
PY
}

fail=0
pass=0

# ── 0) 基线必须先通过 ──────────────────────────────────────
base=$(run_test)
if [ "$base" = "0" ]; then
    echo "✓ 基线通过（退出码 0）"
else
    echo "✗ 基线就没通过（退出码 $base）—— 后面的结论全部无效"
    cat /tmp/mot150/o.txt 2>/dev/null | head -20
    exit 1
fi

for m in M1 M2 M3 M4 M5 M6 M7 M8; do
    restore
    if ! apply_mut "$m"; then
        echo "✗ $m 变异未能生效（锚点没命中）"
        fail=$((fail+1))
        continue
    fi
    got=$(run_test)
    nred=$(grep -c '^FAIL' /tmp/mot150/o.txt 2>/dev/null)
    if [ "$got" != "0" ]; then
        echo "✓ $m 变异被捕获 → $(grep -m1 '^FAIL' /tmp/mot150/o.txt 2>/dev/null)（${nred} 项红，rc=$got）"
        pass=$((pass+1))
    else
        echo "✗ $m 变异**未被捕获**（150 仍全绿）"
        fail=$((fail+1))
    fi
done

restore
echo "---- 还原后复查 ----"
after=$(run_test)
if [ "$after" = "0" ]; then echo "✓ 还原后基线仍通过"; else echo "✗ 还原后基线不通过（rc=$after）"; fail=$((fail+1)); fi

echo "捕获 $pass 个，未捕获 $fail 个"
exit $fail
