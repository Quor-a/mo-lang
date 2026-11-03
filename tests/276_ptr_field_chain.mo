# expect: 6
# v1.1094: struct 字段可为指针类型（自引用链表）+ 链式 ptr 字段访问 a.next.next.v
import "io.mo";
struct Node { v: i64; next: ptr Node; }

fn main() -> i64 {
    let c: Node = Node { v: 3; next: 0; };
    let b: Node = Node { v: 2; next: &c; };
    let a: Node = Node { v: 1; next: &b; };
    print_i64(a.next.next.v);
    let s: i64 = 0;
    let p: ptr Node = &a;
    while p != 0 {
        s = s + p.v;
        p = p.next;
    }
    return s;
}
