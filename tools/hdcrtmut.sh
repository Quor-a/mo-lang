#!/bin/bash
# hdcrtmut —— HDC retrain 的变异验证
# 只看"13 项全过"证明不了什么：断言可能压根没参与判定。
# 这里故意把三条核心机制逐个改坏，确认测试**立刻变红**。
#   M1  online 的"减掉错分那一类"改成"加上"  → 纠正方向反了
#   M2  score 闭式最高位平面取正权           → 补码负数解释失效
#   M3  addsub 的借位传播写错                → 减法变错
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HERE/lib/hdc.mo"
BAK="/tmp/hdcrtmut_bak.mo"
W="/tmp/hdcrtmut_w"
cp "$LIB" "$BAK"
RESTORE_DONE=0
restore() {
  [ "$RESTORE_DONE" = 1 ] && return
  cp "$BAK" "$LIB"; RESTORE_DONE=1
}
trap restore EXIT

run() {
  rm -rf "$W" && mkdir -p "$W" && cp "$HERE"/lib/*.mo "$W/"
  cp "$HERE/tests/124_hdcrt.mo" "$W/test.mo"
  ( cd "$W" && "$HERE/bin/moc" test.mo out.elf ) >/dev/null 2>&1 || { echo "编译失败"; return; }
  chmod +x "$W/out.elf" 2>/dev/null
  ( cd "$W" && ./out.elf ) 2>&1 | tail -1
}

mut() { python3 - "$LIB" "$1" "$2" <<'PY'
import sys
p,a,b=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p).read()
assert a in s, "变异点未找到: "+a
open(p,'w').write(s.replace(a,b,1))
PY
}

echo "基线:"
run

echo "M1  减掉错分那一类 -> 加上:"
mut "hdc_rt_addsub(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW, 0 - 1);" \
    "hdc_rt_addsub(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW, 1);"
run
restore; RESTORE_DONE=0

echo "M2  score 最高位平面取正权:"
mut "HDRT0 = HDRT0 - (1 << (HDRCW - 1)) * HDRT1;" \
    "HDRT0 = HDRT0 + (1 << (HDRCW - 1)) * HDRT1;"
run
restore; RESTORE_DONE=0

echo "M3  addsub 借位传播写错:"
mut "HDRT3 = (HDRT1 ^ (0 - 1)) & HDRT3;" \
    "HDRT3 = HDRT1 & HDRT3;"
run
restore

echo "已还原（变异串不应还在源里）:"
grep -c "HDRT0 = HDRT0 + (1 << (HDRCW - 1)) \* HDRT1;" "$LIB"
