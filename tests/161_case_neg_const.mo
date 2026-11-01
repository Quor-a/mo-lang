# expect: 71
# 测试：case 数字路径后缀接 const（v1.999）case 0 - N
const N: i64 = 3;

fn f(x: i64) -> i64 {
    switch (x) {
        case 0 - N: return 7;
        default: return 1;
    }
    return 0;
}

fn main() -> i64 {
    return f(0 - 3) * 10 + f(0);
}
