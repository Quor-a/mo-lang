#!/bin/bash
# timermut —— 时间轮的变异验证
#
# 只跑一遍 timertest 全绿**证明不了任何事**：
#   定时器"永远不触发"和"触发得正好"，在只看"有没有崩"时都是绿的。
# 所以每个改动都必须造一个对应的坏版本，确认断言真的会变红。
#
# 变异脚本自身的纪律（本项目已栽过三次）：
#   · 备份只删一次，且收尾用 diff 逐字节核对确实还原了
#   · trap 覆盖 EXIT/INT/TERM —— 上次被中断后源码停在变异态，基线全红
#   · 期望值与**基线**比对，不写死"通过 26"（断言数每次新增都会变）
HERE=$(cd "$(dirname "$0")/.." && pwd)
T="$HERE/tools/timertest.sh"
SRC="$HERE/lib/timer.mo"
BK=/tmp/timermutbk
OUT=/tmp/timermutout.txt
rm -rf $BK && mkdir -p $BK
cp "$SRC" "$BK/orig.mo"
restore() { cp "$BK/orig.mo" "$SRC"; }
trap restore EXIT INT TERM

run() { timeout 400 bash "$T" > $OUT 2>&1; echo $?; }
summary() { grep -E "^通过" $OUT | tail -1; }

echo "== 基线 =="
B=$(run)
echo "$(summary)  (rc=$B)"
if [ "$B" != "0" ]; then
  echo "✗ 基线就没过，变异无意义"
  echo "  若上一次是被强杀留下的变异态，用：cp $BK/orig.mo $SRC"
  tail -5 $OUT; exit 1
fi

mut() { # $1=编号 $2=说明 $3=原文 $4=替换
    cp "$BK/orig.mo" "$SRC"
    python3 - "$SRC" "$3" "$4" <<'PY'
import sys
p,a,b=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p).read()
if s.count(a)!=1:
    print("ANCHOR_MISS:%d"%s.count(a)); sys.exit(1)
open(p,'w').write(s.replace(a,b))
PY
    if [ $? -ne 0 ]; then echo "  ✗ $1 锚点未命中，变异未生效"; return 1; fi
    local r; r=$(run)
    if [ "$r" = "0" ]; then echo "  ✗ $1 $2 —— 未被捕获（测试对此无感）"; echo "$(summary)"
    else echo "  ✓ $1 $2 —— 被捕获"; fi
}

echo "== 变异 =="
mut M1 "去掉 L1 分支（长定时也放 L0 → 提前触发）" \
    "    if d >= TM_NSLOT {" \
    "    if 0 {"
mut M2 "槽号用 now 而不是 exp（放进当前槽 → 立刻触发）" \
    "        s = TM_EXP[i] & 63;" \
    "        s = TM_NOWT & 63;"
mut M3 "tm_clock 退回两个独立全局（1 秒分辨率 —— 就是 v1.126 修的那个缺陷）" \
    "var TMC: [2] i64 = 0;

fn tm_clock() -> i64 {
    syscall(228, 1, &TMC, 0, 0, 0, 0);
    return TMC[0] * 1000 + TMC[1] / 1000000;
}" \
    "var TMC_A: i64 = 0;
var TMC_B: i64 = 0;

fn tm_clock() -> i64 {
    syscall(228, 1, &TMC_A, 0, 0, 0, 0);
    return TMC_A * 1000 + TMC_B / 1000000;
}"
mut M4 "tick 数向上取整改成向下取整（50ms → 48ms，提前）" \
    "    ticks = (ms + frac + TM_TICK - 1) / TM_TICK;" \
    "    ticks = (ms + frac) / TM_TICK;"
mut M5 "去掉 tick 相位零头补偿（量化基准退回上一个 tick → 提前最多一个 tick）" \
    "    frac = now - TM_LASTMS;" \
    "    frac = 0;"

restore
# 🔴 收尾必须重建 bin/moc：最后一轮变异留下的是**变异版 moc**，而
#    `cp 备份 $SRC` 与它常常落在同一秒 —— make 只看 mtime，会认为
#    bin/moc 仍比 src/compiler.mo 新而**跳过重建**。
#    于是脚本跑完之后，整个项目一直在用一个被改坏的编译器跑测试：
#    v1.136 的 "empty case: got 0, want 42" 就是这样来的 —— 源码是
#    干净的，bin/moc 却还停在 M5（空 case 不穿透）。
#    **源码干净 ≠ 产物干净**，两个都要还原。
rm -f bin/moc
make bin/moc >/dev/null 2>&1
if diff -q "$BK/orig.mo" "$SRC" >/dev/null; then echo "== 源码已还原（diff 逐字节一致） =="
else echo "✗ 还原失败！源码仍处在变异状态"; exit 1; fi
trap - EXIT INT TERM
# 不删 $BK：一旦被强杀，源码会停在变异态，留一份原始副本供手工恢复
echo "（原始副本保留在 $BK/orig.mo）"
