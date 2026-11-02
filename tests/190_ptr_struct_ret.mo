# expect: 77
# 测试：-> ptr P 返回类型（v1.1027）—— 通过返回指针修改全局结构体
struct P { x: i64; y: i64; }

var G: P;

fn get() -> ptr P {
    return &G;
}

fn main() -> i64 {
    let p: ptr P = get();
    p.x = 77;
    return G.x;
}
