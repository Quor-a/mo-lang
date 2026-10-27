# 93 —— 接口（interface）与运行时动态分派
#
# 设计：接口值就是 { obj; vt } 两个字段的结构体，于是不需要动类型系统、
# 也不需要 IR —— 结构体 + 函数指针 + obj.method() 语法糖拼起来即可。
# vt 由 impl 自动生成，其中的函数地址在**全部解析结束后**回填。
import "assert.mo";

interface Shape {
    fn area(self: ptr) -> i64;
    fn perim(self: ptr) -> i64;
}
interface Talker {
    fn say(self: ptr, n: i64) -> i64;
}

class Rect {
    w: i64;
    h: i64;
}
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_perim(self: Rect) -> i64 { return (self.w + self.h) * 2; }

class Sq {
    s: i64;
}
fn Sq_area(self: Sq) -> i64 { return self.s * self.s; }
fn Sq_perim(self: Sq) -> i64 { return self.s * 4; }
fn Sq_say(self: Sq, n: i64) -> i64 { return self.s * n; }

impl Shape for Rect { area; perim; }
impl Shape for Sq { area; perim; }
impl Talker for Sq { say; }

fn main() -> i64 {
    let r: Rect;
    r.w = 3;
    r.h = 4;
    let q: Sq;
    q.s = 5;

    # 同一个变量、同一行调用，运行时走不同的实现
    let a: Shape;
    a.obj = &r;
    a.vt = &Shape_Rect_vt;
    assert_eq("rect area", a.area(), 12);
    assert_eq("rect perim", a.perim(), 14);

    a.obj = &q;
    a.vt = &Shape_Sq_vt;
    assert_eq("sq area", a.area(), 25);
    assert_eq("sq perim", a.perim(), 20);

    # 带额外实参的接口方法
    let t: Talker;
    t.obj = &q;
    t.vt = &Talker_Sq_vt;
    assert_eq("sq say", t.say(3), 15);

    # 方法顺序不必与接口声明一致（按名字索引进 vt）
    assert_eq("sq perim", a.perim(), 20);
    return test_done();
}
