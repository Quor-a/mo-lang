# expect: 65
# 推断 let + struct 字面量/struct 变量（v1.1088）：rax=地址 → 块拷
struct P { x: i64; y: i64; }

fn main() -> i64 {
    let a = P { x: 5; y: 6; };
    let c = a;
    return c.x + c.y*10;
}
