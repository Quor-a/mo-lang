# expect: 42
# 测试：函数指针调用 f(x)（v1.1016）—— ptr 变量后跟 () 走 call rax
fn dbl(n: i64) -> i64 {
    return n * 2;
}

fn apply(f: ptr, x: i64) -> i64 {
    return f(x);
}

fn main() -> i64 {
    return apply(&dbl, 21);
}
