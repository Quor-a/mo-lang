# expect: 1
# 测试：函数指针相等比较（v1.1017 回归入库）
fn dbl(n: i64) -> i64 {
    return n * 2;
}

fn main() -> i64 {
    let f: ptr = &dbl;
    let g: ptr = &dbl;
    if f == g { return 1; }
    return 0;
}
