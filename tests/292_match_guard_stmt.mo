# 292: match 语句版守卫绑定
import "io.mo";
fn main() -> i64 {
    let x: i64 = 5;
    let r: i64 = 0;
    match x {
        y if y > 3 => { r = y * 10; }
        _ => { r = 1; }
    }
    print_i64(r);
    return r;
}
# expect: 50
