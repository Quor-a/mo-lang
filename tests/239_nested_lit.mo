# expect: 215
# 嵌套 struct 字面量（v1.1059）：字段值为内层字面量、多层嵌套、
# 嵌套字面量后的语句层字段整体赋值。
# 5+6+300+4000 = 4311 mod 256 = 215
struct Q { x: i64; y: i64; }
struct P { q: Q; n: i64; }
struct R { p: P; m: i64; }
fn main() -> i64 {
    let r: R = R { p: P { q: Q { x: 1; y: 2; }; n: 3; }; m: 4; };
    r.p.q = Q { x: 5; y: 6; };
    return r.p.q.x + r.p.q.y + r.p.n * 100 + r.m * 1000;
}
