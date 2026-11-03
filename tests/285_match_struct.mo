# expect: 53
import "io.mo";
struct P { x: i64; y: i64; }
fn f(r: P) -> i64 {
    match r {
        P { y: 0; } => { return 1; }
        P { x: 5; y: 2; } => { return 2; }
        _ => { return 3; }
    }
}
fn main() -> i64 {
    let r: P = P { x: 3; y: 9; };
    let s: i64 = 0;
    match r {
        P { x: 1; } => { s = 1; }
        P { y: 9; } => { s = 2; }
        _ => { s = 3; }
    }
    return s * 10 + f(P { x: 5; y: 0; }) * 10 + f(P { x: 5; y: 2; }) * 10 + f(P { x: 5; y: 7; });
}
