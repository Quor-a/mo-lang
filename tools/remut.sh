#!/bin/bash
# 变异验证：把 regex.mo 故意改坏，确认 tests/131_regex.mo 会拦下来。
# 判据 = 变异后测试必须有失败（或编译报错）。只看"基线全过"证明不了
# 断言非空转 —— 断言可能根本没参与决策。
set -u
cd "$(dirname "$0")/.."
SRC=lib/regex.mo
TST=tests/131_regex.mo
BAK=build/remut.bak
mkdir -p build
cp "$SRC" "$BAK"

restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

run() {
    if ! ./bin/moc "$TST" build/remut.elf > build/remut.log 2>&1; then
        echo "COMPILE-FAIL"
        return 0
    fi
    local rc=0
    timeout 90 ./build/remut.elf > build/remut.out 2>&1 || rc=$?
    local last
    last=$(tail -1 build/remut.out)
    echo "rc=$rc [$last]"
}

mutate() {
python3 - "$1" <<'PY'
import sys
p = 'lib/regex.mo'
s = open(p).read()
m = sys.argv[1]
def seg(a, b):
    i = s.index(a); j = s.index(b, i)
    return i, j
if m == 'M1':
    s = s.replace('if TH_VIS[p] == TH_GEN { continue; }', 'if 0 { continue; }')
elif m == 'M2':
    i, j = seg('fn rx_star()', 'fn rx_plus()')
    s = s[:i] + s[i:j].replace('    CU_S = s;', '    CU_S = CU_S;') + s[j:]
elif m == 'M3':
    old = """            STK_P[STK_N] = RX_B[p];
            STK_T[STK_N] = sr;
            STK_N = STK_N + 1;
            STK_P[STK_N] = RX_A[p];"""
    new = """            STK_P[STK_N] = RX_A[p];
            STK_T[STK_N] = sr;
            STK_N = STK_N + 1;
            STK_P[STK_N] = RX_B[p];"""
    assert old in s, 'M3 anchor'
    s = s.replace(old, new)
elif m == 'M4':
    s = s.replace('if neg == 1 {', 'if 0 {')
elif m == 'M5':
    s = s.replace("""    if ST_SP != 0 {
        RX_ERR = 8;
        return 0 - 1;
    }""", """    if 0 {
        RX_ERR = 8;
        return 0 - 1;
    }""")
open(p, 'w').write(s)
PY
}

echo "baseline: $(run)"
ok=0
for m in M1 M2 M3 M4 M5; do
    restore
    mutate "$m"
    if ! diff -q "$BAK" "$SRC" > /dev/null; then
        r="$(run)"
    else
        r="NOT-APPLIED"
    fi
    if echo "$r" | grep -q "rc=0"; then
        echo "✗ $m 未捕获 ($r)" 
    else
        echo "✓ $m 变异被捕获 -> $r"
        ok=$((ok + 1))
    fi
done
restore
echo "captured $ok / 5"
