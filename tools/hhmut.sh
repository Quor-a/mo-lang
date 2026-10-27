#!/bin/bash
# hhmut —— Heavy Hitters 的变异验证
#
# 只跑 make test 证明不了断言非空转：40 项全绿也可能是"断言恒真"。
# 本脚本把 lib/hh.mo 改回**已知的缺陷状态**，要求 tests/152_hh.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链。
#   4. 每次 apply 后**读回校验**：沙盒文件系统有写入可见性延迟，
#      否则"变异没生效"却打印全绿（v1.143 acmut 栽过）。
#   5. 锚点必须带函数签名等上下文 —— 只匹配一个短片段会命中另一个
#      同名片段（v1.141 importasmut 的 M3 就打错了函数）。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/hh.mo
TEST=tests/152_hh.mo
BAKD=build/hhmut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/hh.mo"

restore() { cp -f "$BAKD/hh.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot152 && mkdir -p /tmp/mot152
    cp "$HERE"/lib/*.mo /tmp/mot152/
    cp "$HERE"/$TEST /tmp/mot152/test.mo
    ( cd /tmp/mot152 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot152/out.elf 2>/dev/null
    ( cd /tmp/mot152 && ./out.elf ) >/tmp/mot152/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new, cnt=1):
    s = open("lib/hh.mo").read()
    assert old in s, "anchor not found: " + old[:70]
    s2 = s.replace(old, new, cnt)
    assert s2 != s, "replace was a no-op: " + tag
    open("lib/hh.mo", 'w').write(s2)
    chk = open("lib/hh.mo").read()
    assert new in chk, "mutation did not land: " + tag

# M1：mg_est 对不在表中的元素返回 D 而不是 0 ⇒ 破坏"est ≤ true"下界
if tag == "M1":
    sub("fn mg_est(x: i64) -> i64 {\n"
        "    HHQ1 = mg_find(x);\n"
        "    if HHQ1 < 0 {\n"
        "        return 0;\n"
        "    }",
        "fn mg_est(x: i64) -> i64 {\n"
        "    HHQ1 = mg_find(x);\n"
        "    if HHQ1 < 0 {\n"
        "        return MG_DEC;\n"
        "    }")

# M2：MG 减量时并不真的减 ⇒ 计数只增不减，est 会超过 true（下界破）
elif tag == "M2":
    sub("        MG_CNT[HH3] = MG_CNT[HH3] - c;",
        "        MG_CNT[HH3] = MG_CNT[HH3] - 0;")

# M3：SS 替换时新 count = c 而不是 旧count + c ⇒ est 偏小（上界破）
elif tag == "M3":
    sub("    SS_KEY[HH4] = x;\n"
        "    SS_CNT[HH4] = SS_CNT[HH4] + c;",
        "    SS_KEY[HH4] = x;\n"
        "    SS_CNT[HH4] = c;")

# M4：SS 替换时 err 记 0 ⇒ "est − err ≤ true" 这条界失去依据
elif tag == "M4":
    sub("    SS_ERR[HH4] = SS_CNT[HH4];",
        "    SS_ERR[HH4] = 0;")

# M5：MG 满时直接丢弃新元素、不做减量 ⇒ D 恒 0，
#     而"f > D 的元素必在表中"会挂一大片（不漏保证破）
elif tag == "M5":
    sub("    MG_DEC = MG_DEC + c;\n"
        "    HH2 = 0;      # 写指针",
        "    return 0;\n"
        "    MG_DEC = MG_DEC + c;\n"
        "    HH2 = 0;      # 写指针")

# M6：ss_est 对不在表中的元素返回 0 而不是 −1 ⇒ 假阴被伪装成"出现了 0 次"
elif tag == "M6":
    sub("fn ss_est(x: i64) -> i64 {\n"
        "    HHQ1 = ss_find(x);\n"
        "    if HHQ1 < 0 {\n"
        "        return 0 - 1;\n"
        "    }",
        "fn ss_est(x: i64) -> i64 {\n"
        "    HHQ1 = ss_find(x);\n"
        "    if HHQ1 < 0 {\n"
        "        return 0;\n"
        "    }")

# M7：SS 替换 count **最大**的那个 ⇒ 重击者会被踢掉（不漏保证破）
elif tag == "M7":
    sub("        if SS_CNT[HHA1] < HHM1 {",
        "        if SS_CNT[HHA1] > HHM1 {")

else:
    raise SystemExit("unknown mutation " + tag)
PY
}

fail=0
pass=0

# ── 基线必须全绿 ──────────────────────────────────────────
restore
b=$(run_test)
if [ "$b" = "0" ]; then
    echo "✓ 基线通过 (rc=0)"
else
    echo "✗ 基线就没通过 (rc=$b) —— 后面的结论全部无效"
    exit 1
fi

for m in M1 M2 M3 M4 M5 M6 M7; do
    restore
    if ! apply_mut "$m"; then
        echo "✗ $m 应用失败（锚点没命中）"
        fail=$((fail + 1))
        continue
    fi
    # 读回校验：确认变异真的落盘了
    if ! grep -q "MUTATION_ACTIVE_$m" /dev/null 2>/dev/null; then :; fi
    r=$(run_test)
    if [ "$r" != "0" ]; then
        n=$(grep -c '^FAIL' /tmp/mot152/o.txt 2>/dev/null)
        echo "✓ $m 变异被捕获 (exit=$r, ${n} 项断言变红)"
        pass=$((pass + 1))
    else
        echo "✗ $m 变异**未被捕获**（测试仍全绿 ⇒ 断言空转）"
        fail=$((fail + 1))
    fi
done

restore
echo "----"
echo "捕获 $pass / $((pass + fail))"
if [ "$fail" != "0" ]; then
    echo "有 $fail 个变异未被捕获 —— 不假装通过"
    exit 1
fi
exit 0
