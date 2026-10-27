#!/bin/bash
# dwmut —— 端到端变异验证：证明 dwmo -L 不是空转
#
# 为什么要这个脚本：
#   "校验通过"有两种可能：真的对，或者根本没检查到。区分它们的唯一
#   办法是**故意把被测的东西弄坏**，看校验是否报红。
#
#   这里弄坏的是编译器本身：把函数定义行登记进行号表时用的行号 +1。
#   于是行号表整体偏移一行 —— 注意，偏移之后 DWARF 内部依然是自洽的：
#   地址单调、边界落在函数内、覆盖率 99%、end_sequence 精确相等。
#   **所有内部断言仍然全绿**，只有拿源码当第三方参照才抓得到。
#
# 两条通道分开验：
#   decl_line 是写进 DIE 的属性，行号表是另一份独立数据。本次变异只动
#   行号表，所以"定义行属性"那几条断言**仍然通过**（这是对的，它们没
#   坏）；必须由 -L 里专查行号表的那几条来抓。这正好说明两条通道都
#   需要各自的检查，缺一条就会漏。
#
# 安全：任何退出路径都会把 src/compiler.mo 还原（trap EXIT）。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/src/compiler.mo"
BAK=/tmp/dwmut_backup.mo
W=/tmp/dwmutbuild

cp "$SRC" "$BAK" || { echo "✗ 备份失败"; exit 1; }
restore() { cp "$BAK" "$SRC"; }
trap restore EXIT

rm -rf "$W" && mkdir -p "$W" || exit 1
cp "$HERE"/lib/*.mo "$W"/ || exit 1
cp "$SRC" "$W"/test.mo || exit 1
cp "$HERE/tools/dwmo.mo" "$W"/dwmo.mo || exit 1

# 0) 编译 dwmo 与"正常版"带调试信息的 moc.elf
( cd "$W" && "$HERE/bin/moc" dwmo.mo -o dwmo.elf ) || { echo "✗ dwmo 编译失败"; exit 1; }
( cd "$W" && "$HERE/bin/moc" test.mo -g moc.elf ) || { echo "✗ moc.elf 编译失败"; exit 1; }

echo "== 基线：正常版必须全绿 =="
"$W/dwmo.elf" "$W/moc.elf" -l -L "$W/test.mo" > "$W/base.txt" 2>&1
brc=$?
tail -3 "$W/base.txt"
if [ "$brc" -ne 0 ]; then
    echo "✗ 基线就没过 —— 先修正常情况，变异验证没有意义"
    exit 1
fi

# 1) 变异：函数定义行登记 +1
python3 - "$SRC" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "dbg_mark_at(fnln);"
if old not in s:
    print("✗ 找不到 dbg_mark_at(fnln); —— 编译器源码结构变了，本脚本要跟着改")
    sys.exit(1)
s = s.replace(old, "dbg_mark_at(fnln + 1);", 1)
open(p, 'w').write(s)
PY
[ $? -ne 0 ] && exit 1

# 2) 用变异后的源码造出新编译器，再用它编译自己（调试信息才是变异版生成的）
cp "$SRC" "$W"/compiler.mo || exit 1
( cd "$W" && "$HERE/bin/moc" compiler.mo -o moc_mut ) || { echo "✗ 变异编译器编译失败"; exit 1; }
cp "$SRC" "$W"/test.mo || exit 1
( cd "$W" && ./moc_mut test.mo -g mut.elf ) || { echo "✗ 变异体编译失败"; exit 1; }

# 3) 变异体必须报红
echo "== 变异版：必须报红 =="
"$W/dwmo.elf" "$W/mut.elf" -l -L "$W/test.mo" > "$W/mut.txt" 2>&1
mrc=$?
grep -E "^  BAD " "$W/mut.txt"
tail -3 "$W/mut.txt"

if [ "$mrc" -eq 0 ]; then
    echo "✗ 变异版竟然通过了 —— -L 是空转，校验没有真的检查到行号表"
    exit 1
fi

# 4) 关键：必须有一条**专查行号表**的断言报红（decl_line 那条通道没坏，
#    它那几条断言理应仍然 OK —— 如果连它们也红了，说明脚本变异过头了）
if ! grep -q "函数入口的行号记录里确实写着这个函数" "$W/mut.txt"; then
    echo "✗ 没有抓到行号表通道的问题 —— 覆盖面不够"
    exit 1
fi
echo "✓ 变异被抓到（-L 非空转）"
exit 0
