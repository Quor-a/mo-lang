#!/bin/bash
# seed 冒烟测试 —— **改 seed 后必须立刻跑**
#
# 为什么单独有这个：make boot 只覆盖 compiler.mo 用到的路径。seed 改动如果
# 破坏了别的语法，boot 可能照样通过（也有可能不通过但报错点离根因很远）。
# 这里用两个最小程序（返回常量 / 标量赋值）在几秒内确认 seed 基本可用。
#
# 🔴 教训（本轮真实踩到）：测试文件被 make 清理后，seed 报
#    "cannot open input"，我却误判成词法改动破坏了 seed，白查一轮。
#    所以脚本自带测试文件，不依赖外部残留。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT/build"
S="$ROOT/bin/seed"
fail=0
cat > _sm1.mo <<'MO'
fn main() -> i64 { return 42; }
MO
cat > _sm2.mo <<'MO'
fn main() -> i64 {
    let x: i64 = 100;
    x = x + 3;
    return x;
}
MO
cat > _sm3.mo <<'MO'
fn main() -> i64 {
    let x: i64 = 100;
    x /= 7; x %= 5; x += 3; x *= 2; x -= 4;
    return x;
}
MO
# _sm3 期望 10 = 100/7(14) %5(4) +3(7) *2(14) -4(10)，手推过
for f in "_sm1 42" "_sm2 103" "_sm3 10"; do
  set -- $f; n=$1; exp=$2
  rm -f $n.elf
  if ! timeout 60 $S $n.mo $n.elf 2>/tmp/_sm_err; then
    echo "✗ $n: 编译失败"; cat /tmp/_sm_err; fail=1; continue
  fi
  chmod +x $n.elf
  ./$n.elf >/dev/null 2>&1; got=$?
  if [ "$got" != "$exp" ]; then echo "✗ $n: 得到 $got 期望 $exp"; fail=1
  else echo "✓ $n = $got"; fi
done
if [ $fail = 0 ]; then echo "seed 冒烟通过"; else echo "seed 冒烟失败"; fi
exit $fail
