# expect: 31
import "io.mo";

fn main() -> i64 {
    let x: f64 = 2.9;
    let y: i64 = 3;
    let r: i64 = 0;
    if x as i64 == 2 { r = r + 1; }
    if (y as f64) == 3.0 { r = r + 2; }
    let p: ptr = "hi";
    if p as i64 > 0 { r = r + 4; }
    if (1.5 + (y as f64)) == 4.5 { r = r + 8; }
    if (x as i64) * 10 == 20 { r = r + 16; }
    print_i64(r);
    return r;
}
