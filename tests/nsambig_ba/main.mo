# expect: 111
# import B 再 import A：helper 绑定到 A —— 与 ab 版只差 import 顺序
import "ambB.mo";
import "ambA.mo";
fn main() -> i64 {
    return helper();
}
