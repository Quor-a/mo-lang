#!/bin/bash
# cbfcumut —— Counting Bloom Filter / Conservative Update 的变异验证
#
# 只跑 make test 证明不了断言非空转：34 项全绿也可能是"断言恒真"。
# 本脚本把 lib/cbf.mo / lib/cms.mo 改回**已知的缺陷状态**，
# 要求 tests/147_cbfcu.mo 必须变红。
#
# ⚠️ 本脚本自身要避开的三个坑（都是"验证机制静默失效"，项目已栽过多次）：
#   1. 备份放 /tmp → 沙盒中断后 /tmp 被清空，源码停在变异态而备份也没了。
#      现在备份放 build/（项目目录内），且**收尾不删**，自愈有依据。
#   2. `out=$(cmd | tail -1); rc=$?` 取到的是 tail 的退出码，恒 0
#      → "变异应当被捕获"永远失败、"基线应当通过"永远通过。
#      现在不用管道取 rc，直接 `cmd >file 2>&1; echo $?`。
#   3. 沙盒文件系统有写入可见性延迟：写完立刻 cp 可能读到旧内容，
#      于是"变异没生效"却打印全绿。现在 apply 后**读回校验**。
#
# 🔴 本脚本**预期有一个变异不会被捕获**（M6），并且这是**正确**的：
#    c=1 时 "max(T, v+c)" 与 "只更新 == v 的行" 数学等价。
#    "改了代码却没变红"本身也是信息 —— 它说明那两种写法不是两条因果链。
#    如实保留在脚本里，不挑掉、不假装通过。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC1=lib/cbf.mo
SRC2=lib/cms.mo
BAKD=build/cbfcumut_bak
mkdir -p "$BAKD"
cp -f "$SRC1" "$BAKD/cbf.mo"
cp -f "$SRC2" "$BAKD/cms.mo"

restore() {
    cp -f "$BAKD/cbf.mo" "$SRC1"
    cp -f "$BAKD/cms.mo" "$SRC2"
}
# 中断/被杀也要还原，否则下一轮基线从污染态开始
trap restore EXIT INT TERM

# ── 跑一次 147_cbfcu，返回其退出码 ─────────────────────────
run_test() {
    rm -rf /tmp/mot147 && mkdir -p /tmp/mot147
    cp "$HERE"/lib/*.mo /tmp/mot147/
    cp "$HERE"/tests/147_cbfcu.mo /tmp/mot147/test.mo
    ( cd /tmp/mot147 && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1 || return 99
    chmod +x /tmp/mot147/out.elf 2>/dev/null
    ( cd /tmp/mot147 && ./out.elf ) >/tmp/mot147/o.txt 2>&1
    echo $?
}

apply_mut() {
    python3 - "$1" <<'PY'
import sys
tag = sys.argv[1]

def sub(path, old, new, cnt=1):
    s = open(path).read()
    assert old in s, "anchor not found: " + old[:50]
    s2 = s.replace(old, new, cnt)
    open(path, 'w').write(s2)
    # 读回校验：写完立刻读可能拿到旧内容（沙盒写入可见性延迟）
    chk = open(path).read()
    assert new in chk, "mutation did not land: " + tag

if tag == "M1":
    # cbf_add 去掉饱和 → 第 16 次插入让 4-bit 回绕成 0 → 假阴
    sub("lib/cbf.mo",
        "        if v >= 15 {\n            CBFSAT = CBFSAT + 1;\n        } else {\n            cbf_setc(h, idx, v + 1);\n        }",
        "        cbf_setc(h, idx, v + 1);")

elif tag == "M2":
    # cbf_remove 去掉 v==0 检查 → 0-1 在 4-bit 里回绕成 15 → 删了反而"存在"
    sub("lib/cbf.mo",
        "        if v == 0 {\n            CBFNEG = CBFNEG + 1;\n        } else {\n            cbf_setc(h, idx, v - 1);\n        }",
        "        cbf_setc(h, idx, v - 1);")

elif tag == "M3":
    # cbf_query 只看第一个位置 → 假阳率暴涨
    sub("lib/cbf.mo",
        "    CFM = 1;\n    CFI = 0;\n    while CFI < k {\n        idx = cbf_pos(h, x, CFI);",
        "    CFM = 1;\n    CFI = 0;\n    while CFI < 1 {\n        idx = cbf_pos(h, x, CFI);")

elif tag == "M4":
    # CU 退化成普通 add（每行都加 c）→ 误差回到普通 CMS 水平
    sub("lib/cms.mo",
        "        if CMSP[pos] < v + c { CMSP[pos] = v + c; }",
        "        CMSP[pos] = CMSP[pos] + c;")

elif tag == "M5":
    # cbf_cell / cbf_setc 的位偏移 *4 改 *2 → 计数器错位
    s = open("lib/cbf.mo").read()
    old = "sh = (idx - (idx / 16) * 16) * 4;"
    assert s.count(old) == 2, "anchor count != 2: %d" % s.count(old)
    s = s.replace(old, "sh = (idx - (idx / 16) * 16) * 2;")
    open("lib/cbf.mo", 'w').write(s)
    assert "* 2;" in open("lib/cbf.mo").read(), "mutation did not land"

elif tag == "M6":
    # CU 的 max 形式改回"只更新 == v 的行"
    # 🔴 预期**未捕获**：c=1 时二者数学等价（见文件头说明）
    sub("lib/cms.mo",
        "        if CMSP[pos] < v + c { CMSP[pos] = v + c; }",
        "        if CMSP[pos] == v { CMSP[pos] = v + c; }")
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
    else
        echo "  $M caught (rc=$rc)"
    fi
    # M6 预期未被捕获（数学等价），不计入 fail
    if [ "$M" != "M6" ] && [ "$rc" = "0" ]; then fail=1; fi
done

restore
echo "=== mutated-source check ==="
if grep -q "CMSP\[pos\] = CMSP\[pos\] + c;" lib/cms.mo; then echo "  ERROR cbf/cms still mutated"; fail=1; fi
if grep -q "sh = (idx - (idx / 16) \* 16) \* 2;" lib/cbf.mo; then echo "  ERROR cbf still mutated"; fail=1; fi
echo "=== RESULT fail=$fail ==="
exit $fail
