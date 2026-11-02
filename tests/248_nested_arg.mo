# expect: 135
# 嵌套 struct 字面量作函数实参（v1.1067）：get(Q { p: P {...}; n: .. })
# —— emit_lit_struct 字段值为 struct 时逐 word 整块拷贝（存地址 bug 修复）。
# 123 + 12 = 135
struct P { x: i64; y: i64; }
struct Q { p: P; n: i64; }
fn get(q: Q) -> i64 { return q.p.x * 100 + q.p.y * 10 + q.n; }
fn main() -> i64 {
    let r1: i64 = get(Q { p: P { x: 1; y: 2; }; n: 3; });
    let q2: Q = Q { p: P { x: 5; y: 6; }; n: 1; };
    return r1 + q2.p.x + q2.p.y + q2.n;
}
