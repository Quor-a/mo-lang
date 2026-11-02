# expect: 15
# 测试：数组作 ptr 参数传递（ptr 索引按字节, a[i*8]）（v1.1015 回归入库）
fn sum(a: ptr, n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n { s = s + a[i * 8]; i = i + 1; }
    return s;
}

fn main() -> i64 {
    let t: [5] i64 = [1, 2, 3, 4, 5];
    return sum(t, 5);
}
