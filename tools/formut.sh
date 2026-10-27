#!/bin/bash
# for 循环的变异验证
#
# 132_for.mo 的 14 项断言全绿**证明不了** parse_for 是对的 ——
# 判据必须能区分「布局正确」和「恰好没碰到」。下面每个变异都把
# parse_for 改回一种**具体错法**，它必须让测试变红，否则说明断言空转。
#
# ⚠ 本脚本会反复 make bin/moc（约 6 次），耗时数分钟。
# ⚠ M1/M2 会让测试**死循环**，所以每条都套 timeout —— 没有它，
#    "变异被捕获"这件事本身会把 CI 挂住。
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SRC=src/compiler.mo
BAK=build/formut.bak
mkdir -p build
# 备份取自 **src/mo/ 分片拼接**而不是 cp $SRC ——
# 第一次跑本脚本时被强杀，SRC 停在 M5 变异态，而 `cp $SRC $BAK`
# 把污染版当成了基线，于是下一轮一开工就"基线没通过"。
# 分片是权威源（sync-check 就是拿它比对 compiler.mo 的），
# 即使 SRC 被污染，从这里重建也一定干净。
cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
    src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
    src/mo/compiler_part5.mo > "$BAK"
restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

# 返回 0=通过 1=测试失败 2=编译失败/超时
run_one() {
  # 🔴 必须强制重建：make 只看 mtime，而 `cp $BAK $SRC` 与上一次构建的
  # 间隔可能落在同一秒，make 会认为 bin/moc 仍比 compiler.mo 新而**跳过
  # 重建** —— 于是每个变异测的都是**上一个**变异编译出来的 moc。
  # 症状极具误导性：同一组变异两轮跑出不同结论（M1 这轮"未被捕获"、
  # 上轮"被捕获"），看起来像断言空转，实际是结果整体错位了一格。
  rm -f bin/moc
  make bin/moc >/dev/null 2>&1 || return 2
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp lib/*.mo /tmp/mot/ 2>/dev/null
  cp tests/132_for.mo /tmp/mot/test.mo
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
  if ! diff -q "$BAK" "$SRC" >/dev/null; then :; else echo "✗ $1 变异没生效"; fail=$((fail+1)); return; fi
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

check "M1 continue 跳回循环头（不跳 step）" \
  "loop_push(chk, end, stp);" "loop_push(chk, end, 0 - 1);"
check "M2 break 跳回循环头" \
  "loop_push(chk, end, stp);" "loop_push(chk, chk, stp);"
check "M3 for 不做作用域（多个 for 不能各用 i）" \
  "    sv(K_DEPTH, d);
    # init" "    # init"
# M4 原先是 parse_block(d + 1) -> parse_block(d)，结果**未被捕获**。
# 那不是断言空转：新布局下 step 在 body 之前解析，init 变量此时还没被
# pop，所以两层同层确实无差别（只影响 body 局部变量的存活范围，而
# for 末尾的 sym_pop_scope(d) 无论如何都会清掉它们）。换成去掉 pop ——
# 它才真正对应"多个 for 各用 i"这条性质。
check "M4 for 结束不回收 init 变量（第二个 for 的 i 冲突）" \
  "    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);" "    sv(K_DEPTH, d - 1);"
check "M5 body 后不跳回 step（只跑一轮）" \
  "    emit_jmp(stp);
    place_label(end);" "    place_label(end);"

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
