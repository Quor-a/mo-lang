# expect: 15
# 类型化指针 ptr i64 / ptr P（v1.1043）：形参与局部声明均支持；
# ptr i64 索引按元素步（p[1]=6），ptr P 字段访问 p.v=9。6+9=15。
fn g2(p: ptr i64) -> i64 { return p[1]; }

struct Bx { v: i64; }

fn gv(p: ptr Bx) -> i64 { return p.v; }

fn main() -> i64 {
    let a: [2] i64 = [5, 6];
    let b: Bx;
    b.v = 9;
    return g2(a) + gv(&b);
}
