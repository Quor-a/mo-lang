# expect: 24
# 测试：数组字段宽度计入 sizeof（v1.1035，3×8=24）
struct Inner { v: [3] i64; }

fn main() -> i64 {
    return sizeof(Inner);
}
