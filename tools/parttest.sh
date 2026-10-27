#!/bin/bash
# 分批跑 tests/ —— 全量一次跑会因编译密集让沙盒 502，故切成小批。
#
#   bash tools/parttest.sh <起始序号> <结束序号>   # 单文件用例 tests/*.mo
#   bash tools/parttest.sh dir                     # 多文件用例 tests/*/
#   bash tools/parttest.sh err                     # 编译错误用例 tests/errors/*.mo
#
# 三类加起来就是 tests/run.sh 的全量口径，分开跑只是为了不超时。
# 注意：目录用例必须把 main.mo 改名成 test.mo —— 编译器无参时只找 test.mo，
# 漏了这步会 25 个目录全部报"编译失败"，看着像回归其实是脚本写错。
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CC="$HERE/bin/moc"
MODE=${1:-1}; A=${2:-35}
[ "$MODE" = "dir" ] || [ "$MODE" = "err" ] || { START=$MODE; END=$A; }
pass=0; fail=0

run_one() {
  local name=$1 exp=$2
  ( cd /tmp/mot && "$CC" ) >/dev/null 2>&1 || { echo "FAIL(编译) $name"; fail=$((fail+1)); return; }
  chmod +x /tmp/mot/out.elf 2>/dev/null
  ( cd /tmp/mot && ./out.elf ); got=$?
  if [ "$got" = "$exp" ]; then pass=$((pass+1));
  else echo "FAIL $name 期望 $exp 实得 $got"; fail=$((fail+1)); fi
}

if [ "$MODE" = "dir" ]; then
  for d in "$HERE"/tests/*/; do
    [ "$(basename $d)" = "errors" ] && continue
    [ -f "$d/main.mo" ] || continue
    exp=$(grep -m1 '# expect:' "$d/main.mo" | sed 's/.*expect: *//'); [ -z "$exp" ] && exp=0
    rm -rf /tmp/mot && mkdir -p /tmp/mot && cp "$HERE"/lib/*.mo /tmp/mot/
    cp "$d"*.mo /tmp/mot/ && mv /tmp/mot/main.mo /tmp/mot/test.mo
    run_one "$(basename $d)/" "$exp"
  done
  echo "目录用例: 通过 $pass / 失败 $fail"; [ $fail -eq 0 ]; exit $?
fi

if [ "$MODE" = "err" ]; then
  for f in "$HERE"/tests/errors/*.mo; do
    frag=$(grep -m1 '# expect-error:' "$f" | sed 's/.*expect-error: *//')
    rm -rf /tmp/mot && mkdir -p /tmp/mot && cp "$f" /tmp/mot/test.mo
    out=$( cd /tmp/mot && "$CC" 2>&1 ); rc=$?
    if [ $rc -eq 0 ]; then echo "FAIL $(basename $f) 应报错但编译通过"; fail=$((fail+1));
    elif [ -n "$frag" ] && ! echo "$out" | grep -q "$frag"; then
      echo "FAIL $(basename $f) 报错不含 '$frag'（实得：$out）"; fail=$((fail+1));
    else pass=$((pass+1)); fi
  done
  echo "错误用例: 通过 $pass / 失败 $fail"; [ $fail -eq 0 ]; exit $?
fi

i=0
for f in "$HERE"/tests/*.mo; do
  i=$((i+1)); [ $i -lt $START ] && continue; [ $i -gt $END ] && break
  exp=$(grep -m1 '# expect:' "$f" | sed 's/.*expect: *//'); [ -z "$exp" ] && exp=0
  rm -rf /tmp/mot && mkdir -p /tmp/mot && cp "$HERE"/lib/*.mo /tmp/mot/ 2>/dev/null
  cp "$f" /tmp/mot/test.mo
  run_one "$(basename $f)" "$exp"
done
echo "批 $START-$END: 通过 $pass / 失败 $fail"
[ $fail -eq 0 ]
