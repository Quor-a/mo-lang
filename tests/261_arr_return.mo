# expect: 79
# 函数返回数组（v1.1079）：fn mk() -> [3] i64; return 数组变量; let q: [3] i64 = mk();（rax=数组地址约定；返回全局/静态数组）
var g: [3] i64 = [7, 8, 9];

fn mk() -> [3] i64 {
    return g;
}

fn main() -> i64 {
    let q: [3] i64 = mk();
    return q[0] + q[2] * 8;
}
