# expect: 5
# 295: struct 形参(引用语义) return 按值拷贝 —— 形参槽解引用一层 (v1.1111)
import "io.mo";
struct Inner { v: i64; }
fn use_it(x: Inner) -> Inner {
    return x;
}
fn main() -> i64 {
    let r: Inner = Inner { v: 5; };
    let r2: Inner = use_it(r);
    print_i64(r2.v);
    return r2.v;
}
