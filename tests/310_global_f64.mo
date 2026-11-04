# expect: 31
import "io.mo";

var PI: f64 = 3.14;
var NEG: f64 = -2.75;
var EPS: f64;
var GA: [2] f64 = [1.5, -2.5];

fn main() -> i64 {
    let r: i64 = 0;
    if PI > 3.13 && PI < 3.15 { r = r + 1; }
    if NEG < 0.0 { r = r + 2; }
    if EPS == 0.0 { r = r + 4; }
    if GA[0] == 1.5 { r = r + 8; }
    if GA[1] < 0.0 && GA[1] == -2.5 { r = r + 16; }
    print_i64(r);
    return r;
}
