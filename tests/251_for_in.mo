# expect: 163
# for-in 数组遍历（v1.1070）：一维元素遍历、break/continue、
# 二维外层遍历行（行变量是 ptr(标量)，行内 p[i] 按标量步索引）。
fn main() -> i64 {
    let a: [3] i64 = [1, 2, 3];
    let s: i64 = 0;
    for x in a {
        s = s + x;            # 6
    }
    let b: [4] i64 = [5, 6, 7, 8];
    for x in b {
        if x == 7 { break; }
        s = s + x;            # +5+6 = 17
    }
    for x in b {
        if x == 6 { continue; }
        s = s + x * 10;       # +50+70+80 = 217
    }
    let m: [2][2] i64 = [[1, 2], [3, 4]];
    for row in m {
        s = s + row[0] + row[1];   # +3+7 = 227
    }
    return s - 64;   # 227-64 = 163
}
