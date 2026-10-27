#!/bin/bash
# modcondtest —— modb 的条件断点与观察点验证
#
# 为什么单独一个脚本：
#   无条件断点只能证明"能停"，证明不了"停在对的那一次"。条件断点
#   靠表达式求值决定停不停，观察点靠值变化决定停不停 —— 两者的失败
#   模式都是**静默**：条件写错会被当成"不成立"而永不触发，看起来和
#   "程序没跑到"一模一样。本脚本的核心就是防这类静默。
#
# 验证策略：
#   1. 正向：条件成立的那一次停住，且变量值真的是条件里的值
#   2. 计数：stat 的"命中 / 条件放过"必须逐位对上（命中 1 / 放过 5）
#   3. 反例：永不成立的条件必须一次都不停，程序正常跑完
#   4. 错误表达式必须**报出来**，不能静默当不成立
#   5. 观察点：值变化时停下并报出旧值->新值
#   6. 反向验证：作用域外的变量必须报找不到
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
chk() {
    if [ "$2" = "1" ]; then PASS=$((PASS+1)); echo "  OK   $1";
    else FAIL=$((FAIL+1)); echo "  BAD  $1"; fi
}
has() { if grep -q -- "$1" <<<"$OUT"; then echo 1; else echo 0; fi; }
nohas() { if grep -q -- "$1" <<<"$OUT"; then echo 0; else echo 1; fi; }
field() { grep -o "$1" <<<"$OUT" | head -1; }

echo "== 编译 modb（含条件断点与观察点）=="
rm -rf /tmp/modbbuild && mkdir -p /tmp/modbbuild
cp "$HERE"/lib/*.mo /tmp/modbbuild/ || exit 1
cp "$HERE"/tools/modb.mo /tmp/modbbuild/test.mo || exit 1
( cd /tmp/modbbuild && "$HERE/bin/moc" ) || { echo "✗ modb.mo 编译失败"; exit 1; }
cp /tmp/modbbuild/out.elf "$HERE/bin/modb" || exit 1
chmod +x "$HERE/bin/modb"

echo "== 编译被测程序（带 -g）=="
rm -rf /tmp/modcond && mkdir -p /tmp/modcond
cp "$HERE"/lib/*.mo /tmp/modcond/ || exit 1
cp "$HERE"/examples/dbgloop.mo /tmp/modcond/test.mo || exit 1
( cd /tmp/modcond && "$HERE/bin/moc" test.mo -g out.elf ) || { echo "✗ dbgloop 编译失败"; exit 1; }

cd /tmp/modcond || exit 1

echo "== 1. 条件断点：停在条件成立的那一轮 =="
printf 'b 22 if i == 5\nr\np i\np sum\nstat\nq\n' > c1.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c1.txt 2>&1)
chk "命中时 i = 5"        "$(has 'i = 5')"
chk "命中时 sum = 15"     "$(has 'sum = 15')"
chk "命中计数 = 1"        "$(has '断点命中   1')"
chk "条件放过 = 5"        "$(has '条件放过   5')"

echo "== 2. 计数是硬的：i==0 应当第一次就停，放过 0 次 =="
printf 'b 22 if i == 0\nr\nstat\nq\n' > c2.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c2.txt 2>&1)
chk "i==0 放过 0 次"      "$(has '条件放过   0')"
chk "i==0 命中 1 次"      "$(has '断点命中   1')"

echo "== 3. 反例：永不成立的条件必须一次都不停 =="
printf 'b 22 if i == 999\nr\nstat\nq\n' > c3.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c3.txt 2>&1)
chk "没有命中"            "$(nohas '断点命中 #')"
chk "放过 10 次（全轮）"  "$(has '条件放过   10')"
chk "程序正常跑完（55）"  "$(has '55')"
chk "正常退出码 0"        "$(has '退出码 0')"

echo "== 4. 其它比较运算符与算术 =="
printf 'b 22 if i > 7\nr\np i\nstat\nq\n' > c4.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c4.txt 2>&1)
chk "i > 7 停在 i = 8"    "$(has 'i = 8')"
chk "i > 7 放过 8 次"     "$(has '条件放过   8')"

printf 'b 22 if i + 1 == 6\nr\np i\nstat\nq\n' > c5.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c5.txt 2>&1)
chk "算术 i+1==6 停在 i=5" "$(has 'i = 5')"

printf 'b 22 if sum >= 15\nr\np sum\nstat\nq\n' > c6.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c6.txt 2>&1)
chk "sum >= 15 停在 15"   "$(has 'sum = 15')"

echo "== 4b. 复合条件：&& || 括号 =="
printf 'b 22 if i > 3 && i < 6\nr\np i\nstat\nq\n' > k1.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k1.txt 2>&1)
chk "&& 停在 i = 4"         "$(has 'i = 4')"
chk "&& 放过 4 次"          "$(has '条件放过   4')"

printf 'b 22 if i == 1 || i == 8\nr\nc\np i\nstat\nq\n' > k2.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k2.txt 2>&1)
chk "|| 第二次停在 i = 8"   "$(has 'i = 8')"
chk "|| 命中 2 次"          "$(has '断点命中   2')"
chk "|| 放过 7 次"          "$(has '条件放过   7')"

printf 'b 22 if (i == 5)\nr\np i\nstat\nq\n' > k3.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k3.txt 2>&1)
chk "括号包裹 (i == 5) 停 i=5" "$(has 'i = 5')"
chk "括号包裹不放过错误"      "$(nohas '条件无法求值')"

printf 'b 22 if (i > 3) && (i < 6)\nr\np i\nq\n' > k4.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k4.txt 2>&1)
chk "两侧都加括号停在 i = 4"  "$(has 'i = 4')"

printf 'b 22 if i == (4 + 1)\nr\np i\nq\n' > k5.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k5.txt 2>&1)
chk "括号里的算术 i == (4+1)"  "$(has 'i = 5')"

printf 'b 22 if i == 5 && sum == 15\nr\np i\np sum\nq\n' > k6.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k6.txt 2>&1)
chk "&& 读第二个变量 i = 5"   "$(has 'i = 5')"
chk "&& 读第二个变量 sum = 15" "$(has 'sum = 15')"

echo "== 4c. 优先级：&& 比 || 紧 =="
# 若 || 更紧，这个条件等价于 (i==5 || i==7) && sum==100，一次都不成立 → 命中 0
printf 'b 22 if i == 5 || i == 7 && sum == 100\nr\np i\nstat\nq\n' > k7.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k7.txt 2>&1)
chk "&& 更紧：停在 i = 5"      "$(has 'i = 5')"
chk "&& 更紧：命中 1 次"       "$(has '断点命中   1')"

echo "== 4d. 不做短路：拼错的变量名必须报出来 =="
# 故意在左侧为真时右侧藏一个错名。若实现做短路，右侧不求值、错误被吞，
# 断点表现为"条件成立就停"，拼写错误永远发现不了。
printf 'b 22 if i == 0 || zzz == 1\nr\nq\n' > k8.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k8.txt 2>&1)
chk "短路会吞掉的错误被报出"  "$(has '条件无法求值')"

printf 'b 22 if (i == 5\nr\nq\n' > k9.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x k9.txt 2>&1)
chk "括号不配对报错"          "$(has '条件无法求值')"

echo "== 5. 坏表达式必须报出来，不能静默当不成立 =="
printf 'b 22 if zzz == 1\nr\nq\n' > c7.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c7.txt 2>&1)
chk "未知变量名报错"      "$(has '条件无法求值')"

printf 'b 22 if i\nr\nq\n' > c8.txt
OUT=$(timeout 60 "$HERE/bin/modb" out.elf -x c8.txt 2>&1)
chk "缺比较运算符报错"    "$(has '条件无法求值')"

echo "== 6. 观察点：变量值改变时停下 =="
printf 'b 22\nr\nwatch sum\nstat\nq\n' > w1.txt
OUT=$(timeout 120 "$HERE/bin/modb" out.elf -x w1.txt 2>&1)
chk "watch sum 初值 0"    "$(has '观察点: sum = 0')"
chk "watch sum 触发 0->1" "$(has '观察点触发: sum  0 -> 1')"

printf 'b 22\nr\nwatch i\nq\n' > w2.txt
OUT=$(timeout 120 "$HERE/bin/modb" out.elf -x w2.txt 2>&1)
chk "watch i 触发 0->1"   "$(has '观察点触发: i  0 -> 1')"

echo "== 7. 反向验证：作用域外的变量必须报找不到 =="
printf 'b 22\nr\nwatch zzz\nq\n' > w3.txt
OUT=$(timeout 120 "$HERE/bin/modb" out.elf -x w3.txt 2>&1)
chk "watch 未知变量报错"  "$(has '找不到变量 zzz')"

echo "== 8. 观察点在另一个函数里（addv 的局部 s）=="
printf 'b addv\nr\nwatch s\nq\n' > w4.txt
OUT=$(timeout 120 "$HERE/bin/modb" out.elf -x w4.txt 2>&1)
chk "addv 里 watch s 触发" "$(has '观察点触发: s  0 -> 1')"

echo
echo "通过 $PASS / 失败 $FAIL"
if [ "$FAIL" != 0 ]; then exit 1; fi
exit 0
