# num —— 大数的数论与常用计算（对标 Python 的 math / 内建 pow）
#
#   Python            墨语言
#   ----------------  ----------------------
#   a ** n             big_pow(a, n)
#   pow(a, n, m)       big_modpow(a, n, m)
#   math.gcd(a, b)     big_gcd(a, b)
#   math.factorial(n)  big_fact(n)
#   math.isqrt(n)      big_isqrt(n)
#
# 没有浮点类型，所以 math.sin / log / sqrt(浮点) 这一类**不做**；
# 需要小数的场景请用 lib/matrix.mo 与 lib/stat.mo 的定点（SCALE=1000）。
import "big.mo";
import "random.mo";

# 快速幂：a^n，n >= 0
fn big_pow(a: i64, n: i64) -> i64 {
    let r: i64 = big_from_i64(1);
    let base: i64 = big_alloc(big_len(a) + 4);
    big_copy(base, a);
    let e: i64 = n;
    while e > 0 {
        if (e & 1) == 1 {
            r = big_mul(r, base);
        }
        e = e / 2;
        if e > 0 {
            base = big_mul(base, base);
        }
    }
    return r;
}

# 指数也可以是**大数**的模幂。RSA 解密指数 d 通常是大数，所以这个版本不能省。
# 代价：每次迭代要做一次大数除法，比 i64 版本慢很多。
fn big_modpow_big(a: i64, e: i64, m: i64) -> i64 {
    let r: i64 = big_from_i64(1);
    let base: i64 = big_mod(a, m);
    let two: i64 = big_from_i64(2);
    let ee: i64 = big_alloc(big_len(e) + 4);
    big_copy(ee, e);
    while big_is_zero(ee) == 0 {
        # 取最低位：ee mod 2
        let bit: i64 = big_mod(ee, two);
        if big_is_zero(bit) == 0 {
            r = big_mod(big_mul(r, base), m);
        }
        ee = big_div(ee, two);
        if big_is_zero(ee) == 0 {
            base = big_mod(big_mul(base, base), m);
        }
    }
    return r;
}

# 模幂：(a^n) mod m，指数 n 是 **i64**（不是大数句柄！）。
#
# 注意：句柄与整数在墨语言里都是 i64，编译器分不清。
# 传 big_from_i64(n) 进去不会报错，只会静默算成 a^(那个地址) mod m ——
# 本库的第一个版本就栽在这里。需要大指数请用 big_modpow_big。
# 每步都取模，所以中间结果的大小始终与 m 相当 ——
# 这正是"先算 a^n 再取模"做不到的事（那个中间值会有天文数字位）。
fn big_modpow(a: i64, n: i64, m: i64) -> i64 {
    let r: i64 = big_from_i64(1);
    let base: i64 = big_mod(a, m);
    let e: i64 = n;
    while e > 0 {
        if (e & 1) == 1 {
            r = big_mod(big_mul(r, base), m);
        }
        e = e / 2;
        if e > 0 {
            base = big_mod(big_mul(base, base), m);
        }
    }
    return r;
}

# 欧几里得算法
fn big_gcd(a: i64, b: i64) -> i64 {
    let x: i64 = big_abs(a);
    let y: i64 = big_abs(b);
    while big_is_zero(y) == 0 {
        let t: i64 = big_mod(x, y);
        x = y;
        y = t;
    }
    return x;
}

fn big_fact(n: i64) -> i64 {
    let r: i64 = big_from_i64(1);
    let i: i64 = 2;
    while i <= n {
        # big_mul_small 要求乘数 < RADIX(10000)，超了就走通用乘法
        if i < 10000 {
            r = big_mul_small(r, i);
        } else {
            r = big_mul(r, big_from_i64(i));
        }
        i = i + 1;
    }
    return r;
}

fn big_fib(n: i64) -> i64 {
    let a: i64 = big_from_i64(0);
    let b: i64 = big_from_i64(1);
    let i: i64 = 0;
    while i < n {
        let t: i64 = big_add(a, b);
        a = b;
        b = t;
        i = i + 1;
    }
    return a;
}

# 10^k。用作 isqrt 的迭代初值。
fn big_pow10(k: i64) -> i64 {
    let r: i64 = big_from_i64(1);
    let i: i64 = 0;
    while i < k {
        r = big_mul_small(r, 10);
        i = i + 1;
    }
    return r;
}

# 整数平方根：floor(sqrt(n))
#
# 牛顿迭代 + **收敛后再修正**。只靠迭代会在边界差一，
# 所以最后两段循环把结果夹到 x^2 <= n < (x+1)^2 —— 这点修正不能省。
fn big_isqrt(n: i64) -> i64 {
    if big_is_zero(n) == 1 { return big_from_i64(0); }
    if big_neg(n) == 1 { return big_from_i64(0); }
    let d: i64 = big_len(n) * 4;
    let x: i64 = big_pow10(d / 2 + 1);
    let two: i64 = big_from_i64(2);
    let i: i64 = 0;
    while i < 64 {
        let q: i64 = big_div(n, x);
        let nx: i64 = big_div(big_add(x, q), two);
        if big_cmp(nx, x) >= 0 {
            x = nx;
            break;
        }
        x = nx;
        i = i + 1;
    }
    let one: i64 = big_from_i64(1);
    # 向下修正
    while 1 {
        if big_cmp(big_mul(x, x), n) > 0 {
            x = big_sub(x, one);
        } else {
            break;
        }
    }
    # 向上修正
    while 1 {
        if big_cmp(big_mul(big_add(x, one), big_add(x, one)), n) <= 0 {
            x = big_add(x, one);
        } else {
            break;
        }
    }
    return x;
}

# 各位数字之和（Project Euler 16 就是 2^1000 的这个值）
fn big_digit_sum(a: i64) -> i64 {
    let n: i64 = big_len(a);
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let v: i64 = big_limb(a, i);
        while v > 0 {
            s = s + (v % 10);
            v = v / 10;
        }
        i = i + 1;
    }
    return s;
}

# 十进制位数
fn big_digits(a: i64) -> i64 {
    let n: i64 = big_len(a);
    if n == 0 { return 1; }
    let top: i64 = big_limb(a, n - 1);
    let d: i64 = (n - 1) * 4;
    while top > 0 {
        d = d + 1;
        top = top / 10;
    }
    return d;
}

# 费马素性测试（概率性）：k 轮全通过则"可能是素数"。
#
# 如实标注为**费马**测试而不是 Miller-Rabin：它会被卡迈克尔数骗过
# （最小的例子是 561）。写 Miller-Rabin 需要分解 n-1 = d*2^s，
# 代码量翻倍 —— 这里先做对、做清楚，不假装更强。
fn big_is_probable_prime(n: i64, k: i64) -> i64 {
    let two: i64 = big_from_i64(2);
    let one: i64 = big_from_i64(1);
    if big_cmp(n, two) < 0 { return 0; }
    if big_cmp(n, two) == 0 { return 1; }
    if big_cmp(big_mod(n, two), big_from_i64(0)) == 0 { return 0; }

    let nm1: i64 = big_sub(n, one);
    let i: i64 = 0;
    while i < k {
        # 底数取 [2, n-2] 之间的随机数
        let a: i64 = big_mod(big_from_i64(rand_range_i64(1000000)), nm1);
        if big_cmp(a, one) <= 0 { a = two; }
        # 费马条件：a^(n-1) ≡ 1 (mod n)
        let r: i64 = big_modpow_big(a, nm1, n);
        if big_cmp(r, one) != 0 { return 0; }
        i = i + 1;
    }
    return 1;
}
