# struct 字面量全家示例（let/实参/赋值/返回）
struct P { x: i64; y: i64; }

fn get(p: P) -> i64 {
    return p.x + p.y * 10;
}

fn mk() -> P {
    return P { x: 1; y: 2; };
}

fn main() -> i64 {
    let a: P = P { x: 3; y: 4; };    # let 初始化
    let b: P = mk();                  # 返回字面量
    a = P { y: 6; x: 5; };            # 赋值字面量（乱序）
    return a.x + a.y + b.x * 100 + get(P { x: 7; y: 0; });
    # 5 + 60 + 100 + 7 = 172
}
