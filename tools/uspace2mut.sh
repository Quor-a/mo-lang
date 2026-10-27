#!/bin/bash
# uspace2mut —— 证明 uspace2 的判据**真的能区分**「真做了」与「碰巧」
#
#   make uspace2mut
#
# 做法：把 examples/uspace2.mo 里七条因果链分别改坏，每次重新构建并跑，
# 期望对应断言变红。只要有一个变异「改坏了却全绿」，那组断言就是空转的。
#
# 为什么用 x86-64 端而不是两端都跑
# --------------------------------
# ARM64 端要过 Unicorn 模拟，七个变异 × 完整两端会拖到十几分钟并撞沙盒超时。
# x86-64 端是真跑、构建快，而关键断言（拓扑序 / 环 / 签名 / 往返）两端都有，
# 所以这里用 x86-64 端做快速判据，完整两端对照由 uspace2test.sh 负责。
#
# 判据不是「测试通过」，而是「改坏之后必须失败」
# ----------------------------------------------
# 判据脚本自身的失效是本项目反复出现的第三类问题，所以：
#   · 备份放在项目目录 build/ 下（/tmp 会被清空，v1.128 记过）
#   · 开工前 preflight：备份必须含全部锚点，否则说明源码本来就是脏的
#   · 收尾一律还原并复检，不留变异态
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=examples/uspace2.mo
BAK=build/uspace2.mo.bak
mkdir -p build
cp $SRC $BAK

restore(){ cp $BAK $SRC; }
trap restore EXIT

# ---------------- preflight ----------------
python3 - "$BAK" <<'PY'
import sys
s=open(sys.argv[1]).read()
need=["MARK[i] = 1;","CY = 1; return 0 - 2;","vcmp(ver, &PVER + pdv(i)) != 1",
      "if pcheck(i) != 0","fn sv_clear() -> i64 {","if sg != PSIG[i]","ORD[ON] = i;"]
miss=[n for n in need if n not in s]
if miss:
    print("preflight: 备份缺锚点 %s —— 源码可能是脏的，先还原再跑" % miss)
    sys.exit(1)
print("preflight: 7 个锚点齐全")
PY
[ $? -ne 0 ] && { echo "uspace2mut: preflight 失败"; exit 2; }

run_one(){
  rm -f /tmp/mo_u2m.x86 /tmp/mo_u2m.log
  rm -rf /mo
  ARCH=x86_64 bash tools/android_native.sh $SRC /tmp/mo_u2m.x86 >/dev/null 2>&1
  if [ ! -f /tmp/mo_u2m.x86 ]; then echo "BUILD-FAIL"; return; fi
  timeout 120 /tmp/mo_u2m.x86 > /tmp/mo_u2m.log 2>&1
  local bad=0
  grep -q "\[order\] = liba,libb,app" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[cycle\] = -2"     /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[downgrade\] = -8" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[still run\] = 45" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[tampered\] = -12" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[after clear files\] = 0" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[bad stream\] = -12" /tmp/mo_u2m.log || bad=$((bad+1))
  grep -q "\[app survives\] = 45" /tmp/mo_u2m.log || bad=$((bad+1))
  rm -rf /mo
  echo $bad
}

apply(){ python3 - "$SRC" "$1" "$2" "$3" "$4" <<'PY'
import sys
p,a,b,c,d=sys.argv[1:6]
s=open(p).read()
pairs=[(a,b)]
if c: pairs.append((c,d))
for old,new in pairs:
    n=s.count(old)
    if n!=1:
        print("apply: 锚点出现 %d 次（应为 1）: %r" % (n, old[:50])); sys.exit(1)
    s=s.replace(old,new)
open(p,'w').write(s)
print("applied")
PY
}

muts=0; caught=0
run_mut(){
  local name="$1"; local a="$2"; local b="$3"; local c="$4"; local d="$5"
  restore
  R=$(apply "$a" "$b" "$c" "$d")
  if [ "$R" != "applied" ]; then echo "✗ $name 变异未生效（锚点不唯一）"; return; fi
  N=$(run_one)
  muts=$((muts+1))
  if [ "$N" = "BUILD-FAIL" ]; then echo "✗ $name 构建失败（变异过于粗暴，不算捕获）"; return; fi
  if [ "$N" -gt 0 ]; then
    echo "✓ $name 被捕获（$N 项变红）"; caught=$((caught+1))
  else
    echo "✗ $name **未被捕获** —— 这组断言是空转的"
  fi
  restore
}

echo "uspace2mut:"

# M1 拓扑序改前序：依赖会排在宿主之后，装包时依赖还没装
run_mut "M1 拓扑改前序" \
  "    MARK[i] = 1;
    dep_split(&PDEP + pdp(i));" \
  "    MARK[i] = 1;
    ORD[ON] = i;
    ON = ON + 1;
    dep_split(&PDEP + pdp(i));" \
  "    MARK[i] = 2;
    ORD[ON] = i;
    ON = ON + 1;
    return 0;" \
  "    MARK[i] = 2;
    return 0;"

# M2 环检测不置标志：dfs 照样返回，resolve 却以为没环
run_mut "M2 环检测不置 CY" \
  "if MARK[i] == 1 { CY = 1; return 0 - 2; }" \
  "if MARK[i] == 1 { return 0 - 2; }" "" ""

# M3 升级不比较版本：降级被静默接受
run_mut "M3 升级不比版本" \
  "if vcmp(ver, &PVER + pdv(i)) != 1 { return 0 - 8; }" \
  "if vcmp(ver, &PVER + pdv(i)) != 9 { return 0 - 8; }" "" ""

# M4 执行前不验签：篡改过的包照跑
run_mut "M4 执行前不验签" \
  "if pcheck(i) != 0 { return 0 - 12; }" \
  "if pcheck(i) != 0 { return 0 - 99; }" "" ""

# M5 清空失效：往返测的是没清干净的残留
run_mut "M5 sv_clear 失效" \
  "fn sv_clear() -> i64 {
    let i: i64 = 0;" \
  "fn sv_clear() -> i64 {
    return 0;
    let i: i64 = 0;" "" ""

# M6 unpack 不验签：坏包直接装进去
run_mut "M6 unpack 不验签" \
  "if sg != PSIG[i] {" \
  "if sg != sg {" "" ""

# M7 验签失败不还原：坏包进来把好包一起弄丢
run_mut "M7 验签失败不还原" \
  "        if had >= 0 {
            scopy(&PNAME + pnm(i), &BKN);" \
  "        if had < 0 {
            scopy(&PNAME + pnm(i), &BKN);" "" ""

restore
echo "uspace2mut: $caught/$muts 被捕获"
if [ "$caught" = "$muts" ]; then echo "uspace2mut: PASS"; exit 0; fi
echo "uspace2mut: FAIL"; exit 1
