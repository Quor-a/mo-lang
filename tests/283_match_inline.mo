# expect: 230
import "io.mo";
fn f(c: i64) -> i64 {
    return match c { 1 => 5, 2 => 6, _ => 0 } + 1;
}
fn main() -> i64 {
    let c: i64 = 2;
    let a = match c { 1 => 10, _ => 20 };
    let b: i64 = match c { 1 => 100, 2 => 200, _ => 300 };
    let r: i64 = 0;
    r = match c { 1 => 1, _ => 2 };
    return a + b + r + f(c) + match c { 1 => 0, _ => 1 };
}
