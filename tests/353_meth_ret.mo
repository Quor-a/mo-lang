
class P { x: i64; y: i64; }
fn mk(x: i64, y: i64) -> P {
    let p: P;
    p.x = x;
    p.y = y;
    return p;
}
fn P_sum(self: ptr) -> i64 { return load64(self) + load64(self + 8); }
fn main() -> i64 {
    let p: P = mk(3, 4);
    let s: i64 = p.x + p.y;          # 7
    let q: P = mk(10, 20);
    s = s + q.x * q.y;               # +200 = 207
    s = s + mk(30, 12).sum();        # +42 = 249
    if s != 249 { return 1; }
    return 0;
}
