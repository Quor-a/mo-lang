# expect: 207
# 命名实参·负默认值（v1.1040）：DFVHAS 位图区分"有默认"与默认值本身为负。
# f(b:1) → a=-5, b=1 → -50+1 = -49 mod 256 = 207
fn f(a: i64 = 0 - 5, b: i64 = 7) -> i64 {
    return a * 10 + b;
}

fn main() -> i64 {
    return f(b: 1);
}
