# expect: 11
# 测试：const 作 enum 显式值（v1.986）
const BASE: i64 = 10;
enum E { A = BASE; B; }

fn main() -> i64 {
    return E.B;
}
