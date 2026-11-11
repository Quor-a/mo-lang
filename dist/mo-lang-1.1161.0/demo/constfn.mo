import "io.mo";
# v1.1160: const fn 里的循环 + break / continue —— 全部在编译期折叠
const fn sum_to(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n { s = s + i; i = i + 1; }
    return s;
}
const fn first_div(n: i64) -> i64 {
    let i: i64 = 2;
    let r: i64 = 0 - 1;
    while i < n {
        if n % i == 0 { r = i; break; }
        i += 1;
    }
    return r;
}
const fn sum_odd(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n {
        if i % 2 == 0 { i += 1; continue; }
        s += i;
        i += 1;
    }
    return s;
}
const fn inr(x: i64, lo: i64, hi: i64) -> i64 {
    if x >= lo && x <= hi { return 1; }
    return 0;
}
const fn gcd(a: i64, b: i64) -> i64 {
    let x: i64 = a;
    let y: i64 = b;
    let t: i64 = 0;
    while y != 0 { t = x % y; x = y; y = t; }
    return x;
}
fn main() -> i64 {
    print_i64(sum_to(10));
    print(" ");
    print_i64(first_div(35));
    print(" ");
    print_i64(sum_odd(6));
    print(" ");
    print_i64(gcd(48, 18));
    print(" ");
    print_i64(inr(5, 1, 10) * 100 + inr(20, 1, 10));
    print("\n");
    return 0;
}
