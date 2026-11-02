# struct 字段默认值（v1.1061）：未列出的字段取声明时默认。
struct P { x: i64 = 10; y: i64 = 20; }
fn main() -> i64 {
    let a: P = P { y: 2; };
    return a.x + a.y;   # 10+2 = 12
}
