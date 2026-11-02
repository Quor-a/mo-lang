# expect: 3
# 测试：默认参数含 ptr 类型（p = 0）（v1.1037）
struct S { x: i64; }

fn g(p: ptr S = 0, n: i64 = 3) -> i64 { return n; }

fn main() -> i64 {
    return g();
}
