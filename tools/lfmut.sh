#!/bin/bash
# lfmut —— lib/lf.mo 的变异验证
#
# 三条变异各对应一条因果链：
#   M1 去掉两处 & 255        → 返回值通道重新依赖 ABI 未定义的垃圾高位
#                              （v1.132 起主键已是 LF_EXP，故 M1 不再造成
#                               语义错误，但双通道计数 LF_DUAL 必须涨）
#   M2 lf_scan 不做危险指针检查 → 受保护的槽位也被回收 → UAF
#   M3 lf_mk 不打包 tag         → ABA 拦不住
#
# 🔴 四条踩过的坑，本脚本专门防：
#   1) 备份放 /tmp 会被沙盒回收 → 源码停在变异态而备份没了，只能手工还原。
#      备份改放 build/。
#   2) "改了点东西然后看它失败"不等于"改到了那条因果链"。
#   3) `out=$(cmd | tail -1); rc=$?` 取的是 tail 的退出码，恒为 0 ——
#      判据必须直接取自被测脚本，不能取自管道末端（v1.132 修）。
#   4) 脚本被强杀时 trap 未必跑完，下一轮基线被上一轮的变异污染。
#      故开工前先**自愈**：用同一批 (干净,变异) 对做反向替换。
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/lib/lf.mo"
BAK="$HERE/build/lfmut.bak"
mkdir -p "$HERE/build"

# 自愈：把任何残留的变异态反向替换回干净态
heal() {
python3 - "$SRC" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
pairs=[
 ('        if r == 0 {   # MUT_M1', '        if (r & 255) == 0 {'),
 ('    if r != 0 {   # MUT_M1',     '    if (r & 255) != 0 {'),
 ('        hit = 0;   # MUT_M2\n        j = 1000000;', '        hit = 0;\n        j = 0;'),
 ('    return i;   # MUT_M3\n    return t * 4294967296 + i;', '    return t * 4294967296 + i;'),
]
n=0
for b,a in pairs:
    if b in s:
        s=s.replace(b,a); n=n+1
if n:
    open(p,'w').write(s)
print(n)
PY
}

N=$(heal)
if [ "$N" != "0" ]; then
    echo "  ⚠ 检测到残留变异态，已自愈 $N 处"
fi
if grep -q 'MUT_M' "$SRC"; then
    echo "  ✗ lib/lf.mo 仍有无法自愈的变异标记，先手工还原"
    echo "通过 0 / 失败 1"; exit 1
fi
cp "$SRC" "$BAK"

restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

PASS=0; FAIL=0
TMO="$HERE/build/lfmut.out"
run() {   # run <名字> <期望: ok|mut>
    local name="$1" want="$2"
    local out rc nf np
    bash "$HERE/tools/lftest.sh" >"$TMO" 2>&1
    rc=$?
    out=$(tail -1 "$TMO")
    nf=$(grep -o '失败 [0-9]*' "$TMO" | tail -1 | awk '{print $2}')
    np=$(grep -o '通过 [0-9]*' "$TMO" | tail -1 | awk '{print $2}')
    echo "  $name -> $out (rc=$rc 通过${np:-?}/失败${nf:-?})"
    if [ "$want" = "ok" ]; then
        if [ $rc -eq 0 ] && [ "${nf:-1}" = "0" ]; then PASS=$((PASS+1));
        else FAIL=$((FAIL+1)); echo "    ✗ 基线应当通过"; fi
    else
        if [ $rc -ne 0 ] && [ "${nf:-0}" != "0" ]; then PASS=$((PASS+1));
        else FAIL=$((FAIL+1)); echo "    ✗ 变异应当被捕获（测试仍全绿 = 空转）"; fi
    fi
}

echo "基线"
run "baseline" "ok"

echo "M1 去掉两处 & 255（返回值通道重新依赖垃圾高位）"
python3 - <<'PY'
p='lib/lf.mo'; s=open(p).read()
s=s.replace('        if (r & 255) == 0 {','        if r == 0 {   # MUT_M1',1)
s=s.replace('    if (r & 255) != 0 {','    if r != 0 {   # MUT_M1',1)
open(p,'w').write(s)
PY
run "M1" "mut"
restore

echo "M2 lf_scan 不做危险指针检查"
python3 - <<'PY'
p='lib/lf.mo'; s=open(p).read()
s=s.replace('        hit = 0;\n        j = 0;','        hit = 0;   # MUT_M2\n        j = 1000000;',1)
open(p,'w').write(s)
PY
run "M2" "mut"
restore

echo "M3 lf_mk 不打包 tag"
python3 - <<'PY'
p='lib/lf.mo'; s=open(p).read()
s=s.replace('    return t * 4294967296 + i;','    return i;   # MUT_M3\n    return t * 4294967296 + i;',1)
open(p,'w').write(s)
PY
run "M3" "mut"
restore
# 🔴 收尾必须重建 bin/moc（与 switchmut.sh 同源）：最后一轮留下的是变异版
#    moc，而还原与它常落在同一秒，make 只看 mtime 会跳过重建 —— 于是脚本
#    跑完后整个项目一直用改坏的编译器跑测试。源码干净 ≠ 产物干净。
rm -f bin/moc
make bin/moc >/dev/null 2>&1

# 收尾核对：源码必须真的回到干净状态（diff 逐字节）
if ! diff -q "$BAK" "$SRC" >/dev/null 2>&1; then
    echo "  ✗ 还原失败：源码与备份不一致"; FAIL=$((FAIL+1))
fi
# 备份保留在 build/ 下不删：下一轮开工可自愈，避免 trap 与 rm 的竞争

echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
