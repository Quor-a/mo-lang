#!/bin/bash
# selectmut —— select 的变异验证
#
# 只看"17 项全过"证明不了断言非空转：必须证明**把实现改坏后它会变红**。
#
# 三个变异各对应一条真实的失效模式：
#   M1 公平性退化  —— 随机起点改固定起点 → 先写的 case 独占，后者饥饿
#   M2 漏唤醒      —— 调度器不再唤醒 select 等待者 → 阻塞场景永久挂住
#   M3 重复唤醒    —— 去掉"只有已挂起才入队"的判定 → 运行中的协程被重复入队
#
# 🔴 还原必须逐字节核对（diff），不能只看"没报错"：
#    本项目已两次栽在"备份 / 还原脚本自身静默失效"上。
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
BACKUP=/tmp/selectmut_backup
rm -rf $BACKUP && mkdir -p $BACKUP
cp lib/select.mo lib/csp.mo $BACKUP/

restore() {
  # 脚本末尾会删掉备份目录，而 trap 在那时也会触发 —— 备份不存在时
  # 不能再报"还原失败"（上一版因此打印两行假错误）。
  if [ ! -f "$BACKUP/select.mo" ]; then return 0; fi
  cp $BACKUP/select.mo lib/select.mo
  cp $BACKUP/csp.mo lib/csp.mo
  if ! diff -q $BACKUP/select.mo lib/select.mo >/dev/null; then echo "!! 还原失败 select.mo"; fi
  if ! diff -q $BACKUP/csp.mo lib/csp.mo >/dev/null; then echo "!! 还原失败 csp.mo"; fi
}

# 🔴 必须有 trap：本项目上一次跑这个脚本时被外部打断，源码停在变异状态，
#    下一轮"基线"直接 17/17 全红 —— 而备份目录已被清理，无法还原。
trap restore EXIT INT TERM

run() {
  bash tools/selecttest.sh > /tmp/selectmut_out.txt 2>&1
  echo $?
}

echo "== 基线 =="
BASE_RC=$(run)
tail -1 /tmp/selectmut_out.txt
BASE_PASS=$(grep -c "✓" /tmp/selectmut_out.txt)
if [ "$BASE_RC" != "0" ]; then echo "!! 基线就失败了，后面的变异没有意义"; restore; exit 1; fi

mut() {
  local name="$1" file="$2" from="$3" to="$4"
  python3 - "$file" "$from" "$to" <<'PY'
import sys
p,a,b=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p).read()
if a not in s: print("ANCHOR-NOT-FOUND"); sys.exit(2)
open(p,'w').write(s.replace(a,b,1))
PY
  if [ $? -ne 0 ]; then echo "  ✗ $name 锚点没找到，变异没生效"; return 2; fi
  MRC=$(run)
  MPASS=$(grep -c "✓" /tmp/selectmut_out.txt)
  if [ "$MRC" != "0" ]; then
    echo "  ✓ $name 变异被捕获（通过 $MPASS / 基线 $BASE_PASS）"
    grep "✗" /tmp/selectmut_out.txt | head -3
    restore; return 0
  else
    echo "  ✗ $name 变异**未被捕获** —— 断言空转或锚点不是真正的因果链"
    restore; return 1
  fi
}

R1=0; R2=0; R3=0
mut "M1 公平性退化（固定起点）" lib/select.mo \
    "if n > 1 { start = rand_range(n); }" "if n > 1 { start = 0; }"
R1=$?
mut "M2 漏唤醒（不调 csp_wakesel）" lib/csp.mo \
    "    csp_wakesel(c);
    return 0;" "    return 0;"
R2=$?
# M3 用的是 ST 检查而不是 claim 标记：实测把 claim（CSP_SACT[i]=2）去掉后
# 测试仍全绿 —— 因为 `if CSP_ST[i] == 7` 已经防住了重复入队，claim 只是
# 第二道冗余保险。**变异必须打在真正的因果链上**，所以改成破坏 ST 检查。
mut "M3 重复唤醒（去掉挂起判定）" lib/csp.mo \
    "                if CSP_ST[i] == 7 {" "                if 1 {"
R3=$?

echo "== 收尾核对 =="
if diff -q $BACKUP/select.mo lib/select.mo >/dev/null && diff -q $BACKUP/csp.mo lib/csp.mo >/dev/null; then
  echo "  ✓ 源码已还原（逐字节一致）"
else
  echo "  ✗ 源码未还原！"; R1=1
fi
rm -rf $BACKUP
[ $R1 -eq 0 ] && [ $R2 -eq 0 ] && [ $R3 -eq 0 ]
