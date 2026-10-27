#!/usr/bin/env bash
# adaudit —— 对已有神经网络示例跑梯度流审计
#
# 为什么要有这个脚本：
#   1.39 那轮，卷积层收不到任何梯度而结果照样 8/8，是手工诊断才发现的。
#   现在有了 ad_audit()，就让**已有示例**每次都跑一遍 ——
#   新加算子、改初始化、改结构，一旦引入静默断裂，这里会报出来。
#
# 判定：审计问题数 > 0 时**不判失败**，只汇总。
#   因为其中断裂有"合理"与"不合理"两类，需要人看 ——
#   AD 正确性终究是语义问题（arXiv:2007.05282v2），不是能自动判定的。
#   本脚本检查的是：审计能跑起来、三类问题都被覆盖到、数量可复现。
set -u
cd "$(dirname "$0")/.."
MOC=./bin/moc
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ✓ $1"; else FAIL=$((FAIL+1)); echo "  ✗ $1 (得到 $2 期望 $3)"; fi; }

run() {  # $1=示例  $2=期望退出码
  local ex="$1" want="$2" out rc
  out=$(timeout 300 $MOC "$ex" /tmp/_ada.elf 2>&1) || { echo "  ✗ $ex 编译失败"; echo "$out"|head -3; FAIL=$((FAIL+1)); return; }
  out=$(timeout 400 /tmp/_ada.elf 2>&1); rc=$?
  echo "--- $ex"
  echo "$out" | grep -E 'gradient audit' | sed 's/^/    /'
  chk "$ex 退出码" "$rc" "$want"
  # 审计必须真的被执行过
  echo "$out" | grep -q 'gradient audit' && { PASS=$((PASS+1)); echo "  ✓ $ex 审计已执行"; } || { FAIL=$((FAIL+1)); echo "  ✗ $ex 审计未执行"; }
}

echo "=== adaudit: 已有神经网络示例的梯度流审计 ==="
run examples/nnet2.mo    0
run examples/cnn_ad.mo   0
run examples/cnn_shift.mo 0
run examples/adcheck.mo  0
run examples/lrelu_ab.mo 0
run examples/pool_ab.mo  0

echo
echo "=== 审计工具自检（tests/99）==="
timeout 300 $MOC tests/99_gradaudit.mo /tmp/_t99.elf >/dev/null 2>&1
timeout 200 /tmp/_t99.elf > /tmp/_t99.out 2>&1
# A 场景只调用一次 good()，故 PASS 恰好 1 次（第一版写成 2，是断言写错）
chk "正常场景 0 问题"  "$(grep -c 'gradient audit: PASS' /tmp/_t99.out)" "1"
grep -q '从未进入计算图' /tmp/_t99.out && { PASS=$((PASS+1)); echo "  ✓ 抓到'权重不进图'"; } || { FAIL=$((FAIL+1)); echo "  ✗ 未抓到'权重不进图'"; }
grep -q '未知算子' /tmp/_t99.out && { PASS=$((PASS+1)); echo "  ✓ 抓到未知算子"; } || { FAIL=$((FAIL+1)); echo "  ✗ 未抓到未知算子"; }
grep -q '结构性断裂' /tmp/_t99.out && { PASS=$((PASS+1)); echo "  ✓ 抓到结构性断裂"; } || { FAIL=$((FAIL+1)); echo "  ✗ 未抓到结构性断裂"; }

echo
echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ] || exit 1
