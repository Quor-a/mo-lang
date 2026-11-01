# expect: 8
# 测试：编译期 alignof 进 const 表达式（v1.995）
const S: i64 = alignof([3] i64);

fn main() -> i64 {
    return S;
}
