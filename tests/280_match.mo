# expect: 120
# v1.1098: match 表达式 —— 数字/const/enum 模式 + _ default + continue 穿透
import "io.mo";

const K1: i64 = 5;
enum C { A; B; }

fn main() -> i64 {
    let x: i64 = K1;
    let r: i64 = 0;
    let i: i64 = 0;
    while i < 3 {
        match x {
            1 => { r = r + 1; }
            K1 => { r = r + 10; }
            _ => { r = r + 100; }
        }
        match i {
            0 => { i = i + 1; continue; }
            _ => { }
        }
        i = i + 10;
    }
    let c: i64 = B;
    match c {
        A => { return 7; }
        B => { return r + 100; }
    }
    return 0;
}
