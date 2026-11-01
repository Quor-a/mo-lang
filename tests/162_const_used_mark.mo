# expect: 3
# 测试：case/数组长度使用 const 标记 used（v1.1000）——A 被 case 用不报 unused；
# DEAD 未使用仍报；局部数组 const 长度正常。
const A: i64 = 3;
const DEAD: i64 = 1;

fn f(x: i64) -> i64 {
    switch (x) {
        case A: return 3;
        default: return 1;
    }
    return 0;
}

fn main() -> i64 {
    return f(3);
}
