# expect: 2
# const 数组（v1.1046）：const A: [3] i64 = [...]，数据段常量区 + 运行时下标。
const A: [3] i64 = [1, 2, 3];
fn main() -> i64 {
    return A[1];
}
