# expect: 30
# 全局 struct 字面量初始化（v1.1091）：var G: P = P { x: 1; y: 2; };
struct P { x: i64; y: i64; }

var G: P = P { x: 1; y: 2; };

fn bump() -> i64 {
    G.x = G.x + 1;
    return G.x;
}

fn main() -> i64 {
    bump();
    return bump() * 10;
}
