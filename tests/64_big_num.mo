# 数论与常用计算：对标 Python 的 pow / math.*
# expect: 1
import "big.mo";
import "num.mo";
import "assert.mo";

fn main() -> i64 {
    heap_init();

    # 2^1000：i64 绝对装不下
    let p: i64 = big_pow(big_from_i64(2), 1000);
    assert_eq("digits", big_digits(p), 302);
    assert_eq("digitsum", big_digit_sum(p), 1366);

    # 幂的小例子
    assert_eq("pow", big_cmp(big_pow(big_from_i64(3), 40), big_from_str("12157665459056928801")), 0);
    assert_eq("pow0", big_cmp(big_pow(big_from_i64(7), 0), big_from_i64(1)), 0);

    # 阶乘
    assert_eq("fact20", big_cmp(big_fact(20), big_from_str("2432902008176640000")), 0);
    assert_eq("fact0", big_cmp(big_fact(0), big_from_i64(1)), 0);

    # 斐波那契
    assert_eq("fib0", big_cmp(big_fib(0), big_from_i64(0)), 0);
    assert_eq("fib1", big_cmp(big_fib(1), big_from_i64(1)), 0);
    assert_eq("fib10", big_cmp(big_fib(10), big_from_i64(55)), 0);
    assert_eq("fib500_digits", big_digits(big_fib(500)), 105);

    # gcd
    assert_eq("gcd1", big_cmp(big_gcd(big_from_str("12345678901234567890"), big_from_str("9876543210")), big_from_i64(90)), 0);
    assert_eq("gcd2", big_cmp(big_gcd(big_from_i64(12), big_from_i64(18)), big_from_i64(6)), 0);
    assert_eq("gcd0", big_cmp(big_gcd(big_from_i64(0), big_from_i64(7)), big_from_i64(7)), 0);

    # 模幂（指数是 i64）
    assert_eq("modpow", big_cmp(big_modpow(big_from_i64(2), 1000, big_from_i64(1009)), big_from_i64(942)), 0);
    assert_eq("modpow2", big_cmp(big_modpow(big_from_i64(5), 3, big_from_i64(13)), big_from_i64(8)), 0);
    # 大指数版本
    assert_eq("modpowbig", big_cmp(big_modpow_big(big_from_i64(2), big_from_i64(1000), big_from_i64(1009)), big_from_i64(942)), 0);

    # 整数平方根：floor(sqrt(2^100)) = 2^50
    let q: i64 = big_pow(big_from_i64(2), 100);
    assert_eq("isqrt", big_cmp(big_isqrt(q), big_pow(big_from_i64(2), 50)), 0);
    # 非完全平方数：floor(sqrt(10)) = 3
    assert_eq("isqrt10", big_cmp(big_isqrt(big_from_i64(10)), big_from_i64(3)), 0);
    assert_eq("isqrt0", big_cmp(big_isqrt(big_from_i64(0)), big_from_i64(0)), 0);
    assert_eq("isqrt1", big_cmp(big_isqrt(big_from_i64(1)), big_from_i64(1)), 0);
    # 边界：完全平方数本身
    assert_eq("isqrt_sq", big_cmp(big_isqrt(big_from_i64(81)), big_from_i64(9)), 0);
    # 边界：完全平方数减一（牛顿法最容易在这里差一）
    assert_eq("isqrt_sqm1", big_cmp(big_isqrt(big_from_i64(80)), big_from_i64(8)), 0);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
