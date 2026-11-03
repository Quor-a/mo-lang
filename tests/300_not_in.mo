# expect: 53
import "io.mo";

fn main() -> i64 {
    let a: [4] i64 = [7, 8, 9, 10];
    let r: i64 = 0;
    if 99 not in a { r = r + 1; }
    if 8 not in a { r = r + 2; }
    if "z" not in "hello" { r = r + 4; }
    if "ell" not in "hello" { r = r + 8; }
    if 7 in a { r = r + 16; }
    if "ell" in "hello" { r = r + 32; }
    print_i64(r);
    return r;
}
