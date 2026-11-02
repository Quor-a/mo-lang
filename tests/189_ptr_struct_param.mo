# expect: 110
# 测试：ptr P 形参（v1.1026）—— 跨函数通过指针修改结构体
struct P { x: i64; y: i64; }

fn bump(p: ptr P) -> i64 {
    p.x = p.x + 1;
    return p.x;
}

fn main() -> i64 {
    let r: P;
    r.x = 9;
    return bump(&r) * 10 + r.x;
}
