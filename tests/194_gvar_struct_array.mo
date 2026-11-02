# expect: 0
# 测试：全局结构体数组（v1.1030 回归入库）—— var G: [2] P;
struct P { x: i64; y: i64; }

var G: [2] P;

fn main() -> i64 {
    G[1].x = 7;
    return G[0].x + G[1].x - 7;
}
