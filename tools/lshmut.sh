#!/bin/bash
# lshmut —— 变异验证：证明 tests/137_lsh.mo 的 18 项断言真的在起作用
#
# 为什么需要它：只看"18 全过"证明不了任何一条断言非空转。
# 本项目反复出现"测试全绿但什么都没验"，本轮就有两次：
#   · SimHash 退化成只加不减（签名恒定），而 "cos=1 时 ham=0" 照样通过
#   · 手写的一张 cos 表与真值差到 0.5，而它压根没被任何断言使用
#
# 本脚本自身的失效史（与 lfmut v1.132、scopemut v1.129 同源）：
#   · 备份放 /tmp —— 沙盒中断一次就没了，源码停在变异态
#   · 用"已还原"标志跳过还原 —— 备份了污染版，三次还原全还原成污染版，
#     而脚本照样打印全绿
#   · 用 grep 变异串核对还原 —— 注释里写着同一个串，恒判"还没还原"
# 所以这里：备份放 build/、每次都重新拷贝、还原用 diff 逐字节核对。

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/lib/lsh.mo"
BAK="$HERE/build/lsh.mo.orig"
MOC="$HERE/bin/moc"
mkdir -p "$HERE/build"

# ── 跑一次测试，返回退出码（断言失败数即退出码）──────────────
run_test() {
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp "$HERE"/lib/*.mo /tmp/mot/ 2>/dev/null
  cp "$HERE"/tests/137_lsh.mo /tmp/mot/test.mo
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

# ── 开工前：源码必须干净，否则从分片重建 ─────────────────────
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
# 每项：名字 | sed 表达式
NAMES=(
  "M1 MinHash 退回 raw a*x+b（不对元素 ID 做混合）"
  "M2 SimHash 减分支恒假（退化成只加不减）"
  "M3 band 哈希常数化（所有对都成为候选）"
  "M4 banding 只查 1 个 band（S 曲线退化成 s^r）"
)
# 用 python 做**精确子串**替换，不用 sed 正则 ——
# 本脚本第一版用 sed：M3 的锚点 `^    return h;$` 手工验证能匹配，
# 在脚本里却恒判"未生效"（正则转义与 bash 数组引号叠加，排查成本高而收益低）。
# 子串替换要么命中要么明确报"锚点不存在"，不会静默什么都不做。
OLDS=(
  'LSV = LSA[t] * (lsh_mix(x) & 2147483647) + LSB[t];'
  'if ((LSW >> LSJ) & 1) == 0 { LSP[acc + LSJ] = LSP[acc + LSJ] - 1; }'
  '    return h;'
  'while LSI < LSBAND {'
)
NEWS=(
  'LSV = LSA[t] * x + LSB[t];'
  'if 0 == 1 { LSP[acc + LSJ] = LSP[acc + LSJ] - 1; }'
  '    return 0;'
  'while LSI < 1 {'
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
  echo "✗ lshmut 失败：$FAILED 项变异未被捕获"
  exit 1
fi
echo "✓ lshmut 全部通过：$((${#NAMES[@]})) 个变异均被捕获"
exit 0
