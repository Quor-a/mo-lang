# expect: 3
# 测试：-Wall while 常量条件告警（v1.1005）
# while (0) 告警不影响运行；正常 while 不告警。
fn main() -> i64 {
    let i: i64 = 0;
    while (i < 3) { i = i + 1; }
    return i;
}
