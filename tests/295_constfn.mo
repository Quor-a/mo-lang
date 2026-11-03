# expect: 16
# v1.1112: const fn —— 编译期折叠（单参数，体仅字面量/参数/算术）
import "io.mo";

const fn sq(x: i64) -> i64 {
    return x * x;
}

const fn cube(x: i64) -> i64 {
    return x * sq(x);
}

fn main() -> i64 {
    let a: i64 = sq(4);
    print_i64(a);
    let b: i64 = cube(2);
    print_i64(b);
    return a;
}
