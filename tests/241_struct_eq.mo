# expect: 111
# struct 值相等比较（v1.1060）：== / != 逐 word 展开；嵌套 struct 也支持。
# a!=b →1, a==a →10, q1==q2 →100 → 111
struct P { x: i64; y: i64; }
struct Q { p: P; n: i64; }
fn main() -> i64 {
    let a: P = P { x: 1; y: 2; };
    let b: P = P { x: 1; y: 3; };
    let c: i64 = 0;
    if a != b { c = c + 1; }
    if a == a { c = c + 10; }
    let q1: Q = Q { p: P { x: 5; y: 5; }; n: 9; };
    let q2: Q = Q { p: P { x: 5; y: 5; }; n: 9; };
    if q1 == q2 { c = c + 100; }
    return c;
}
