# expect: 42
# 测试：局部 const 声明（v1.989）
const B: i64 = 40;

fn main() -> i64 {
    const L: i64 = B + 2;
    return L;
}
