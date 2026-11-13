
class P { x: i64; y: i64; }
fn main() -> i64 {
    let a: P;
    a.x = 1; a.y = 9;
    let b: P;
    b.x = 2; b.y = 3;
    let r: i64 = 0;
    if a < b { r = r + 1; }
    if a <= b { r = r + 2; }
    if b > a { r = r + 4; }
    if b >= a { r = r + 8; }
    if a >= b { return 1; }
    let c: P;
    c.x = 1; c.y = 9;
    if a >= c { r = r + 16; }
    if a <= c { r = r + 32; }
    if a < c { return 2; }
    if a > c { return 3; }
    # 负数字段
    let d: P;
    d.x = 0 - 5; d.y = 1;
    let e: P;
    e.x = 2; e.y = 0 - 100;
    if d < e { r = r + 64; }
    if r != 127 { return 4; }
    return 0;
}
