# expect: 129
import "io.mo";
fn g(s: ptr) -> i64 {
    return match s { "a" => 1, "b" => 2, _ => 3 } + match s { "a" => 10, _ => 20 };
}
fn main() -> i64 {
    let s = "hi";
    let t: i64 = match s { "hi" => 7, "yo" => 9, _ => 11 };
    let c: i64 = 2;
    let n1 = match c { 1 => 5, _ => 6 } + 100;
    return n1 + g("b") + match "z" { "z" => 1, _ => 2 } + t - t;
}
