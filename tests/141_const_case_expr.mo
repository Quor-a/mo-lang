# 测试：case 表达式 const A + 1（v1.979）
# expect: 10
const A: i64 = 1;

fn main() -> i64 {
    let x: i64 = 2;
    switch (x) {
        case A + 1: return 10;
    }
    return 0;
}
