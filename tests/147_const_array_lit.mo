# expect: 196
# 测试：const/enum 作数组字面量元素（v1.985, 708 mod 256）
const A: i64 = 7;
var T: [3] i64 = [A, 2, A + 1];

fn main() -> i64 {
    return T[0] * 100 + T[2];
}
