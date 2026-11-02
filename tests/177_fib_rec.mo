# expect: 109
# 测试：递归 fib(20)=6765（v1.1014 回归入库）—— 6765 mod 256 = 109
fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    return fib(20);
}
