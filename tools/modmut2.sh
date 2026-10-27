#!/bin/bash
# modmut2 —— 条件断点与观察点的**变异验证**
#
# 为什么需要它：
#   tools/modcondtest.sh 的 21 项全过，本身证明不了什么 —— 如果条件
#   判断压根没参与决策（恒真/恒假），"停在 i=5"这类断言也可能碰巧成立。
#   本脚本故意把判断改坏，确认测试**真的会变红**。
#
# 三个变异：
#   M1  条件恒真  —— 反例（i==999 永不成立）必须失败：会误停
#   M2  观察点比较反号 —— 观察点必须失败：永不触发
#   M3  || 忽略左操作数 —— 复合条件的优先级/结合必须失败
#
# ⚠️ 期望值一律与**基线**比对，不写死 "通过 N / 失败 0"：
#    测试项数每次新增都会变，写死的话脚本会一直"抓到变异"，
#    而实际上只是在比两个不同的数字。
#
# 任何退出路径都还原 tools/modb.mo（trap EXIT）。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/tools/modb.mo"
BAK="$HERE/tools/.modb.mo.bak"

cp "$SRC" "$BAK" || exit 1
# 🔴 备份只能删一次：还原函数若自己删备份，第二次调用就会 cp 失败，
#    于是**第二个变异留在源码里没被还原** —— 脚本跑完看起来全绿，
#    源码却已被改坏。这里 restore 不删备份，末尾统一清理。
restore() {
    if [ -f "$BAK" ]; then cp "$BAK" "$SRC"; else echo "  !!  备份丢失，无法还原"; fi
}
trap restore EXIT

mutate() {
    python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    print("mutate: 匹配数 %d（应为 1），放弃变异" % s.count(old)); sys.exit(2)
open(p, 'w').write(s.replace(old, new))
PY
}

run() { bash "$HERE/tools/modcondtest.sh" 2>&1 | tail -1; }

echo "== 基线 =="
BASE=$(run)
echo "  $BASE"

echo "== M1：条件恒真（cv = 1，不看表达式）=="
mutate "        cv = eval_cond(&BPC + bi * 96);" "        cv = 1;" || exit 1
M1=$(run)
echo "  $M1"

restore

echo "== M2：观察点比较反号（v == WV0 才触发）=="
mutate "            if v != WV0 {" "            if v == WV0 {" || exit 1
M2=$(run)
echo "  $M2"

restore

echo "== M3：|| 忽略左操作数（只看右操作数）=="
mutate "            if a != 0 { return 1; }" "            if b != 0 { return 1; }" || exit 1
M3=$(run)
echo "  $M3"

restore
trap - EXIT
rm -f "$BAK"

echo
OK=1
# 还原后必须核对：变异字符串不能还在源码里，否则脚本"全绿"而源码已坏
if grep -q "cv = 1;" "$SRC"; then echo "  BAD  M1 变异残留，源码已被改坏"; OK=0; fi
if grep -q "if v == WV0" "$SRC"; then echo "  BAD  M2 变异残留，源码已被改坏"; OK=0; fi
if grep -q "if b != 0 { return 1; }" "$SRC"; then
    if ! grep -q "if a != 0 { return 1; }" "$SRC"; then echo "  BAD  M3 变异残留，源码已被改坏"; OK=0; fi
fi
case "$BASE" in *"失败 0"*) ;; *) echo "  BAD  基线就不是全过: $BASE"; OK=0;; esac
if [ "$M1" = "$BASE" ]; then echo "  BAD  M1 没被抓到（条件恒真却仍全过 = 条件没参与决策）"; OK=0;
else echo "  OK   M1 被抓到: $M1"; fi
if [ "$M2" = "$BASE" ]; then echo "  BAD  M2 没被抓到（比较反号却仍全过 = 观察点没在比）"; OK=0;
else echo "  OK   M2 被抓到: $M2"; fi
if [ "$M3" = "$BASE" ]; then echo "  BAD  M3 没被抓到（|| 丢掉左操作数仍全过 = 复合条件没在算）"; OK=0;
else echo "  OK   M3 被抓到: $M3"; fi

if [ "$OK" != 1 ]; then exit 1; fi
echo "  三个变异都被捕获 —— 条件求值、观察点比较与复合条件确实在起作用"
exit 0
