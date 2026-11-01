# expect: 11
# 测试：const 混合优先级 + 重复定义报错（v1.991）
# (11%4)*4+255 = 267 → 267 mod 256 = 11；重复 const 在 errors/ 语义中另验。
const N: i64 = 11;
const R: i64 = (N % 4) * (1 << 2) + (0xF0 | 0x0F);

fn main() -> i64 {
    return R;
}
