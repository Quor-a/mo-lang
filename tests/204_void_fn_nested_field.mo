# expect: 42
# 测试：void 函数 + 嵌套数组字段 q.p[i].y（v1.1036）
struct P { x: i64; y: i64; }
struct Q { p: [2] P; z: i64; }

fn setf(q: ptr Q, i: i64, val: i64) { q.p[i].y = val; }

fn main() -> i64 {
    let q: Q;
    setf(&q, 1, 42);
    return q.p[1].y;
}
