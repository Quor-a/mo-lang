#!/bin/bash
# pkgv3mut —— 证明"签名检查"真的在拦，而不是空转
#
#   make pkgv3mut
#
# 每个变异都要回到一个**真实的错误状态**，然后看测试会不会红。
# 判据不是"跑通"，是"必须和基线不一样"。
#
# 只跑 x86-64 端：签名逻辑与架构无关，两端等价已由 pkgv3test 的 82 项证明。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
SRC=examples/pkgv3.mo
mkdir -p build
BAK=build/pkgv3.mo.orig
cp "$SRC" "$BAK"
trap 'cp "$BAK" "$SRC"' EXIT INT TERM

# 基线的关键行（签名相关）—— 变异后至少一项必须变化
KEYLINES='\[11\] sip vec bad|\[12\] tamper ver|\[13\] goodkey|\[13\] wrongkey|\[10\] unpack ret|pkg ok'

run_x86() {
    rm -rf /tmp/mo_pkgs_v3
    rm -f /tmp/pkgv3_mut
    if ! ARCH=x86_64 bash tools/android_native.sh "$SRC" /tmp/pkgv3_mut >/tmp/pkgv3mut_build.log 2>&1; then
        echo "BUILD-FAIL"; return
    fi
    [ -f /tmp/pkgv3_mut ] || { echo "BUILD-FAIL"; return; }
    /tmp/pkgv3_mut 2>&1 | grep -E "$KEYLINES" | tr -d ' \r'
}

apply() {   # apply <old> <new>
python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p,o,n=sys.argv[1:4]
s=open(p).read()
c=s.count(o)
if c!=1:
    print("ANCHOR-MISS(%d)"%c); sys.exit(1)
open(p,'w').write(s.replace(o,n,1))
print("OK")
PY
}

echo "=== pkgv3 签名变异验证 ==="
BASE=$(run_x86)
if [ "$BASE" = "BUILD-FAIL" ]; then echo "✗ 基线构建失败"; exit 1; fi
echo "基线:"; echo "$BASE" | sed 's/^/    /'
echo "$BASE" | grep -q "pkgok=1" || { echo "✗ 基线 pkg ok 不是 1"; exit 1; }
echo "  ✓ 基线通过"

PASS=0; FAIL=0
mut() {  # mut <编号> <描述> <old> <new>
    cp "$BAK" "$SRC"
    r=$(apply "$3" "$4")
    if [ "$r" != "OK" ]; then echo "  ✗ M$1 $2 锚点: $r"; FAIL=$((FAIL+1)); return; fi
    got=$(run_x86)
    if [ "$got" = "$BASE" ]; then
        echo "  ✗ M$1 $2 **未被捕获**（与基线完全相同）"
        FAIL=$((FAIL+1))
    elif [ "$got" = "BUILD-FAIL" ]; then
        echo "  ✓ M$1 $2 被捕获（构建失败）"; PASS=$((PASS+1))
    else
        echo "  ✓ M$1 $2 被捕获"
        diff <(echo "$BASE") <(echo "$got") | grep '^>' | sed 's/^/        /'
        PASS=$((PASS+1))
    fi
}

mut 1 "签名 hex 退回小端" \
    'b = (v >> ((7 - i) * 8)) & 255;' 'b = (v >> (i * 8)) & 255;'
mut 2 "unpack 不验签" \
    'if sg != sig_compute(s) { return -9; }' 'if sg != sg { return -9; }'
mut 3 "签名只覆盖 code（漏掉元数据）" \
    '    p = take_seg(s, 0, &T);
    while k < 5 {' \
    '    p = take_seg(s, 0, &T);
    p = take_seg(s, p, &T);
    p = take_seg(s, p, &T);
    p = take_seg(s, p, &T);
    p = take_seg(s, p, &T);
    while k < 1 {'
mut 4 "rotl64 退回 (1 << r)" \
    '((one << r) - 1)' '((1 << r) - 1)'
mut 5 "SipHash 常数差一" \
    'SV0 = 8317987319222330741 ^ k0;' 'SV0 = 8317987319222330740 ^ k0;'

cp "$BAK" "$SRC"
echo
echo "捕获 $PASS 个，未捕获 $FAIL 个"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
