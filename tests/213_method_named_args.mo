# expect: 115
# 方法命名实参（v1.1042）：c.add(d: 1) → self=5, d=1, e 补默认 10。
# self 传址：5 + 1*100 + 10 = 115
struct C { n: i64; }

fn C_add(self: C, d: i64 = 3, e: i64 = 10) -> i64 {
    self.n = self.n + d * 100 + e;
    return self.n;
}

fn main() -> i64 {
    let c: C;
    c.n = 5;
    return c.add(d: 1);
}
