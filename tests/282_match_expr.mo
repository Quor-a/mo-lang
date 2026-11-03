# expect: 32
# v1.1100: match 表达式 —— let 右值 / 赋值右值 / {} 或裸表达式臂
import "io.mo";

fn main() -> i64 {
    let c: i64 = 2;
    let r: i64 = match c {
        1 => { 10 }
        2 => { 20 }
        _ => { 30 }
    };
    r = match c {
        1 => 1,
        _ => 2,
    };
    return r + 30;
}
