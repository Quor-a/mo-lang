# expect: 6
# 数组字面量直接作实参（v1.1045）：f([1,2,3], 3)。
# 编译期发射到数据段常量区，实参=地址。10+20=30, 30+10*100=1030 mod 256 = 6
fn sum(p: ptr i64, n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n { s = s + p[i]; i = i + 1; }
    return s;
}
fn main() -> i64 {
    let a: i64 = sum([10, 20], 2);
    let b: i64 = sum([1, 2, 3, 4], 4);
    return a + b * 100;
}
