# expect: 64
# 测试：编译期 sizeof 进 const 表达式（v1.993）
const S: i64 = sizeof([8] i64);

fn main() -> i64 {
    return S;
}
