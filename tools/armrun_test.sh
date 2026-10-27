#!/bin/bash
# armrun_test —— ARM64（Android 原生）运行时验证
#
# 交叉编译出来的 ARM64 程序本机是 x86-64，**从来没法执行**。
# 这里用 Unicorn 模拟 ARM64 CPU，并自己实现 Linux 的 syscall 表，
# 让程序真的跑起来、真的算出结果。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
ELF=/tmp/mo_armrun.arm64
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1 || {
  echo "armrun: 跳过（缺少 unicorn，见 tools/pyreq.sh）"
  exit 0
}

echo "armrun:"

bash tools/android_native.sh examples/andromo.mo $ELF >/dev/null 2>&1
chk $? "ARM64 构建"

S=$(python3 $ROOT/tools/armrun.py $ELF --steps 2000000000 2>/dev/null)
echo "$S" | grep -q "Mo on Android"
chk $? "  程序真的启动并输出"
echo "$S" | grep -q "counting primes below 200000"
chk $? "  读到范围参数 200000"

# π(200000) = 17984 —— 这是数学上的已知值，不是"跑起来了"就算过
echo "$S" | grep -q "primes below 200000 = 17984"
chk $? "  素数计数正确（π(200000)=17984）"

echo "$S" | grep -q "退出码     : 0"
chk $? "  正常退出（exit_group 被正确处理）"

if [ $fail -eq 0 ]; then echo "armrun: OK（ARM64 程序在模拟器里真跑通了）"; else echo "armrun: $fail 项未通过"; exit 1; fi
