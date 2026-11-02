# expect: 6
# 测试：嵌套结构体数组字段 q.p[1].y（v1.1035）
struct P { x: i64; y: i64; }
struct Q { p: [2] P; z: i64; }

fn main() -> i64 {
    let q: Q;
    q.p[1].y = 4;
    q.z = 2;
    return q.p[0].x + q.p[1].y + q.z;
}
