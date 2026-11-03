# expect: 78
# v1.1095: range for —— for i in A..B（数字/const/enum 端点），含 continue/break 语义
import "io.mo";

const N: i64 = 5;

fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    for i in 0..10 {
        s = s + i;
    }
    let t: i64 = 0;
    for i in 0..N {
        t = t + i;
    }
    let u: i64 = 0;
    for i in 1..10 {
        if i == 5 { continue; }
        if i > 7 { break; }
        u = u + i;
    }
    print_i64(s);
    print_i64(t);
    return s + t + u;
}
