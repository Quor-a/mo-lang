#!/bin/bash
# SDM 序列存储 —— 变异验证
#
# 只跑 17 条断言不能证明断言非空转：条件压根没参与决策时也可能碰巧成立。
# 这里真的去改源码，确认每条关键断言都能变红。
#
# M1 sq_clean_nn 去掉吸附      → 最近邻清洗失效
# M2 双 bank 退化成单 bank      → 清洗记忆与转移记忆合并（叠加污染）
# M3 sq_nearest 循环变量改回 SQI → 链只走 40 步却声称走了 120 步
#
# M3 会死循环，用 timeout 兜住：rc=124 也算「抓到」。
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

SRC=lib/sdmseq.mo
SRC2=lib/sdm.mo
cp -f "$SRC" /tmp/sdmseq.bak
cp -f "$SRC2" /tmp/sdm.bak

# 备份**不能**在还原时删掉 —— 1.102 那次就是这么出的事：
# 第一次还原把备份删了，后面几次还原全是空操作，变异留在源码里，
# 而脚本照样打印全绿。备份只在脚本末尾清一次。
restore() {
  [ -f /tmp/sdmseq.bak ] && cp -f /tmp/sdmseq.bak "$SRC"
  [ -f /tmp/sdm.bak ] && cp -f /tmp/sdm.bak "$SRC2"
  return 0
}
cleanup() {
  rm -f /tmp/sdmseq.bak /tmp/sdm.bak
}
trap restore EXIT

run125() {
  rm -rf /tmp/motm && mkdir -p /tmp/motm
  cp lib/*.mo /tmp/motm/
  cp tests/125_sdmseq.mo /tmp/motm/test.mo
  ( cd /tmp/motm && "$HERE/bin/moc" ) >/dev/null 2>&1 || return 99
  chmod +x /tmp/motm/out.elf 2>/dev/null
  ( cd /tmp/motm && timeout 30 ./out.elf )
}

echo "== 基线 =="
base=$(run125); echo "$base"
restore
if ! echo "$base" | grep -q "failed 0"; then
  echo "基线就不是全绿，变异结果无意义"; exit 1
fi

mut() {
  local name=$1
  restore
  python3 - "$name" <<'PY'
import sys, re
which = sys.argv[1]
if which == "M1":
    p = 'lib/sdmseq.mo'; s = open(p).read()
    old = "fn sq_clean_nn() -> i64 {\n    SQBEST = sq_nearest(SQY);\n    sdm_copy(SQY, sq_item(SQBEST));\n    return 0;\n}"
    new = "fn sq_clean_nn() -> i64 {\n    SQBEST = sq_nearest(SQY);\n    return 0;\n}"
    assert s.count(old) == 1, "M1 锚点未命中"
    open(p, 'w').write(s.replace(old, new))
elif which == "M2":
    p = 'lib/sdm.mo'; s = open(p).read()
    a = "    return SDCNT2[i];"
    b = "    if SDBANK != 0 { SDCNT2[i] = v; }"
    assert s.count(a) == 1 and s.count(b) == 1, "M2 锚点未命中"
    s = s.replace(a, "    return SDCNT[i];")
    s = s.replace(b, "    if SDBANK != 0 { SDCNT[i] = v; }")
    open(p, 'w').write(s)
elif which == "M3":
    p = 'lib/sdmseq.mo'; s = open(p).read()
    old = "    SQNI = 0;\n    while SQNI < SQN {"
    new = "    SQI = 0;\n    while SQI < SQN {"
    assert s.count(old) == 1, "M3 锚点未命中"
    s = s.replace(old, new)
    s = s.replace("            SQBEST = SQNI;", "            SQBEST = SQI;")
    s = s.replace("        SQNI = SQNI + 1;", "        SQI = SQI + 1;")
    open(p, 'w').write(s)
PY
  [ $? -ne 0 ] && { echo "$name 变异未生效"; return 1; }
  out=$(run125)
  if echo "$out" | grep -q "failed 0"; then
    echo "$name  未抓到（仍全绿）"
    return 1
  fi
  echo "$name  抓到："
  echo "$out" | grep -E "^FAIL|ran " | head -4
  return 0
}

ok=0
mut M1 && ok=$((ok + 1))
mut M2 && ok=$((ok + 1))
mut M3 && ok=$((ok + 1))
restore

# 还原核对：备份只删一次，且必须确认变异字符串**不在**源码里 ——
# 1.102 那次就是备份被删、第二次还原失败，变异留在源码里而脚本照样全绿。
if grep -q "SQBEST = sq_nearest(SQY);" lib/sdmseq.mo && \
   grep -q "sdm_copy(SQY, sq_item(SQBEST));" lib/sdmseq.mo && \
   grep -q "return SDCNT2\[i\];" lib/sdm.mo; then
  echo "还原核对 OK"
else
  echo "还原核对失败！"; exit 1
fi

cleanup
echo "变异验证：$ok / 3 被抓到"
[ "$ok" = 3 ]
