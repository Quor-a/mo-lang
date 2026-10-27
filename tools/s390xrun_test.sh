#!/bin/bash
# s390xrun_test —— s390x（大端）运行时验证（在 CPU 模拟器里真跑）
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
ELF=build/mo_s390x.s390x
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1 || {
  echo "s390xrun: 跳过（缺少 unicorn，见 tools/pyreq.sh）"; exit 0
}
echo "s390xrun:"
mkdir -p build
bash tools/s390x_native.sh examples/s390hello.mo $ELF >/dev/null 2>&1
chk $? "s390x 构建（大端、静态无 libc）"

S=$(MO_PYLIBS=${MO_PYLIBS:-/data/workspace/pylibs} python3 $ROOT/tools/s390xrun.py $ELF --steps 200000 2>/dev/null)
echo "$S" | grep -q "hello from s390x"
chk $? "  程序真的启动并输出"
# 不应重复（收敛保护生效）
N=$(echo "$S" | grep -c "hello from s390x")
[ "$N" = "1" ]
chk $? "  输出不重复（收敛保护生效）"

if [ $fail -eq 0 ]; then echo "s390xrun: OK（s390x 程序在模拟器里真跑通了）"; else echo "s390xrun: $fail 项未通过"; exit 1; fi
