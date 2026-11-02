# expect: 26
# struct 字面量作实参（v1.1053）：f(P { x: 5; y: 0; }) 双路径（调用+方法）。
# p.get() = 1 + 20 = 21；get2(P{5,0}) = 5 → 26
struct P { x: i64; y: i64; }
fn P_get(self: P) -> i64 {
    return self.x + self.y * 10;
}
fn get2(p: P) -> i64 {
    return p.x + p.y;
}
fn main() -> i64 {
    let p: P = P { x: 1; y: 2; };
    return p.get() + get2(P { x: 5; y: 0; });
}
