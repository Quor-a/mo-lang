# expect: 5
import "io.mo";
fn main() -> i64 {
    let m: [2][3] i64 = [[1, 2, 3], [4, 5, 6]];
    let r: i64 = 0;
    if 5 in m { r = r + 1; }
    if 9 in m { r = r + 2; }
    if 1 in m { r = r + 4; }
    if 5 not in m { r = r + 8; }
    return r;
}
