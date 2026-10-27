# 141 —— 泛型 trait bound
#
#  泛型本来是**结构化**匹配的：只要类型碰巧有个同名方法，instantiate 就放行。
#  实测过：Sneaky 从没 `impl Shape`，只要定义了 Sneaky_area / Sneaky_perim，
#  `instantiate pg(Sneaky)` 照样编译通过并运行（输出 12）。
#
#  trait bound 把契约改成**名义**的：必须显式 impl 才算实现了接口。
#  写法 <T: Shape> / <T: Shape + Tag> / <T: Shape, U>。
#
#  负例不在这个文件里 —— 它们必须编译失败，由 tools/tbtest.sh 单独跑。
import "assert.mo";

interface Shape {
    fn area(self: ptr) -> i64;
    fn perim(self: ptr) -> i64;
}
interface Tag {
    fn tag(self: ptr) -> i64;
}

class Rect { w: i64; h: i64; }
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_perim(self: Rect) -> i64 { return (self.w + self.h) * 2; }
fn Rect_tag(self: Rect) -> i64 { return 77; }
impl Shape for Rect { area; perim; }
impl Tag for Rect { tag; }

class Sq { s: i64; }
fn Sq_area(self: Sq) -> i64 { return self.s * self.s; }
fn Sq_perim(self: Sq) -> i64 { return self.s * 4; }
impl Shape for Sq { area; perim; }

# ---- 1. 基本 bound：同一份泛型，两个类型 ----
generic fn perimg<T: Shape>(a: T) -> i64 { return a.perim(); }
instantiate perimg(Rect) as perim_rect;
instantiate perimg(Sq) as perim_sq;

# ---- 2. 多 bound：<T: Shape + Tag> ----
generic fn tagg<T: Shape + Tag>(a: T) -> i64 { return a.tag(); }
instantiate tagg(Rect) as tag_rect;

# ---- 3. 多类型参数，只给第一个加 bound ----
generic fn pickg<T: Shape, U>(a: T, b: U) -> i64 { return a.area(); }
instantiate pickg(Rect, i64) as pick_ri;

# ---- 4. 前向引用：impl 出现在 instantiate 之后 ----
#  bound 检查推迟到全部解析结束后才做，所以顺序无关。
class Tri { b: i64; h: i64; }
fn Tri_area(self: Tri) -> i64 { return self.b * self.h / 2; }
fn Tri_perim(self: Tri) -> i64 { return self.b + self.h + self.b; }
generic fn areag<T: Shape>(a: T) -> i64 { return a.area(); }
instantiate areag(Tri) as area_tri;
impl Shape for Tri { area; perim; }

# ---- 5. 回归：不带 bound 的泛型照旧 ----
generic fn nog<T>(a: T) -> i64 { return a.area(); }
instantiate nog(Rect) as nog_rect;

fn main() -> i64 {
    let r: Rect;
    r.w = 3;
    r.h = 4;
    let q: Sq;
    q.s = 5;
    let t: Tri;
    t.b = 6;
    t.h = 7;

    # 非空转守卫：两个类型的 perim 必须**不同**。
    # 否则上面两条断言可能只是"两个 instantiate 绑到了同一份实现"。
    assert_eq("rect perim", perim_rect(r), 14);
    assert_eq("sq perim", perim_sq(q), 20);

    assert_eq("rect area via bound", area_tri(t), 21);
    assert_eq("two bounds", tag_rect(r), 77);
    assert_eq("bound on first only", pick_ri(r, 9), 12);
    assert_eq("no bound still works", nog_rect(r), 12);

    # 同一泛型、两个类型：结果必须不同（单态化没退化成动态分派）
    if perim_rect(r) == perim_sq(q) { assert_eq("monomorph distinct", 0, 1); }
    return test_done();
}
