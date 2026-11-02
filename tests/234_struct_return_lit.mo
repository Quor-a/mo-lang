# expect: 15
# struct 字面量作 return 值（v1.1055）：return P { ... }; 按值返回，
# 与变量返回、字面量赋值共存。1+20+500+6=527 mod 256 = 15
struct P { x: i64; y: i64; }
fn mk() -> P {
    return P { x: 3; y: 4; };
}
fn mk2() -> P {
    let q: P = 0;
    q.x = 1;
    q.y = 2;
    return q;
}
fn main() -> i64 {
    let a: P = mk2();
    let b: P = P { x: 5; y: 6; };
    return a.x + a.y * 10 + b.x * 100 + b.y;
}
