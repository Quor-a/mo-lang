#!/bin/bash
# adopmut —— autodiff「漏加载 op」缺陷的变异验证
#
# 背景（v1.160）：lib/autodiff.mo 有三个遍历 tape 的函数把 op 声明为 0
#   后在循环里从不加载，于是 op 恒 0：
#     ad_backward → 所有算子分支不命中 → 梯度全 0（静默）
#     ad_forward  → ad_known_op(0)==0  → return -1
#     ad_audit    → 每条 tape 都误报「未知算子」
#   全库 8 个函数里有 5 个写对了（ad_infer_nin / ad_init_note_all /
#   ad_asd_detect / ad_replay_core / ad_rev_step），漏的正是这三个。
#
# 本脚本逐个把修复加回去的那行改回 op = 0，测试必须变红。
# 只改库不改进编译器，所以不需要重建 moc。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=lib/autodiff.mo
BAK=build/adopmut.bak
W=/tmp/moadop

TESTS="77_autodiff 78_matgrad 79_convgrad 80_nnad_parity 99_gradaudit 104_init_audit 107_fdcheck 108_asd"

cp $SRC $BAK
FUNCS="ad_backward ad_audit ad_forward"
overall=0

run_tests() {
  local red=0
  rm -rf $W; mkdir -p $W/lib
  cp $ROOT/lib/*.mo $W/lib/
  for t in $TESTS; do
    rm -rf $W/t; mkdir -p $W/t
    cp $ROOT/lib/*.mo $W/t/
    cp $ROOT/tests/$t.mo $W/t/test.mo
    ( cd $W/t && timeout 120 $ROOT/bin/moc test.mo out.elf >/dev/null 2>&1 \
      && timeout 120 ./out.elf >/dev/null 2>&1; echo $? > $W/rc )
    rc=$(cat $W/rc)
    exp=$(grep -m1 '# expect:' $ROOT/tests/$t.mo | sed 's/.*expect: *//')
    [ -z "$exp" ] && exp=0
    if [ "$rc" != "$exp" ]; then red=$((red+1)); fi
  done
  echo $red
}

echo "基线（未变异）："
base=$(run_tests)
echo "  红 = $base / $(echo $TESTS | wc -w)"
if [ "$base" != "0" ]; then echo "  ✗ 基线就有红项，先修好再谈变异"; cp $BAK $SRC; exit 1; fi
echo "  ✓ 基线全绿"

for fn in $FUNCS; do
  python3 - "$SRC" "$fn" <<'PY'
import re,sys
p,fn=sys.argv[1],sys.argv[2]
lines=open(p).read().split('\n')
fns=[]
for i,l in enumerate(lines):
    m=re.match(r'^fn\s+(\w+)',l)
    if m: fns.append((i,m.group(1)))
b=None
for idx,(ln,name) in enumerate(fns):
    if name==fn:
        b=(ln, fns[idx+1][0] if idx+1<len(fns) else len(lines))
        break
s,e=b
done=False
for i in range(s,e):
    if 'op = load64(&AD_TOP + t * 8);' in lines[i]:
        lines[i]=lines[i].replace('op = load64(&AD_TOP + t * 8);','op = 0;')
        done=True
        break
assert done, f"{fn} 里没找到 op 加载行（锚点失效）"
open(p,'w').write('\n'.join(lines))
PY
  if [ $? -ne 0 ]; then echo "M($fn) 锚点失效 —— 变异未生效"; overall=1; cp $BAK $SRC; continue; fi
  red=$(run_tests)
  if [ "$red" -gt 0 ]; then
    echo "M($fn 的 op 加载改回 op=0)：✓ 捕获，$red 项变红"
  else
    echo "M($fn 的 op 加载改回 op=0)：✗ 未捕获（0 项变红）"
    overall=1
  fi
  cp $BAK $SRC
done

# 收尾必须强制还原并复检
cp $BAK $SRC
chk=$(grep -c 'op = load64(&AD_TOP + t \* 8);' $SRC)
echo "还原后 op 加载行数 = $chk（应为 4）"
if [ "$chk" != "4" ]; then echo "✗ 还原失败"; exit 1; fi

if [ $overall -eq 0 ]; then echo "adopmut: OK（三处修复均有变异守护）"; else echo "adopmut: 有变异未被捕获"; exit 1; fi
