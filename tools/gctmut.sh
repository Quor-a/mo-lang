#!/bin/bash
# gctmut —— 变异验证：逐个把 gc.mo 改坏，确认 gctest 会变红。
#
# 为什么必须做：17 项断言全绿证明不了它们非空转。
#   例如"标记传播"若压根没跑，链/树测试会给出 1 而不是 1000 —— 只有在
#   断言真的参与决策时才看得出来。
#
# 每个变异都必须**直接回到缺陷状态**：
#   "改点东西然后看它失败"是不够的，得确认改的正是那条因果链。

HERE=$(cd "$(dirname "$0")/.." && pwd)
GC="$HERE/lib/gc.mo"
BAK=/tmp/gc_orig.mo
cp "$GC" "$BAK"
restore() { cp "$BAK" "$GC"; }
trap restore EXIT

cd "$HERE"
BAD=0

run_mut() {
  local name="$1"
  if bash tools/gctest.sh >/tmp/gctmut_out.txt 2>&1; then
    echo "  ✗ $name：变异未被捕获（测试仍然全过 → 断言空转）"
    BAD=$((BAD+1))
  else
    local n
    n=$(grep -c "✗" /tmp/gctmut_out.txt)
    echo "  ✓ $name：被捕获（$n 项变红）"
  fi
  cp "$BAK" "$GC"
}

apply() {
  python3 - "$GC" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert a in s, "锚点未找到: " + a
open(p, 'w').write(s.replace(a, b, 1))
PY
}

echo "== 变异验证（每个都应让测试变红）=="

apply '    gc_propagate();' '    # gc_propagate();'
run_mut "M1 去掉标记传播（只扫根，不做传递闭包）"

apply 'if blk_ismark(p) == 0 {' 'if blk_ismark(p) == 1 {'
run_mut "M2 清除时判断取反（回收存活的、留下死掉的）"

apply '        if v >= p {' '        if v == p + 16 {'
run_mut "M3 blk_of 只认块起始（内部指针不再保活）"

apply '    scan_range(&probe, SB);' '    # scan_range(&probe, SB);'
run_mut "M4 不扫栈（局部变量持有的对象被回收）"

apply '    while i < MS_MAX { MS[i] = 0; i = i + 1; }' '    while i < 0 { MS[i] = 0; i = i + 1; }'
run_mut "M5 标记栈只清 MSP 个（propagate 后 MSP 已归 0 → 一个都不清）"

# 收尾：源码必须真的干净
if diff -q "$BAK" "$GC" >/dev/null; then
  echo "  ✓ 源码已还原（与原件逐字节一致）"
else
  echo "  ✗ 源码未还原"
  BAD=$((BAD+1))
fi

echo
if [ "$BAD" = "0" ]; then echo "gctmut: 全部变异均被捕获"; exit 0; fi
echo "gctmut: 有 $BAD 个变异未被捕获"
exit 1
