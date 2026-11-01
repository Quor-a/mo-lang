# expect: 0
# 测试：f-string 表达式插值（v1.1009 回归入库）—— {n + 1} 完整表达式
import "io.mo";
import "str.mo";

fn main() -> i64 {
    let n: i64 = 41;
    print(f"n={n + 1}!\n");
    return 0;
}
