#!/bin/bash
# uefirun_test —— UEFI 应用运行时验证（在 CPU 模拟器里真跑）
#
# 本机没有 OVMF（UEFI 固件），所以手工搭一个最小 UEFI 环境：
# 造 EFI_SYSTEM_TABLE + ConOut，把 OutputString 指到"魔法地址"上下 hook。
# 这样就能看到应用**真的打印了什么**，而不只是检查 PE 头。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
EFI=/tmp/mo_uefirun.efi
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1 || {
  echo "uefirun: 跳过（缺少 unicorn，见 tools/pyreq.sh）"
  exit 0
}
echo "uefirun:"

bash tools/uefi.sh examples/uefi.mo $EFI >/dev/null 2>&1
chk $? "UEFI 构建"

S=$(python3 $ROOT/tools/uefirun.py $EFI 2>/dev/null)
echo "$S" | grep -q "Mo UEFI application"
chk $? "  启动并打印横幅"
echo "$S" | grep -q "running in the firmware environment"
chk $? "  确认固件环境路径（非 syscall/VGA）"
echo "$S" | grep -q "fib: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377"
chk $? "  递归 fib 在固件里算对"
echo "$S" | grep -q "sum 1..100 = 5050"
chk $? "  整数计算正确（5050）"

if [ $fail -eq 0 ]; then echo "uefirun: OK（UEFI 应用在模拟器里真跑通了）"; else echo "uefirun: $fail 项未通过"; exit 1; fi
