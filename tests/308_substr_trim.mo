# expect: 63
import "io.mo";
import "str.mo";
import "mem.mo";

fn main() -> i64 {
    let s: ptr = "abcdef";
    let t: ptr = substr(s, 1, 3);
    let r: i64 = 0;
    if t[0] == 98 && t[1] == 99 && t[2] == 100 && t[3] == 0 { r = r + 1; }
    let u: ptr = trim("  hi  ");
    if u[0] == 104 && u[1] == 105 && u[2] == 0 { r = r + 2; }
    if strlen(u) == 2 { r = r + 4; }
    if strlen(substr(s, 0, 6)) == 6 { r = r + 8; }
    let v: ptr = trim("   mid   ");
    if v[0] == 109 && strlen(v) == 3 { r = r + 16; }
    let z: ptr = substr(s, 3, 0);
    if z[0] == 0 { r = r + 32; }
    print_i64(r);
    return r;
}
