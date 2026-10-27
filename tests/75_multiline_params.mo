# 75 —— 函数参数列表可以跨行写
#
# 曾经的 bug：predeclare() 数形参个数时遇到换行写成了 `j = j - 1`，
# 而循环末尾还有 `j = j + 1`，一减一加原地不动 → **编译器无限循环**。
# 症状是 moc 挂死且无任何输出（连报错都没有），极难自己排查。
fn sum3(a: i64, b: i64,
        c: i64) -> i64 {
    return a + b + c;
}

# 更极端：每个参数各占一行
fn sum4(a: i64,
        b: i64,
        c: i64,
        d: i64) -> i64 {
    return a + b + c + d;
}

# 换行在右括号前
fn id1(x: i64
) -> i64 {
    return x;
}

fn main() -> i64 {
    if sum3(1, 2, 3) != 6 { return 1; }
    if sum4(1, 2, 3, 4) != 10 { return 1; }
    if id1(7) != 7 { return 1; }
    return 0;
}
