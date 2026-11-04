# expect: 146
import "io.mo";
fn main() -> i64 {
    let s: str = "abcdefgh";
    let i: i64 = 1;
    let j: i64 = 4;
    let a: str = s[i..j];
    let b: str = s[3..6];
    let c: str = b[2..7];
    return a[0] + a[2] + b[1] + c[0] + i;
}
