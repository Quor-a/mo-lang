# expect: 5
# 嵌套字面量 + 前置比较表达式（v1.1064 修复）：内层 P{} 经
# emit_lit_struct 返回常量区地址，外层字段一律 g_struct_copy，
# R_SADDR 残留不再参与判定。修复前：q2.p 存地址 → 80。
struct P { x: i64; y: i64; }
struct Q { p: P; n: i64; }
fn main() -> i64 {
    let a: P = P { x: 1; y: 2; };
    let b: P = P { x: 1; y: 2; };
    if a != b { return 1; }
    let q2: Q = Q { p: P { x: 5; y: 5; }; n: 9; };
    return q2.p.x;   # 5
}
