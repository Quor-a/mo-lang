# C FFI 示例：直接调用 libc
#
# 编译链接：
#   ./bin/moc examples/ffi.mo -c /tmp/ffi.o
#   bash tools/molink.sh /tmp/ffi.o -o /tmp/ffi
#   /tmp/ffi
#
# 墨语言的调用约定本来就是 System V（rdi/rsi/rdx/rcx/r8/r9），
# 所以调 C 函数**不需要任何参数转换**。

extern fn printf(fmt: ptr, ...) -> i64;
extern fn strlen(s: ptr) -> i64;
extern fn malloc(n: i64) -> ptr;
extern fn free(p: ptr) -> i64;
extern fn strcmp(a: ptr, b: ptr) -> i32;
extern fn abs(x: i64) -> i64;

fn main() -> i64 {
    printf("hello from C: %d + %d = %d\n", 2, 3, 2 + 3);

    let s: ptr = "four";
    printf("strlen(\"%s\") = %d\n", s, strlen(s));

    # C 的 int 只写 eax，所以返回 int 的函数要声明成 i32，
    # 否则 -1 会被读成 4294967295。
    printf("strcmp(abc, abd) = %d\n", strcmp("abc", "abd"));

    let p: ptr = malloc(64);
    printf("malloc -> %d (nonzero ok)\n", 1);
    free(p);

    printf("abs(-7) = %d\n", abs(0 - 7));
    return 0;
}
