# expect: 6
# 294: 前向 struct 类型（v1.1110）—— 签名引用 + 定义复用；ptr 自引用
import "io.mo";
struct Node { v: i64; next: ptr Node; }
fn sum_list(p: ptr Node) -> i64 {
    if p == 0 { return 0; }
    return p.v + sum_list(p.next);
}
fn main() -> i64 {
    let c: Node = Node { v: 3; next: 0; };
    let b: Node = Node { v: 2; next: &c; };
    let a: Node = Node { v: 1; next: &b; };
    let s: i64 = sum_list(&a);
    print_i64(s);
    return s;
}
