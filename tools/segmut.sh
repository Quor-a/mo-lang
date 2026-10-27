#!/bin/bash
# segmut —— 线段树 + 懒标记的变异验证
#
# 只跑 make test 证明不了断言非空转：144 项全绿也可能是"断言恒真"。
# 本脚本把 lib/seg.mo 改回**已知的缺陷状态**，要求 tests/151_seg.mo 必须变红。
#
# ── 本脚本自身要避开的坑（都是"验证机制静默失效"，项目已栽过多次）──
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      备份放 build/（项目目录内），**收尾不删**。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败。这里不用管道取 rc。
#   3. 变异必须**直接回到缺陷状态**。改一点东西然后看它失败是不够的
#      —— 得确认改的正好是那条因果链。
#   4. 每次 apply 后**读回校验**：沙盒文件系统有写入可见性延迟。
#   5. 必须有 timeout：下推/递归改坏可能死循环，会把整条链拖死。
#   6. 开工前**预检源码是否已是变异态** —— 否则备份本身就是污染版。
#   7. 预检用**计数**而非子串：sg_radd 与 sg_rset、sg_qsum 与 sg_qmax
#      函数体高度对称，单靠子串会命中到另一个函数（v1.141 importas 栽过）。
#   8. 每次都 rm -f 掉产物强制重建：cp 与上次构建落在同一秒时 make 会跳过，
#      于是每个变异测的是**上一个**变异的产物（v1.135 for 栽过）。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/seg.mo
BAKD=build/segmut_bak
mkdir -p "$BAKD"
cp -f "$SRC" "$BAKD/seg.mo"

restore() { cp -f "$BAKD/seg.mo" "$SRC"; }
trap restore EXIT INT TERM

run_test() {
    rm -rf /tmp/mot151m && mkdir -p /tmp/mot151m
    cp "$HERE"/lib/*.mo /tmp/mot151m/
    cp "$HERE"/tests/151_seg.mo /tmp/mot151m/test.mo
    rm -f /tmp/mot151m/out.elf
    ( cd /tmp/mot151m && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot151m/out.elf 2>/dev/null
    ( cd /tmp/mot151m && timeout 60 ./out.elf ) >/tmp/mot151m/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(old, new):
    s = open("lib/seg.mo").read()
    assert old in s, "anchor not found: " + old[:70]
    s2 = s.replace(old, new, 1)
    assert s2 != s, "replace was a no-op: " + tag
    open("lib/seg.mo", 'w').write(s2)
    assert new in open("lib/seg.mo").read(), "mutation did not land: " + tag

if tag == "M1":
    # apply_set 不清掉 ADD ⇒ "add 后 set" 时旧加法被额外叠加一次
    sub("    SEGP[h + 1 + 4 * st + p] = 1;\n"
        "    SEGP[h + 1 + 2 * st + p] = 0;\n",
        "    SEGP[h + 1 + 4 * st + p] = 1;\n")
elif tag == "M2":
    # push 直接返回 ⇒ 懒标记永不下推，子节点全是陈旧值
    sub("fn sg_push(p: i64, l: i64, r: i64, h: i64, st: i64) -> i64 {\n"
        "    if l == r { return 0; }\n",
        "fn sg_push(p: i64, l: i64, r: i64, h: i64, st: i64) -> i64 {\n"
        "    if l == r { return 0; }\n"
        "    return 0;\n")
elif tag == "M3":
    # 区间赋值退化成区间加（这是本库相对 Fenwick 的核心能力之一）
    sub("            let d0: i64 = sg_apply_set(p, l, r, v, h, st);\n",
        "            let d0: i64 = sg_apply_add(p, l, r, v, h, st);\n")
elif tag == "M4":
    # qmax 返回 sum ⇒ max 变成 sum 的别名（半群性断言应当抓到）
    sub("    if ql <= l {\n"
        "        if r <= qr { return SEGP[h + 1 + st + p]; }\n",
        "    if ql <= l {\n"
        "        if r <= qr { return SEGP[h + 1 + p]; }\n")
elif tag == "M5":
    # apply_set 只改 SUM 不改 MAX ⇒ max 停在旧值
    sub("    SEGP[h + 1 + p] = v * cnt;\n"
        "    SEGP[h + 1 + st + p] = v;\n",
        "    SEGP[h + 1 + p] = v * cnt;\n")
elif tag == "M6":
    # pull 时 max 取 sum（sg_radd 那处）⇒ max 聚合错
    sub("    let m1: i64 = SEGP[h + 1 + st + 2 * p];\n"
        "    let m2: i64 = SEGP[h + 1 + st + 2 * p + 1];\n",
        "    let m1: i64 = SEGP[h + 1 + 2 * p];\n"
        "    let m2: i64 = SEGP[h + 1 + 2 * p + 1];\n")
else:
    raise SystemExit("unknown mutation " + tag)
PY
}

# ── 0) 预检：源码必须处于干净态（用计数，不用子串）─────────
DIRTY=$(python3 - <<'PY'
s = open("lib/seg.mo").read()
bad = []
def ck(tag, cond):
    if not cond:
        bad.append(tag)
ck("M1", s.count("SEGP[h + 1 + 2 * st + p] = 0;") == 2)
ck("M2", s.count("if l == r { return 0; }\n    return 0;") == 0)
ck("M3", s.count("sg_apply_set(") == 4)
ck("M4", s.count("return SEGP[h + 1 + p];") == 1)
ck("M5", s.count("SEGP[h + 1 + st + p] = v;") == 1)
ck("M6", s.count("let m1: i64 = SEGP[h + 1 + st + 2 * p];") == 2)
print(",".join(bad))
PY
)
if [ -n "$DIRTY" ]; then
    echo "✗ 预检失败：源码已处于变异态（$DIRTY）—— 备份会跟着污染，后面结论全部无效"
    echo "  先把 lib/seg.mo 手工还原（或从上一次 build/segmut_bak 取回）再跑"
    exit 1
fi

fail=0

# ── 1) 基线必须先通过 ──────────────────────────────────────
base=$(run_test)
if [ "$base" = "0" ]; then
    echo "✓ 基线通过（退出码 0）"
else
    echo "✗ 基线就没通过（退出码 $base）—— 后面的结论全部无效"
    head -20 /tmp/mot151m/o.txt 2>/dev/null
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
    nred=$(grep -c '^FAIL' /tmp/mot151m/o.txt 2>/dev/null)
    if [ "$got" != "0" ]; then
        first=$(grep -m1 '^FAIL' /tmp/mot151m/o.txt 2>/dev/null)
        if [ "$got" = "124" ]; then
            echo "✓ $m 变异被捕获 → 程序挂住（timeout，exit 124，${nred} 项红）"
        else
            echo "✓ $m 变异被捕获 → ${first}（${nred} 项红，rc=$got）"
        fi
    else
        echo "✗ $m 变异**未被捕获**（151 仍全绿）"
        fail=$((fail+1))
    fi
done

restore
echo "---- 还原后复查 ----"
after=$(run_test)
if [ "$after" = "0" ]; then echo "✓ 还原后基线仍通过"; else echo "✗ 还原后基线不通过（rc=$after）"; fail=$((fail+1)); fi

echo "未捕获的变异数：$fail"
exit $fail
