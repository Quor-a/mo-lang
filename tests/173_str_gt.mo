# expect: 1
# 测试：字符串字典序比较 >（v1.1011 回归入库）
import "str.mo";

fn main() -> i64 {
    if ("abc" > "abb") { return 1; }
    return 0;
}
