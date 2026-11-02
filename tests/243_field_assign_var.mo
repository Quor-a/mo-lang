# expect: 22
# 语句层字段整体赋值（struct 变量）r.f = q2（v1.1062）：字段基地址
# 真 push、源 movabs+mov rdi、pop rsi、逐 word 内联拷贝。全局/局部源均支持。
# 5+6+6+5 = 22
struct Q { x: i64; y: i64; }
struct R { q: Q; m: i64; }
var gq: Q;
fn main() -> i64 {
    let q2: Q = Q { x: 5; y: 6; };
    let r: R;
    r.q = q2;
    gq = q2;
    let r2: R;
    r2.q = gq;
    return r.q.x + r.q.y + r2.q.y + gq.x;
}
