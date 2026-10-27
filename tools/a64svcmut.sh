#!/usr/bin/env bash
# a64svcmut —— 证明 a64svctest 真的在验东西：把实现改坏，测试必须变红。
#
# 变异一半打在**模拟器**（异常模型是它按 ARM ARM 补的，不是 Unicorn 自带的），
# 一半打在**汇编器**（svc 的机器码是它算的）。只打一边的话，"隔离"到底是谁
# 提供的就说不清。
#
# 每个变异都要：① 锚点命中且唯一  ② 改坏后测试失败  ③ 改回后基线仍通过。
# 开工前先自愈（反向替换）：上一轮若被强杀，源码可能停在变异态，而备份也可能
# 是污染版（v1.129 / v1.132 栽过）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64svcmut
rm -rf $W; mkdir -p $W/pristine
cp tools/kern64run.py $W/pristine/kern64run.py
cp examples/a64as.mo  $W/pristine/a64as.mo

apply() {
python3 - "$1" "$2" "$3" <<'PY'
import sys
p,old,new=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p,encoding='utf-8').read()
n=s.count(old)
if n!=1: sys.exit("ANCHOR ERROR in %s: %r count=%d"%(p,old[:70],n))
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY
}
heal() {
python3 - "$1" "$2" "$3" <<'PY'
import sys
p,mut,clean=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(s.replace(mut,clean))
PY
}

# 自愈：把六个变异串一律改回干净串（幂等）
heal tools/kern64run.py "take_sync(uc, EC_SVC64, uc.reg_read(UC_ARM64_REG_PC) - 4)" \
                        "take_sync(uc, EC_SVC64, uc.reg_read(UC_ARM64_REG_PC))"
heal tools/kern64run.py "        pass                                  # MUT-M2" \
                        "        uc.reg_write(UC_ARM64_REG_PSTATE, pst)"
heal tools/kern64run.py "            pass                              # MUT-M3" \
                        "            uc.reg_write(UC_ARM64_REG_SP, uc.reg_read(UC_ARM64_REG_SP_EL1))"
heal tools/kern64run.py "                if False:                     # MUT-M4" \
                        "                if el == 0 and is_priv_sys(w):"
heal tools/kern64run.py "            if False:                         # MUT-M5" \
                        "            if args.exc == 1 and cur_el(uc) == 0:"
heal examples/a64as.mo  'emit(0xD4000021)' 'emit(0xD4000001)'

CAP=0; TOT=0
run_mut() {
  name=$1; file=$2; old=$3; new=$4
  TOT=$((TOT+1))
  cp $W/pristine/$(basename $file) $file
  if ! apply "$file" "$old" "$new"; then echo "✗ $name 锚点未命中"; return 0; fi
  if bash tools/a64svctest.sh > $W/$name.log 2>&1; then
    echo "✗ $name 未被捕获（测试仍通过）"
  else
    red=$(sed -n 's/^通过 [0-9]* 项，失败 \([0-9]*\) 项$/\1/p' $W/$name.log | tail -1)
    echo "✓ $name 被捕获，失败 ${red:-?} 项"
    CAP=$((CAP+1))
  fi
}

# M1 svc 的 preferred return address 是**下一条**指令；写成上一条就原地死循环
run_mut M1 tools/kern64run.py \
  "take_sync(uc, EC_SVC64, uc.reg_read(UC_ARM64_REG_PC))" \
  "take_sync(uc, EC_SVC64, uc.reg_read(UC_ARM64_REG_PC) - 4)"
# M2 eret 不恢复 PSTATE → 用户一直停在 EL1，特权指令不再被陷入
run_mut M2 tools/kern64run.py \
  "        uc.reg_write(UC_ARM64_REG_PSTATE, pst)" \
  "        pass                                  # MUT-M2"
# M3 陷入时不切内核栈 → 内核踩在用户栈上（程序照样跑完，只有栈地址判据能抓）
run_mut M3 tools/kern64run.py \
  "            uc.reg_write(UC_ARM64_REG_SP, uc.reg_read(UC_ARM64_REG_SP_EL1))" \
  "            pass                              # MUT-M3"
# M4 EL0 执行特权指令不陷入 → 用户能改 VBAR，svc 之后跳到乱处
run_mut M4 tools/kern64run.py \
  "                if el == 0 and is_priv_sys(w):" \
  "                if False:                     # MUT-M4"
# M5 EL0 直写 UART 不拦 → 隔离形同虚设
run_mut M5 tools/kern64run.py \
  "            if args.exc == 1 and cur_el(uc) == 0:" \
  "            if False:                         # MUT-M5"
# M6 汇编器把 svc 的机器码算错 → 根本不是系统调用
run_mut M6 examples/a64as.mo \
  'emit(0xD4000001)' 'emit(0xD4000021)'

# 还原 + 基线复验
cp $W/pristine/kern64run.py tools/kern64run.py
cp $W/pristine/a64as.mo     examples/a64as.mo
if diff -q $W/pristine/kern64run.py tools/kern64run.py > /dev/null &&
   diff -q $W/pristine/a64as.mo     examples/a64as.mo > /dev/null; then
  echo "源码已还原"
else
  echo "✗ 还原失败"
fi
if bash tools/a64svctest.sh > $W/base.log 2>&1; then
  echo "基线复验通过"
else
  echo "✗ 基线复验失败"; tail -5 $W/base.log
fi
echo "a64svcmut: $CAP / $TOT 被捕获"
[ "$CAP" = "$TOT" ] || exit 1
exit 0
