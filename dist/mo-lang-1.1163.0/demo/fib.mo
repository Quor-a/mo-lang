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
