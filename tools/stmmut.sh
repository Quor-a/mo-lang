#!/bin/bash
# stmmut —— STM 的变异验证：五个"改坏"必须各自被 stmtest 抓到
#
# 🔴 与早期脚本最大的不同：**从不改仓库源码**。每次把 lib 拷到独立临时目录，
#    只改那份拷贝 —— 于是"脚本被强杀导致源码停在变异态"这一类失效根本不存在。
#    （本项目在 scopemut / lfmut / sdmseqmut 上各栽过一次。）
#
# 每个变异都必须**直接回到缺陷状态**，而不是"改点东西然后看它失败"：
#   M1 时钟非原子自增        —— 实测丢 6/4000
#   M2 持有锁就跳过版本校验  —— 实测丢 90/4000
#   M3 ptr 按字节写          —— 只改到最低字节，值"差一点点"
#   M4 回滚不做 undo         —— 事务不再原子
#   M5 读不记录读集          —— 读集校验彻底空转
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=/tmp/mostmmut
rm -rf $TMP; mkdir -p $TMP
PASS=0; FAIL=0

prep() {
  local d=$TMP/$1
  rm -rf -- "$d" 2>/dev/null; mkdir -p $d/lib
  cp "$HERE"/lib/*.mo $d/lib/
  cp "$HERE"/examples/stmbench.mo $d/
}

# 用环境变量传替换串，避免 shell 引号把多行与特殊字符搞坏
mutate() {
  OLD="$MOLD" NEW="$MNEW" python3 - "$TMP/$1/lib/stm.mo" <<'PYEOF'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
}

run() { bash "$HERE"/tools/stmtest.sh "$TMP/$1" 2>&1 | tail -1; }

echo "-- 基线 --"
prep base
B=$(run base)
echo "  $B"
case "$B" in
  *"失败 0"*) PASS=$((PASS+1));;
  *) FAIL=$((FAIL+1)); echo "  x 基线就红了，后面的变异无意义";;
esac

do_mut() {
  local id=$2
  prep $1
  MOLD="$3"; MNEW="$4"
  if ! mutate $1 >/dev/null 2>&1; then
    echo "  x $id 锚点没找到 —— 变异没生效，脚本会假报通过"; FAIL=$((FAIL+1)); return
  fi
  local r; r=$(run $1)
  case "$r" in
    *"失败 0"*) echo "  x $id 未被捕获：$r"; FAIL=$((FAIL+1));;
    *) echo "  v $id 被捕获：$r"; PASS=$((PASS+1));;
  esac
}

echo "-- 变异 --"
do_mut m1 "M1 时钟非原子自增" \
"    wv = stm_nextver(tid);" \
"    wv = STM_CLOCK + 1;
    STM_CLOCK = wv;"

do_mut m2 "M2 持锁跳过版本校验" \
"        if (ov / 2) != (STM_RQ[STM_T6] / 2) {
            return 0;
        }" \
"        if (ov / 2) != (ov / 2) {
            return 0;
        }"

do_mut m3 "M3 ptr 按字节写" \
"    lf_store(q, v);" \
"    q[0] = v;"

do_mut m4 "M4 提交时不校验读集" \
"    if stm_validate(tid) == 0 {" \
"    if stm_validate(tid) == 12345 {"

do_mut m5 "M5 读不记录读集" \
"        STM_RN[tid] = STM_RN[tid] + 1;" \
"        STM_RN[tid] = STM_RN[tid] + 0;"

echo "变异验证：捕获 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ] || exit 1
exit 0
