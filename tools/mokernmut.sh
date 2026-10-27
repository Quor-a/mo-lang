#!/usr/bin/env bash
# mokernmut —— 证明 tools/mokerntest.sh 真的能抓到缺陷
#
# 每个变异都是"改一行看起来无害的代码"，测试必须变红。改了代码却测不出
# 变化，往往不是代码对，而是判据瞎（v1.165 拓扑序那次就是三行 grep 分着
# 写，于是"liba 出现在输出里"和"liba 排第一"成了同一件事）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=examples/mokern.mo
BAK=/tmp/mokern.mo.bak
cp $SRC $BAK
CAP=0; MISS=0

apply() { python3 - "$1" "$2" <<'PY'
import sys
p='examples/mokern.mo'
s=open(p).read()
old,new=sys.argv[1],sys.argv[2]
if old not in s:
    print("ANCHOR MISSING: "+old); sys.exit(3)
open(p,'w').write(s.replace(old,new,1))
PY
}

run() {
    local name=$1
    local out
    out=$(bash tools/mokerntest.sh 2>&1 | tail -1)
    if echo "$out" | grep -q "失败 0 项"; then
        echo "✗ $name 未被捕获：$out"
        MISS=$((MISS+1))
    else
        echo "✓ $name 被捕获：$out"
        CAP=$((CAP+1))
    fi
    cp $BAK $SRC
}

# M1：data abort 的返回地址不 +4 → 出错指令原地重来 → 死循环，永远到不了 DONE
apply 'addi(0, 0, 4);                 # 返回地址 +4' \
      'addi(0, 0, 0);                 # 返回地址 +4'
run "M1 abort 返回地址不 +4"

# M2：内核私有块的 AP 从 00 改成 01 → 越权不再被拦，PF2 消失
apply 'ld64(9, 1025, 0, 16448, 64);' \
      'ld64(9, 1089, 0, 16448, 64);'
run "M2 内核私有块 AP=00→01"

# M3：_start 里不设 elr_el1 → eret 跳到 0，用户任务根本不起来
apply '    msr_(49665, 0);                # msr elr_el1, x0' \
      '    movz_(0, 0, 0);                # msr elr_el1, x0'
run "M3 不设 elr_el1"

# M4：UART 地址装错半字 → 字符写进 0x0900 而不是 0x09000000，一行都打不出
apply '    ldaddr(25, 2304);              # 0x09000000' \
      '    movz_(25, 2304, 0);            # 0x09000000'
run "M4 UART 地址装错半字"

# M5：不建内核私有块 → EL0 访问是转换错误而不是权限错误，PF2 不该出现
apply '    strx(9, 14, 16);' \
      '    movz_(9, 0, 0);'
run "M5 不建内核私有块描述符"

cp $BAK $SRC
echo "捕获 $CAP 个，未捕获 $MISS 个"
exit $((MISS > 0))
