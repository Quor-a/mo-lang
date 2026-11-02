# expect: 21
# 字符串 switch（v1.1047）：逐 case g_str_eq 内容比较，r11 保判别串。
# "cat" → r=2 → 21
fn main() -> i64 {
    let s: str = "cat";
    let r: i64 = 0;
    switch (s) {
        case "dog": { r = 1; }
        case "cat": { r = 2; }
        case "bird": { r = 3; }
        default: { r = 9; }
    }
    return r * 10 + 1;
}
