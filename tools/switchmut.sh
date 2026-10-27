#!/bin/bash
# switch 的变异验证
#
# 133_switch.mo 的 24 项断言全绿**证明不了** parse_switch 是对的 ——
# 判据必须能区分「生成正确」和「恰好没碰到」。下面每个变异都把
# 编译器改回一种**具体错法**，它必须让测试变红，否则说明断言空转。
#
# ⚠ 本脚本会反复 make bin/moc（约 6 次），耗时数分钟。
# ⚠ 每个 run_one 都套 timeout：M2 会让测试**段错误**，M1 会让它静默
#   走 default —— 两者都不会自己退出，没有 timeout 会把 CI 挂住。
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SRC=src/compiler.mo
BAK=build/switchmut.bak
mkdir -p build
# 备份取自 **src/mo/ 分片拼接**而不是 cp $SRC ——
# 与 formut.sh 同源的教训：第一次被强杀后 SRC 停在变异态，
# `cp $SRC $BAK` 会把污染版当成基线，下一轮一开工就"基线没通过"。
# 分片是权威源（sync-check 拿它比对 compiler.mo），从这里重建一定干净。
cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
    src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
    src/mo/compiler_part5.mo > "$BAK"
restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

# 返回 0=通过 1=测试失败 2=编译失败/超时
run_one() {
  # 🔴 必须强制重建：make 只看 mtime，`cp $BAK $SRC` 与上次构建可能落在
  # 同一秒，make 会认为 bin/moc 仍更新而**跳过重建** —— 于是每个变异
  # 测的都是**上一个**变异编译出来的 moc，结果整体错位一格。
  rm -f bin/moc
  make bin/moc >/dev/null 2>&1 || return 2
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp lib/*.mo /tmp/mot/ 2>/dev/null
  cp tests/133_switch.mo /tmp/mot/test.mo
  ( cd /tmp/mot && timeout 30 "$ROOT/bin/moc" ) >/dev/null 2>&1 || return 2
  chmod +x /tmp/mot/out.elf 2>/dev/null
  out=$( cd /tmp/mot && timeout 20 ./out.elf 2>&1 ); rc=$?
  if [ "$rc" != 0 ]; then echo "$out"; return 1; fi
  echo "$out" | grep -q "failed 0" || { echo "$out"; return 1; }
  return 0
}

apply() { # $1=锚点(唯一) $2=替换
  python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(a) == 1, f"锚点不唯一或不存在({s.count(a)}): {a}"
open(p, 'w').write(s.replace(a, b))
PY
}

pass=0; fail=0
check() { # $1=名字 $2=锚点 $3=替换
  restore
  if ! apply "$2" "$3"; then echo "✗ $1 锚点问题"; fail=$((fail+1)); return; fi
  if diff -q "$BAK" "$SRC" >/dev/null; then echo "✗ $1 变异没生效"; fail=$((fail+1)); return; fi
  o=$(run_one); rc=$?
  if [ "$rc" != 0 ]; then
    echo "✓ $1 变异被捕获 (rc=$rc) ${o:0:60}"
    pass=$((pass+1))
  else
    echo "✗ $1 变异未被捕获 —— 断言空转"
    fail=$((fail+1))
  fi
}

echo "== 基线（源码必须干净）=="
o=$(run_one); rc=$?
echo "基线 rc=$rc ${o:0:80}"
[ "$rc" = 0 ] || { echo "✗ 基线就没通过，先修再谈变异"; exit 1; }

# M1：跳转表的 case 槽不回填 —— 表项全部停留在 default。
#   语义完全合理、编译通过、运行不崩，只是**命中任何 case 都走 default**。
#   只有具体数值能抓住它。
check "M1 跳转表 case 槽不回填（全部走 default）" \
  "        k = 0;
        while k < n {
            let slot: i64" "        k = 0;
        while k < 0 {
            let slot: i64"

# M2：绝对地址漏掉 ELF 头的 176 字节。这就是本轮真实踩到的那个坑 ——
#   跳转表路径无一例外段错误，而比较链路径全对（相对跳转不依赖基址）。
check "M2 表地址漏掉 +176" \
  "let cb: i64 = 4194304 + 176;" "let cb: i64 = 4194304;"

# M3：case 末尾不补 jmp end —— 退回 C 的隐式穿透。
check "M3 case 穿透（不补 jmp end）" \
  "if fell == 0 { emit_jmp(end); }" "if fell == 0 { fell = 0; }"

# M4：continue 取栈顶而不跳过 switch 层 —— 会拿到 switch 压的 cnt=-1。
check "M4 continue 不跳过 switch 层" \
  "        if c >= 0 {
            let s: i64" "        if 1 == 1 {
            let s: i64"

# M5：空 case 不再视为穿透 —— `case 1: case 2: body` 里 case 1 会直接跳出。
check "M5 空 case 不穿透" \
  "if any == 0 { fell = 1; }" "if any == 0 { fell = 0; }"

restore
# 🔴 收尾必须重建 bin/moc：最后一轮变异留下的是**变异版 moc**，而
#    `cp 备份 $SRC` 与它常常落在同一秒 —— make 只看 mtime，会认为
#    bin/moc 仍比 src/compiler.mo 新而**跳过重建**。
#    于是脚本跑完之后，整个项目一直在用一个被改坏的编译器跑测试：
#    v1.136 的 "empty case: got 0, want 42" 就是这样来的 —— 源码是
#    干净的，bin/moc 却还停在 M5（空 case 不穿透）。
#    **源码干净 ≠ 产物干净**，两个都要还原。
rm -f bin/moc
make bin/moc >/dev/null 2>&1
echo "== 结果：捕获 $pass / 失败 $fail =="
[ "$fail" = 0 ]
