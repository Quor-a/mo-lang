# expect: 29
# struct 字面量赋值（v1.1054）：p = P { ... }; 局部+全局、乱序字段。
# g.x=1 g.y=9 p.x=6 p.y=7 → 1+90+6+700=797 mod 256 = 29
struct P { x: i64; y: i64; }
var g: P;
fn main() -> i64 {
    g = P { y: 9; x: 1; };
    let p: P = 0;
    p = P { x: 6; y: 7; };
    return g.x + g.y * 10 + p.x + p.y * 100;
}
