#!/bin/bash
# hllmut —— 变异验证：证明 tests/138_hll.mo 的 29 项断言真的在起作用
#
# 为什么需要它：只看"29 全过"证明不了任何一条断言非空转。
# 本轮最有力的例子就是那个 bit63 缺陷本身 ——
#   它不报错、不崩溃、估计值始终是个像样的数，
#   只有"V 恰为 m/2 且不再下降"这一个数字能揪出它。
#   所以必须反过来问：如果把这个缺陷放回去，测试会不会红？
#
# 本脚本自身的失效史（与 lfmut v1.132、scopemut v1.129、lshmut v1.137 同源）：
#   · 备份放 /tmp —— 沙盒中断一次就没了，源码停在变异态
#   · 用"已还原"标志跳过还原 —— 备份了污染版，三次还原全还原成污染版，
#     而脚本照样打印全绿
#   · 用 grep 变异串核对还原 —— 注释里写着同一个串，恒判"还没还原"
# 所以这里：备份放 build/、每次都重新拷贝、还原用 diff 逐字节核对。

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/lib/hll.mo"
BAK="$HERE/build/hll.mo.orig"
MOC="$HERE/bin/moc"
mkdir -p "$HERE/build"

# ── 跑一次测试，返回退出码（断言失败数即退出码）──────────────
# ⚠️ rm -f bin/moc 之外的重建风险：本脚本只换 lib/ 不换编译器，
#    但如果上一次构建与 cp 落在同一秒，make 会认为 bin/moc 仍更新。
#    这里**直接用现成的 bin/moc**（由 Makefile 依赖保证），
#    并显式 rm 掉 out.elf，避免用到上一个变异的产物。
run_test() {
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp "$HERE"/lib/*.mo /tmp/mot/ 2>/dev/null
  cp "$HERE"/tests/138_hll.mo /tmp/mot/test.mo
  ( cd /tmp/mot && "$MOC" test.mo out.elf ) >/dev/null 2>&1 || return 99
  ( cd /tmp/mot && ./out.elf ) >/dev/null 2>&1
  return $?
}

# ── 还原：用 build/ 下的干净副本覆盖，并 diff 核对 ───────────
restore() {
  cp "$BAK" "$SRC"
  if ! diff -q "$BAK" "$SRC" >/dev/null 2>&1; then
    echo "✗ 还原失败：$SRC 与干净副本不一致"
    return 1
  fi
  return 0
}
trap restore EXIT INT TERM

# ── 开工前：源码必须干净 ────────────────────────────────────
if [ ! -f "$BAK" ]; then
  # 发布包不含 build/（全是中间产物），首次运行必然走到这里。
  # 此时只能以**当前**源码为基线 —— 若它已被上一轮中断的变异污染，
  # 基线会静默变成污染版。所以这里明确打印出来，不假装它必然干净。
  echo "⚠ 首次运行：以当前 $SRC 建立基线副本"
  cp "$SRC" "$BAK"
fi
if ! diff -q "$BAK" "$SRC" >/dev/null 2>&1; then
  echo "⚠ 源码与干净副本不一致，先还原"
  restore || exit 1
fi

# ── 基线 ────────────────────────────────────────────────────
BASE_RC=0
run_test; BASE_RC=$?
if [ "$BASE_RC" != 0 ]; then
  echo "✗ 基线未通过（rc=$BASE_RC）—— 后面的变异结论全部无效"
  exit 1
fi
echo "基线通过（rc=0）"

# ── 变异定义 ────────────────────────────────────────────────
NAMES=(
  "M1 mix 退回算术右移（bit63 归零 → 只用一半桶）"
  "M2 桶索引去掉 & (m-1)（符号扩展 → 负桶号）"
  "M3 rho 不 +1（clz−p，估计系统性偏小）"
  "M4 小基数修正永不生效（恒返回原始估计）"
  "M5 桶取 min 而不是 max"
)
# 用 python 做**精确子串**替换，不用 sed 正则 ——
# 子串替换要么命中要么明确报"锚点不存在"，不会静默什么都不做。
OLDS=(
  '    a = a ^ hll_shr(a, 31);'
  '    let idx: i64 = (h >> (64 - p)) & (m - 1);'
  '        rho = hll_clz64(w) - p + 1;'
  '    if e <= 2.5 * f64(m) {'
  '    if rho > HLLP[s + 1 + idx] {'
)
NEWS=(
  '    a = a ^ (a >> 31);'
  '    let idx: i64 = h >> (64 - p);'
  '        rho = hll_clz64(w) - p;'
  '    if 0 == 1 {'
  '    if rho < HLLP[s + 1 + idx] {'
)

apply_mut() {
  python3 - "$SRC" "$1" "$2" <<'PYEOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
if old not in s:
    sys.stderr.write("anchor not found\n")
    sys.exit(3)
open(path, 'w').write(s.replace(old, new, 1))
PYEOF
}

FAILED=0
N=${#NAMES[@]}
for i in $(seq 0 $((N-1))); do
  # 每次都重新拷贝干净副本，绝不复用上轮状态
  cp "$BAK" "$SRC"
  apply_mut "${OLDS[$i]}" "${NEWS[$i]}"
  if diff -q "$BAK" "$SRC" >/dev/null 2>&1; then
    echo "✗ ${NAMES[$i]}：变异未生效（锚点没匹配上），判为失败"
    FAILED=$((FAILED+1))
    continue
  fi
  RC=0
  run_test; RC=$?
  if [ "$RC" != 0 ]; then
    echo "✓ ${NAMES[$i]} 变异被捕获（rc=$RC，非 0 即断言变红）"
  else
    echo "✗ ${NAMES[$i]} 变异**未被捕获**（rc=0）—— 相关断言可能是空转"
    FAILED=$((FAILED+1))
  fi
  restore || { echo "✗ 还原失败，中止"; exit 1; }
done

echo "----"
if [ "$FAILED" != 0 ]; then
  echo "✗ hllmut 失败：$FAILED 项变异未被捕获"
  exit 1
fi
echo "✓ hllmut 全部通过：$((${#NAMES[@]})) 个变异均被捕获"
exit 0
