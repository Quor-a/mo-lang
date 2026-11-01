# expect: 11
# 测试：字符串 == / != 比较（v1.1007 回归入库）
import "str.mo";

fn main() -> i64 {
    let a: i64 = 0;
    if ("ab" == "ab") { a = a + 1; }
    if ("ab" != "cd") { a = a + 10; }
    if ("ab" == "cd") { a = a + 100; }
    return a;
}
