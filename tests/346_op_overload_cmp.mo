# expect: 19
# 比较重载全集 + 无重载类型走原逻辑
struct P { x: i64; y: i64; }
fn P_eq(self: P, o: P) -> i64 {
    if self.x == o.x {
        if self.y == o.y { return 1; }
    }
    return 0;
}
fn P_ne(self: P, o: P) -> i64 {
    let e: i64 = P_eq(self, o);
    if e == 1 { return 0; }
    return 1;
}
fn P_le(self: P, o: P) -> i64 {
    if self.x < o.x { return 1; }
    if self.x == o.x {
        if self.y <= o.y { return 1; }
    }
    return 0;
}
fn mk(x: i64, y: i64) -> P {
    let v: P;
    v.x = x;
    v.y = y;
    return v;
}
fn main() -> i64 {
    let a: P = mk(1, 2);
    let b: P = mk(1, 2);
    let c: P = mk(3, 9);
    let e: i64 = 0;
    if a != c { e = e + 1; }        # 1
    if a <= c { e = e + 2; }        # 2
    if c <= c { e = e + 16; }       # 16
    if c < a { e = e + 100; }       # no
    return e + 0;
}
