# expect: 111
# struct 值相等比较（v1.1060/1063）：== / != 逐 word 累积（sete r10b;
# and r11b）+ xor 取反；嵌套 struct 支持。
# a!=b →1, a==a →10, q1==q2 →100 → 111
struct P { x: i64; y: i64; }
struct Q { p: P; n: i64; }
fn main() -> i64 {
    let a: P = P { x: 1; y: 2; };
    let b: P = P { x: 1; y: 3; };
    let c: i64 = 0;
    if a != b { c = c + 1; }
    if a == a { c = c + 10; }
    let q1: Q;
    let q2: Q;
    q1.p.x = 5; q1.p.y = 5; q1.n = 9;
    q2.p.x = 5; q2.p.y = 5; q2.n = 9;
    if q1 == q2 { c = c + 100; }
    return c;
}
