# expect: 62
# ptr 算术（v1.1044）：字节步（Mo 库生态约定 &arr + i*8），类型保留 ptr i64 不退化。
# e = p+16 → a[2]=30；b = e-8 → a[1]=20 → 30 + 20*1000 = 20030 mod 256 = 62
fn main() -> i64 {
    let a: [3] i64 = [10, 20, 30];
    let p: ptr i64 = a;
    let e: ptr i64 = p + 16;
    let s: i64 = e[0];
    let b: ptr i64 = e - 8;
    return s + b[0] * 1000;
}
