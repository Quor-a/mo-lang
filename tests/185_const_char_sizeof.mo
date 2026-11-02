# expect: 139
# 测试：const 内字符字面量 + sizeof 混合（v1.1022 回归入库）
# 65 + 1*10 + 16*100 = 1675 → mod 256 = 139
const CA: i64 = 'A';
const CB: i64 = 'B' - 'A';
const SZ: i64 = sizeof(i64) * 2;

fn main() -> i64 {
    return CA + CB * 10 + SZ * 100;
}
