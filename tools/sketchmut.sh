#!/bin/bash
# sketchmut —— Bloom / CMS 的变异验证
#
# 只跑 make test 证明不了断言非空转：25 项全绿也可能是"断言恒真"。
# 本脚本把 lib/bloom.mo / lib/cms.mo 改回**已知的缺陷状态**，
# 要求 tests/145_sketch.mo 必须变红。
#
# ⚠️ 本脚本自身踩过的三个坑（都是"验证机制静默失效"）：
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      现在备份放 build/（项目目录内），且**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败、"基线应当通过"永远通过。
#      现在用 `set -o pipefail` 或分两步取 rc。
#   3. 还原与上次编译落在同一秒 → make 认为 bin/moc 仍是新的，
#      于是每个变异测的是**上一个**变异的编译器。
#      现在每次先 `rm -f bin/moc` 强制重建。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC_B=lib/bloom.mo
SRC_C=lib/cms.mo
BAKD=build/sketchmut_bak
mkdir -p "$BAKD"
cp -f "$SRC_B" "$BAKD/bloom.mo"
cp -f "$SRC_C" "$BAKD/cms.mo"

restore() {
    cp -f "$BAKD/bloom.mo" "$SRC_B"
    cp -f "$BAKD/cms.mo" "$SRC_C"
}
# 中断/被杀也要还原，否则下一轮基线从污染态开始
trap restore EXIT INT TERM

# ── 跑一次 145_sketch，返回其退出码 ────────────────────────
run_sketch() {
    rm -rf /tmp/mot && mkdir -p /tmp/mot
    cp "$HERE"/lib/*.mo /tmp/mot/
    cp "$HERE"/tests/145_sketch.mo /tmp/mot/test.mo
    ( cd /tmp/mot && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot/out.elf 2>/dev/null
    ( cd /tmp/mot && ./out.elf ) >/tmp/mot/sk.out 2>&1
    echo $?
}

rebuild() {
    rm -f "$HERE"/bin/moc          # 关键：否则测到的是上一个变异的编译器
    ( cd "$HERE" && make bin/moc ) >/dev/null 2>&1
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]
def sub(path, old, new):
    s = open(path).read()
    assert old in s, "anchor not found: " + old[:40]
    open(path,'w').write(s.replace(old, new, 1))

if tag == "M1":   # bloom_has 永不判否 → 假阳率 100%
    sub("lib/bloom.mo",
        "if (BLMP[base + BW] & (1 << BB)) == 0 { return 0; }",
        "if (BLMP[base + BW] & (1 << BB)) == 0 { return 1; }")
elif tag == "M2": # double hashing 去掉 h2|=1 → k 个位置不再互异
    sub("lib/bloom.mo",
        "fn bl_h2(x: i64) -> i64 { return bl_mix(x ^ bl_c1()) | 1; }",
        "fn bl_h2(x: i64) -> i64 { return bl_mix(x ^ bl_c1()); }")
elif tag == "M6": # CMS 去掉 h2≡0 退化保护（w=20 时概率 1/w，非"廉价保险"）
    s = open("lib/cms.mo").read()
    a = "    if h2v == 0 { h2v = 1; CMSDEG = CMSDEG + 1; }"
    b = "    if h2v == 0 { h2v = 1; }"
    assert a in s and b in s
    s = s.replace(a, "", 1).replace(b, "", 1)
    open("lib/cms.mo","w").write(s)
elif tag == "M3": # CMS 取 max 而不是 min → 误差暴涨
    sub("lib/cms.mo", "if CV < CM { CM = CV; }", "if CV > CM { CM = CV; }")
elif tag == "M4": # bloom_new 不再校验 2 的幂 → 负例断言必须红
    sub("lib/bloom.mo",
        "    if t != mbits { BLBAD = 1; return 0 - 1; }",
        "    if t != mbits { t = mbits; }")
elif tag == "M5": # cms_add 赋c 而非 累加 → 必然低估
    sub("lib/cms.mo",
        "CMSP[base + CI * w + CJ] = CMSP[base + CI * w + CJ] + c;",
        "CMSP[base + CI * w + CJ] = c;")
else:
    sys.exit("unknown " + tag)
PY
}

# M2 说明：实测未被捕获，且**这是正确的结论**（见 lib/bloom.mo 的 h2 注释）：
#   k << m/gcd 时 h2 偶不偶数不影响 k 个位置的互异性（200 样本重复 0 次），
#   |1 只排除 h2 ≡ 0 (mod m)，概率 1/1024，本参数区间一次未遇。
#   保留 M2 是为了把"改了却没有可观测后果"这件事钉住，
#   而不是为了让脚本看起来 6/6。

# ── 基线必须全过（否则后面的"被捕获"毫无意义）──────────────
rebuild
rc0=$(run_sketch)
if [ "$rc0" != "0" ]; then
    echo "✗ 基线未通过 rc=$rc0（源码可能仍处于变异态）"
    exit 1
fi
echo "✓ 基线通过 rc=0"

pass=0; fail=0
for m in M1 M2 M3 M4 M5 M6; do
    restore
    apply_mut "$m" || { echo "✗ $m 应用失败"; fail=$((fail+1)); continue; }
    rebuild
    rc=$(run_sketch)
    if [ "$rc" != "0" ]; then
        echo "✓ $m 变异被捕获 (rc=$rc)"
        pass=$((pass+1))
    else
        echo "✗ $m 未被捕获 —— 断言可能空转"
        fail=$((fail+1))
    fi
done

restore
# 收尾核对：变异字符串确实不在源码里（不靠"还原了"这个假设）
if grep -q "return 1; }" "$SRC_B" && grep -q "CV > CM" "$SRC_C"; then
    echo "✗ 收尾核对失败：源码仍含变异"
    fail=$((fail+1))
fi

echo "sketchmut: captured=$pass not_captured=$fail"
[ "$fail" = "0" ]
