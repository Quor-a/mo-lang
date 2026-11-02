# expect: 6
# 测试：函数指针表 [N] ptr（v1.1019）—— [N] ptr 类型 + &fn 元素 + 间接调用
fn inc(n: i64) -> i64 { return n + 1; }

fn main() -> i64 {
    let t: [1] ptr;
    t[0] = &inc;
    let f: ptr = t[0];
    return f(5);
}
