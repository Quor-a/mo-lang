#!/bin/bash
# import as 的变异验证：证明 importastest.sh 的断言不是空转。
#
# 每个变异都**直接回到缺陷状态**，不是"改点东西然后看它失败"：
#   M1 不给函数登记命名空间      -> 两个库的同名 helper 又混在一起
#   M2 模块内查不到时不回退全局  -> 库内部用不了 ufun 这类全局符号
#   M3 查找时忽略命名空间        -> 隔离失效，带 as 后裸名又可见
#   M4 import 时不设置当前前缀   -> A/B 的函数全落进全局
#   M5 去掉"重复 import as"检查  -> 空模块 + 静默回退到全局
#
# 两条硬约束（都是本项目栽过的地方）：
#   1) 备份放 build/ 而不是 /tmp —— /tmp 被清过一次，源码停在变异态
#      而备份也没了，只能手工还原。
#   2) 每次都 rm -f bin/moc 强制重建 —— cp 与上次构建落在同一秒时
#      make 认为产物仍是最新的，于是每个变异测的是**上一个**变异的 moc。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p build

P4=src/mo/compiler_part4.mo
P5=src/mo/compiler_part5.mo
B4=build/importas_p4.bak
B5=build/importas_p5.bak

# ---- 变异对：a = 干净版，b = 变异版 ----
A1='    if kind == 0 { store64(heap + O_SPFX + i * 8, gv(K_PFX)); }
    else { store64(heap + O_SPFX + i * 8, 0); }'
B1='    store64(heap + O_SPFX + i * 8, 0);'

A2='    if pf != 0 { return sym_lookup_in(name, 0, 1); }'
B2='    if pf != 0 { return 0 - 1; }'

A3='            if load64(heap + O_SPFX + i * 8) == pf {'
B3='            if 1 == 1 {'

A4='    sv(K_PFX, pfx);'
B4v='    sv(K_PFX, 0);'

A5='        if imp_have(p) == 1 {'
B5='        if imp_have(p) == 2 {'

NAMES=(M1 M2 M3 M4 M5)
FILES=($P4 $P4 $P4 $P5 $P5)
BAKS=($B4 $B4 $B4 $B5 $B5)

# ---- 开工前自愈：源码可能停在上一轮被强杀时的变异态 ----
python3 - <<'PYEOF'
import sys
pairs = [
 ("src/mo/compiler_part4.mo", [
   ('    store64(heap + O_SPFX + i * 8, 0);\n    sv(K_NSYM, i + 1);',
    '    if kind == 0 { store64(heap + O_SPFX + i * 8, gv(K_PFX)); }\n    else { store64(heap + O_SPFX + i * 8, 0); }\n    sv(K_NSYM, i + 1);'),
   ('    if pf != 0 { return 0 - 1; }', '    if pf != 0 { return sym_lookup_in(name, 0, 1); }'),
   ('            if 1 == 1 {', '            if load64(heap + O_SPFX + i * 8) == pf {'),
 ]),
 ("src/mo/compiler_part5.mo", [
   ('    sv(K_PFX, 0);', '    sv(K_PFX, pfx);'),
   ('        if imp_have(p) == 2 {', '        if imp_have(p) == 1 {'),
 ]),
]
n = 0
for path, ps in pairs:
    s = open(path).read()
    for b, a in ps:
        if b in s:
            s = s.replace(b, a)
            n += 1
    open(path, 'w').write(s)
print("HEALED %d" % n)
PYEOF

cp "$P4" "$B4"; cp "$P5" "$B5"

restore() {
  cp "$B4" "$P4" 2>/dev/null
  cp "$B5" "$P5" 2>/dev/null
  make sync >/dev/null 2>&1
  rm -f bin/moc
  make bin/moc >/dev/null 2>&1
}
trap restore EXIT INT TERM

echo "--- 基线 ---"
rm -f bin/moc; make bin/moc >/dev/null 2>&1
bash tools/importastest.sh >/tmp/iat_base.log 2>&1
base=$?
echo "基线退出码 = $base"
[ "$base" = 0 ] || { echo "FAIL 基线就没通过"; exit 1; }

caught=0; total=0
i=0
while [ $i -lt 5 ]; do
  name=${NAMES[$i]}; f=${FILES[$i]}
  total=$((total+1))
  cp "$B4" "$P4"; cp "$B5" "$P5"
  python3 - "$f" "$i" <<'PYEOF'
import sys
path = sys.argv[1]; idx = int(sys.argv[2])
A = [None]*5; B = [None]*5
# 🔴 每个锚点都以 \n 开头：按"行首缩进"精确匹配。
#    第一版没加 \n，M3 的 12 空格是 sym_dup 里 16 空格那一行的**后缀**，
#    于是 replace(...,1) 命中的是 sym_dup 而不是 sym_lookup_in ——
#    变异改到了无关函数上，测试全绿，脚本却打印"未被捕获"。
A[0] = '\n    if kind == 0 { store64(heap + O_SPFX + i * 8, gv(K_PFX)); }\n    else { store64(heap + O_SPFX + i * 8, 0); }'
B[0] = '\n    store64(heap + O_SPFX + i * 8, 0);'
A[1] = '\n    if pf != 0 { return sym_lookup_in(name, 0, 1); }'
B[1] = '\n    if pf != 0 { return 0 - 1; }'
A[2] = '\n            if load64(heap + O_SPFX + i * 8) == pf {'
B[2] = '\n            if 1 == 1 {'
A[3] = '\n    sv(K_PFX, pfx);'
B[3] = '\n    sv(K_PFX, 0);'
A[4] = '\n        if imp_have(p) == 1 {'
B[4] = '\n        if imp_have(p) == 2 {'
s = open(path).read()
if A[idx] not in s:
    print("ANCHOR-MISSING")
    sys.exit(3)
open(path, 'w').write(s.replace(A[idx], B[idx], 1))
print("APPLIED")
PYEOF
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "FAIL $name 变异锚点未找到（脚本失效，不是被测代码的问题）"
  else
    make sync >/dev/null 2>&1
    rm -f bin/moc; make bin/moc >/dev/null 2>&1
    bash tools/importastest.sh >/tmp/iat_m.log 2>&1
    mrc=$?
    if [ "$mrc" != 0 ]; then
      echo "PASS $name 变异被捕获（退出码 $mrc）"
      caught=$((caught+1))
    else
      echo "FAIL $name 未被捕获：改坏了却仍然全绿"
    fi
  fi
  restore
  i=$((i+1))
done

echo "捕获 $caught / $total"
[ "$caught" = "$total" ] || exit 1
exit 0
