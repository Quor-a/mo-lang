# expect: 17
# 数组值比较 == / !=（v1.1063）：逐 word 累积比较（sete r10b; and r11b）
# + invert 取反（xor r11b,1）。同时修复 struct 比较只看最后一 word 的 bug。
# 7 + 10 + 100 = 117
fn main() -> i64 {
    let a: [3] i64;
    a[0] = 1; a[1] = 2; a[2] = 3;
    let b: [3] i64;
    b[0] = 1; b[1] = 2; b[2] = 3;
    let c: [3] i64;
    c[0] = 1; c[1] = 9; c[2] = 3;
    let r: i64 = 0;
    if a == b { r = r + 7; }
    if a != c { r = r + 10; }
    if a == c { r = r + 1000; }
    if a != b { r = r + 10000; }
    return r;   # 17
}
