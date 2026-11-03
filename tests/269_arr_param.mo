# expect: 6
# 数组形参（v1.1087）：fn sum(a: [3] i64) —— 按 ptr(元素) 传入
fn sum(a: [3] i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 3 {
        s = s + a[i];
        i = i + 1;
    }
    return s;
}

fn main() -> i64 {
    let a: [3] i64 = [1,2,3];
    return sum(a);
}
