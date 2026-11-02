# expect: 27
# 方法调用缺省实参（v1.1041）：c.add(1) 补 e=10；self 传址，c.n 累积。
# add(1): 5+100+10=115；add(1,2): 115+100+2=217 → 115+217000=217115 mod 256 = 27
struct C { n: i64; }

fn C_add(self: C, d: i64 = 3, e: i64 = 10) -> i64 {
    self.n = self.n + d * 100 + e;
    return self.n;
}

fn main() -> i64 {
    let c: C;
    c.n = 5;
    return c.add(1) + c.add(1, 2) * 1000;
}
