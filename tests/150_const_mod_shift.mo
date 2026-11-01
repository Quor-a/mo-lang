# expect: 18
# 测试：const 取模与移位（v1.988）13%4=1, 1<<3=8 → 1*10+8=18
const N: i64 = 13;
const M: i64 = N % 4;
const S: i64 = 1 << 3;

fn main() -> i64 {
    return M * 10 + S;
}
