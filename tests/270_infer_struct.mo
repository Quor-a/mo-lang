# expect: 43
# 推断 let + struct 返回值（v1.1088）：let p = mk(); 两字寄存器返回值按 rax/rdx 落槽
struct P { x: i64; y: i64; }

fn mk() -> P {
    let r: P = P { x: 3; y: 4; };
    return r;
}

fn main() -> i64 {
    let p = mk();
    return p.x + p.y*10;
}
