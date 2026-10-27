#!/usr/bin/env bash
# unimut —— uni.mo 的变异验证
#
# 断言全绿证明不了表是对的：区间表错位、delta 偏移差一、特殊映射没标记，
# 都可能只让个别数字变而测试照样通过。这里逐个把实现改回「有缺陷」的
# 状态，要求测试**必须**变红；某条变异没被捕获，说明对应断言冗余度不够。
#
# M1 类别位掩码收窄（cat ≥ 16 全错）
# M2 delta 偏移差一（大小写结果整体偏 1）
# M3 不置 UNI_UNK（未覆盖与「无映射」无法区分）
# M4 二分右边界写成开区间（每个区间最后一个码点查不到）
# M5 命中特殊多字符映射但不置 UNI_SPEC

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MOC="$HERE/bin/moc"
SRC="$HERE/lib/uni.mo"
BAK="$HERE/build/uni.mo.orig"
TEST="$HERE/tests/145_uni.mo"
TMP=/tmp/mot_um
mkdir -p "$HERE/build"

# 开工前自愈：上一轮若被强杀，SRC 可能停在变异态，而 BAK 也可能是污染版。
# 用同一批「干净 / 变异」文本做反向替换，再把干净的 SRC 存为 BAK。
python3 - "$SRC" <<'HEAL'
import sys
p = sys.argv[1]
s = open(p).read()
# 方向必须是「变异文本 → 干净文本」。第一版写反了，于是自愈把正确的
# `cp <= h` 改成了变异态 `cp < h`，源码被自愈本身污染 —— 验证脚本自身的
# 失效，与已记录的「还原机制把源码污染」是同一类。
pairs = [
    ('return (v >> 32) & 15;', 'return (v >> 32) & 255;'),
    ('& 16777215) - 8383;', '& 16777215) - 8384;'),
    ('if cp < h { return v; }', 'if cp <= h { return v; }'),
]
for mutated, clean in pairs:
    s = s.replace(mutated, clean)
open(p, 'w').write(s)
HEAL
cp "$SRC" "$BAK"

run_test() {
    rm -rf "$TMP" && mkdir -p "$TMP"
    cp "$HERE"/lib/*.mo "$TMP"/ 2>/dev/null
    cp "$TEST" "$TMP"/test.mo
    ( cd "$TMP" && "$MOC" ) >/dev/null 2>&1 || return 1
    chmod +x "$TMP/out.elf" 2>/dev/null
    ( cd "$TMP" && timeout 10 ./out.elf ) >"$TMP/out.txt" 2>&1
    return $?
}

restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

mutate() { python3 - "$SRC" "$1" "$2" <<'MUT'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    print('  锚点未命中：%s' % old)
    sys.exit(3)
open(p, 'w').write(s.replace(old, new))
MUT
}

nfail_of() { grep -o 'failed [0-9]*' "$TMP/out.txt" | tail -1 | sed 's/failed //'; }

echo "── 基线 ──"
run_test; rc=$?
if [ $rc -ne 0 ]; then
    echo "  基线未通过（rc=$rc）：$(tail -2 "$TMP/out.txt" | tr '\n' ' ')"
    echo "unimut: 基线不通过，后续结论无意义"
    exit 1
fi
echo "  基线通过"

fail=0
run_mut() {
    local name=$1 old=$2 new=$3
    restore
    if ! mutate "$old" "$new"; then
        echo "✗ $name 变异未生效"; fail=$((fail+1)); return
    fi
    run_test; rc=$?
    local n
    n=$(nfail_of)
    if [ $rc -eq 0 ]; then
        echo "✗ $name 未被捕获（测试仍全绿）"; fail=$((fail+1))
    elif [ -z "$n" ]; then
        echo "✓ $name 被捕获（程序挂住，timeout 生效）"
    else
        echo "✓ $name 被捕获（$n 项断言变红）"
    fi
}

run_mut "M1 类别掩码收窄" 'return (v >> 32) & 255;' 'return (v >> 32) & 15;'
run_mut "M2 delta 偏移差一" '& 16777215) - 8384;' '& 16777215) - 8383;'
run_mut "M3 不置 UNI_UNK" 'if uni_covered(cp) == 0 { UNI_UNK = 1; return 0 - 1; }' 'if uni_covered(cp) == 0 { return 0 - 1; }'
run_mut "M4 右边界开区间" 'if cp <= h { return v; }' 'if cp < h { return v; }'
run_mut "M5 不置 UNI_SPEC" 'if k == 2 { UNI_SPEC = 1; return cp; }' 'if k == 2 { return cp; }'

restore
echo "── 还原校验 ──"
if cmp -s "$SRC" "$BAK"; then echo "  源码已还原"; else echo "  还原失败"; fail=$((fail+1)); fi

if [ $fail -eq 0 ]; then echo "unimut: 全部变异被捕获"; else echo "unimut: $fail 条未达预期"; fi
exit $fail
