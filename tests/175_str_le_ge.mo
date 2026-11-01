# expect: 87
# 测试：字符串 <= >= 比较（v1.1012 回归入库）—— 1111 mod 256 = 87
import "str.mo";

fn main() -> i64 {
    let a: i64 = 0;
    if ("abc" <= "abc") { a = a + 1; }
    if ("abc" >= "abc") { a = a + 10; }
    if ("abd" >= "abc") { a = a + 100; }
    if ("abb" <= "abc") { a = a + 1000; }
    return a;
}
