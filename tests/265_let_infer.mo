# expect: 3
# 无类型推断 let（v1.1083）：let f = add; 裸函数名作值 + 推断
fn add(a: i64, b: i64) -> i64 {
    return a + b;
}

fn main() -> i64 {
    let f = add;
    let x = 2;
    return f(1, x);
}
