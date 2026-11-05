# expect: 2
# v1.1149: match 区间臂 —— 闭区间 [lo, hi]，语句与表达式两种形式
import "io.mo";
fn grade(x: i64) -> i64 {
    match x {
        90..100 => { return 4; }
        60..89 => { return 3; }
        0..59 => { return 2; }
        _ => { return 0; }
    }
}
fn main() -> i64 {
    print_i64(grade(95));
    print_i64(grade(70));
    print_i64(grade(30));
    print_i64(grade(-5));
    let v = match 42 {
        0..9 => 1,
        40..49 => 2,
        _ => 3,
    };
    return v;
}
