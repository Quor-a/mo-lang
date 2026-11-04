# expect: 47
import "io.mo";

fn main() -> i64 {
    let f: [3] f64 = [1.5, 2.5, -3.5];
    let b: [5] byte = [72, 101, 108, 108, 111];
    let a: [3] i64 = [7, 8, 9];
    let r: i64 = 0;
    if 2.5 in f { r = r + 1; }
    if 9.5 in f { r = r + 2; }
    if -3.5 in f { r = r + 4; }
    if 108 in b { r = r + 8; }
    if 88 in b { r = r + 16; }
    if 8 in a { r = r + 32; }
    if 2.5 not in f { r = r + 64; }
    print_i64(r);
    return r;
}
