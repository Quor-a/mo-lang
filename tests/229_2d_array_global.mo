# expect: 15
# 全局二维数组遍历（v1.1050）：B[i][j] = i*3+j 求和 = 0+1+2+3+4+5 = 15
var B: [2][3] i64 = 0;
fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 2 { let j: i64 = 0; while j < 3 { B[i][j] = i * 3 + j; j = j + 1; } i = i + 1; }
    i = 0;
    while i < 2 { let j: i64 = 0; while j < 3 { s = s + B[i][j]; j = j + 1; } i = i + 1; }
    return s;
}
