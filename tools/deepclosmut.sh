#!/usr/bin/env bash
# deepclosmut —— 深层闭包的变异验证
#
# 只跑 tests/130_deepclosure.mo 得到 8/8，证明不了断言非空转：
# 万一 cap_depth 恒返回 0（深层捕获整体没生效），而各层偏移恰好错开，
# 也可能"碰巧"给出部分正确值。所以必须把实现**故意改坏**，
# 确认每一次都被抓到。
#
# M1  cap_depth 返回值封顶为 1 —— 模拟 v1.129 的"只支持一层"，
#     跨 2 层的读写会落到中间层的同偏移处。
# M2  g_walk_static 少走一层 —— 静态链步数错，跨层读到的不是目标帧。
# M3  解析完嵌套函数不恢复 K_FNBASE —— 外层局部变量被误判成捕获。
#
# 🔴 两个脚本自身的坑（本项目已栽过多次，这里一并钉死）：
#    1. 备份放 build/ 下，不放 /tmp —— /tmp 会在沙盒重启时蒸发，
#       源码于是停在变异态，而备份也没了（1.128/1.129 都发生过）。
#    2. 还原**每次都拷贝**，不用"已还原"标志跳过，也不 grep 变异串核对
#       （变异串可能在注释里也出现，grep 会恒判"还没还原"）。
#       核对方式改成还原后与备份逐字节 diff。
set -u

cd "$(dirname "$0")/.." || exit 1
BAK=build/deepclos_bak
mkdir -p "$BAK"
cp -f src/mo/compiler_part2.mo "$BAK/" || exit 1
cp -f src/mo/compiler_part5.mo "$BAK/" || exit 1

restore() {
    cp -f "$BAK/compiler_part2.mo" src/mo/compiler_part2.mo 2>/dev/null
    cp -f "$BAK/compiler_part5.mo" src/mo/compiler_part5.mo 2>/dev/null
    if ! diff -q "$BAK/compiler_part2.mo" src/mo/compiler_part2.mo >/dev/null 2>&1; then
        echo "✗ 还原失败：part2 与备份不一致" >&2
    fi
    if ! diff -q "$BAK/compiler_part5.mo" src/mo/compiler_part5.mo >/dev/null 2>&1; then
        echo "✗ 还原失败：part5 与备份不一致" >&2
    fi
    make sync >/dev/null 2>&1
}
trap restore EXIT INT TERM

# 开工前自检：源码必须处于干净状态，否则本轮的"基线"本身就不成立
if grep -q "MUTANT-M1\|MUTANT-M2" src/mo/compiler_part2.mo 2>/dev/null; then
    echo "✗ 源码处于变异态，先还原" >&2
    exit 1
fi

rebuild() {
    make sync >/dev/null 2>&1 || return 1
    ./build.sh self bin/seed >/dev/null 2>&1 || return 1
    return 0
}

# 返回 0 = 测试通过，1 = 测试失败，2 = 编译器本身建不起来
run_case() {
    if ! rebuild; then echo "BUILD-FAIL"; return 2; fi
    if ! ./bin/moc tests/130_deepclosure.mo build/dcm.elf >/dev/null 2>&1; then
        echo "COMPILE-FAIL"; return 1
    fi
    local out
    out=$(./build/dcm.elf 2>&1)
    echo "$out" | tail -1
    # 🔴 判据必须同时要求「跑了 8 条」和「0 失败」：
    #    assert.mo 输出的是 "ran 8, failed 0"。只 grep 失败数的话，
    #    编译产物根本没跑起来（输出为空）也会被当成"0 失败"。
    #    第一版脚本 grep 的是中文"失败 0"，与 assert.mo 的实际输出
    #    "failed 0" 不匹配 → run_case 恒返回 1 → 每个变异都"被捕获"。
    #    这是**脚本自身空转**，比被测代码的 bug 更危险。
    # 🔴 不写死条数：测试每加一条用例，写死的 "ran 8" 就会让 run_case
    #    恒返回 1 —— 于是每个变异都"被捕获"，而基线也永远"不通过"。
    #    只要求"确实跑了若干条"且"0 失败"。
    if ! echo "$out" | grep -qE "ran [0-9]+"; then return 1; fi
    if echo "$out" | grep -q "failed 0"; then return 0; fi
    return 1
}

echo "=== 基线（必须 8/8，否则后面的变异结果都没有意义）==="
restore
b=$(run_case); brc=$?
echo "基线: $b (rc=$brc)"
if [ "$brc" != "0" ]; then echo "✗ 基线未通过，中止"; exit 1; fi

mutate() {
    local name="$1"; shift
    restore
    "$@" || { echo "✗ $name 注入失败"; return 1; }
    local out rc
    out=$(run_case); rc=$?
    echo "--- $name: $out (rc=$rc)"
    if [ "$rc" = "0" ]; then
        echo "✗ $name 未被捕获（测试仍然通过 —— 断言空转）"
        return 1
    fi
    if [ "$rc" = "2" ]; then
        echo "⚠ $name 让编译器建不起来 —— 这不算捕获，检查变异是否合法"
        return 1
    fi
    echo "✓ $name 变异被捕获"
    return 0
}

fail=0

mutate "M1 cap_depth 封顶为 1" python3 - <<'EOF'
p='src/mo/compiler_part2.mo'
s=open(p).read()
a='            return n - i;'
b='            if n > 1 { return 1; }  # MUTANT-M1\n            return n - i;'
assert s.count(a)==1, s.count(a)
open(p,'w').write(s.replace(a,b))
EOF
[ $? != 0 ] && fail=1

mutate "M2 静态链少走一层" python3 - <<'EOF'
p='src/mo/compiler_part2.mo'
s=open(p).read()
a='    let i: i64 = 1;\n    while i < n {'
b='    let i: i64 = 1;\n    while i < n - 1 {  # MUTANT-M2'
assert s.count(a)==1, s.count(a)
open(p,'w').write(s.replace(a,b))
EOF
[ $? != 0 ] && fail=1

# M3 原为「不恢复 K_FNBASE 槽」—— v1.130 把 cap_depth 改成读 O_EBS 独立
# 地址后，那个槽已经没人读了，该变异因此恒不被捕获。这不是好消息，
# 是「变异已失效」：它测的是一条已经绕开的因果链。
# 换成针对**新机制**的变异：不做 EBS 入栈。
mutate "M3 不做 EBS 入栈" python3 - <<'EOF'
p='src/mo/compiler_part5.mo'
s=open(p).read()
a='    store64(heap + O_EBS + load64(heap + O_NEST) * 8, ra);'
b='    # MUTANT-M3'
assert s.count(a)==1, s.count(a)
open(p,'w').write(s.replace(a,b))
EOF
[ $? != 0 ] && fail=1

mutate "M4 层数从 0 起算" python3 - <<'EOF'
p='src/mo/compiler_part2.mo'
s=open(p).read()
a='    let i: i64 = n - 1;'
b='    let i: i64 = 0;  # MUTANT-M4'
assert s.count(a)==1, s.count(a)
open(p,'w').write(s.replace(a,b))
EOF
[ $? != 0 ] && fail=1

restore
echo
if [ "$fail" = "0" ]; then echo "✓ 四个变异全部被捕获"; else echo "✗ 有变异未被捕获"; fi
exit "$fail"
