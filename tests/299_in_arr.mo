# expect: 23
import "io.mo";

fn main() -> i64 {
    let a: [4] i64 = [7, 8, 9, 10];
    let v: i64 = 10;
    let r: i64 = 0;
    if 7 in a { r = r + 1; }
    if v in a { r = r + 2; }
    if 8 in a { r = r + 4; }
    if 11 in a { r = r + 8; }
    if "ell" in "hello" { r = r + 16; }
    if "x" in "hello" { r = r + 32; }
    print_i64(r);
    return r;
}
