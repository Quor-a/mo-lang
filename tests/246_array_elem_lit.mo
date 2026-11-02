# expect: 16
# 数组元素 struct 字面量赋值（v1.1065）：a[i] = P { x: ..; y: ..; };
# 逐字段直接 store 元素地址+偏移；未赋值元素保持 0。
# 3+4+9 = 16
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let a: [2] P;
    a[0] = P { x: 3; y: 4; };
    a[1] = P { x: 9; y: 0; };
    return a[0].x + a[0].y + a[1].x;
}
