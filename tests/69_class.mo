# 类：数据封装 + 继承 + 方法（C 风格显式 this）
# expect: 1
import "assert.mo";

class Rect {
    w: i64;
    h: i64;
}
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_perim(self: Rect) -> i64 { return (self.w + self.h) * 2; }
fn Rect_set(self: Rect, a: i64, b: i64) -> i64 {
    self.w = a;
    self.h = b;
    return 0;
}
fn Rect_grow(self: Rect, k: i64) -> i64 {
    self.w = self.w + k;
    return self.w;
}

# 继承：Shape 的字段在前，Square 的在后
class Shape { x: i64; y: i64; }
class Square : Shape { side: i64; }
fn Square_perim(self: Square) -> i64 { return self.side * 4; }
fn Square_where(self: Square) -> i64 { return self.x * 100 + self.y; }
fn Square_move(self: Square, dx: i64, dy: i64) -> i64 {
    self.x = self.x + dx;
    self.y = self.y + dy;
    return 0;
}

# byte 字段
class Buf { tag: byte; n: i64; }
fn Buf_tag(self: Buf) -> i64 { return self.tag; }

fn main() -> i64 {
    let r: Rect;
    r.w = 3;
    r.h = 4;
    assert_eq("area", Rect_area(&r), 12);
    assert_eq("perim", Rect_perim(&r), 14);
    # 方法能改状态，且改的是**同一个对象**
    assert_eq("set", Rect_set(&r, 5, 6), 0);
    assert_eq("after set w", r.w, 5);
    assert_eq("after set h", r.h, 6);
    assert_eq("area2", Rect_area(&r), 30);
    assert_eq("grow", Rect_grow(&r, 10), 15);
    assert_eq("grow visible", r.w, 15);

    # 继承：基类字段与派生类字段并存
    let s: Square;
    s.x = 1;
    s.y = 2;
    s.side = 10;
    assert_eq("perim", Square_perim(&s), 40);
    assert_eq("where", Square_where(&s), 102);
    assert_eq("move", Square_move(&s, 2, 3), 0);
    assert_eq("moved x", s.x, 3);
    assert_eq("moved y", s.y, 5);
    assert_eq("where2", Square_where(&s), 305);

    # byte 字段
    let b: Buf;
    b.tag = 65;
    b.n = 7;
    assert_eq("byte field", Buf_tag(&b), 65);
    assert_eq("after byte", b.n, 7);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
