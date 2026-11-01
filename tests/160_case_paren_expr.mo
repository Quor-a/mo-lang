# expect: 91
# 测试：case 括号表达式 + 后缀折叠（v1.998）case (N * 2) - 1
const N: i64 = 5;

fn f(x: i64) -> i64 {
    switch (x) {
        case (N * 2) - 1: return 9;
        default: return 1;
    }
    return 0;
}

fn main() -> i64 {
    return f(9) * 10 + f(0);
}
