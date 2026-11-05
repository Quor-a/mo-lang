# expect: 36
import "io.mo";
# v1.1143: `?` 错误传播 + defer 块形式
var acc: i64 = 0;
fn risky(x: i64) -> i64 {
    if x < 0 { return x; }
    return x * 2;
}
fn chain(x: i64) -> i64 {
    defer { acc = acc + 1; }
    let a = risky(x)?;
    let b = risky(a)?;
    return a + b;
}
fn main() -> i64 {
    let ok = chain(3)?;
    let bad = chain(0 - 4);
    return ok * 100 + bad + acc * 10000;
}
