# expect: 102
# 测试：取数组元素地址 &a[i]（v1.1024）—— p = &a[1]; p[8] 写 a[2]
fn main() -> i64 {
    let a: [3] i64 = [1, 2, 3];
    let p: ptr = &a[1];
    p[8] = 99;
    return a[0] + a[1] + a[2];
}
