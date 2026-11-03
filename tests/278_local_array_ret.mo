# expect: 28
# v1.1096: 局部数组返回 —— 拷入隐藏全局缓冲后返回地址（v1.1089 硬错的解除）
import "io.mo";

fn mk() -> [4] i64 {
    let a: [4] i64 = [1, 2, 3, 4];
    a[0] = a[0] * 10;
    return a;
}

fn sum(a: [4] i64) -> i64 {
    return a[0] + a[3];
}

fn main() -> i64 {
    let x: [4] i64 = mk();
    let s1: i64 = sum(x);
    let y: [4] i64 = mk();
    let s2: i64 = sum(y);
    print_i64(s1);
    print_i64(s2);
    return s1 + s2;
}
