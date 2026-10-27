#!/bin/bash
# kernrun_test —— 内核运行时验证（在 CPU 模拟器里真跑）
#
# 与 targets_test.sh 的区别：那边只验证"产物结构正确"，
# 这里验证"内核真的能启动、真的能响应输入、真的算对了"。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
ELF=/tmp/mo_kernrun.elf
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

# unicorn 是唯一能跑 ring0 的可用模拟器（qemu-user 只能跑用户态）
KERN_RUN="$ROOT/tools/kernrun.py"

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1 || {
  echo "kernrun: 跳过（缺少 unicorn，见 tools/pyreq.sh）"
  exit 0
}
echo "kernrun:"

bash tools/kernel.sh examples/kernel.mo $ELF >/dev/null 2>&1
chk $? "内核构建"

# 1) 能启动并打印横幅
S=$(python3 $KERN_RUN $ELF 2>/dev/null)
echo "$S" | grep -q "Mo Kernel v1"
chk $? "  启动并打印横幅"
echo "$S" | grep -q "no libc, no syscalls"
chk $? "  确认无 libc 路径"
echo "$S" | grep -q "mo>"
chk $? "  进入 shell 提示符"

# 2) 键盘输入 + 命令解析
S=$(python3 $KERN_RUN $ELF --keys "help" 2>/dev/null)
echo "$S" | grep -q "commands: help"
chk $? "  help 命令（键盘 I/O 正常）"

# 3) 算术：add 3 4 必须等于 7
S=$(python3 $KERN_RUN $ELF --keys "add 3 4" 2>/dev/null)
echo "$S" | grep -q "= 7"
chk $? "  add 3 4 = 7（内核里的整数计算）"

# 4) 格式错误必须**提示用法**，而不是静默给出错误结果
S=$(python3 $KERN_RUN $ELF --keys "add 34" 2>/dev/null)
echo "$S" | grep -q "usage: add"
chk $? "  add 34 → 提示用法（不静默算错）"
if echo "$S" | grep -q "= -45"; then
    echo "  ✗ add 34 仍给出 -45（静默错误结果）"; fail=$((fail+1))
fi

# 5) 未知命令
S=$(python3 $KERN_RUN $ELF --keys "zzz" 2>/dev/null)
echo "$S" | grep -q "? zzz"
chk $? "  未知命令回显"

if [ $fail -eq 0 ]; then echo "kernrun: OK（内核在模拟器里真跑通了）"; else echo "kernrun: $fail 项未通过"; exit 1; fi
