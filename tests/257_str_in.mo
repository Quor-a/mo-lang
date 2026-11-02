# expect: 101
# in 运算符（v1.1075）：a in b = a 是 b 的子串（0/1）。
fn main() -> i64 {
    let r: i64 = 0;
    if "ell" in "hello" { r = r + 1; }
    if "xyz" in "hello" { r = r + 10; }
    if "hello" in "hello" { r = r + 100; }
    return r;   # 1+100=101? expect 首算: 1+100=101
}
