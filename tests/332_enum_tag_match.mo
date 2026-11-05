# expect: 25
import "io.mo";
# v1.1152: enum 判别式的数字/区间臂按 tag 匹配（此前 rax 是 variant
# struct 指针，数字/区间臂永不命中——真 bug 修复）
enum C { A(i64); B(i64); }
fn main() -> i64 {
    let a = C.A(9);
    let b = C.B(2);
    let r: i64 = 0;
    # 数字臂: A(tag 0) → 5
    let x: i64 = match a {
        0 => 5,
        _ => 0,
    };
    if x == 5 { r = r + 1; }
    # 区间臂: B(tag 1) ∈ 1..3 → 25
    let y: i64 = match b {
        1..3 => 25,
        _ => 0,
    };
    if y == 25 { r = r + 25; }
    # r = 26 时数字臂与区间臂都按 tag 正确命中
    if r == 26 { return 25; }
    return 99;
}
