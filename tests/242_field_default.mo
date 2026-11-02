# expect: 52
# struct 字段默认值（v1.1060）：struct P { x: i64 = 10; }——let/全局/
# 字面量未列字段均取默认。10+20+2+10 = 42
struct P { x: i64 = 10; y: i64 = 20; }
struct S { a: i64; }
var g: P;
fn main() -> i64 {
    let a: P;
    let b: P = P { y: 2; };
    g = P { y: 10; };
    return a.x + a.y + b.x + b.y + g.y;   # 10+20+10+2+10 = 52? 校: a.y 默认20
}
