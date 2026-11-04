# expect: 253
import "io.mo";
fn main() -> i64 {
    let a: [5] i64 = [10, 20, 30, 40, 50];
    let i: i64 = 0 - 2;
    let b: [5] byte = [65, 66, 67, 68, 69];
    let s1: str = b[1..0 - 2];
    let v: i64 = s1[1];
    return a[0 - 1] * 100 + a[i] + a[0 - 5] + v;
}
