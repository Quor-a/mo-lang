#!/bin/bash
# kern64mut.sh —— 证明 kern64test 不是空转：故意改坏，必须变红
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
mkdir -p build
BAK=build/kern64mut
cp tools/mo2x.mo $BAK.mo
restore_mo2x() { cp $BAK.mo tools/mo2x.mo; }
trap 'restore_mo2x; make mo2x >/dev/null 2>&1' EXIT INT TERM
run() { bash tools/kern64test.sh >/tmp/k64m.log 2>&1; echo $?; }

echo "基线                : $(run)   (期望 0)"

# M1：UART 基址写错 —— 内核照样跑，只是往错误地址写，输出消失
python3 - <<'PY'
p='tools/mo2x.mo'; s=open(p,encoding='utf-8').read()
s=s.replace('0x09000000UL','0x08000000UL'); open(p,'w',encoding='utf-8').write(s)
PY
make mo2x >/dev/null 2>&1
echo "M1 UART 基址改错    : $(run)   (期望非 0)"
restore_mo2x; make mo2x >/dev/null 2>&1

# M2：aarch64 不分派 —— 直接落到 x86 的 VGA 前导，产物能编能链但往 0xB8000 写
python3 - <<'PY'
p='tools/mo2x.mo'; s=open(p,encoding='utf-8').read()
s=s.replace('if KERN_ARCH == 2 { return kern_header_aarch64(); }',
            'if KERN_ARCH == 2 { return kern_header(); }')
open(p,'w',encoding='utf-8').write(s)
PY
make mo2x >/dev/null 2>&1
echo "M2 分派失效(落 x86) : $(run)   (期望非 0)"
restore_mo2x; make mo2x >/dev/null 2>&1
echo "还原后              : $(run)   (期望 0)"
