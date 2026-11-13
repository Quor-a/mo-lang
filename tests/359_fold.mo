import "io.mo";
fn main() -> i64 {
    # 359: 双常量折叠（v1.1179）
    let a: i64 = 2 + 3 * 4;
    if a != 14 { return 1; }
    let b: i64 = 100 - 7 - 3;
    if b != 90 { return 2; }
    let c: i64 = 6 * 7 * 3;
    if c != 126 { return 3; }
    let d: i64 = (1 + 2) + (3 + 4);
    if d != 10 { return 4; }
    let e: i64 = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10;
    if e != 55 { return 5; }
    let f: i64 = 12 & 10;
    if f != 8 { return 6; }
    let g: i64 = 12 | 3;
    if g != 15 { return 7; }
    let h: i64 = 12 ^ 5;
    if h != 9 { return 8; }
    # 常量与变量混合（不得误折叠）
    let k: i64 = 5;
    let m: i64 = 2 + k * 3;
    if m != 17 { return 9; }
    print_i64(a); print_nl();
    return 0;
}
