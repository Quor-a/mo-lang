#!/bin/bash
# dwmotest —— 墨语言版 DWARF 校验器（tools/dwmo.mo）的验证
#
# 为什么单独一个脚本：
#   dwvar.py 是 Python 版，靠 readelf + objdump 干同一件事。墨语言版
#   自己解析 ELF/DWARF/机器码，不借任何外部工具。两份实现跑**同一份
#   源码**生成的 elf，两份都必须通过 —— 任何一方挂掉都说明另一方的
#   结论不可信。
#
# 为什么必须在 /tmp 下编译：
#   moc 的 import 解析依赖 cwd，直接编 tools/dwmo.mo 会找不到 lib/。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/dwmobuild
rm -rf "$W" && mkdir -p "$W" || exit 1
cp "$HERE"/lib/*.mo "$W"/ || exit 1

# ---- 1. 编译被测程序（与 dwvar.py 用同一份源码）----
cat > "$W/test.mo" <<'EOF'
import "io.mo";

struct Point { x: i64; y: i64; }

var TOTAL: i64 = 0;
var LIMIT: i64 = 100;

fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn addup(a: i64, b: i64) -> i64 {
    let t: i64 = a;
    let fl: f64 = 1.5;
    let bl: bool = true;
    let sp: ptr = "hi";
    let bf: [4] i64 = 0;
    let p: Point;
    return t + b;
}

fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 10 {
        s = s + fib(i);
        i = i + 1;
    }
    return s + addup(1, 2);
}
EOF
( cd "$W" && "$HERE/bin/moc" test.mo -g test.elf ) || {
    echo "✗ 被测程序编译失败"; exit 1; }

# ---- 2. 编译墨语言版校验器 ----
cp "$HERE"/tools/dwmo.mo "$W"/dwmo.mo || exit 1
( cd "$W" && "$HERE/bin/moc" dwmo.mo -o dwmo.elf ) || {
    echo "✗ dwmo.mo 编译失败"; exit 1; }
cp "$W/dwmo.elf" "$HERE/bin/dwmo" && chmod +x "$HERE/bin/dwmo"

echo "== 墨语言版 dwmo（不调 readelf / objdump）=="
"$HERE/bin/dwmo" "$W/test.elf"
rc=$?
echo "== 墨语言版 dwmo -l（行号表）=="
# 🔴 不能用 `| tail` 再取 $? —— 那拿到的是 tail 的退出码，
#    dwmo 失败也会被判成通过（管道吞退出码）。先落盘再取。
"$HERE/bin/dwmo" "$W/test.elf" -l > "$W/lout.txt" 2>&1
lrc=$?
tail -12 "$W/lout.txt"
if [ "$lrc" -ne 0 ]; then rc=1; fi
echo "== Python 版 dwvar.py（对照）=="
python3 "$HERE/tools/dwvar.py" 2>&1 | tail -1
exit $rc
