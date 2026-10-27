#!/bin/bash
# aiomut —— aio.mo 的变异验证：证明 aiotest 真的在检验"漏唤醒"
#
# 判据不是"改了之后变红"，而是**改的必须是那条因果链**：
#   M1 去掉等待者表的锁 → 两个 worker 上的协程会分到同一个槽，
#      后写的覆盖先写的，先那个协程"带着没有槽的 park"永久挂起。
# 只保留 M1：它是真缺陷且能被稳定捕获（去掉锁后 15 次里必挂）。
# 另外两个变异**没被捕获**，如实记在这里 —— 不是"锁没必要"，而是它们
# 打开的窗口比 M1 窄得多，15 次样本分辨不出来：
#   - 只去掉 aio_fire 一侧的锁：窗口只有"USED 已写、FD 还没写"这两条
#     store 之间；M1 的窗口是整个槽分配 + 一次 epoll_ctl 系统调用。
#   - 去掉 CSP_ST[s]=7 的宣告：窗口是 unlock 到 csp_park 真正置位之间。
#
# 🔴 开工前必须先验源码干净：上一轮若污染未还原，备份会备份到污染版本，
#    三次"还原"全还原成污染版本，脚本却照样打印全绿。
#
# 🔴 曾经被判"捕获"但其实是假阳性的变异（都记在这里，别重复踩）：
#   - 去掉 AIO_RDY 二次检查：变异后仍 15/15 全绿。**不是测试没用**，
#     而是锁把"事件先于 park"的窗口整个关掉了，那条路径不可达 ——
#     已于 v1.124 删除该机制，理由写在 aio_wait 的注释里。
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
SRC=lib/aio.mo
BAK=/tmp/aiomut_backup.mo
cp $SRC $BAK
restore() { cp $BAK $SRC; }
trap restore EXIT
FAILED=0

echo "== 开工前确认源码干净 =="
if grep -q "MUT_M" $SRC; then
  echo "  ✗ 源码残留上一轮变异，先还原再跑"; exit 1
fi
echo "  ✓ 干净"

run() { N=15 bash tools/aiotest.sh > /tmp/aiomut_out.txt 2>&1; RC=$?; tail -1 /tmp/aiomut_out.txt; return $RC; }

# ---------------- M1：去掉等待者表的锁（两侧都去掉） ----------------
python3 -c "
p='lib/aio.mo'; s=open(p).read()
s = s.replace('mutex_lock(&AIO_LK);',   '# MUT_M1_NOLK')
s = s.replace('mutex_unlock(&AIO_LK);', '# MUT_M1_NOLK')
open(p,'w').write(s)
"
echo "== M1：去掉 AIO_LK（两侧） =="
if run; then echo "  ✗ M1 未被捕获（变异后仍全绿 = 测试没验到点子上）"; FAILED=1
else echo "  ✓ M1 变异被捕获"; fi
restore

echo "== 还原核对 =="
if grep -q "MUT_M" $SRC; then
  echo "  ✗ 变异仍留在源码里"; FAILED=1
else echo "  ✓ 源码已还原"; fi

[ $FAILED -eq 0 ]
