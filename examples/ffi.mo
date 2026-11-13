# C FFI 示例：直接调用 libc
#
# 编译链接：
#   ./bin/moc examples/ffi.mo -c /tmp/ffi.o
#   bash tools/molink.sh /tmp/ffi.o -o /tmp/ffi
#   /tmp/ffi
#
# 墨语言的调用约定本来就是 System V（rdi/rsi/rdx/rcx/r8/r9），
# 所以调 C 函数**不需要任何参数转换**。
#
# v1.1171 注：extern 暂不支持 C 的 variadic（...）—— printf 不可直接
# 声明；输出用 puts/putchar（非 variadic）。

extern fn strlen(s: ptr) -> i64;
extern fn malloc(n: i64) -> ptr;
extern fn free(p: ptr) -> i64;
extern fn strcmp(a: ptr, b: ptr) -> i32;
extern fn abs(x: i64) -> i64;
extern fn puts(s: ptr) -> i32;
extern fn putchar(c: i32) -> i32;

fn print_num(v: i64) -> i64 {
    if v < 0 {
        putchar(45);
        v = 0 - v;
    }
    if v >= 10 {
        print_num(v / 10);
    }
    putchar(48 + v % 10);
    return 0;
}

fn main() -> i64 {
    puts("hello from C FFI");

    let s: ptr = "four";
    puts("strlen(\"four\") =");
    print_num(strlen(s));
    putchar(10);

    # C 的 int 只写 eax，所以返回 int 的函数要声明成 i32，
    # 否则 -1 会被读成 4294967295。
    puts("strcmp(abc, abd) =");
    print_num(strcmp("abc", "abd"));
    putchar(10);

    let p: ptr = malloc(64);
    puts("malloc ok");
    free(p);

    puts("abs(-7) =");
    print_num(abs(0 - 7));
    putchar(10);
    return 0;
}
