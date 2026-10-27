# expect: 222
# import A 再 import B：helper 绑定到 B（最后被处理）
import "ambA.mo";
import "ambB.mo";
fn main() -> i64 {
    return helper();
}
