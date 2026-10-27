#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
#  str 字典序比较 变异验证
#
#  只看 "ran 32, failed 0" 证明不了任何事 —— 断言可能压根没参与判断。
#  这里逐个把实现改坏，确认测试**真的变红**。
#
#  🔴 两个必须遵守的纪律（都是本项目栽过的）：
#    1) 备份只在最后删一次。曾经在 restore() 里顺手 rm 备份，
#       于是第二次还原是空操作、变异留在源码里，脚本却照样打印全绿。
#    2) 收尾用 diff 逐字节核对，而不是 grep 变异串 ——
#       后者会被"源码里本来就有同样一段"骗过。
# ─────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=src/mo/compiler_part4.mo
BAK=$(mktemp /tmp/strcmpmut.XXXXXX)
cp "$SRC" "$BAK"

# 🔴 必须**每次都拷贝**，不能用"已还原"标志跳过。
restore() {
    cp "$BAK" "$SRC"
    make sync >/dev/null 2>&1
    ./build.sh self bin/seed >/dev/null 2>&1
}
trap restore EXIT

run_test() {
    rm -rf /tmp/mot; mkdir -p /tmp/mot
    cp tests/128_strcmp.mo /tmp/mot/test.mo
    cp lib/*.mo /tmp/mot/
    ( cd /tmp/mot && "$ROOT/bin/moc" ) >/dev/null 2>&1
    chmod +x /tmp/mot/out.elf 2>/dev/null
    ( cd /tmp/mot && ./out.elf 2>&1 ) | tail -1
}

# 基线
restore
base=$(run_test)
if echo "$base" | grep -q "failed 0"; then
    echo "✓ 基线：$base"
else
    echo "✗ 基线就没过：$base"; exit 1
fi

mutate() {
    local name="$1" old="$2" new="$3"
    cp "$BAK" "$SRC"
    python3 - "$old" "$new" <<'PY'
import sys
p = 'src/mo/compiler_part4.mo'
s = open(p).read()
old, new = sys.argv[1], sys.argv[2]
c = s.count(old)
assert c == 1, "锚点不唯一或找不到: count=%d" % c
open(p, 'w').write(s.replace(old, new))
PY
    if [ $? -ne 0 ]; then echo "✗ $name 变异未能施加"; exit 1; fi
    make sync >/dev/null 2>&1
    ./build.sh self bin/seed >/dev/null 2>&1
    local out
    out=$(run_test)
    if echo "$out" | grep -q "failed 0"; then
        echo "✗ $name 变异未被捕获（测试仍全过）"
        exit 1
    else
        echo "✓ $name 变异被捕获 → $out"
    fi
}

# M1：退回**有符号**比较（setb 0x92 → setl 0x9c）。
#     UTF-8 多字节码 >= 0x80 全部变成负数，CJK 跑到 ASCII 前面。
mutate "M1 setb→setl（有符号比较）" \
    "g_str_cmp(0x92);" \
    "g_str_cmp(0x9c);"

# M2：< 与 > 互换（setb 0x92 → seta 0x97）
mutate "M2 < 与 > 互换" \
    "g_str_cmp(0x92);" \
    "g_str_cmp(0x97);"

# M3：退回地址比较 —— 字符串从此按地址排序
mutate "M3 退回地址比较" \
    "g_str_cmp(0x92);" \
    "g_cmp_set(0x9c);"

# 收尾核对
restore
if diff -q "$BAK" "$SRC" >/dev/null; then
    echo "✓ 源码已还原（与备份逐字节相同）"
    trap - EXIT
    rm -f "$BAK"
    exit 0
else
    echo "✗ 还原失败：源码与备份不一致"
    diff "$BAK" "$SRC" | head -10
    exit 1
fi
