# expect: 14
# 293: match 三层嵌套 struct 模式（语句版+表达式版）
import "io.mo";
struct R { z: i64; }
struct P { q: R; }
struct Q { p: P; }
fn main() -> i64 {
    let v: Q = Q { p: P { q: R { z: 7; }; }; };
    let r: i64 = 0;
    match v {
        Q { p: P { q: R { z: a; }; }; } => { r = a; }
        _ => { r = 1; }
    }
    print_i64(r);
    let r2: i64 = match v {
        Q { p: P { q: R { z: b; }; }; } => b,
        _ => 1,
    };
    print_i64(r2);
    return r + r2;
}
