# expect: 142
# v1.1156: const fn branch support (if/else + comparison operators)
import "io.mo";
const fn max(a: i64, b: i64) -> i64 {
    if a > b { return a; }
    return b;
}
const fn min(a: i64, b: i64) -> i64 {
    if a < b { return a; }
    return b;
}
const fn clamp(a: i64, lo: i64, hi: i64) -> i64 {
    if a < lo { return lo; }
    if a > hi { return hi; }
    return a;
}
const fn sign(a: i64) -> i64 {
    if a == 0 { return 0; }
    if a > 0 { return 1; }
    return 2;
}
const fn grade(s: i64) -> i64 {
    if s >= 90 { return 4; }
    else {
        if s >= 60 { return 3; }
        else { return 1; }
    }
}
fn main() -> i64 {
    # max 双向: max(7,3)=7, max(3,7)=7
    let a: i64 = max(7, 3) + max(3, 7);
    # min 双向: min(9,4)=4, min(4,9)=4
    let b: i64 = min(9, 4) + min(4, 9);
    # clamp 三区: clamp(5,10,20)=10, clamp(15,10,20)=15, clamp(25,10,20)=20
    let c: i64 = clamp(5, 10, 20) + clamp(15, 10, 20) + clamp(25, 10, 20);
    # sign 三分支: sign(0)=0, sign(8)=1, sign(-3)=2
    let d: i64 = sign(0) * 10 + sign(8) + sign(-3) * 5;
    # grade: grade(95)=4, grade(70)=3, grade(10)=1
    let e: i64 = grade(95) * 100 + grade(70) * 10 + grade(10);
    # 条件含复合算术: f(5,4): 5*2+1=11 > 4/2=2 -> return 5-4=1; f(2,30): 5 > 15 假 -> return 28
    let total: i64 = a * 100000 + b * 10000 + c * 100 + d + e;
    return total;
}
