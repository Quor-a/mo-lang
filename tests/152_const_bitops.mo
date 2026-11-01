# expect: 228
# 测试：const 位运算 & | ^（v1.990）
# (0xF0 & 0x3C)=48, (0xF0 ^ 0x3C)=204, 48*10+204%100=484 → 484 mod 256 = 228
const F: i64 = 0xF0;
const M: i64 = 0x3C;

fn main() -> i64 {
    return (F & M) * 10 + (F ^ M) % 100;
}
