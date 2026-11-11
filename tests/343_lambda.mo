# expect: 64
# 测试：lambda 表达式（v1.1165）—— fn(..){..} 作第一类值
#   ML 1978 引入 -> Scheme/Swift/Kotlin/Rust 标配。Mo 此前只有命名函数取址。
fn apply(f: ptr, x: i64) -> i64 {
    return f(x);
}

fn main() -> i64 {
    # lambda 赋给变量
    let dbl: ptr = fn(n: i64) -> i64 { return n * 2; };
    let a: i64 = apply(dbl, 21);
    # lambda 内联作实参
    let b: i64 = apply(fn(n: i64) -> i64 { return n + 1; }, 9);
    # 多 lambda：各自独立编号
    let c: i64 = apply(fn(n: i64) -> i64 { return n * 3; }, 4);
    return a + b + c;
}
