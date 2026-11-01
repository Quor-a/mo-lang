# expect: 3
# 测试：-Wall 未使用 const 警告（v1.987）
# DEAD 只在 -Wall 下告警，不影响编译与运行；USED 正常折叠。
const DEAD: i64 = 1;
const USED: i64 = 3;

fn main() -> i64 {
    return USED;
}
