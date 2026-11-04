# expect: 116
import "io.mo";
fn main() -> i64 {
    let m: [4] i64 = [1, 2, 3, 4];
    let r: i64 = 0;
    m[0], m[1] = m[1], m[0];
    r = r * 10 + m[0] * 10 + m[1];
    m[2], m[3] = m[3] * 2, m[2] + 1;
    r = r * 100 + m[2] * 10 + m[3];
    let a: i64 = 7;
    let b: i64 = 9;
    a, b = b, a;
    r = r * 100 + a * 10 + b;
    m[0], m[3] = 100, 200;
    r = r * 10000 + (m[0] + m[3]) / 3;
    return r;
}
