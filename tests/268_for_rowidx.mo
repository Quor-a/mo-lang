# expect: 15
# for-in 行索引（v1.1086）：for v in m[1] 遍历第 1 行（4+5+6=15）
fn main() -> i64 {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let s: i64 = 0;
    for v in m[1] {
        s = s + v;
    }
    return s;
}
