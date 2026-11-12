# expect: 7
struct P { x: i64; y: i64; }
fn P_gt(self: P, o: P) -> i64 {
    if self.x > o.x { return 1; }
    if self.x == o.x {
        if self.y > o.y { return 1; }
    }
    return 0;
}
fn P_ge(self: P, o: P) -> i64 {
    if self.x > o.x { return 1; }
    if self.x == o.x {
        if self.y >= o.y { return 1; }
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
    let a: P = mk(3, 9);
    let b: P = mk(1, 2);
    let c: P = mk(3, 9);
    let e: i64 = 0;
    if a > b { e = e + 1; }         # 1
    if a >= c { e = e + 2; }        # 2
    if a > c { e = e + 100; }       # no
    if b >= c { e = e + 100; }      # no
    if c > b { e = e + 4; }         # 4
    return e;
}
