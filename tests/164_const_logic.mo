# expect: 1
# 测试：const 逻辑与/或（v1.1002）
const OK: i64 = 1 && 1;
const NO: i64 = 0 || 0;

fn main() -> i64 {
    return OK - NO;
}
