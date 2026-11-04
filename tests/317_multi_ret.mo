# expect: 26
import "io.mo";
fn mk2() -> [2][3] i64 {
    let g: [2][3] i64 = [[1, 2, 3], [4, 5, 6]];
    return g;
}
fn main() -> i64 {
    let a: [2][3] i64 = mk2();
    return a[0][1] * 10 + a[1][2];
}
