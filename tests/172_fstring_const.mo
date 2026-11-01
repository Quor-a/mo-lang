# expect: 0
# 测试：f-string 内嵌 const（v1.1010 回归入库）
import "io.mo";
import "str.mo";
const X: i64 = 77;

fn main() -> i64 {
    print(f"X={X}\n");
    return 0;
}
