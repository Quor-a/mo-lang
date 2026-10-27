#!/bin/bash
# ffitest —— C FFI 端到端验证
#
# 每一步都是"真链接 + 真运行 + 比对输出"，不只看 .o 里有没有重定位。
# 因为 extern 调用错了通常**不报错**：要么跳进未映射地址段错误，
# 要么静默没输出（如 raw exit 不 flush stdio）。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"
LINK="$HERE/tools/molink.sh"
TMP=/tmp/moffi
rm -rf $TMP && mkdir -p $TMP/lib
cp lib/*.mo $TMP/lib/
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

# 1) libc write / strlen / malloc / free / sqrt
cat > $TMP/a.mo <<'MO'
extern fn write(fd: i64, buf: ptr, n: i64) -> i64;
extern fn malloc(n: i64) -> ptr;
extern fn free(p: ptr) -> i64;
extern fn strlen(s: ptr) -> i64;

fn main() -> i64 {
    let s: ptr = "abc\n";
    write(1, s, strlen(s));
    let p: ptr = malloc(64);
    write(1, "malloc\n", 7);
    free(p);
    return 0;
}
MO
cd $TMP
$MOC a.mo -c a.o >/dev/null 2>&1
bash "$LINK" a.o -o a >/dev/null 2>&1
ck "$(./a)" "$(printf 'abc\nmalloc')" "libc: write/strlen/malloc/free"

# 2) printf 格式化（验证 stdio 缓冲被 flush）
cat > $TMP/b.mo <<'MO'
extern fn printf(fmt: ptr, ...) -> i64;

fn main() -> i64 {
    printf("%d + %d = %d\n", 2, 3, 5);
    return 0;
}
MO
$MOC b.mo -c b.o >/dev/null 2>&1
bash "$LINK" b.o -o b >/dev/null 2>&1
ck "$(./b)" "2 + 3 = 5" "libc: printf 格式化且输出被 flush"

# 3) 返回值与字符串比较（验证 C 的返回值能正确使用）
#    注：qsort 那种"把墨函数当回调传给 C"目前**不支持**
#    —— 墨语言里函数名不是值，取不到地址（见文档已知限制）。
cat > $TMP/c.mo <<'MO'
extern fn abs(x: i64) -> i64;
extern fn strcmp(a: ptr, b: ptr) -> i32;

fn main() -> i64 {
    if strcmp("abc", "abc") != 0 { return 1; }
    if strcmp("abc", "abd") >= 0 { return 2; }
    # strcmp 返回 int：不声明 -> i32 的话 -1 会被读成 4294967295
    if strcmp("abc", "abd") >= 0 { return 3; }
    return abs(0 - 7);
}
MO
$MOC c.mo -c c.o >/dev/null 2>&1
bash "$LINK" c.o -o c >/dev/null 2>&1
RC=0; ./c >/dev/null 2>&1 || RC=$?
ck "$RC" "7" "libc: strcmp(i32 符号扩展)/abs 返回值正确"

# 4) -nostdlib 也能跑（不依赖 libc 的纯墨程序）
cat > $TMP/d.mo <<'MO'
import "io.mo";
fn main() -> i64 {
    print("nostdlib ok");
    return 7;
}
MO
$MOC d.mo -c d.o >/dev/null 2>&1
bash "$LINK" d.o -nostdlib -o d >/dev/null 2>&1
OUT=$(./d); RC=$?
ck "$OUT" "nostdlib ok" "nostdlib: 输出正确"
ck "$RC" "7" "nostdlib: 退出码正确"

# 5) .o 结构：ET_REL + 重定位类型
T=$(readelf -h a.o | grep -c "REL (Relocatable file)")
ck "$T" "1" ".o 是 ET_REL"
R=$(readelf -r a.o | grep -c "R_X86_64_PLT32")
if [ "$R" -ge 3 ]; then PASS=$((PASS+1)); echo "  ✓ 重定位类型正确 (R_X86_64_PLT32 × $R)"; else FAIL=$((FAIL+1)); echo "  ✗ 重定位数量不足 ($R)"; fi

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ]
