# expect: 80
# 测试：sizeof 数组类型与结构体（v1.1033 回归入库）
# 32*10 + 16 = 336 → mod 256 = 80
struct P { x: i64; y: i64; }

fn main() -> i64 {
    return sizeof([4] i64) * 10 + sizeof(P);
}
