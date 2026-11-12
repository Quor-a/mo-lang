# expect: 85
# 重载嵌套与结合性：((a+b)*b) + (a-b)
struct Vec2 { x: i64; y: i64; }
fn Vec2_add(self: Vec2, o: Vec2) -> Vec2 {
    let r: Vec2;
    r.x = self.x + o.x;
    r.y = self.y + o.y;
    return r;
}
fn Vec2_sub(self: Vec2, o: Vec2) -> Vec2 {
    let r: Vec2;
    r.x = self.x - o.x;
    r.y = self.y - o.y;
    return r;
}
fn Vec2_mul(self: Vec2, o: Vec2) -> Vec2 {
    let r: Vec2;
    r.x = self.x * o.x;
    r.y = self.y * o.y;
    return r;
}
fn mk(x: i64, y: i64) -> Vec2 {
    let v: Vec2;
    v.x = x;
    v.y = y;
    return v;
}
fn main() -> i64 {
    let a: Vec2 = mk(10, 20);
    let b: Vec2 = mk(1, 2);
    let s: Vec2 = a + b;        # (11,22)
    let m: Vec2 = s * b;        # (11,44)
    let d: Vec2 = a - b;        # (9,18)
    let t: Vec2 = m + d;        # (20,62)
    return t.x + t.y + b.x + b.y;  # 85
}
