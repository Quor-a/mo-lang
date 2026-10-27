#!/bin/bash
# 性能基线：跑 examples/bench.mo 多次取中位数，与基线对比
#
#   bash tools/benchtest.sh           对比基线（超出阈值则失败）
#   bash tools/benchtest.sh --update  写入新基线
#
# 为什么需要它：上一轮实测发现寄存器分配会**增大**体积，于是"真 IR"
# 的价值变成性能。但没有性能基线就无法判断改动是快了还是慢了 ——
# 这个脚本让性能成为**可回归**的量。
set -e
cd "$(dirname "$0")/.."
BASE=docs/perf_baseline.txt
N=${N:-5}
TOL=${TOL:-25}          # 允许波动 ±25%（机器噪声 + 调度影响）

mkdir -p build
./bin/moc examples/bench.mo build/bench.elf

# 跑 N 次，收集每个 workload 的耗时（ns）
declare -A SUM MIN MAX
for i in $(seq 1 $N); do
  while read -r name val unit; do
    [ "$unit" = "ns" ] || continue
    SUM[$name]=$(( ${SUM[$name]:-0} + val ))
    if [ -z "${MIN[$name]:-}" ] || [ "$val" -lt "${MIN[$name]}" ]; then MIN[$name]=$val; fi
    if [ -z "${MAX[$name]:-}" ] || [ "$val" -gt "${MAX[$name]}" ]; then MAX[$name]=$val; fi
  done < <(./build/bench.elf)
done

# 中位数近似：用 (总和 - 最小 - 最大) / (N-2)，对 N>=3 稳健
echo "=== 性能基线（$N 次，去掉极值取均值）==="
RESULT=""
for k in arith call recur array local; do
  if [ -z "${SUM[$k]:-}" ]; then echo "❌ 缺少 workload: $k"; exit 1; fi
  v=$(( ( ${SUM[$k]} - ${MIN[$k]} - ${MAX[$k]} ) / (N - 2) ))
  ms=$(( v / 1000000 ))
  printf "  %-8s %8d ns  (%d ms)\n" "$k" "$v" "$ms"
  RESULT="$RESULT$k $v
"
done

if [ "${1:-}" = "--update" ]; then
  printf '%s' "$RESULT" > "$BASE"
  echo "✅ 基线已写入 $BASE"
  exit 0
fi

if [ ! -f "$BASE" ]; then
  echo "⚠️  无基线，先跑：bash tools/benchtest.sh --update"
  exit 0
fi

echo "=== 与基线对比（容差 ±${TOL}%）==="
FAIL=0
IMPROVE=0
while read -r k v; do
  [ -z "$k" ] && continue
  old=$(grep "^$k " "$BASE" | awk '{print $2}')
  [ -z "$old" ] && continue
  lo=$(( old * (100 - TOL) / 100 ))
  hi=$(( old * (100 + TOL) / 100 ))
  pct=$(( (v - old) * 100 / old ))
  if [ "$v" -gt "$hi" ]; then
    printf "  ❌ %-8s %10d → %10d  (%+d%%)  变慢，超出容差\n" "$k" "$old" "$v" "$pct"
    FAIL=1
  elif [ "$v" -lt "$lo" ]; then
    # 变快不算回归，但要提示更新基线，否则每次都红
    printf "  ⚡ %-8s %10d → %10d  (%+d%%)  变快，请更新基线\n" "$k" "$old" "$v" "$pct"
    IMPROVE=1
  else
    printf "  ✓ %-8s %10d → %10d  (%+d%%)\n" "$k" "$old" "$v" "$pct"
  fi
done <<< "$RESULT"

# 顺带记录体积，让"体积 vs 性能"的取舍可同时观察
SZ=$(python3 tools/codesize.py bin/moc 2>/dev/null | grep '代码段' | grep -o '[0-9]*' | head -1)
echo "  代码段体积: ${SZ} 字节"

if [ "$FAIL" = "1" ]; then
  echo "❌ 性能回归（变慢）"
  exit 1
fi
if [ "$IMPROVE" = "1" ]; then
  echo "⚡ 有变快项（不是回归）；确认后跑：bash tools/benchtest.sh --update"
  exit 0
fi
echo "✅ 性能在容差内"
