#!/bin/bash
# riscvrun_test —— RISC-V 64 运行时验证（在 CPU 模拟器里真跑）
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
ELF=/tmp/mo_riscvrun.rv64
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1 || {
  echo "riscvrun: 跳过（缺少 unicorn，见 tools/pyreq.sh）"; exit 0
}

echo "riscvrun:"
bash tools/riscv_native.sh examples/andromo.mo $ELF >/dev/null 2>&1
chk $? "RISC-V 构建"

S=$(python3 $ROOT/tools/riscvrun.py $ELF 50000 --steps 2000000000 2>/dev/null)
echo "$S" | grep -q "Mo on Android"
chk $? "  程序真的启动并输出"
echo "$S" | grep -q "counting primes below 50000"
chk $? "  ecall 路径下 argc/argv 生效"
echo "$S" | grep -q "primes below 50000 = 5133"
chk $? "  素数计数正确（π(50000)=5133）"
echo "$S" | grep -q "退出码     : 0"
chk $? "  正常退出"

if [ $fail -eq 0 ]; then echo "riscvrun: OK（RISC-V 程序在模拟器里真跑通了）"; else echo "riscvrun: $fail 项未通过"; exit 1; fi
