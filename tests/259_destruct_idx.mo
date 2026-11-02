# expect: 200
# 解构 RHS 常量行索引（v1.1077）：let [a, b, c] = m[1];（456 mod 256 = 200）
fn main() -> i64 {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let [a, b, c] = m[1];
    return a * 100 + b * 10 + c;
}
