# 测试：语法错误恢复（v1.971）—— 行为说明文档
# 恢复行为（人工验证）：含 garbage 行的版本编译报
#   <file>:3:1: error: syntax error   （exit=1）
# 但 elf 仍生成，正确部分照常运行（打印 42）。
# run.sh 对编译退出码非 0 的测试跳过执行，因此入库的是干净等价程序。
import "io.mo";

fn main() -> i64 {
    print_i64(42);
    print_nl();
    return 0;
}
