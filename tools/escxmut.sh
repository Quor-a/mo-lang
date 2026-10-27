#!/usr/bin/env bash
# escxmut —— \xHH 转义的变异验证
#
# 只看"测试全过"证明不了断言非空转。这里逐个把实现改回有缺陷的样子，
# 确认测试**真的会变红**。
#
# 🔴 变异脚本自己也会静默失效（1.102 / 1.111 都栽过）：
#    - 用"已还原"标志跳过末尾还原 → 变异留在源码里，脚本照样全绿
#    - 用 grep 变异串核对还原 → 源码里本来就有的同名串会让它恒判"没还原"
#    所以这里：每次都无条件 cp 回去，末尾再 diff 逐字节核对。
set -u
cd "$(dirname "$0")/.."

SRC=src/compiler.mo
BAK=/tmp/escxmut_backup.mo
BAD=/tmp/escxmut_bad.mo
OUT=/tmp/escxmut_bin
ERR=/tmp/escxmut_err

cat > "$BAD" <<'EOF'
fn main() -> i64 {
    let t: i64 = "a\xZZ";
    return 0;
}
EOF

cp "$SRC" "$BAK"
restore() { cp "$BAK" "$SRC"; }
trap restore EXIT

# 判据有两条，缺一不可：
#   1) tests/129 必须变红
#   2) 位数不足的 \x 必须**报错**（退出码非 0 且信息里含 bad \x escape）
#      只删一条检查时 \xZZ 仍会被另一条拦住 —— 见 M3 的说明。
check_now() {
    rm -f bin/moc
    if ! make bin/moc >/dev/null 2>&1; then
        echo "  （编译器构建失败，算抓到）"; return 0
    fi
    ./bin/moc tests/129_escx.mo "$OUT" >/dev/null 2>&1 && "$OUT" >/dev/null 2>&1
    local t=$?
    ./bin/moc "$BAD" /tmp/escxmut_badbin >/dev/null 2>"$ERR"
    local be=$?
    local msg=0
    grep -q 'bad .x escape' "$ERR" 2>/dev/null && msg=1
    if [ "$t" -ne 0 ] || [ "$be" -eq 0 ] || [ "$msg" -ne 1 ]; then
        echo "  测试退出码=$t  非法用例退出码=$be  有报错信息=$msg  → 抓到"
        return 0
    fi
    echo "  测试退出码=$t  非法用例退出码=$be  有报错信息=$msg  → 没抓到，断言空转"
    return 1
}

mutate_and_check() {
    local name="$1" script="$2"
    cp "$BAK" "$SRC"
    if ! python3 "$script"; then echo "$name: 变异打不上"; return 1; fi
    if diff -q "$BAK" "$SRC" >/dev/null; then
        echo "$name: 变异没生效（源码没变）"; return 1
    fi
    echo "== $name =="
    if check_now; then
        echo "✓ $name 被抓到"; return 0
    fi
    echo "✗ $name 没被抓到"; return 1
}

echo "== 基线 =="
cp "$BAK" "$SRC"
rm -f bin/moc
make bin/moc >/dev/null 2>&1 || { echo "基线构建失败"; exit 1; }
./bin/moc tests/129_escx.mo "$OUT" >/dev/null 2>&1 && "$OUT"
base=$?
./bin/moc "$BAD" /tmp/escxmut_badbin >/dev/null 2>"$ERR"
bade=$?
badm=0
grep -q 'bad .x escape' "$ERR" 2>/dev/null && badm=1
echo "基线：测试退出码=$base  非法用例退出码=$bade  有报错信息=$badm"
if [ "$base" -ne 0 ] || [ "$bade" -eq 0 ] || [ "$badm" -ne 1 ]; then
    echo "✗ 基线就不对，后面的变异结果没有意义"
    exit 1
fi

mkdir -p /tmp/escxmut
cat > /tmp/escxmut/m1.py <<'PYEOF'
p = "src/compiler.mo"
s = open(p).read()
old = "    if c == 120 {"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "    if c == 200 {"))
PYEOF

cat > /tmp/escxmut/m2.py <<'PYEOF'
p = "src/compiler.mo"
s = open(p).read()
old = "        return hi * 16 + lo;"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "        return lo * 16 + hi;"))
PYEOF

# 🔴 只删一条检查抓不到：\xZZ 两位都非法，另一条仍会拦住它。
#    必须两条都删，才真的回到"静默给个值"的状态。
cat > /tmp/escxmut/m3.py <<'PYEOF'
p = "src/compiler.mo"
lines = open(p).read().split("\n")
out = []
n = 0
for l in lines:
    if "if hi < 0" in l or "if lo < 0" in l:
        n = n + 1
        continue
    out.append(l)
assert n == 2, n
open(p, "w").write("\n".join(out))
PYEOF

fails=0
mutate_and_check "M1 禁用 \\xHH（落回原样分支）" /tmp/escxmut/m1.py || fails=$((fails+1))
mutate_and_check "M2 高低位互换"                 /tmp/escxmut/m2.py || fails=$((fails+1))
mutate_and_check "M3 位数不足不报错（静默）"      /tmp/escxmut/m3.py || fails=$((fails+1))

restore
if ! diff -q "$BAK" "$SRC" >/dev/null; then
    echo "✗ 还原失败：源码与备份不一致"
    exit 1
fi
echo "✓ 源码已逐字节还原"

# 还原后重建，别把变异版 moc 留在 bin/ 里
rm -f bin/moc
make bin/moc >/dev/null 2>&1

echo "== 结果 =="
if [ "$fails" -eq 0 ]; then
    echo "✓ 全部变异都被抓到"
    exit 0
fi
echo "✗ 有 $fails 个变异没被抓到"
exit 1
