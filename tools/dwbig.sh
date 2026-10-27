#!/bin/bash
# dwbig —— 拿 dwmo -s 去扫真实大程序（自举出来的 bin/moc 本体）
#
# 为什么需要这个脚本：
#   dwmotest.sh 只在一份 20 来行的小程序上跑 dwmo。小程序函数体短、
#   指令种类少，解码器里写错的分支可能根本没被走到 —— 于是"dwmo 是对的"
#   这个结论的覆盖面一直只有那 20 行。
#
#   这里改成扫 bin/moc 自己（355 个函数 / 4 万多条例指令）：
#     1. dwmo -s   与被测程序无关的通用校验，7 项
#     2. dwmo -S   逐函数输出 lo/hi/指令数，拿去和 objdump 交叉验证
#
# 交叉验证的定位说清楚：
#   dwmo 自己不调 objdump（否则就不叫自包含了）。这里是测试时拿外部
#   反汇编器当独立参照，用来证明 dwmo 的结论可信。没有 objdump 时
#   自动跳过这一段，只跑 -s。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/dwbigbuild
rm -rf "$W" && mkdir -p "$W" || exit 1

# 1) 用 -g 重新编译 bin/moc（自举产物必须带调试信息才有 DWARF 可校验）
cp "$HERE/src/compiler.mo" "$W/test.mo" || exit 1
( cd "$W" && "$HERE/bin/moc" test.mo -g moc.elf ) || {
    echo "✗ 带 -g 编译 compiler.mo 失败"; exit 1; }

# 2) 编译 dwmo
cp "$HERE"/lib/*.mo "$W"/ || exit 1
cp "$HERE/tools/dwmo.mo" "$W"/dwmo.mo || exit 1
( cd "$W" && "$HERE/bin/moc" dwmo.mo -o dwmo.elf ) || {
    echo "✗ dwmo.mo 编译失败"; exit 1; }
cp "$W/dwmo.elf" "$HERE/bin/dwmo" && chmod +x "$HERE/bin/dwmo"

echo "== dwmo -s（扫 bin/moc 本体，通用校验）=="
"$HERE/bin/dwmo" "$W/moc.elf" -s
rc=$?

echo "== dwmo -l -L（行号表 + 源码语义级校验）=="
# -L：把源码喂进来。行号是编译器自己报的、行号表也是编译器自己生成的，
# 两相比对只能证明"自洽"。只有拿源码当第三方参照才能证明"对得上"。
"$HERE/bin/dwmo" "$W/moc.elf" -l -L "$W/test.mo"
lrc=$?
if [ "$lrc" -ne 0 ]; then rc=1; fi

echo "== 与 objdump 交叉验证（逐函数指令数）=="
if ! command -v objdump >/dev/null 2>&1; then
    echo "  （无 objdump，跳过）"
    exit $rc
fi

"$HERE/bin/dwmo" "$W/moc.elf" -S > "$W/perf.txt" 2>/dev/null
python3 - "$W/moc.elf" "$W/perf.txt" <<'PY'
import re, subprocess, sys
elf, perf = sys.argv[1], sys.argv[2]
out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", elf],
                     capture_output=True, text=True).stdout
addrs = []
for ln in out.splitlines():
    m = re.match(r"^\s+([0-9a-f]+):", ln)
    if m:
        addrs.append(int(m.group(1), 16))
addrs.sort()
fns = []
for ln in open(perf):
    p = ln.split()
    if len(p) == 3 and all(x.lstrip("-").isdigit() for x in p):
        fns.append((int(p[0]), int(p[1]), int(p[2])))
if not fns:
    print("  ✗ 没解析出函数表"); sys.exit(1)
import bisect
bad = 0
tot_mo = 0
tot_od = 0
for lo, hi, n in fns:
    a = bisect.bisect_left(addrs, lo)
    b = bisect.bisect_left(addrs, hi)
    m = b - a
    tot_mo += n
    tot_od += m
    if m != n:
        bad += 1
        if bad <= 5:
            print("  [!!] lo=%d dwmo=%d objdump=%d" % (lo, n, m))
print("  函数数            %d" % len(fns))
print("  dwmo  指令总数    %d" % tot_mo)
print("  objdump 指令总数  %d" % tot_od)
if bad == 0:
    print("  ✓ 逐函数指令数与 objdump 完全一致")
else:
    print("  ✗ %d 个函数的指令数与 objdump 不一致" % bad)
sys.exit(1 if bad else 0)
PY
prc=$?
if [ $prc -ne 0 ]; then rc=1; fi
exit $rc
