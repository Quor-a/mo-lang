# expect: 207
# 测试：字符字面量与整数比较/运算（v1.1013 回归入库）—— 2511 mod 256 = 207
fn main() -> i64 {
    let a: i64 = 0;
    if 'A' == 65 { a = a + 1; }
    if 'A' < 'B' { a = a + 10; }
    let c: i64 = 'z' - 'a';
    a = a + c * 100;
    return a;
}
