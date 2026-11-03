# expect: 37
import "io.mo";
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let r: P = P { x: 3; y: 9; };
    let a = match r {
        P { y: v; } => v * 2,
        _ => 111,
    };
    let b: i64 = match r {
        P { x: 3; y: w; } => w + 1,
        _ => 0,
    };
    return a + b + match r { P { y: v; } => v, _ => 0 };
}
