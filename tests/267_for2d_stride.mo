# expect: 14
# 二维 for-in 步长修复（v1.1085）：行 stride=24 非 2 次幂，不能 shl，必须 imul
fn main() -> i64 {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let s: i64 = 0;
    for row in m {
        s = s + row[0] + row[2];
    }
    return s;
}
