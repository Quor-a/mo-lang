# 测试：enum 值用于 const 表达式（v1.981）
# expect: 2
enum Color { RED; GREEN; }
const X: i64 = GREEN + 1;

fn main() -> i64 {
    return X;
}
