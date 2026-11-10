# expect: 98
import "io.mo";
# v1.1155: const fn 多参数 —— 支持最多 8 个 i64 参数、+ - * / % 全算术、
#          const fn 体可嵌套调用其它 const fn（编译期折叠）。
const fn hypot(a: i64, b: i64) -> i64 {
    return a * a + b * b;
}
const fn scale(a: i64, b: i64, k: i64) -> i64 {
    return hypot(a, b) * k;
}
const fn mix(a: i64, b: i64, c: i64, d: i64) -> i64 {
    return (a + b) * (c - d);
}
# const 声明里调用多参数 const fn（const_atom 折叠路径）
const BASE: i64 = hypot(3, 4) / 5;     # 25/5 = 5
fn main() -> i64 {
    let x: i64 = hypot(3, 4);        # 25
    let y: i64 = scale(3, 4, 2);     # 50
    let z: i64 = mix(1, 2, 10, 4);   # 18
    return x + y + z + BASE;         # 98
}