# expect: 111
# 测试：ptr null 检查习惯用法（v1.1029 回归入库）—— p != 0 / q == 0 / p == &r
struct P { x: i64; }

fn main() -> i64 {
    let r: P;
    let p: ptr P = &r;
    let q: ptr = 0;
    let a: i64 = 0;
    if p != 0 { a = a + 1; }
    if q == 0 { a = a + 10; }
    if p == &r { a = a + 100; }
    return a;
}
