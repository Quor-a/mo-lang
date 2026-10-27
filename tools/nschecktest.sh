#!/bin/bash
# nscheck 自检
#
# 两件事必须同时成立，缺一个都不算验证过：
#   1. 仓库现有的 193 个程序必须**没有**歧义调用（判据不能一上来就红一片）
#   2. 哨兵用例必须**被报出来**（判据不是空转）
#
# 只有 1 没有 2 = 判据恒真、什么都没查；只有 2 没有 1 = 判据太松会淹没告警。
#
# 哨兵是 tests/nsambig_ab 与 tests/nsambig_ba：两个程序只差 import 顺序，
# 实测退出码分别是 222 与 111 —— 同一个 helper() 调用绑到了不同实现，
# 且不报错。这是「模块命名空间缺失」的端到端证据，不是静态推断。
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/tools/nscheck.py"
pass=0; fail=0

ck() { # ck <名字> <期望rc> <命令...>
  local name=$1 want=$2; shift 2
  "$@" >/tmp/nscheck.out 2>&1; got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS $name rc=$got"; pass=$((pass+1))
  else
    echo "FAIL $name 期望rc=$want 实得rc=$got"
    head -5 /tmp/nscheck.out; fail=$((fail+1))
  fi
}

echo "=== 1. --all 必须干净 ==="
ck "--all 无歧义调用" 0 python3 "$PY" --all
# 用**下界**而不是等值：写死 193 会在每次新增程序时误报 ——
# 报的还是"覆盖数不对"，看着像 --all 漏扫了，实际只是仓库多了文件。
# 这条判据要抓的是"静默少收"（比如 import 解析退回 cwd 导致闭包变小），
# 少收会让数字掉下去，下界抓得到；新增文件让数字变大，不该判失败。
n=$(grep "检查程序数" /tmp/nscheck.out | sed 's/.*检查程序数: *\([0-9]*\).*/\1/')
[ "${n:-0}" -ge 193 ] \
  && { echo "PASS 覆盖 $n 个程序（>=193，不是漏扫后的空集合）"; pass=$((pass+1)); } \
  || { echo "FAIL 覆盖数 $n < 193"; grep "检查程序数" /tmp/nscheck.out; fail=$((fail+1)); }

echo "=== 2. 哨兵必须被报出（判据非空转）==="
ck "哨兵 ab 报歧义" 1 python3 "$PY" "$HERE/tests/nsambig_ab/main.mo"
grep -q "helper()" /tmp/nscheck.out \
  && { echo "PASS 报出 helper()"; pass=$((pass+1)); } \
  || { echo "FAIL 没点名 helper()"; fail=$((fail+1)); }
ck "哨兵 ba 报歧义" 1 python3 "$PY" "$HERE/tests/nsambig_ba/main.mo"

echo "=== 3. 无歧义的对照程序不该被报（判据不误报）==="
ck "对照 127_str 不报" 0 python3 "$PY" "$HERE/tests/127_str.mo"

echo "=== 4. --lib 是清单模式，恒 rc=0 ==="
ck "--lib 恒 0" 0 python3 "$PY" --lib

echo
echo "nschecktest: ran $((pass+fail)), failed $fail"
[ "$fail" = 0 ]
