# expect: 225
# 嵌套解构（v1.1082）：let [[x, y], [z, w]] = m;（4321 mod 256 = 225）
fn main() -> i64 {
    let m: [2][2] i64 = [[1,2],[3,4]];
    let [[x, y], [z, w]] = m;
    return x + y*10 + z*100 + w*1000;
}
