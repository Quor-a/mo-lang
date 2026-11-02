# expect: 161
# 测试：取结构体字段地址 &r.x（v1.1023）—— p[8]=7 改 y
struct P { x: i64; y: i64; }

fn main() -> i64 {
    let r: P;
    r.x = 41;
    let p: ptr = &r.x;
    p[8] = 7;
    return r.x * 10 + r.y;
}
