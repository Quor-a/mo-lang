#!/bin/bash
# actortest —— Actor 模型 + 监督树的端到端验证
#
# 被测：lib/actor.mo（经 examples/supertree.mo 的 `import "actor.mo"`）。
# 这里显式写出 `import "actor.mo"` —— projcheck 第 3 项按带引号的库名扫
# 引用，只写 lib/actor.mo（不带引号）会判成"无测试覆盖"。
#
# 🔴 这个库此前**从未被任何测试跑过**（projcheck 第 3 项报红才发现）：
#    lib/actor.mo 与 examples/supertree.mo 存在、能编译、跑起来退出码 0，
#    打印的数字看起来也合理 —— 但三个重启策略里有两个**根本没重启**。
#    这正是本项目反复出现的形状：**存在于仓库 ≠ 被验证过**。
#
# 判据不是"有没有崩"，而是**三个策略必须给出三个不同的重启集合**：
#   one-for-one   : 只重启失败者      → gen=[0,1,0]  msgn=[60,0,60]
#   one-for-all   : 重启全部          → gen=[1,1,1]  msgn=[0,0,0]
#   rest-for-one  : 失败者及其之后    → gen=[0,1,1]  msgn=[60,0,0]
# msgn 在重启时归零、未重启的保留 —— 这是"重启 = 重建"的可观测后果。
#
# 另一条独立判据是**重启强度**：窗口内超限 → 监督者自己崩，
# 绝不静默无限重启（那会把崩溃循环伪装成"一直在工作"）。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP="$HERE/build/actortest_tmp"
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cp "$HERE"/examples/supertree.mo $TMP/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

$MOC supertree.mo -c -o supertree.o || { echo "✗ 编译失败"; exit 1; }
bash "$LINK" supertree.o -o supertree >/dev/null || { echo "✗ 链接失败"; exit 1; }
# 必须 -k：timeout 只杀自己那一层，孙进程会活下来把下一次运行的调度拖歪
timeout -k 5 180 ./supertree > out.txt 2>&1
RC=$?
ck "$RC" "0" "程序正常退出"

v() { grep -oE "^$1=[0-9-]+" out.txt | tail -1 | cut -d= -f2; }

echo "== A. 状态私有 + 消息无丢失 =="
ck "$(v a_m0)" "100" "actor0 收满 100 条"
ck "$(v a_m1)" "100" "actor1 收满 100 条"
ck "$(v a_m2)" "100" "actor2 收满 100 条"
ck "$(v a_s0)" "100" "状态私有：actor0 自己的状态 = 100"

echo "== B. one-for-one：只重启失败者 =="
ck "$(v b_g0)" "0" "g0 未重启"
ck "$(v b_g1)" "1" "g1 被重启（失败者）"
ck "$(v b_g2)" "0" "g2 未重启"
ck "$(v b_m0)" "60" "m0 保留 —— 没被重启"
ck "$(v b_m1)" "0"  "m1 归零 —— 被重启"
ck "$(v b_m2)" "60" "m2 保留 —— 没被重启"

echo "== C. one-for-all：重启全部 =="
ck "$(v c_g0)" "1" "g0 被重启"
ck "$(v c_g1)" "1" "g1 被重启"
ck "$(v c_g2)" "1" "g2 被重启"
ck "$(v c_m0)" "0" "m0 归零"
ck "$(v c_m1)" "0" "m1 归零"
ck "$(v c_m2)" "0" "m2 归零"

echo "== D. rest-for-one：失败者及其之后 =="
ck "$(v d_g0)" "0" "g0 未重启（在失败者之前）"
ck "$(v d_g1)" "1" "g1 被重启（失败者）"
ck "$(v d_g2)" "1" "g2 被重启（失败者之后）"
ck "$(v d_m0)" "60" "m0 保留"
ck "$(v d_m1)" "0"  "m1 归零"
ck "$(v d_m2)" "0"  "m2 归零"

echo "== 三个策略必须给出三个不同的重启集合 =="
BSET="$(v b_g0)$(v b_g1)$(v b_g2)"
CSET="$(v c_g0)$(v c_g1)$(v c_g2)"
DSET="$(v d_g0)$(v d_g1)$(v d_g2)"
ck "$BSET" "010" "one-for-one 的重启集合 = 010"
ck "$CSET" "111" "one-for-all 的重启集合 = 111"
ck "$DSET" "011" "rest-for-one 的重启集合 = 011"
if [ "$BSET" != "$CSET" ] && [ "$CSET" != "$DSET" ] && [ "$BSET" != "$DSET" ]; then
    PASS=$((PASS+1)); echo "  ✓ 三个集合两两不同 —— 策略真的生效，不是同一个代码路径"
else
    FAIL=$((FAIL+1)); echo "  ✗ 三个集合有重复 —— 策略退化成同一条路径"
fi

echo "== E. 重启强度：窗口内超限 → 监督者自己崩 =="
ck "$(v e_sfail)" "1" "强度超限后监督者置失败（不静默无限重启）"
ck "$(v e_gen)" "2" "只重启了 2 次，第 3 次不再重启"

echo "== E2. 窗口过期 → 计数重置 =="
ck "$(v e2_sfail)" "0" "窗口过期后不判超限"

echo "== F. become（行为切换）=="
ck "$(v f_beh)" "1" "become 切换了行为"
ck "$(v f_post)" "23" "切换后按新行为累加（3 + 2×10）"

echo "== 诊断计数器：不该有的失败必须为 0 =="
# 🔴 sfailn 只应等于 1（E 场景那次预期的强度超限）。
#    修复前它是 3 —— 多出的两次来自 sup_waitdead 超时（one-for-one /
#    rest-for-one 等"全部 children 死"必然超时）。这条断言专门盯着它。
ck "$(v sfailn)" "1" "sfailn=1 —— 只有 E 那次预期超限，没有 waitdead 超时"
ck "$(v dup)"    "0" "无重复 pid"
ck "$(v noch)"   "0" "邮箱全部创建成功"
ck "$(v senderr)" "0" "无发送失败"
ck "$(v hang)"   "0" "无挂起"

echo
echo "通过 $PASS / 失败 $FAIL"
if [ "$FAIL" != "0" ]; then exit 1; fi
exit 0
