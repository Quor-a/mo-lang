# expect: 21
# struct 解构（v1.1081）：let P { x, y } = r; —— 字段逐一 load 到新栈槽。
struct P { x: i64; y: i64; }

fn main() -> i64 {
    let r: P = P { x: 1; y: 2; };
    let P { x, y } = r;
    return x + y*10;
}
