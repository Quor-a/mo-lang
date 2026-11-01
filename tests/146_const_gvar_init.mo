# 测试：const 表达式作全局 var 初始化器（v1.984）
# expect: 200
const MAX: i64 = 100;
var SZ: i64 = MAX * 2;

fn main() -> i64 {
    return SZ;
}
