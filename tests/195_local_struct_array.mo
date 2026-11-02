# expect: 0
# 测试：局部结构体数组无初始化（v1.1031 回归入库）
struct P { x: i64; y: i64; }

fn main() -> i64 {
    let a: [2] P;
    a[1].x = 8;
    return a[0].x + a[1].x - 8;
}
