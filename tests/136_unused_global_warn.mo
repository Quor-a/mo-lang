# 测试：-Wall 未使用全局变量警告（v1.972 续）
# 警告不影响编译产物与运行，默认（无 -Wall）完全静默。
# 警告行为人工验证：
#   $ moc -Wall t.mo out.elf
#   t.mo: warning: unused global 'dead_g'
#   （used_g 被 set_g 读写不报；main/函数不在此类）
import "io.mo";

var used_g: i64 = 5;
var dead_g: i64 = 9;

fn set_g() -> i64 {
    used_g = used_g + 1;
    return used_g;
}

fn main() -> i64 {
    print_i64(set_g());
    print_nl();
    return 0;
}
