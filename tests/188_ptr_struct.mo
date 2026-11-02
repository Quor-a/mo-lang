# expect: 5
# 测试：ptr P 指向结构体的指针类型 + p.x 字段访问（v1.1025）
struct P { x: i64; y: i64; }

fn main() -> i64 {
    let r: P;
    r.x = 5;
    let p: ptr P = &r;
    return p.x;
}
