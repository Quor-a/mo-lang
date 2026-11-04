# expect: 217
import "io.mo";
fn mki() -> [2][3] i64 {
    return [[1, 2, 3], [4, 5, 6]];
}
fn mkb() -> [2][2] byte {
    return [[1, 2], [3, 4]];
}
fn main() -> i64 {
    let a: [2][3] i64 = mki();
    let b: [2][2] byte = mkb();
    return a[1][0] * 100 + a[0][2] * 10 + a[1][2] + b[1][0] * 10 + b[0][1] + b[0][0] + b[1][1];
}
