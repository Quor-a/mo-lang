#!/bin/bash
# modtypetest —— modb「类型感知打印」的验证
#
# 为什么单独一个脚本：
#   p 此前一律按 8 字节整数打印 —— byte/bool/f64 全都是"看起来有值"，
#   结构体只能看到第一个字段，静态完全看不出错。类型信息本来就在
#   DWARF 里，只是没用上。本脚本逐项验证它真的被用上了。
#
# 验证策略：
#   1. 正向：结构体（含嵌套与 byte 字段）、数组、bool、byte、f64 各自
#      按类型打印，值必须与源码写入的一致
#   2. 反向：作用域外的变量必须"找不到"；不存在的成员必须报错
#      —— 否则"打印正确"可能只是无条件通过
#   3. 变异：把 bool 的格式化判定改坏，测试必须失败（否则是空转）
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
chk() {
    if [ "$2" = "1" ]; then PASS=$((PASS+1)); echo "  OK   $1";
    else FAIL=$((FAIL+1)); echo "  BAD  $1"; fi
}
has() { if grep -q -- "$1" <<<"$OUT"; then echo 1; else echo 0; fi; }

build_modb() {
    rm -rf /tmp/modtybuild && mkdir -p /tmp/modtybuild
    cp "$HERE"/lib/*.mo /tmp/modtybuild/ || return 1
    cp "$HERE"/tools/modb.mo /tmp/modtybuild/test.mo || return 1
    ( cd /tmp/modtybuild && "$HERE/bin/moc" ) || return 1
    cp /tmp/modtybuild/out.elf "$HERE/bin/modb" && chmod +x "$HERE/bin/modb"
}

echo "== 编译 modb =="
if build_modb >/dev/null 2>&1; then echo "  OK   编译"; PASS=$((PASS+1)); else echo "  BAD  编译"; FAIL=$((FAIL+1)); exit 1; fi

echo "== 编译被测程序（带 -g）=="
rm -rf /tmp/modtyt && mkdir -p /tmp/modtyt
cp "$HERE"/lib/*.mo /tmp/modtyt/ || exit 1
cp "$HERE"/examples/dbgtype.mo /tmp/modtyt/test.mo || exit 1
( cd /tmp/modtyt && "$HERE/bin/moc" test.mo -g out.elf ) || { echo "  BAD  被测程序编译"; exit 1; }

printf 'b 33\nr\np p1\np p1.y\np p1.bv\np p1.in.v\np arr\np arr[2]\np flag\np bv\np fv\np s\np nosuch\np p1.nosuch\nq\n' >/tmp/modtyt/c.txt
OUT=$("$HERE/bin/modb" /tmp/modtyt/out.elf -x /tmp/modtyt/c.txt 2>&1)

echo "== 正向：按类型打印 =="
chk "结构体展开 {x = 3, y = 4, bv = 7, in = {v = 5}}" "$(has 'p1 = {x = 3, y = 4, bv = 7, in = {v = 5}}')"
chk "成员 p1.y = 4"            "$(has 'p1.y = 4')"
chk "byte 成员 p1.bv = 7"      "$(has 'p1.bv = 7')"
chk "嵌套成员 p1.in.v = 5"     "$(has 'p1.in.v = 5')"
chk "数组 [10, 20, 30, 40]"    "$(has 'arr = \[10, 20, 30, 40\]')"
chk "下标 arr[2] = 30"         "$(has 'arr\[2\] = 30')"
chk "bool 打印 true"           "$(has 'flag = true')"
chk "byte 打印 7"              "$(has 'bv = 7')"
chk "f64 打印 1.5000"          "$(has 'fv = 1.5000')"
chk "i64 打印 42"              "$(has 's = 42')"

echo "== 反向：必须报错，不能静默 =="
chk "不存在的变量要报找不到"    "$(has 'nosuch = modb: 当前作用域找不到变量')"
chk "不存在的成员要报错"        "$(has 'p1.nosuch = modb: 没有这个成员')"

echo "== 变异：bool 判定改坏必须被抓到 =="
cp "$HERE"/tools/modb.mo /tmp/modty_backup.mo
sed -i 's/die_nm_eq(d, "bool") == 1/die_nm_eq(d, "zzz") == 1/' "$HERE"/tools/modb.mo
if build_modb >/dev/null 2>&1; then
    OUT2=$("$HERE/bin/modb" /tmp/modtyt/out.elf -x /tmp/modtyt/c.txt 2>&1)
    if grep -q 'flag = true' <<<"$OUT2"; then G=0; else G=1; fi
    chk "变异后 bool 不再打印 true" "$G"
else
    chk "变异后仍能编译" "0"
fi
cp /tmp/modty_backup.mo "$HERE"/tools/modb.mo
build_modb >/dev/null 2>&1

echo
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = 0 ]
