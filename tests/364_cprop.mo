import "io.mo";
# 364: cprop 消费端（v1.1185）—— let 常量读直接发 movabs；被赋值过的变量真读；
#       控制流边界（emit_jcc/emit_jmp/place_label）清 K_CRBX/K_LAST。
fn main() -> i64 {
    let a: i64 = 5;
    let b: i64 = a * 2 + 1;      # a 从未写 → 常量读 11
    let i: i64 = 0;
    while i < 3 { i = i + 1; }   # i 被写 → 真读
    let c: i64 = 0;
    c = a + b;                    # 赋值后 c 失效，再读真读
    if c != 16 { return 1; }
    if b != 11 { return 2; }
    if i != 3 { return 3; }
    let d: i64 = 2;
    d = d * 8;                    # d 写过
    if d != 16 { return 4; }
    return 0;
}
