#!/bin/bash
# modbtest —— 墨语言自己写的调试器（tools/modb.mo）的验证
#
# 为什么单独一个脚本：
#   调试器这一环此前一直缺：编译器、链接器、包管理器、LSP 都是墨语言
#   写的，能读自家 -g 信息的调试器却没有，自包含生态在最后一环是断的。
#   modb 用 ptrace 起停进程、按行号/函数名下断点、按 DWARF 的 fbreg
#   偏移读变量 —— 本脚本逐项验证这些能力**真的在工作**。
#
# 验证策略：
#   1. 断点定位：命中位置必须落在 addv()、第 5 行
#   2. 变量：s = 7（3+4），形参 a=3 / b=4（1.100 补的形参 DIE）
#   3. 回溯：#1 帧必须是 main()（调用者）
#   4. 反向验证：断点下在 main 的行再 p s，必须**找不到**（作用域）
#      —— 否则"找到"可能只是无条件通过
#   5. 固化本轮最大的坑：同一地址，/proc/<pid>/mem 读得对，
#      PTRACE_PEEKDATA 恒返回 -14(EFAULT)。两条通道都打出来对照。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
chk() {
    if [ "$2" = "1" ]; then PASS=$((PASS+1)); echo "  OK   $1";
    else FAIL=$((FAIL+1)); echo "  BAD  $1"; fi
}
has() { if grep -q "$1" <<<"$OUT"; then echo 1; else echo 0; fi; }

echo "== 编译 modb（墨语言调试器）=="
rm -rf /tmp/modbbuild && mkdir -p /tmp/modbbuild
cp "$HERE"/lib/*.mo /tmp/modbbuild/ || exit 1
cp "$HERE"/tools/modb.mo /tmp/modbbuild/test.mo || exit 1
( cd /tmp/modbbuild && "$HERE/bin/moc" ) || { echo "✗ modb.mo 编译失败"; exit 1; }
cp /tmp/modbbuild/out.elf "$HERE/bin/modb" || exit 1
chmod +x "$HERE/bin/modb"

echo "== 编译被测程序（带 -g）=="
rm -rf /tmp/modbt && mkdir -p /tmp/modbt
cp "$HERE"/lib/*.mo /tmp/modbt/ || exit 1
cp "$HERE"/examples/dbgdemo.mo /tmp/modbt/test.mo || exit 1
( cd /tmp/modbt && "$HERE/bin/moc" test.mo -g out.elf ) || { echo "✗ dbgdemo 编译失败"; exit 1; }

cd /tmp/modbt || exit 1

echo "== 1. 行号断点 + 变量 + 回溯 + 继续 =="
printf 'b 5\nr\np s\nbt\nc\nq\n' > c1.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c1.txt 2>&1)
chk "断点命中在 addv()"      "$(has 'addv()  第 5 行')"
chk "局部变量 s = 7"          "$(has 's = 7')"
chk "回溯含调用者 main()"     "$(has 'main()  第 11 行')"
chk "继续后正常退出"          "$(has '程序退出，退出码 0')"

echo "== 2. 形参（1.100 补的 DWARF 形参 DIE）=="
printf 'b 5\nr\np a\np b\nq\n' > c2.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c2.txt 2>&1)
chk "形参 a = 3"              "$(has 'a = 3')"
chk "形参 b = 4"              "$(has 'b = 4')"

echo "== 3. 按函数名下断点（函数定义行可下断点，1.98 的成果）=="
printf 'b addv\nr\nq\n' > c3.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c3.txt 2>&1)
chk "b addv 命在第 3 行"      "$(has 'addv()  第 3 行')"

echo "== 4. 反向验证：作用域（断点在 main 时 p s 必须找不到）=="
printf 'b 12\nr\np s\nq\n' > c4.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c4.txt 2>&1)
chk "作用域外 p s 报找不到"   "$(has '找不到变量 s')"

echo "== 5. 不存在的行号必须报错而不是静默 =="
printf 'b 9999\nq\n' > c5.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c5.txt 2>&1)
chk "无对应代码的行号报错"    "$(has '没有对应的代码地址')"

echo "== 6. 单步（rip 必须前进）=="
printf 'b 5\nr\nregs\ns\nregs\nq\n' > c6.txt
OUT=$(timeout 40 "$HERE/bin/modb" out.elf -x c6.txt 2>&1)
N=$(grep -o 'rip 0x[0-9a-f]*' <<<"$OUT" | sort -u | wc -l)
if [ "$N" -ge 2 ]; then R=1; else R=0; fi
chk "单步后 rip 变化" "$R"

echo "== 7. 固化内存通道的差异（/proc/pid/mem 对，PEEKDATA 恒 EFAULT）=="
chk "/proc/pid/mem 读到真值"  "$(grep -q 'mem(text)    0x[0-9a-f]' <<<"$OUT" && echo 1 || echo 0)"
chk "PTRACE_PEEKDATA 恒失败"  "$(has 'ptrace(text) 0x-e')"

echo
echo "通过 $PASS / 失败 $FAIL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
