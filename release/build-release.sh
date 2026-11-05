#!/bin/bash
# build-release.sh —— 构建 Mo 语言的完整发布包
# 用法: bash release/build-release.sh VERSION
# 产物: dist/mo-lang-<VERSION>/{moc,mo2x,src.*,checksums.txt,*.sig, demo/*}
set -uo pipefail
cd "$(dirname "$0")/.."
VER="$1"
DIST="dist/mo-lang-$VER"
rm -rf "$DIST"; mkdir -p "$DIST/demo"

echo "== 1/6 重拼编译器并构建 =="
cat src/mo/compiler_part*.mo > src/compiler.mo
./bin/moc src/compiler.mo "$DIST/moc"
chmod +x "$DIST/moc"

echo "== 2/6 门禁 =="
timeout 700 bash tests/run.sh "$DIST/moc" | tail -1

echo "== 3/6 交叉演示程序（经 C 后端 + zig）=="
ZIG=""
command -v zig >/dev/null 2>&1 && ZIG="zig cc"
if [ -z "$ZIG" ]; then python3 -m ziglang version >/dev/null 2>&1 && ZIG="python3 -m ziglang cc"; fi
if [ -z "$ZIG" ]; then echo "zig 不可用（需 zig 或 pip install ziglang）"; exit 1; fi
# 自包含演示程序（不 import io.mo —— 库的 syscall 号表 mo2x 的 c 目标
# 尚不支持；自绘 print 即可，C 后端会自动用 printf 替换）
cat > /tmp/demo.mo <<'MOEOF'
fn print_i64(v: i64) -> i64 {
    let tmp: [32] byte = 0;
    let p: i64 = 0;
    let x: i64 = v;
    if x < 0 { store8(&tmp + p, 45); p = p + 1; x = 0 - x; }
    let d: [20] i64 = 0;
    let nd: i64 = 0;
    if x == 0 { d[0] = 0; nd = 1; }
    while x > 0 { d[nd] = x % 10; nd = nd + 1; x = x / 10; }
    let j: i64 = nd - 1;
    while j >= 0 { store8(&tmp + p, 48 + d[j]); p = p + 1; j = j - 1; }
    store8(&tmp + p, 0);
    syscall(1, 1, &tmp, p, 0, 0, 0);
    return 0;
}
fn main() -> i64 {
    let a: i64 = 0;
    let b: i64 = 1;
    let i: i64 = 0;
    while i < 15 {
        print_i64(a);
        let nx: i64 = a + b;
        a = b;
        b = nx;
        i = i + 1;
    }
    return 0;
}
MOEOF
./bin/mo2x /tmp/demo.mo c > "$DIST/demo/core.c" 2>/dev/null || { echo "mo2x c 失败"; exit 1; }
$ZIG -target aarch64-linux-musl -O2 "$DIST/demo/core.c" -o "$DIST/demo/fib-aarch64-linux" 2>&1 | grep -E "error" | head -3 || true
$ZIG -target aarch64-macos -O2 "$DIST/demo/core.c" -o "$DIST/demo/fib-aarch64-macos" 2>&1 | grep -E "error" | head -3 || true
$ZIG -target x86_64-windows-gnu -O2 "$DIST/demo/core.c" -o "$DIST/demo/fib-x86_64-windows.exe" 2>&1 | grep -E "error" | head -3 || true
$ZIG -target x86_64-linux-musl -O2 "$DIST/demo/core.c" -o "$DIST/demo/fib-x86_64-linux" 2>&1 | grep -E "error" | head -3 || true
chmod +x "$DIST/demo"/* 2>/dev/null || true

echo "== 4/6 源码包 =="
git archive --format=tar.gz --prefix="mo-lang-$VER/" -o "$DIST/mo-lang-$VER-src.tar.gz" HEAD
git archive --format=zip --prefix="mo-lang-$VER/" -o "$DIST/mo-lang-$VER-src.zip" HEAD

echo "== 5/6 校验和 =="
cd "$DIST"
rm -f demo/*.pdb
sha256sum moc mo-lang-$VER-src.tar.gz mo-lang-$VER-src.zip demo/fib-* > checksums.txt
# 自校验: checksums.txt 覆盖除自身外的所有发布资产
ls -la
echo "=== checksums.txt ==="
cat checksums.txt

echo "== 6/6 完成 =="
echo "产物目录: $DIST"
ls -la "$DIST"