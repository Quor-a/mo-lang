# expect: 15
# struct 字面量在函数内构造并返回（v1.1048）：mk(5) → x=5,y=10 → 15
struct P { x: i64; y: i64; }
fn mk(a: i64) -> P {
    let r: P = P { x: a; y: a * 2; };
    return r;
}
fn main() -> i64 {
    let q: P = mk(5);
    return q.x + q.y;
}
