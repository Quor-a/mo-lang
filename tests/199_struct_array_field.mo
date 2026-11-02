# expect: 9
# 测试：结构体字段为数组类型（v1.1035）
# struct W { a: [2] P; b: i64; }，w.a[1].x = 6, w.b = 3 → 9
struct P { x: i64; y: i64; }
struct W { a: [2] P; b: i64; }

fn main() -> i64 {
    let w: W;
    w.a[1].x = 6;
    w.b = 3;
    return w.a[1].x + w.b;
}
