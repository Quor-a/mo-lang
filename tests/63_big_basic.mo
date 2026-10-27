# 任意精度整数：四则运算与比较
# expect: 1
import "big.mo";
import "num.mo";
import "assert.mo";

fn main() -> i64 {
    heap_init();

    # 加法：结果超出 i64 也能对
    let a: i64 = big_from_i64(12345);
    let b: i64 = big_from_str("987654321987654321");
    assert_eq("add", big_cmp(big_add(a, b), big_from_str("987654321987666666")), 0);

    # 减法（含借位）
    assert_eq("sub", big_cmp(big_sub(b, a), big_from_str("987654321987641976")), 0);
    # 减法得负
    assert_eq("sub_neg", big_cmp(big_sub(a, b), big_from_str("-987654321987641976")), 0);

    # 乘法
    assert_eq("mul", big_cmp(big_mul(a, b), big_from_str("12192592604937592592745")), 0);
    # 负数乘法
    assert_eq("mul_neg", big_cmp(big_mul(big_from_i64(-3), big_from_i64(7)), big_from_i64(-21)), 0);
    assert_eq("mul_neg2", big_cmp(big_mul(big_from_i64(-3), big_from_i64(-7)), big_from_i64(21)), 0);

    # 除法：Python 语义（向下取整，余数与除数同号）
    assert_eq("div1", big_cmp(big_div(big_from_i64(-7), big_from_i64(3)), big_from_i64(-3)), 0);
    assert_eq("mod1", big_cmp(big_mod(big_from_i64(-7), big_from_i64(3)), big_from_i64(2)), 0);
    assert_eq("div2", big_cmp(big_div(big_from_i64(7), big_from_i64(-3)), big_from_i64(-3)), 0);
    assert_eq("mod2", big_cmp(big_mod(big_from_i64(7), big_from_i64(-3)), big_from_i64(-2)), 0);
    # 整除
    assert_eq("div3", big_cmp(big_div(big_from_i64(100), big_from_i64(10)), big_from_i64(10)), 0);
    assert_eq("mod3", big_cmp(big_mod(big_from_i64(100), big_from_i64(10)), big_from_i64(0)), 0);

    # 比较
    assert_eq("cmp_gt", big_cmp(big_from_i64(5), big_from_i64(3)), 1);
    assert_eq("cmp_lt", big_cmp(big_from_i64(3), big_from_i64(5)), -1);
    assert_eq("cmp_eq", big_cmp(big_from_i64(5), big_from_i64(5)), 0);
    assert_eq("cmp_neg", big_cmp(big_from_i64(-5), big_from_i64(3)), -1);

    # 零
    assert_eq("zero", big_is_zero(big_from_i64(0)), 1);
    assert_eq("zero2", big_is_zero(big_sub(big_from_i64(5), big_from_i64(5))), 1);

    # 字符串往返
    let s: [128] byte = 0;
    big_to_str(big_from_str("-12345678901234567890"), &s);
    assert_eq("roundtrip", streq(&s, "-12345678901234567890"), 1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
