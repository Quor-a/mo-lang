#!/bin/bash
# hdcmut —— HDC 的变异验证
# 只看"27 项全过"证明不了什么：断言可能压根没参与判定。
# 这里故意把三条核心性质逐个改坏，确认测试**立刻变红**。
#   M1  binding XOR → OR      （BSC 的精确自逆被破坏）
#   M2  CIM 去掉逐级复制      （退化成 i.i.d.，序结构消失）
#   M3  sim 口径 1−2ham/D → 1−ham/D（正交判据整体失效）
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HERE/lib/hdc.mo"
BAK="/tmp/hdcmut_bak.mo"
W="/tmp/hdcmut_w"
cp "$LIB" "$BAK"
restore() { cp "$BAK" "$LIB"; }
trap restore EXIT

run() {
  rm -rf "$W" && mkdir -p "$W" && cp "$HERE"/lib/*.mo "$W/"
  cp "$HERE/tests/123_hdc.mo" "$W/test.mo"
  ( cd "$W" && "$HERE/bin/moc" test.mo out.elf ) >/dev/null 2>&1 || { echo "编译失败"; return; }
  chmod +x "$W/out.elf" 2>/dev/null
  ( cd "$W" && ./out.elf ) 2>&1 | tail -1
}

echo "基线:"
run

echo "M1  binding XOR -> OR:"
sed -i 's|HDP\[dst + _h0\] = HDP\[a + _h0\] \^ HDP\[b + _h0\];|HDP[dst + _h0] = HDP[a + _h0] \| HDP[b + _h0];|' "$LIB"
run
restore

echo "M2  CIM 去掉逐级复制:"
sed -i 's|^        hdc_copy(base + HDI \* HDW, base + (HDI - 1) \* HDW);|        hdc_fill(base + HDI * HDW);|' "$LIB"
run
restore

echo "M3  sim 口径 1-2ham/D -> 1-ham/D:"
sed -i 's|return ((HDD - _h0 - _h0) << 16) / HDD;|return ((HDD - _h0) << 16) / HDD;|' "$LIB"
run
restore

echo "已还原"
grep -c "HDI - 1" "$LIB"
