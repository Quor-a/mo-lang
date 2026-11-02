# expect: 33
# len() 内建（v1.1068）：编译期返回数组外层元素个数；
# 二维取最外维；循环边界用法；非数组实参报错（errors 另测）。
# (2+5)*3 + 10 + 2 = 33
const N: i64 = 4;
fn main() -> i64 {
    let a: [N] i64 = [1, 2, 3, 4];
    let m: [2][3] i64;
    let b: [5] i64;
    let s: i64 = 0;
    let i: i64 = 0;
    while i < len(a) { s = s + a[i]; i = i + 1; }
    return (len(m) + len(b)) * 3 + s + len(m);
}
