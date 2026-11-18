import "io.mo";
# 363: 常量 return 的函数边界 + 循环（v1.1184 epilogue K_LAST 清零修复的回归网）
fn c1() -> i64 { return 7; }
fn c2(n: i64) -> i64 { if n > 0 { return 3; } return 5; }
fn c3() -> i64 { return 0; }
fn main() -> i64 {
    let i: i64 = 0;
    while i < 3 { i = i + 1; }
    let s: i64 = c1() + c2(1) + c3();
    if i != 3 { return 1; }
    if s != 10 { return 2; }
    if c2(0 - 1) != 5 { return 3; }
    if c3() != 0 { return 4; }
    return 0;
}
