# expect: 0
# 测试：-Wall 常量条件告警（v1.1004）
# if (0) 在 -Wall 下告警但不影响运行；正常条件不告警。
fn main() -> i64 {
    if (0) { return 1; }
    return 0;
}
