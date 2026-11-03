# expect: 21
# 变量行 for-in（v1.1090）：for row in m { for v in row {...} }（上界=外层登记的 _fl_ 行长度）
fn main() -> i64 {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let s: i64 = 0;
    for row in m {
        for v in row {
            s = s + v;
        }
    }
    return s;
}
