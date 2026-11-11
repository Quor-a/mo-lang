fn print_sp() -> i64 { let sp: [2] byte = 0; store8(&sp, 32); store8(&sp + 1, 0); syscall(1, 1, &sp, 1, 0, 0, 0); return 0; }
fn print_nl2() -> i64 { let nl: [2] byte = 0; store8(&nl, 10); store8(&nl + 1, 0); syscall(1, 1, &nl, 1, 0, 0, 0); return 0; }
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
const fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); }
var D: [fact(5)] i64 = 0;
fn main() -> i64 {
    D[119] = 3;
    print_i64(D[119]); print_nl2();
    return 0;
}
