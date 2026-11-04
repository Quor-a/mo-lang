# expect: 150
import "io.mo";
fn main() -> i64 {
    let s: str = "abcdef";
    let sub: str = s[1..3];
    let bs: str = b_slice();
    let r: i64 = sub[0] + sub[1] + bs[0] + bs[2];
    return r;
}
fn b_slice() -> str {
    let b: [6] byte = [104, 101, 108, 108, 111, 33];
    return b[1..4];
}
