# 测试：const 用作 case 标签（v1.977）+ switch 报错防死循环修复
# expect: 20
const ONE: i64 = 1;
const TWO: i64 = 2;

fn main() -> i64 {
    let x: i64 = 2;
    let r: i64 = 0;
    switch (x) {
        case ONE: r = 10;
        case TWO: r = 20;
        default: r = 99;
    }
    return r;
}
