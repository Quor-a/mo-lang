# 二维数组示例（行主布局）
fn main() -> i64 {
    let m: [2][3] i64;
    let i: i64 = 0;
    while i < 2 {
        let j: i64 = 0;
        while j < 3 {
            m[i][j] = i * 10 + j;
            j = j + 1;
        }
        i = i + 1;
    }
    return m[1][2] * 2 + 48;   # 24 + 48 = 72
}
