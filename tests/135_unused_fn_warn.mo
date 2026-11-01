# 测试：-Wall 未使用函数警告（v1.972）
# 警告不影响编译产物与运行，默认（无 -Wall）完全静默。
# 本测试验证 main 正常性；警告行为人工验证：
#   $ moc -Wall t.mo out.elf
#   t.mo: warning: unused function 'dead_fn'
#   （used_fn/main 不报；extern 与 import 的库函数不报）
import "io.mo";

fn used_fn() -> i64 { return 7; }
fn dead_fn() -> i64 { return 8; }

fn main() -> i64 {
    print_i64(used_fn());
    print_nl();
    return 0;
}
