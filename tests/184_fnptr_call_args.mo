# expect: 137
# 测试：数组元素函数指针多实参调用（v1.1021 回归入库）
fn add(a: i64, b: i64) -> i64 { return a + b; }
fn sub(a: i64, b: i64) -> i64 { return a - b; }

fn main() -> i64 {
    let t: [2] ptr = [&add, &sub];
    return t[0](10, 3) * 10 + t[1](10, 3);
}
