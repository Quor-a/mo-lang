import "io.mo";
var TS: [2] i64 = 0;
fn now_ns() -> i64 { let r: i64 = syscall(228, 1, &TS, 0, 0, 0, 0); return TS[0] * 1000000000 + TS[1]; }
var ACC: i64 = 0;
fn w_const(n: i64) -> i64 {          # 常量除数 → 魔数
    let i: i64 = 0; let s: i64 = 0;
    while i < n { s = s + (i % 7) + (i / 7); i = i + 1; }
    return s;
}
fn w_var(n: i64) -> i64 {            # 变量除数 → idiv
    let d: i64 = 7;
    let i: i64 = 0; let s: i64 = 0;
    while i < n { s = s + (i % d) + (i / d); i = i + 1; }
    return s;
}
fn main() -> i64 {
    let n: i64 = 3000000;
    let a: i64 = 0; let b: i64 = 0;
    let r: i64 = 0;
    while r < 5 {
        let t0: i64 = now_ns(); a = a + w_const(n); let t1: i64 = now_ns();
        let t2: i64 = now_ns(); b = b + w_var(n);   let t3: i64 = now_ns();
        print("魔数 "); print_i64(t1 - t0); print(" ns   idiv "); print_i64(t3 - t2); print(" ns\n");
        r = r + 1;
    }
    if a != b { print("CHECKSUM 不一致！\n"); }
    else { print("结果一致\n"); }
    return 0;
}
