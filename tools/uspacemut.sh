#!/bin/bash
# uspacemut —— 证明 uspacetest 的判据真的在拦，而不是空转
#
#   make uspacemut
#
# 做法：逐个把 uspace.mo 改坏（注入真实缺陷），跑 uspacetest，
# 期望**至少一个判据变红**。全部被捕获 = 判据有效。
#
# 只跑 ARM64 端与 x86-64 端的主体判据，两端都会跑（uspacetest 内部已含两端）。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=examples/uspace.mo
BAK=build/uspace.mo.orig
mkdir -p build

# ---------------- 还原机制 ----------------
# 🔴 备份必须在**确认源码干净之后**才取。若上一轮被强杀、源码停在变异态，
# 这里的 cp 会把污染版当成基线，于是"基线没通过"—— 而真正的错误在更前面
# （v1.135 / v1.142 各栽过一次）。
restore(){ [ -f "$BAK" ] && cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

# 开工自检：源码里不应残留任何一个变异标记
if grep -q "MUT_MARK" "$SRC"; then
  echo "uspacemut: 源码处于变异态，先自愈"
  restore
fi
cp "$SRC" "$BAK"

mut(){
  python3 - "$SRC" "$1" "$2" <<'EOF'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if a not in s:
    print("ANCHOR-MISS")
    sys.exit(3)
open(p,'w').write(s.replace(a, b, 1))
EOF
}

run(){
  bash tools/uspacetest.sh >/tmp/mo_uspace_mut.log 2>&1
  grep -c "✗" /tmp/mo_uspace_mut.log
}

echo "uspacemut: 基线"
B=$(run)
if [ "$B" != "0" ]; then
  echo "  ✗ 基线就有 $B 项失败，判据本身不可信"; exit 1
fi
echo "  ✓ 基线 0 项失败"

NAMES=(
  "M1 pk_run 不做校验和检查"
  "M2 pk_del 不减少包数"
  "M3 fnv 返回常数"
  "M4 VM 的乘法改成加法"
  "M5 解释器不执行命令"
)
ANCH=(
  'if fnv(&PK + s + 64, clen) != load64(&PK + s + 56) { return 0 - 6; }|if 0 != 0 { return 0 - 6; }'
  '    PN = last;|    PN = PN;'
  '    return h;
}|    return 0;
}'
  'VS[sp - 2] * VS[sp - 1]|VS[sp - 2] + VS[sp - 1]'
  '            do_line(&LINE);|            NCMD = NCMD + 0;'
)

pass=0
i=0
while [ $i -lt 5 ]; do
  A=${ANCH[$i]%%|*}
  Bv=${ANCH[$i]##*|}
  restore
  if ! mut "$A" "$Bv"; then
    echo "  ✗ ${NAMES[$i]}：锚点未命中（变异没打中，不是判据的问题）"
  else
    N=$(run)
    if [ "$N" -gt 0 ]; then
      echo "  ✓ ${NAMES[$i]}：被捕获，$N 项变红"
      pass=$((pass+1))
    else
      echo "  ✗ ${NAMES[$i]}：未被捕获"
    fi
  fi
  i=$((i+1))
done
restore

echo "uspacemut: $pass / 5 被捕获"
[ "$pass" = "5" ]
