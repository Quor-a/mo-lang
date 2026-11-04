# expect: 5
import "io.mo";
fn main() -> i64 {
    let m: [2][2] f64 = [[1.5, 2.5], [3.5, -3.5]];
    let r: i64 = 0;
    if 2.5 in m { r = r + 1; }
    if 9.5 in m { r = r + 2; }
    if -3.5 in m { r = r + 4; }
    return r;
}
