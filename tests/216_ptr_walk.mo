# expect: 6
# ptr 遍历（v1.1044）：字节步 p = p + 8；p[0] 元素步读当前 i64。
fn main() -> i64 {
    let a: [3] i64 = [1, 2, 3];
    let p: ptr i64 = a;
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 3 { s = s + p[0]; i = i + 1; p = p + 8; }
    return s;
}
