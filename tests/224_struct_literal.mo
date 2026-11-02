# expect: 251
# struct 字面量（v1.1048）：let p: P = P { x: 7; y: 2+3; }; 字段乱序可、右值为表达式。
# 7 + 500 = 507 mod 256 = 251
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let p: P = P { y: 2 + 3; x: 7; };
    return p.x + p.y * 100;
}
