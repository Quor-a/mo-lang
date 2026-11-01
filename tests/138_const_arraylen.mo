# 测试：const 用作数组长度（v1.975）
# expect: 5
const MAX: i64 = 8;

fn main() -> i64 {
    let a: [MAX] i64 = 0;
    a[7] = 5;
    return a[7];
}
