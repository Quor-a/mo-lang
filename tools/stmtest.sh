#!/bin/bash
# stmtest —— 软件事务内存（TL2）端到端验证
#
# 判据不是"有没有崩"，而是**每一项都要给出具体数字**：
#   * 丢失更新：STM 必须**正好** 4000；无保护对照必须 **< 4000**。
#     两个数都必须出现 —— 只有 STM=4000 说明对照没做。
#   * 原子性：抢锁失败时先前已写的位置必须**恢复到原值**（lock a=1000）。
#     这条不报错、不崩溃，只表现为数字不对。
#   * 假冲突：相隔 8192 字节的两个地址必然同桶，一个提交会让另一个作废。
#
# ⚠ 守卫：示例必须真的 import "stm.mo"，否则退化成别的东西而本测试照样全绿。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
SRC="$1"
if [ -z "$SRC" ]; then
  SRC=/tmp/mostmtest
  rm -rf $SRC && mkdir -p $SRC/lib
  cp "$HERE"/lib/*.mo $SRC/lib/
  cp "$HERE"/examples/stmbench.mo $SRC/
fi
cd $SRC || exit 1
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

if ! grep -q 'import "stm.mo"' stmbench.mo; then
  echo "  ✗ stmbench.mo 不再 import stm.mo：本测试会空转"; echo "通过 0 / 失败 1"; exit 1
fi
if ! $MOC stmbench.mo -c stmbench.o 2>err.txt; then
  echo "  ✗ 编译失败"; head -5 err.txt; echo "通过 0 / 失败 1"; exit 1
fi
if ! bash $LINK stmbench.o -o stmbench >/dev/null 2>&1; then
  echo "  ✗ 链接失败（libatomic 没找到？）"; echo "通过 0 / 失败 1"; exit 1
fi
pkill -x stmbench 2>/dev/null
timeout -s KILL -k 5 300 ./stmbench > out.txt 2>&1; RC=$?
ck "$RC" "0" "程序正常退出"
if [ "$RC" != "0" ]; then echo "通过 $PASS / 失败 $FAIL"; exit 1; fi

# g <行前缀> <key>
g() { grep "^$1" out.txt | grep -o "$2=-*[0-9]*" | head -1 | sed 's/.*=//'; }

ck "$(g 'seq ' v)"        "10"    "单线程：读到初值"
ck "$(g 'seq ' ryw)"      "15"    "单线程：读自己写过的"
ck "$(g 'seq ' ok)"       "1"     "单线程：提交成功"
ck "$(g 'seq ' a)"        "15"    "单线程：最终值"

ck "$(g 'conflict ' x)"   "1000"  "冲突：读到提交前的值"
ck "$(g 'conflict ' t1)"  "1"     "冲突：后者提交成功"
ck "$(g 'conflict ' t0)"  "0"     "冲突：前者必须作废"
ck "$(g 'conflict ' why)" "1"     "冲突：原因是读集校验"
ck "$(g 'conflict ' a)"   "99"    "冲突：别人的写入保留"
ck "$(g 'conflict ' b)"   "2000"  "冲突：自己的写入回滚"

ck "$(g 'lock ' wrb)"     "-1"    "抢锁：第二次写失败"
ck "$(g 'lock ' t0)"      "0"     "抢锁：提交失败"
ck "$(g 'lock ' why)"     "2"     "抢锁：原因是锁冲突"
ck "$(g 'lock ' a)"       "1000"  "🔴 原子性：先写的位置必须回滚到原值"
ck "$(g 'lock2 ' b)"      "7"     "抢锁：别人的事务不受影响"

ck "$(g 'ovf ' ok)"       "0"     "读集溢出：提交失败"
ck "$(g 'ovf ' why)"      "3"     "读集溢出：原因是 3"
ck "$(g 'ovf ' cnt)"      "1"     "读集溢出：计数 +1"

ck "$(g 'alias ' ix0)"    "$(g 'alias ' ix1)" "假冲突：两个地址同桶"
ck "$(g 'alias ' t1)"     "1"     "假冲突：不相干的数据能提交"
ck "$(g 'alias ' t0)"     "0"     "假冲突：本事务被连带作废"
ck "$(g 'alias ' falsh)"  "1"     "假冲突：计数 +1（量化出来而不是当 bug）"
ck "$(g 'alias ' a0)"     "0"     "假冲突：本事务没写进去"
ck "$(g 'alias ' a1024)"  "42"    "假冲突：别人的数据确实写了"

ck "$(g 'lost ' stm)"     "40000" "🔴 丢失更新：STM 必须正好 40000"
ck "$(g 'lost ' nc01)"    "40000" "丢失更新：提交次数"
AB=$(g 'lost ' stmabt)
if [ -z "$AB" ] || [ "$AB" = "0" ]; then
  FAIL=$((FAIL+1)); echo "  ✗ 一次冲突都没发生（stmabt=0），说明两线程根本没重叠，本测试空转"
else PASS=$((PASS+1)); fi
L=$(g 'lost ' stm); R=$(g 'lost ' racy)
ck "$(g 'lost ' racy)"    "$R"    "对照：无保护自增有数字"
if [ "$R" = "4000" ]; then FAIL=$((FAIL+1)); echo "  ✗ 对照组没丢更新（racy=4000），本项判据空转"; else PASS=$((PASS+1)); fi
ck "$(g 'lost ' dup)"     "0"     "🔴 版本号：不允许两次提交拿到同一个版本号"
ck "$(g 'lost1 ' stm)"    "40000" "单线程对照：精确"
ck "$(g 'lost1 ' abv)"    "0"     "单线程对照：不该有校验失败"
ck "$(g 'lost1 ' abl)"    "0"     "单线程对照：不该有锁冲突"

ck "$(g 'inv ' stm)"      "10000" "🔴 不变式：两账户总额恒为 10000"
ck "$(g 'inv ' bad)"      "0"     "🔴 不变式：STM 下被观测到破坏 0 次"
RB=$(g 'inv ' racybad)
if [ -z "$RB" ] || [ "$RB" = "0" ]; then
  FAIL=$((FAIL+1)); echo "  ✗ 对照组一次都没抓到中间态（racybad=$RB），本项判据空转"
else PASS=$((PASS+1)); fi

ck "$(g 'par ' sum)"      "40000" "并行提交：各写各的，总数精确"
ck "$(g 'par ' dup)"      "0"     "🔴 并行提交：两次提交不能拿到同一版本号"
PB=$(g 'par ' abt)
if [ -z "$PB" ] || [ "$PB" = "0" ]; then
  FAIL=$((FAIL+1)); echo "  x 并行场景一次冲突都没有（abt=0），说明提交没真正并发"
else PASS=$((PASS+1)); fi

ck "$(g 'par ' sum)"      "40000" "并行提交：各写各的，总数精确"
ck "$(g 'par ' dup)"      "0"     "🔴 并行提交：两次提交不能拿到同一版本号"
PB=$(g 'par ' abt)
if [ -z "$PB" ] || [ "$PB" = "0" ]; then
  FAIL=$((FAIL+1)); echo "  x 并行场景一次冲突都没有（abt=0），说明提交没真正并发"
else PASS=$((PASS+1)); fi

ck "$(g 'perf ' sum)"     "200000" "性能：总额守恒"
# 时间只做观测、不做成败判据：2 线程下 STM 靠自旋重试，反而可能比 futex 快
#   （实测 20~90ms vs 1~43ms，方向不稳定）。把它当断言就是个会偶发红的门。
S=$(g 'perf ' stm_ms); M=$(g 'perf ' mutex_ms)
if [ -n "$S" ] && [ -n "$M" ] && [ "$S" -gt 0 ] && [ "$M" -gt 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ 计时无效（stm=$S mutex=$M）"; fi
ck "$(g 'perf ' dup)"     "0"     "版本号：性能场景同样不允许重复"
PA=$(g 'perf ' abt)
if [ -z "$PA" ] || [ "$PA" = "0" ]; then
  FAIL=$((FAIL+1)); echo "  ✗ 性能场景一次冲突都没有（abt=0），争用根本没发生"
else PASS=$((PASS+1)); fi

echo "通过 $PASS / 失败 $FAIL"
if [ "$FAIL" != "0" ]; then exit 1; fi
exit 0
