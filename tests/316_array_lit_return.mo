# expect: 168
import "io.mo";
fn mk(n: i64) -> [3] i64 {
    return [n * 2, n + 5, 9];
}
fn retb() -> [2] byte {
    return [3, 7];
}
fn main() -> i64 {
    let a: [3] i64 = mk(4);
    let r: i64 = a[0] * 100 + a[1] * 10 + a[2];
    let b: [2] byte = retb();
    r = r + b[0] * 10 + b[1];
    return r;
}
