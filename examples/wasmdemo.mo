# wasmdemo.mo —— 同一份源码，两种运行环境：原生 x86-64 与 WebAssembly
#
#   bash tools/wasm.sh   examples/wasmdemo.mo /tmp/demo.wasm  # 编成 WASM 并真跑
#   bash tools/wasmtest.sh                                    # 与原生输出逐字节比对
#
# 关键设计：这里的输出函数**自己定义**（syscall 版），
# 但 mo2x 的 C 后端会**跳过** print / print_i64 / print_nl 的实现，
# 改用前导里的 printf 版本 —— 因为 WASI 根本没有 syscall()。
# 于是同一份源码在原生（syscall）与 WASM（printf）下输出必须逐字节一致，
# wasmtest.sh 验的就是这件事。
fn print(s: i64) -> i64 {
    let n: i64 = 0;
    while load8(s + n) != 0 { n = n + 1; }
    syscall(1, 1, s, n, 0, 0, 0);
    return 0;
}
fn print_nl() -> i64 {
    let c: [1] byte = 0;
    store8(&c, 10);
    syscall(1, 1, &c, 1, 0, 0, 0);
    return 0;
}
fn print_i64(v: i64) -> i64 {
    let b: [24] byte = 0;
    let i: i64 = 0;
    let neg: i64 = 0;
    let u: i64 = v;
    if v < 0 { neg = 1; u = 0 - v; }
    if u == 0 { store8(&b, 48); i = 1; }
    while u > 0 {
        store8(&b + i, 48 + (u - (u / 10) * 10));
        u = u / 10;
        i = i + 1;
    }
    if neg == 1 { store8(&b + i, 45); i = i + 1; }
    while i > 0 {
        i = i - 1;
        let one: [1] byte = 0;
        store8(&one, load8(&b + i));
        syscall(1, 1, &one, 1, 0, 0, 0);
    }
    return 0;
}

fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    print("Mo -> WebAssembly (WASI)\n");
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 20 {
        let f: i64 = fib(i);
        print_i64(f);
        print(" ");
        s = s + f;
        i = i + 1;
    }
    print_nl();
    print("sum=");
    print_i64(s);
    print_nl();
    print_i64(-42);
    print_nl();
    return 42;
}
