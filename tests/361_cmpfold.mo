import "io.mo";
# 361: 双常量比较折叠（v1.1181）
fn main() -> i64 {
    if (2 + 3) == 5 { else_fail(0); } else { return 1; }
    if 3 < 10 { } else { return 2; }
    if 10 <= 3 { return 3; }
    if 7 > 7 { return 4; }
    if 7 >= 7 { } else { return 5; }
    if 4 != 4 { return 6; }
    if 4 != 5 { } else { return 7; }
    if 9 > 9 { return 8; }
    let b: i64 = (2 < 3) + (5 == 5) * 10;   # 11
    if b != 11 { return 9; }
    let neg: i64 = (3 > 10) + (1 >= 2) * 5; # 0
    if neg != 0 { return 10; }
    print_i64(b); print_nl();
    return 0;
}
fn else_fail(x: i64) -> i64 { return x; }
