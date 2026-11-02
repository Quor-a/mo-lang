# 编译期常量表达式示例（const 全集）
const MAX: i64 = 100;
const HALF: i64 = MAX / 2;
const MASK: i64 = 1 << 3 | 4;

fn main() -> i64 {
    let a: [HALF] i64;           # const 作数组长度
    a[0] = HALF + MASK;          # 50 + 12 = 62
    switch (HALF) {
        case 49: return 1;
        case HALF: return a[0] % 256;   # 62
        default: return 0;
    }
}
