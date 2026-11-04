# expect: 63
import "io.mo";
import "str.mo";
import "mem.mo";

var G: [3] i64 = [1, 2, 3];

fn g() -> [3] i64 { return G; }
fn mk() -> ptr { return "xabc"; }

fn main() -> i64 {
    let r: i64 = 0;
    if mk()[3] == 99 { r = r + 1; }
    if mk()[0] == 120 { r = r + 2; }
    if g()[2] == 3 { r = r + 4; }
    if g()[0] == 1 { r = r + 8; }
    let s: ptr = substr("hello", 1, 3);
    if s[0] == 101 && s[2] == 108 { r = r + 16; }
    if mk()[1] == 97 && mk()[3] == 99 { r = r + 32; }
    print_i64(r);
    return r;
}
