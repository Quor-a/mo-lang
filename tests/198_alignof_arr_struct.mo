# expect: 88
# 测试：alignof 数组类型与结构体（v1.1034 回归入库）
struct P { x: i64; y: i64; }

fn main() -> i64 {
    return alignof([4] i64) * 10 + alignof(P);
}
