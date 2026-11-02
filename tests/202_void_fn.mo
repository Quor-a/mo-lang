# expect: 3
# 测试：void 函数（v1.1036）—— 省略 "-> i64"，无 return
struct I2 { a: i64; }

fn fvoid(p: ptr I2) { p.a = 3; }

fn main() -> i64 {
    let s: I2;
    fvoid(&s);
    return s.a;
}
