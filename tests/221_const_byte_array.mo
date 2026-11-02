# expect: 145
# const byte 数组（v1.1046）：[72,73] 尾部补零，ptr byte 读前两字节 72+73=145。
const T: [4] byte = [72, 73];
fn main() -> i64 {
    let p: ptr byte = T;
    return p[0] + p[1];
}
