#!/bin/bash
# cbfmergemut —— CBF 合并（逐格 max）的变异验证
#
# 只跑 make test 证明不了断言非空转：21 项全绿也可能是"断言恒真"。
# 本脚本把 lib/cbf.mo 改回**已知的缺陷状态**，要求 tests/148_cbfmerge.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 沙盒文件系统有写入可见性延迟：写完立刻读可能拿到旧内容，
#      于是"变异没生效"却打印全绿。apply 后**读回校验**。
#   4. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链。
#
# ── 🔴 M1 是本脚本要证明的核心结论 ────────────────────────
#   "整字 max"（对打包后的 i64 取 max）仍然满足**交换律、结合律、幂等律**
#   —— 格的三条律对"错误的运算"一样成立。
#   所以 148 里的交换/结合/幂等三条断言在 M1 下**依然全绿**。
#   抓到它的只有两条：① 与独立算出的逐格 max 比对；② 无假阴检查。
#   脚本会把 M1 下"哪些断言红了"打出来，作为这条结论的证据。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/cbf.mo
BAKD=build/cbfmergemut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/cbf.mo"

restore() { cp -f "$BAKD/cbf.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot148 && mkdir -p /tmp/mot148
    cp "$HERE"/lib/*.mo /tmp/mot148/
    cp "$HERE"/tests/148_cbfmerge.mo /tmp/mot148/test.mo
    ( cd /tmp/mot148 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot148/out.elf 2>/dev/null
    ( cd /tmp/mot148 && ./out.elf ) >/tmp/mot148/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new, cnt=1):
    s = open("lib/cbf.mo").read()
    assert old in s, "anchor not found: " + old[:60]
    s2 = s.replace(old, new, cnt)
    open("lib/cbf.mo", 'w').write(s2)
    chk = open("lib/cbf.mo").read()
    assert new in chk, "mutation did not land: " + tag

LOOP = ("    m = CBFP[dst];\n"
        "    CFI = 0;\n"
        "    while CFI < m {\n"
        "        va = cbf_cell(dst, CFI);\n"
        "        vb = cbf_cell(src, CFI);\n"
        "        if vb > va { cbf_setc(dst, CFI, vb); }\n"
        "        CFI = CFI + 1;\n"
        "    }\n")

if tag == "M1":
    # 整字 max：对打包后的 i64 取 max（max 在 4-bit 字段上不满足分配律）
    sub(LOOP,
        "    m = CBFP[dst];\n"
        "    CFI = 0;\n"
        "    while CFI < CBFP[dst + 2] {\n"
        "        if CBFP[src + 3 + CFI] > CBFP[dst + 3 + CFI] {\n"
        "            CBFP[dst + 3 + CFI] = CBFP[src + 3 + CFI];\n"
        "        }\n"
        "        CFI = CFI + 1;\n"
        "    }\n")

elif tag == "M2":
    # max 改 min ⟹ 大量格被取小到 0 ⟹ 假阴
    sub("        if vb > va { cbf_setc(dst, CFI, vb); }",
        "        if vb < va { cbf_setc(dst, CFI, vb); }")

elif tag == "M3":
    # 去掉参数校验 ⟹ m/k 不同也静默"半合并"
    sub("    if CBFP[dst] != CBFP[src] { CBFBAD = 1; return 0 - 1; }\n"
        "    if CBFP[dst + 1] != CBFP[src + 1] { CBFBAD = 1; return 0 - 1; }\n",
        "")

elif tag == "M4":
    # max 改相加（带饱和）⟹ 破坏幂等律（自合并翻倍）
    sub("        if vb > va { cbf_setc(dst, CFI, vb); }",
        "        if va + vb > 15 { cbf_setc(dst, CFI, 15); } else { cbf_setc(dst, CFI, va + vb); }")

elif tag == "M5":
    # 循环上界用 words（= m/16）⟹ 只合并前 1/16 ⟹ 大量假阴
    sub("    while CFI < m {\n        va = cbf_cell(dst, CFI);",
        "    while CFI < CBFP[dst + 2] {\n        va = cbf_cell(dst, CFI);")

elif tag == "M6":
    # 读反 dst/src ⟹ dst = max(dst,dst) = dst ⟹ 合并变成空操作
    sub("        va = cbf_cell(dst, CFI);\n        vb = cbf_cell(src, CFI);",
        "        va = cbf_cell(src, CFI);\n        vb = cbf_cell(dst, CFI);")
PY
}

fail=0
echo "=== baseline ==="
rc=$(run_test)
if [ "$rc" = "0" ]; then echo "  baseline PASS (rc=0)"; else echo "  baseline FAIL rc=$rc"; fail=1; fi

for M in M1 M2 M3 M4 M5 M6; do
    restore
    apply_mut "$M" || { echo "  $M apply error"; fail=1; continue; }
    rc=$(run_test)
    if [ "$rc" = "0" ]; then
        echo "  $M NOT caught (rc=0)"
        fail=1
    else
        echo "  $M caught (rc=$rc)"
        if [ "$M" = "M1" ]; then
            echo "    ── M1 下红了哪些断言（证明交换/结合/幂等**没**抓到它）："
            grep '^FAIL' /tmp/mot148/o.txt | sed 's/^/    /'
        fi
    fi
done

restore
echo "=== mutated-source check ==="
if grep -q "CBFP\[dst + 3 + CFI\] = CBFP\[src + 3 + CFI\]" lib/cbf.mo; then
    echo "  ERROR cbf.mo still mutated"; fail=1
fi
if grep -q "if va + vb > 15" lib/cbf.mo; then
    echo "  ERROR cbf.mo still mutated (M4)"; fail=1
fi
echo "=== RESULT fail=$fail ==="
exit $fail
