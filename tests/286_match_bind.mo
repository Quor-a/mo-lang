# expect: 29
import "io.mo";
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let r: P = P { x: 3; y: 9; };
    let t: i64 = 0;
    match r {
        P { y: v; } => { t = v; }
        _ => { t = 111; }
    }
    match r {
        P { x: 3; y: w; } => { t = t + w; }
        _ => { t = 222; }
    }
    return t + 11;
}
