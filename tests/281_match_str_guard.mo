# expect: 2
# v1.1099: match 字符串模式 + 守卫 if
import "io.mo";

fn main() -> i64 {
    let s: str = "abc";
    let k: i64 = 1;
    match s {
        "abc" if k > 5 => { return 1; }
        "abc" => { return 2; }
        _ => { return 3; }
    }
    return 0;
}
