# struct 值比较 == / !=（v1.1060/1063）：逐 word 比较，嵌套也支持。
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let a: P = P { x: 1; y: 2; };
    let b: P = P { x: 1; y: 2; };
    let c: P = P { x: 1; y: 3; };
    let r: i64 = 0;
    if a == b { r = r + 1; }
    if a != c { r = r + 10; }
    return r;   # 11
}
