# 86 —— 方法调用语法糖 obj.method(args)
#
# 之前只能写 C 风格 Rect_area(&r)；现在可以 r.area()。
# 关键是它**不能破坏字段赋值** self.w = a;（两者都以 `ident .` 开头）。
#
# 覆盖两个位置：
#   语句位置：r.set(5, 6);
#   表达式位置：let a = r.area();  /  r.area() + 1  /  if r.area() == 30
import "assert.mo";

class Rect {
    w: i64;
    h: i64;
}
fn Rect_set(self: Rect, a: i64, b: i64) -> i64 {
    self.w = a;
    self.h = b;
    return 0;
}
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_zero(self: Rect) -> i64 {
    self.w = 0;
    self.h = 0;
    return 0;
}

# 继承
class Shape { x: i64; y: i64; }
class Square : Shape { side: i64; }
fn Square_perim(self: Square) -> i64 { return self.side * 4; }
fn Square_where(self: Square) -> i64 { return self.x * 100 + self.y; }

fn main() -> i64 {
    let r: Rect;
    r.set(5, 6);
    assert_eq("set w", r.w, 5);
    assert_eq("set h", r.h, 6);
    assert_eq("area", Rect_area(&r), 30);

    # 零参方法
    r.zero();
    assert_eq("zero w", r.w, 0);

    # 字段赋值仍可用（与方法调用同以 `x .` 开头）
    r.w = 3;
    r.h = 4;
    assert_eq("area again", Rect_area(&r), 12);

    # 继承来的类也能用方法语法
    let s: Square;
    s.side = 7;
    s.x = 1;
    s.y = 2;
    assert_eq("perim", Square_perim(&s), 28);
    assert_eq("where", Square_where(&s), 102);

    # 表达式参数
    r.set(1 + 1, 2 * 3);
    assert_eq("expr w", r.w, 2);
    assert_eq("expr h", r.h, 6);

    # 表达式位置（1.43.1）：let a = r.area();
    r.set(5, 6);
    let a: i64 = r.area();
    assert_eq("expr pos", a, 30);
    let b: i64 = r.area() + 1;
    assert_eq("expr arith", b, 31);
    if r.area() == 30 { assert_eq("expr cond", 1, 1); }
    else { assert_eq("expr cond", 0, 1); }
    return test_done();
}
