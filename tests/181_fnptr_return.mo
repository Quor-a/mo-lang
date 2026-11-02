# expect: 20
# 测试：函数指针作返回值（v1.1018 回归入库）—— -> ptr 返回 &fn
fn dbl(n: i64) -> i64 {
    return n * 2;
}

fn get() -> ptr {
    return &dbl;
}

fn main() -> i64 {
    let f: ptr = get();
    return f(10);
}
