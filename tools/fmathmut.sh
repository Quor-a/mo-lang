#!/usr/bin/env bash
# fmathmut —— fmath 范围规约的**变异验证**
#
# 为什么必须有它：只看"fmathrange 全绿"证明不了判据非空转。
# 判据可能根本没在检查（比如阈值写成 1e9），也可能被"误差恰好都小"蒙混。
#
# M1：把 pio2_hi/lo 换回**完整 53 位**的 π/2 最近双精度值
#     （这正是 1.114 抓到的那个 bug：k·(π/2) 不精确 → 2^21 时 4.9e7 ulp）
#     期望：fmathrange 变红。若仍绿，说明判据没在盯归约。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/lib/fmath.mo"
BAK=/tmp/fmathmut_backup.mo
OK=0; BAD=0

# 开工前先验源码是**干净的**：否则备份到的是污染版本，
# 三次"还原"全还原成污染版，脚本却照样打印全绿（1.111 / 1.102 都栽过）。
#
# 🔴 匹配必须带 `return ffrombits(` 前缀：fmath.mo 的**注释里也写着**
#    `0x3ff921fb54442d18`（讲这个 bug 的来历），只 grep 十六进制串会
#    永远"检出污染"，于是还原检查恒失败 —— 脚本自己的静默失效。
GOOD="return ffrombits(0x3ff921fb54000000)"
EVIL="return ffrombits(0x3ff921fb54442d18)"
if ! grep -q "$GOOD" "$SRC"; then
    echo "✗ 源码不是干净的 1.114 版（缺 pio2_hi 新常量）—— 先还原再跑"
    exit 1
fi
cp "$SRC" "$BAK"

restore() {
    cp "$BAK" "$SRC"
    # 核对：变异必须确实不在**代码**里，否则"还原"是空操作
    if grep -q "$EVIL" "$SRC"; then
        echo "✗ 还原失败：变异仍留在源码里"; exit 1
    fi
}
trap restore EXIT

echo "── 基线（应为绿）──"
if bash "$ROOT/tools/fmathrange.sh" >/tmp/fmathmut_base.log 2>&1; then
    echo "✓ 基线通过"; OK=$((OK+1))
else
    echo "✗ 基线就红了 —— 先修好再谈变异"; BAD=$((BAD+1)); exit 1
fi

echo
echo "── M1：π/2 换回完整 53 位最近双精度值（1.114 抓到的 bug）──"
sed -i 's/ffrombits(0x3ff921fb54000000)/ffrombits(0x3ff921fb54442d18)/;
        s/ffrombits(0x3e110b4611a62633)/ffrombits(0x3c91a62633145c07)/' "$SRC"
if ! grep -q "$EVIL" "$SRC"; then
    echo "✗ 变异没打进去 —— sed 没匹配上，脚本在自欺欺人"; BAD=$((BAD+1)); exit 1
fi
if bash "$ROOT/tools/fmathrange.sh" >/tmp/fmathmut_m1.log 2>&1; then
    echo "✗ 变异后仍然绿 —— fmathrange 的判据没在盯范围规约"; BAD=$((BAD+1))
else
    echo "✓ 被捕获："; grep "^  2\^" /tmp/fmathmut_m1.log | head -8
    OK=$((OK+1))
fi

restore
echo
echo "fmathmut: 通过 $OK / 失败 $BAD"
[ $BAD -eq 0 ]
