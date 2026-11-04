# expect: 241
import "io.mo";
fn main() -> i64 {
    let m: [4] i64 = [1, 2, 3, 4];
    let i: i64 = 1;
    let j: i64 = 3;
    m[i], m[j] = m[j], m[i];
    let r: i64 = m[1] * 10 + m[3];
    m[i], m[2] = m[2] * 5, m[i] + 10;
    r = r * 100 + m[1] * 10 + m[2];
    let a: i64 = 5;
    let b: i64 = 6;
    a, b = b, a;
    r = r * 100 + a * 10 + b;
    return r;
}
