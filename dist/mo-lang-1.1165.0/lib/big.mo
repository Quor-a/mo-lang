# big —— 任意精度整数（用墨语言自己写的）
#
# 对标 Python 最标志性的计算能力：int 不溢出。
# 墨语言只有 i64，算 2^1000 或 100! 会静默回绕 ——
# 这正是本项目一贯要消灭的"安静地给出错的结果"。
#
# 表示：句柄指向堆上一块
#     [0]         len   有效 limb 数
#     [1]         neg   0=正 1=负
#     [2 + i]     limb i（低位在前，每 limb 4 位十进制）
#
# 为什么基数取 10^4 而不是 2^32：
#   1) 乘法 limb*limb+carry 最大约 10^8，在 i64 内绝对安全，不用 128 位
#   2) 打印/解析十进制不用做除法，直接 4 位一段
#   代价是空间与速度，但换来"不会静默算错"，这个交换是值的。
#
# 除法用二分试商：基数 10^4，试商范围 [0, 9999]，14 次比较即可定位。
# 比 Knuth D 慢，但好写、好验、不会错。
import "mem.mo";
import "io.mo";
import "str.mo";
import "err.mo";

var RADIX: i64 = 10000;
var LDIG:  i64 = 4;
var MAXL:  i64 = 1024;      # 单个大数最多 1024 个 limb = 4096 位十进制

# big_mod 的余数出口：墨语言没有多返回值，也没有元组
var BIG_REM: i64 = 0;

# ---------------- 底层 ----------------

fn big_alloc(n: i64) -> i64 {
    let p: i64 = alloc8(n + 2);
    store64(p, 0);
    store64(p + 8, 0);
    return p;
}

fn big_len(a: i64) -> i64 { return load64(a); }
fn big_neg(a: i64) -> i64 { return load64(a + 8); }
fn big_set_len(a: i64, n: i64) -> i64 { store64(a, n); return 0; }
fn big_set_neg(a: i64, n: i64) -> i64 { store64(a + 8, n); return 0; }
fn big_limb(a: i64, i: i64) -> i64 { return load64(a + 16 + i * 8); }
fn big_set_limb(a: i64, i: i64, v: i64) -> i64 { store64(a + 16 + i * 8, v); return 0; }

# 去掉前导零，并约定 0 没有符号
fn big_norm(a: i64) -> i64 {
    let n: i64 = big_len(a);
    while n > 0 {
        if big_limb(a, n - 1) != 0 { break; }
        n = n - 1;
    }
    big_set_len(a, n);
    if n == 0 { big_set_neg(a, 0); }
    return 0;
}

fn big_is_zero(a: i64) -> i64 {
    if big_len(a) == 0 { return 1; }
    return 0;
}

# dst = src（dst 必须有足够空间）
fn big_copy(dst: i64, src: i64) -> i64 {
    let n: i64 = big_len(src);
    let i: i64 = 0;
    while i < n {
        big_set_limb(dst, i, big_limb(src, i));
        i = i + 1;
    }
    big_set_len(dst, n);
    big_set_neg(dst, big_neg(src));
    return 0;
}

# ---------------- 构造 ----------------

fn big_zero() -> i64 { return big_alloc(4); }

fn big_from_i64(v: i64) -> i64 {
    let a: i64 = big_alloc(24);
    let neg: i64 = 0;
    let x: i64 = v;
    if x < 0 { neg = 1; x = 0 - x; }
    big_set_neg(a, neg);
    let n: i64 = 0;
    while x > 0 {
        big_set_limb(a, n, x % RADIX);
        x = x / RADIX;
        n = n + 1;
    }
    big_set_len(a, n);
    big_norm(a);
    return a;
}

# 从十进制字符串解析。带前导 '-' 表示负数。
fn big_from_str(s: ptr) -> i64 {
    let a: i64 = big_alloc(MAXL);
    let n: i64 = strlen(s);
    let neg: i64 = 0;
    let st: i64 = 0;
    if load8(s) == 45 { neg = 1; st = 1; }
    big_set_neg(a, neg);
    # 从右往左每 4 位一个 limb
    let i: i64 = n - 1;
    let li: i64 = 0;
    while i >= st {
        let v: i64 = 0;
        let mul: i64 = 1;
        let j: i64 = 0;
        while j < LDIG {
            if i - j < st { break; }
            let c: i64 = load8(s + i - j) - 48;
            v = v + c * mul;
            mul = mul * 10;
            j = j + 1;
        }
        big_set_limb(a, li, v);
        li = li + 1;
        i = i - LDIG;
    }
    big_set_len(a, li);
    big_norm(a);
    return a;
}

# ---------------- 比较 ----------------

# 比较绝对值：-1 / 0 / 1
fn big_cmp_abs(a: i64, b: i64) -> i64 {
    let na: i64 = big_len(a);
    let nb: i64 = big_len(b);
    if na > nb { return 1; }
    if na < nb { return -1; }
    let i: i64 = na - 1;
    while i >= 0 {
        let x: i64 = big_limb(a, i);
        let y: i64 = big_limb(b, i);
        if x > y { return 1; }
        if x < y { return -1; }
        i = i - 1;
    }
    return 0;
}

# 有符号比较
fn big_cmp(a: i64, b: i64) -> i64 {
    let na: i64 = big_neg(a);
    let nb: i64 = big_neg(b);
    if na == 1 {
        if nb == 0 { return -1; }
    } else {
        if nb == 1 { return 1; }
    }
    let c: i64 = big_cmp_abs(a, b);
    if na == 1 { return 0 - c; }
    return c;
}

fn big_eq(a: i64, b: i64) -> i64 {
    if big_cmp(a, b) == 0 { return 1; }
    return 0;
}

# ---------------- 加减 ----------------

fn big_add_abs(a: i64, b: i64) -> i64 {
    let na: i64 = big_len(a);
    let nb: i64 = big_len(b);
    let n: i64 = na;
    if nb > n { n = nb; }
    let r: i64 = big_alloc(n + 2);
    let carry: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let v: i64 = carry;
        if i < na { v = v + big_limb(a, i); }
        if i < nb { v = v + big_limb(b, i); }
        # v 最大 = 1 + (RADIX-1) + (RADIX-1)，减一次 RADIX 必落入 [0, RADIX)
        if v >= RADIX {
            big_set_limb(r, i, v - RADIX);
            carry = 1;
        } else {
            big_set_limb(r, i, v);
            carry = 0;
        }
        i = i + 1;
    }
    if carry == 1 {
        big_set_limb(r, n, 1);
        n = n + 1;
    }
    big_set_len(r, n);
    big_set_neg(r, 0);
    return r;
}

# |a| - |b|，要求 |a| >= |b|
fn big_sub_abs(a: i64, b: i64) -> i64 {
    let na: i64 = big_len(a);
    let nb: i64 = big_len(b);
    let r: i64 = big_alloc(na + 1);
    let borrow: i64 = 0;
    let i: i64 = 0;
    while i < na {
        let v: i64 = big_limb(a, i) - borrow;
        if i < nb { v = v - big_limb(b, i); }
        if v < 0 {
            v = v + RADIX;
            borrow = 1;
        } else {
            borrow = 0;
        }
        big_set_limb(r, i, v);
        i = i + 1;
    }
    big_set_len(r, na);
    big_set_neg(r, 0);
    big_norm(r);
    return r;
}

fn big_add(a: i64, b: i64) -> i64 {
    let na: i64 = big_neg(a);
    let nb: i64 = big_neg(b);
    if na == nb {
        let r: i64 = big_add_abs(a, b);
        big_set_neg(r, na);
        return r;
    }
    let c: i64 = big_cmp_abs(a, b);
    if c == 0 { return big_zero(); }
    if c > 0 {
        let r2: i64 = big_sub_abs(a, b);
        big_set_neg(r2, na);
        return r2;
    }
    let r3: i64 = big_sub_abs(b, a);
    big_set_neg(r3, nb);
    return r3;
}

fn big_sub(a: i64, b: i64) -> i64 {
    let na: i64 = big_neg(a);
    let nb: i64 = big_neg(b);
    if na != nb {
        let r: i64 = big_add_abs(a, b);
        big_set_neg(r, na);
        return r;
    }
    let c: i64 = big_cmp_abs(a, b);
    if c == 0 { return big_zero(); }
    if c > 0 {
        let r2: i64 = big_sub_abs(a, b);
        big_set_neg(r2, na);
        return r2;
    }
    let r3: i64 = big_sub_abs(b, a);
    big_set_neg(r3, 1 - nb);
    return r3;
}

# ---------------- 乘 ----------------

# 大数乘小整数（m < RADIX）
fn big_mul_small(a: i64, m: i64) -> i64 {
    let na: i64 = big_len(a);
    let r: i64 = big_alloc(na + 4);
    let carry: i64 = 0;
    let i: i64 = 0;
    while i < na {
        # limb*m + carry < 10^4*10^4 + 10^4，安全
        let v: i64 = big_limb(a, i) * m + carry;
        big_set_limb(r, i, v % RADIX);
        carry = v / RADIX;
        i = i + 1;
    }
    while carry > 0 {
        big_set_limb(r, i, carry % RADIX);
        carry = carry / RADIX;
        i = i + 1;
    }
    big_set_len(r, i);
    big_set_neg(r, 0);
    big_norm(r);
    return r;
}

fn big_mul(a: i64, b: i64) -> i64 {
    let na: i64 = big_len(a);
    let nb: i64 = big_len(b);
    if na == 0 { return big_zero(); }
    if nb == 0 { return big_zero(); }
    let n: i64 = na + nb;
    let r: i64 = big_alloc(n + 4);
    let i: i64 = 0;
    while i < n + 4 { big_set_limb(r, i, 0); i = i + 1; }
    i = 0;
    while i < na {
        let j: i64 = 0;
        while j < nb {
            let k: i64 = i + j;
            # 及时进位归约：每次累加后立即把值压回 [0, RADIX)，
            # 于是累加器里永远只有 limb*limb + 小量（< 10^8），
            # 不会因为 limb 数变多而溢出 i64。
            let v: i64 = big_limb(r, k) + big_limb(a, i) * big_limb(b, j);
            let c: i64 = v / RADIX;
            big_set_limb(r, k, v - c * RADIX);
            let v2: i64 = big_limb(r, k + 1) + c;
            let c2: i64 = v2 / RADIX;
            big_set_limb(r, k + 1, v2 - c2 * RADIX);
            let v3: i64 = big_limb(r, k + 2) + c2;
            if v3 >= RADIX {
                big_set_limb(r, k + 2, v3 - RADIX);
                big_set_limb(r, k + 3, big_limb(r, k + 3) + 1);
            } else {
                big_set_limb(r, k + 2, v3);
            }
            j = j + 1;
        }
        i = i + 1;
    }
    big_set_len(r, n + 1);
    big_set_neg(r, 0);
    # 符号：异号为负
    if big_neg(a) != big_neg(b) { big_set_neg(r, 1); }
    big_norm(r);
    return r;
}

# ---------------- 除 ----------------
#
# 长除法 + 二分试商。基数 10^4 → 试商范围 [0, 9999]，14 次比较定位一位。
#
# 余数出口：墨语言没有多返回值，所以 big_divmod 返回商，
# 余数放在全局 BIG_REM。调用 big_mod 即取它。

fn big_abs(a: i64) -> i64 {
    let r: i64 = big_alloc(big_len(a) + 4);
    big_copy(r, a);
    big_set_neg(r, 0);
    return r;
}

# |a| / |b|：返回商（非负），余数（非负）写入 BIG_REM
fn big_divmod_abs(a: i64, b: i64) -> i64 {
    let na: i64 = big_len(a);
    let q: i64 = big_alloc(na + 4);
    let i: i64 = 0;
    while i < na { big_set_limb(q, i, 0); i = i + 1; }
    big_set_len(q, na);
    big_set_neg(q, 0);

    let rem: i64 = big_alloc(na + 4);
    big_set_len(rem, 0);
    big_set_neg(rem, 0);

    i = na - 1;
    while i >= 0 {
        # rem = rem * RADIX + a[i]
        # 因为基数就是 RADIX，"乘 RADIX" 等于整体左移一位再填低位
        let nr: i64 = big_len(rem);
        let k: i64 = nr;
        while k > 0 {
            big_set_limb(rem, k, big_limb(rem, k - 1));
            k = k - 1;
        }
        big_set_limb(rem, 0, big_limb(a, i));
        big_set_len(rem, nr + 1);
        big_norm(rem);

        # 二分找最大的 t 使 b*t <= rem
        let lo: i64 = 0;
        let hi: i64 = RADIX - 1;
        let best: i64 = 0;
        while lo <= hi {
            let mid: i64 = (lo + hi) / 2;
            let t: i64 = big_mul_small(b, mid);
            if big_cmp_abs(t, rem) <= 0 {
                best = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        big_set_limb(q, i, best);
        if best > 0 {
            let s: i64 = big_mul_small(b, best);
            let d: i64 = big_sub_abs(rem, s);
            big_copy(rem, d);
        }
        i = i - 1;
    }
    big_norm(q);
    big_norm(rem);
    BIG_REM = rem;
    return q;
}

# 除法。采用 **Python 语义**（向下取整，余数与除数同号），
# 而不是 C 的截断：对标 Python 就该连取整方向都一致。
#   (-7) / 3  = -3， (-7) % 3  = 2
#     7 / (-3) = -3，  7 % (-3) = -2
fn big_divmod(a: i64, b: i64) -> i64 {
    if big_is_zero(b) == 1 {
        err_set(E_ARG, "division by zero", "big_divmod");
        BIG_REM = big_zero();
        return big_zero();
    }
    let q0: i64 = big_divmod_abs(a, b);
    let r0: i64 = BIG_REM;
    let na: i64 = big_neg(a);
    let nb: i64 = big_neg(b);

    if big_is_zero(r0) == 1 {
        big_set_neg(q0, 0);
        return q0;
    }
    if na == nb {
        big_set_neg(q0, 0);
        big_set_neg(r0, na);
        return q0;
    }
    # 异号且余数非零 → 向下取整：
    #   q = -(q0 + 1)
    #   r = 除数符号 * (|b| - r0)
    let one: i64 = big_from_i64(1);
    let q: i64 = big_add_abs(q0, one);
    big_set_neg(q, 1);
    let bb: i64 = big_alloc(big_len(b) + 4);
    big_copy(bb, b);
    big_set_neg(bb, 0);
    let r: i64 = big_sub_abs(bb, r0);
    big_set_neg(r, nb);
    BIG_REM = r;
    return q;
}

fn big_div(a: i64, b: i64) -> i64 { return big_divmod(a, b); }
fn big_mod(a: i64, b: i64) -> i64 {
    big_divmod(a, b);
    return BIG_REM;
}

# ---------------- 转字符串与打印 ----------------

# 写一个 4 位十进制，不足补前导零（最高位段除外）
fn put4(p: i64, v: i64) -> i64 {
    let t: [24] byte = 0;
    utoa(v, &t, 10);
    let l: i64 = strlen(&t);
    let i: i64 = 0;
    while i < 4 - l {
        store8(p + i, 48);
        i = i + 1;
    }
    strcpy(p + (4 - l), &t);
    return 0;
}

fn big_to_str(a: i64, buf: i64) -> i64 {
    let n: i64 = big_len(a);
    let p: i64 = buf;
    if big_neg(a) == 1 {
        store8(p, 45);
        p = p + 1;
    }
    if n == 0 {
        store8(p, 48);
        store8(p + 1, 0);
        return 0;
    }
    # 最高段不补零
    let top: [24] byte = 0;
    utoa(big_limb(a, n - 1), &top, 10);
    strcpy(p, &top);
    p = p + strlen(&top);
    let i: i64 = n - 2;
    while i >= 0 {
        put4(p, big_limb(a, i));
        p = p + 4;
        i = i - 1;
    }
    store8(p, 0);
    return 0;
}

var BP_BUF: [4096] byte = 0;

fn big_print(a: i64) -> i64 {
    big_to_str(a, &BP_BUF);
    print(&BP_BUF);
    return 0;
}

fn big_println(a: i64) -> i64 {
    big_print(a);
    print_nl();
    return 0;
}
