# bignum —— 对标 Python 的任意精度计算
#
#   ./bignum
#
# Python 里这些是一行的事，而墨语言原本只有 i64，算 2^1000 会静默回绕：
#
#   Python:  2 ** 1000
#   Python:  math.factorial(100)
#   Python:  pow(2, 1000, 1009)
#   Python:  math.isqrt(2 ** 100)
#   Python:  math.gcd(...)
#
# 现在 lib/big.mo 与 lib/num.mo 提供了同样的能力。
# 本程序的每一项输出都由 tools/bignumtest.sh 与 Python 逐字节比对。
import "big.mo";
import "num.mo";
import "io.mo";

fn main() -> i64 {
    heap_init();

    # ---- 2^1000（Project Euler 16）----
    let two: i64 = big_from_i64(2);
    let p: i64 = big_pow(two, 1000);
    print("2^1000 = ");
    big_println(p);
    print("digits(2^1000) = ");
    print_i64(big_digits(p));
    print_nl();
    print("digitsum(2^1000) = ");
    print_i64(big_digit_sum(p));
    print_nl();

    # ---- 100! ----
    let f: i64 = big_fact(100);
    print("100! = ");
    big_println(f);
    print("digits(100!) = ");
    print_i64(big_digits(f));
    print_nl();

    # ---- fib(500) ----
    let fb: i64 = big_fib(500);
    print("fib(500) = ");
    big_println(fb);
    print("digits(fib(500)) = ");
    print_i64(big_digits(fb));
    print_nl();

    # ---- 除法与取模（Python 语义：向下取整）----
    let a: i64 = big_from_i64(0 - 7);
    let b: i64 = big_from_i64(3);
    print("(-7) // 3 = ");
    big_println(big_div(a, b));
    print("(-7) % 3 = ");
    big_println(big_mod(a, b));

    let c: i64 = big_from_i64(7);
    let d: i64 = big_from_i64(0 - 3);
    print("7 // (-3) = ");
    big_println(big_div(c, d));
    print("7 % (-3) = ");
    big_println(big_mod(c, d));

    # ---- gcd ----
    let g1: i64 = big_from_str("12345678901234567890");
    let g2: i64 = big_from_str("9876543210");
    print("gcd(12345678901234567890, 9876543210) = ");
    big_println(big_gcd(g1, g2));

    # ---- 模幂：Python pow(a, n, m) ----
    let base: i64 = big_from_i64(2);
    let m: i64 = big_from_i64(1009);
    print("pow(2, 1000, 1009) = ");
    # 指数参数类型是 i64，不是大数句柄 —— 传 big_from_i64(1000) 会静默算错
    big_println(big_modpow(base, 1000, m));

    # ---- 整数平方根 ----
    let sq: i64 = big_isqrt(p);
    print("isqrt(2^1000) = ");
    big_println(sq);
    print("isqrt(2^1000)^2 <= 2^1000 ? ");
    let chk: i64 = big_mul(sq, sq);
    if big_cmp(chk, p) <= 0 { print("yes"); } else { print("no"); }
    print_nl();

    # ---- 一个稍大的乘法，验证不是 i64 ----
    let x: i64 = big_from_str("99999999999999999999999999");
    let y: i64 = big_from_str("88888888888888888888888888");
    print("99999999999999999999999999 * 88888888888888888888888888 = ");
    big_println(big_mul(x, y));

    return 0;
}
