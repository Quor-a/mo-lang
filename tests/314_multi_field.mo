# expect: 5
import "io.mo";
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let p: P = P { x: 1; y: 2; };
    let a: i64 = 5;
    p.x, a = a, p.x;
    let r: i64 = p.x * 10 + a;
    p.x, p.y = p.y, p.x;
    r = r * 100 + p.x * 10 + p.y;
    return r;
}
