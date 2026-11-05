# expect: 196
# v1.1140: str 负下标 s[-N] —— 运行时 strlen 换算，s[-1] = s[len-1]；
# 越界（|N| > len）运行时 panic（z28 单测 rc=1）
import "io.mo";
fn main() -> i64 {
    let s: str = "hello";
    let a: i64 = s[-1];
    let b: i64 = s[-5];
    return a * 100 + b;
}
