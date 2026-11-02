# expect: 43
# 方法调用数组字面量实参（v1.1045，parse_expr_method 同步）：p[0] + p[1]*n = 3 + 40 = 43
struct S { n: i64; }
fn S_get(self: S, p: ptr i64, n: i64) -> i64 {
    return p[0] + p[1] * n;
}
fn main() -> i64 {
    let s: S = 0;
    return s.get([3, 4], 10);
}
