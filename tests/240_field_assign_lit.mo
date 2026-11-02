# expect: 43
# 字段整体赋值（v1.1059）：p.q = Q { ... };（语句层 '.' 链）
# 3 + 40 = 43
struct Q { x: i64; y: i64; }
struct P { q: Q; n: i64; }
fn main() -> i64 {
    let p: P = 0;
    p.q = Q { x: 3; y: 4; };
    return p.q.x + p.q.y * 10;
}
