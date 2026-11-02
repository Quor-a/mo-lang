# expect: 138
# 数组解构 let [x, y, z] = arr;（v1.1073）：逐元素拷贝。
# 3210 mod 256 = 138
fn main() -> i64 {
    let a: [3] i64 = [10, 20, 30];
    let [x, y, z] = a;
    return x + y * 10 + z * 100;
}
