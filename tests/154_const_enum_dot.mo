# expect: 2
# 测试：const 表达式 enum 点访问（v1.992）
enum E { A; B; }
const X: i64 = E.B + 1;

fn main() -> i64 {
    return X;
}
