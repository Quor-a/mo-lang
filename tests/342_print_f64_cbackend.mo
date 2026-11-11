# expect: 12
# v1.1164: mo2x C 后端支持 f64↔i64 内建（fint/f64）—— print_f64 可用。
# 同时覆盖 ptr↔i64 隐式转换（str_dup/memcpy 等）。
import "io.mo";
fn main() -> i64 {
    let x: f64 = 2.5;
    let a: i64 = fint(x * 2.0);
    let b: i64 = fint((f64(3) + 0.5) * 2.0);
    print("f=");
    print_f64(3.14159);
    print("\n");
    return a + b;
}
