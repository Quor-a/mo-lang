# expect: 42
# 测试：ptr P 链式嵌套字段访问 p.i.v（v1.1028 回归入库）
struct Inner { v: i64; }
struct Outer { i: Inner; w: i64; }

fn main() -> i64 {
    let o: Outer;
    o.i.v = 42;
    let p: ptr Outer = &o;
    return p.i.v + p.w;
}
