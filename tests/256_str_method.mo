# expect: 11
# 字符串方法语法（v1.1074）：库自由函数作方法 —— s.trim() → str_trim(s)。
import "str.mo";

fn main() -> i64 {
    let s: str = "hello world";
    let r: i64 = 0;
    if s.contains("wor") { r = r + 1; }
    if s.starts_with("hel") { r = r + 10; }
    if s.ends_with("xyz") { r = r + 100; }
    return r;
}
