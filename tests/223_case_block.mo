# expect: 45
# case 花括号块体（v1.1047）：parse_stmt 裸块分支；块内 let 局部作用域。
# x=3 → case 3 → y=5 → 45
fn main() -> i64 {
    let x: i64 = 3;
    switch (x) {
        case 1: { return 10; }
        case 3: { let y: i64 = 5; return y * 9; }
        default: { return 7; }
    }
    return 0;
}
