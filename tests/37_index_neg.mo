# expect: 0
# v1.1139: 负下标从尾数 —— a[-1] = a[3]（len 已知，运行时换算）
fn main() -> i64 {
    let a: [4] i64 = 0;
    let i: i64 = 0 - 1;
    return a[i];
}
