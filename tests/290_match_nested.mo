# expect: 39
import "io.mo";
struct P { x: i64; y: i64; }
struct Q { p: P; n: i64; }
fn main() -> i64 {
    let r: Q = Q { p: P { x: 3; y: 9; }; n: 5; };
    let a = match r { Q { p: P { y: v; }; n: 5; } => v * 4, _ => 0 };
    print_i64(a);
    match r {
        Q { p: P { x: 3; }; } => { print_i64(3); }
        _ => { print_i64(111); }
    }
    return a + 3;
}
