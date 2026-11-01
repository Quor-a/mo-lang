# 测试：const 一元负号/正号（v1.976）
# expect: 15
const NEG: i64 = -5;
const P: i64 = -NEG * 3;

fn main() -> i64 {
    return P;
}
