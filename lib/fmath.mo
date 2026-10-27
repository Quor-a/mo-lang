# fmath —— f64 数学库（**不依赖 libc**，全部用 f64 算术 + 位操作实现）
#
# ── 为什么自己实现 ──────────────────────────────────────────
#   墨语言此前只有 f64 的 + - * / 与比较，没有 sqrt / exp / log / sin。
#   调 libc 也能有，但那要链接器、要 PLT，且**不是自己的实现**。
#   这里全部自实现，好处是行为可预测：**每个函数的误差都可测**。
#
# ── 依赖的两个内建 ──────────────────────────────────────────
#   fbits(x)     取 IEEE754 位模式（不转换）
#   ffrombits(x) 位模式 → f64（不转换）  ← 本版新增
#   有了后者才能做 ldexp / frexp：改指数字段即可乘 2^k，
#   不需要循环乘（1e300 时循环要跑 500 次）。
#
# ── 精度口径 ────────────────────────────────────────────────
#   所有函数与 Python（C library，正确舍入）逐点比对，
#   误差用 **ULP** 表示（位模式的整数距离），不用相对误差
#   —— 后者在接近 0 处会失真。
#
# ── 已知限制（实测，见 docs/fmath.md）──────────────────────
#   · sin/cos 在 |x| ≤ 2^21 全程 ≤1 ulp（8 个量级逐档实测）。
#     ⚠️ 这条**曾经是 bug**：早期用 π/2 的最近双精度值做分裂，
#        k·(π/2) 不精确，2^21 时误差 4.9e7 ulp，当时被记成"固有损失"。
#        实际是 fdlibm 的低位清零分裂没做（见 fm_pio2_hi 的注释）。
#        → 教训：把"误差随某参数增长"写成已知限制前，先确认它修不了。
#     超出 2^21 未测：k 需 <2^25 才能保证 k·pio2_hi 精确。
#   · 次正规数（denormal）一律返回 0，不保证精度。
#   · pow 走 exp(b·log a)，整数指数不特判，误差略大于 libc。

import "io.mo";

# ── 位模式常量 ──────────────────────────────────────────────
# ⚠️ 0x8000000000000000 超出 i64 正值域，写成 0 - 9223372036854775807 - 1
var FM_EXPMASK: i64 = 0x7ff;
var FM_MANT: i64 = 4503599627370495;          # 0x000fffffffffffff
# ⚠️ 0x8000000000000000 无法写成字面量（超出 i64 正值域），
#    fm_ldexp 里就地用 0 - 9223372036854775807 - 1 计算。

# ── 全局临时（循环变量一律专用，避免被嵌套调用抹掉）────────
# ⚠️ 本项目已多次栽在"共享临时被嵌套调用冲掉"上：不报错、不崩溃，
#    只是结果悄悄变错。凡跨调用存活的值都不许放共享临时。
var FMI: i64 = 0;
var FMJ: i64 = 0;
var FMK: i64 = 0;
var FME: i64 = 0;      # fm_ldexp / fm_exp 内部：指数
var FMP: i64 = 0;      # fm_pow 快速幂的指数（循环内 let 会累积栈帧）
var FMN: i64 = 0;      # 牛顿迭代计数


# ── 高精度常量 ──────────────────────────────────────────────
# 🔴 编译器解析浮点字面量时**小数最多 8 位**（f64_bits 里的 `fdn > 8` 截断），
#    所以 0.693147180559945309... 会被读成 0.69314718 —— 相对误差 1e-9，
#    对数学库是灾难性的，而且**不报错**，只是结果悄悄不准。
#    修法：常量一律用 **IEEE754 位模式**构造（ffrombits），精度与 C 库一致。
fn fm_ln2() -> f64        { return ffrombits(0x3fe62e42fefa39ef); }
fn fm_log2e() -> f64      { return ffrombits(0x3ff71547652b82fe); }
fn fm_inv_ln10() -> f64   { return ffrombits(0x3fdbcb7b1526e50d); }
# ln2 拆两段（hi 的低 32 位为 0），供 exp / log 抵消 k·ln2 的表示误差
fn fm_ln2_hi() -> f64     { return ffrombits(0x3fe62e42fee00000); }
fn fm_ln2_lo() -> f64     { return ffrombits(0x3dea39ef35793c76); }
# 🔴 π/2 的分裂**不能**用"π/2 的最近双精度值 + 余项"。
#    最近双精度值（0x3ff921fb54442d18）53 位全有效，k 乘上去就不精确了：
#    ulp(k·π/2) ≈ 2^(21−52) ≈ 4.7e−10，这个误差**直接进归约结果**，
#    实测 |x|=2^21 时 sin 误差 4.9e7 ulp（约 1e−8 绝对误差）。
#    正解是 fdlibm 的分裂：把低位清零，使 k·pio2_hi 在 k<2^25 时**精确**
#    （有效位 28 + k 的 25 位 ≤ 53），剩下的残差交给 pio2_lo。
#    实测：k·pio2_hi 对 k ≤ 2^21 逐点精确。
fn fm_pio2_hi() -> f64    { return ffrombits(0x3ff921fb54000000); }
fn fm_pio2_lo() -> f64    { return ffrombits(0x3e110b4611a62633); }
fn fm_2opi() -> f64       { return ffrombits(0x3fe45f306dc9c883); }
fn fm_sqrt2() -> f64      { return ffrombits(0x3ff6a09e667f3bcd); }
# 2^52：fm_trunc 的"整数已无法再精确表示"阈值
fn fm_p52() -> f64        { return ffrombits(0x4330000000000000); }

# ── 分类 ────────────────────────────────────────────────────
# 🔴 `v != v` 是 NaN 判据的**唯一**写法（IEEE754 unordered）。
#    1.114 之前编译器生成的 f64 比较**不处理 unordered**，
#    于是 nan == nan 得 1、nan != nan 得 0 —— 所有 isnan 静默失效。
fn fm_isnan(v: f64) -> i64 {
    if v != v { return 1; }
    return 0;
}
fn fm_isinf(v: f64) -> i64 {
    let b: i64 = fbits(v);
    if (b & 0x7fffffffffffffff) == 0x7ff0000000000000 { return 1; }
    return 0;
}
fn fm_isfinite(v: f64) -> i64 {
    let b: i64 = fbits(v);
    if ((b >> 52) & FM_EXPMASK) == FM_EXPMASK { return 0; }
    return 1;
}
fn fm_signbit(v: f64) -> i64 {
    if fbits(v) < 0 { return 1; }
    return 0;
}

fn fm_nan() -> f64 { return ffrombits(0x7ff8000000000000); }
fn fm_inf() -> f64 { return ffrombits(0x7ff0000000000000); }

# ── 符号与取整 ──────────────────────────────────────────────
fn fm_fabs(x: f64) -> f64 {
    if x < 0.0 { return 0.0 - x; }
    return x;
}
fn fm_copysign(x: f64, y: f64) -> f64 {
    if fm_signbit(x) == fm_signbit(y) { return x; }
    return 0.0 - x;
}

# 截断向零（fint 的语义）
fn fm_trunc(x: f64) -> f64 {
    if fm_isfinite(x) == 0 { return x; }
    if fm_fabs(x) >= fm_p52() { return x; }
    return f64(fint(x));
}
fn fm_floor(x: f64) -> f64 {
    if fm_isfinite(x) == 0 { return x; }
    let t: f64 = fm_trunc(x);
    if t > x { return t - 1.0; }
    return t;
}
fn fm_ceil(x: f64) -> f64 {
    if fm_isfinite(x) == 0 { return x; }
    let t: f64 = fm_trunc(x);
    if t < x { return t + 1.0; }
    return t;
}
# 四舍五入，半值远离零
fn fm_round(x: f64) -> f64 {
    if fm_isfinite(x) == 0 { return x; }
    return fm_trunc(x + fm_copysign(0.5, x));
}

fn fm_fmod(a: f64, b: f64) -> f64 {
    if fm_isnan(a) == 1 { return a; }
    if fm_isnan(b) == 1 { return b; }
    if fm_isinf(b) == 1 {
        if fm_isinf(a) == 1 { return fm_nan(); }
        return a;
    }
    if b == 0.0 { return fm_nan(); }
    let q: f64 = fm_floor(a / b);
    return a - q * b;
}

# ── 指数拆解（frexp / ldexp）────────────────────────────────
# 返回 x 的二进制指数：x = m · 2^e，m ∈ [1, 2)
fn fm_exponent(x: f64) -> i64 {
    let b: i64 = fbits(x);
    let e: i64 = (b >> 52) & FM_EXPMASK;
    if e == 0 { return 0 - 1022; }     # 0 或次正规
    # 🔴 偏置是 1023，不是 1022。第一版写错时 fm_exponent(8.0) 得 4，
    #    fm_log / fm_sqrt 的 m 规约区间整体错一位 —— 不报错、不崩溃，
    #    只是 log 结果差几万 ulp（实测 log2(8) 差 32920 ulp）。
    return e - 1023;
}
# m · 2^e —— 直接改指数字段，O(1)，不像循环乘那样与 e 成正比
fn fm_ldexp(m: f64, e: i64) -> f64 {
    if m == 0.0 { return m; }
    let b: i64 = fbits(m);
    let ex: i64 = (b >> 52) & FM_EXPMASK;
    if ex == 0 { return 0.0; }             # 次正规：本库不保证
    if ex == FM_EXPMASK { return m; }      # inf / nan 原样返回
    let ne: i64 = ex + e;
    if ne < 1 { return 0.0; }
    if ne > 2046 { return fm_inf(); }
    let nb: i64 = (b & FM_MANT) | (ne << 52);
    if b < 0 { nb = nb | (0 - 9223372036854775807 - 1); }
    return ffrombits(nb);
}

# ── sqrt ────────────────────────────────────────────────────
# 先折半指数把 x 规约到 [1, 4)，牛顿迭代 4 次（二次收敛，
# 初始估计 (m+1)/2 的最坏相对误差 ≤ 0.09，4 次后 ~1e-16）。
fn fm_sqrt(x: f64) -> f64 {
    if fm_isnan(x) == 1 { return x; }
    if x == 0.0 { return x; }
    if x < 0.0 { return fm_nan(); }
    if fm_isinf(x) == 1 { return x; }
    FME = fm_exponent(x);
    let m: f64 = fm_ldexp(x, 0 - FME);        # m ∈ [1, 2)
    let se: i64 = FME / 2;
    # i64 除法向零取整；FME 为负且奇数时要向下取
    if FME < 0 {
        if FME != se * 2 { se = se - 1; }
    }
    if FME != se * 2 { m = m * 2.0; }         # 奇指数补偿：m ∈ [1, 4)
    # 初始估计用 [1,4] 上的两点插值 1 + (m−1)/3（端点精确、中点误差 6%），
    # 比 0.5·(m+1) 好得多：后者的最坏相对误差 25%，牛顿迭代误差 ε→ε²/2
    # 要 6 次才收敛到 1e-16（实测最大 8 ulp）；前者 4 次即可。
    let g: f64 = 1.0 + (m - 1.0) / 3.0;
    FMN = 0;
    while FMN < 5 {
        g = 0.5 * (g + m / g);
        FMN = FMN + 1;
    }
    return fm_ldexp(g, se);
}

# ── exp ─────────────────────────────────────────────────────
# x = k·ln2 + r，|r| ≤ ln2/2 ≈ 0.3466，exp(r) 用泰勒级数（Horner）。
# ln2 取两段（hi + lo），否则 e·ln2 一项就吃掉 ~1 ulp。
fn fm_exp(x: f64) -> f64 {
    if fm_isnan(x) == 1 { return x; }
    if x > 709.78271289 { return fm_inf(); }
    if x < 0.0 - 745.13321910 { return 0.0; }
    let t: f64 = x * fm_log2e();
    let k: i64 = 0;
    if t >= 0.0 {
        k = fint(t + 0.5);
    } else {
        k = fint(t - 0.5);
    }
    # r = x − k·ln2_hi − k·ln2_lo：两段相减，抵消 k·ln2 的表示误差
    let r: f64 = x - f64(k) * fm_ln2_hi();
    r = r - f64(k) * fm_ln2_lo();
    # 泰勒级数 **逐步 Horner**（不用一个巨大的嵌套表达式）。
    #
    # 🔴 第一版写成单个嵌套表达式，结果比数学上等价的逐步写法**差 8591 ulp**，
    #    而逐步版本身因为漏写 1/10! 又差 82 万 ulp。两个发现：
    #      · 系数必须逐个核对（漏一项只有 ~1e-10 的偏差，肉眼完全看不出）
    #      · 长嵌套表达式与等价逐步写法结果不同，是编译器层面的疑点（另案）
    #    这里用逐步写法：每步一个语句，误差只来自舍入，可与 Python 逐位对齐。
    #
    # 阶乘超出字面量上限（整数部分 < 10^10）的拆成两段：
    #   14! = 13!·14      15! = 13!·210
    let c14: f64 = 1.0 / 6227020800.0 / 14.0;      # 1/14!
    let c15: f64 = 1.0 / 6227020800.0 / 210.0;     # 1/15!
    let h: f64 = c15;
    h = c14 + r * h;
    h = 1.0 / 6227020800.0 + r * h;                # 1/13!
    h = 1.0 / 479001600.0 + r * h;                 # 1/12!
    h = 1.0 / 39916800.0 + r * h;                  # 1/11!
    h = 1.0 / 3628800.0 + r * h;                   # 1/10!
    h = 1.0 / 362880.0 + r * h;                    # 1/9!
    h = 1.0 / 40320.0 + r * h;                     # 1/8!
    h = 1.0 / 5040.0 + r * h;                      # 1/7!
    h = 1.0 / 720.0 + r * h;                       # 1/6!
    h = 1.0 / 120.0 + r * h;                       # 1/5!
    h = 1.0 / 24.0 + r * h;                        # 1/4!
    h = 1.0 / 6.0 + r * h;                         # 1/3!
    h = 1.0 / 2.0 + r * h;                         # 1/2!
    h = 1.0 + r * h;                               # 1/1!
    h = 1.0 + r * h;                               # 常数项 1
    return fm_ldexp(h, k);
}

# ── log ─────────────────────────────────────────────────────
# x = m·2^e，m 规约到 [1/√2, √2)，z = (m−1)/(m+1)，|z| ≤ 0.1716。
# log(m) = 2·atanh(z) = 2(z + z³/3 + z⁵/5 + ...) —— 收敛比泰勒快得多。
fn fm_log(x: f64) -> f64 {
    if fm_isnan(x) == 1 { return x; }
    if x < 0.0 { return fm_nan(); }
    if x == 0.0 { return 0.0 - fm_inf(); }
    if fm_isinf(x) == 1 { return x; }
    FME = fm_exponent(x);
    let m: f64 = fm_ldexp(x, 0 - FME);        # [1, 2)
    if m > fm_sqrt2() {
        m = m * 0.5;
        FME = FME + 1;
    }
    let z: f64 = (m - 1.0) / (m + 1.0);
    let w: f64 = z * z;
    # 2·(z + z³/3 + z⁵/5 + ... + z^19/19)，逐步 Horner
    let p: f64 = 1.0 / 19.0;
    p = 1.0 / 17.0 + w * p;
    p = 1.0 / 15.0 + w * p;
    p = 1.0 / 13.0 + w * p;
    p = 1.0 / 11.0 + w * p;
    p = 1.0 / 9.0 + w * p;
    p = 1.0 / 7.0 + w * p;
    p = 1.0 / 5.0 + w * p;
    p = 1.0 / 3.0 + w * p;
    p = 1.0 + w * p;
    let s: f64 = 2.0 * z * p;
    return s + f64(FME) * fm_ln2_hi() + f64(FME) * fm_ln2_lo();
}

fn fm_log2(x: f64) -> f64 { return fm_log(x) * fm_log2e(); }
fn fm_log10(x: f64) -> f64 { return fm_log(x) * fm_inv_ln10(); }

# ── pow ─────────────────────────────────────────────────────
fn fm_pow(a: f64, b: f64) -> f64 {
    if fm_isnan(b) == 1 { return b; }
    if b == 0.0 { return 1.0; }
    if fm_isnan(a) == 1 { return a; }
    if a == 1.0 { return 1.0; }
    if a == 0.0 {
        if b > 0.0 { return 0.0; }
        return fm_inf();
    }
    if fm_isinf(a) == 1 {
        if fm_signbit(a) == 1 {
            if b > 0.0 {
                if fm_fmod(b, 2.0) == 0.0 { return fm_inf(); }
                return 0.0 - fm_inf();
            }
            return 0.0;
        }
        if b > 0.0 { return fm_inf(); }
        return 0.0;
    }
    if fm_isinf(b) == 1 {
        if fm_fabs(a) < 1.0 {
            if fm_signbit(b) == 1 { return fm_inf(); }
            return 0.0;
        }
        if fm_signbit(b) == 1 { return 0.0; }
        return fm_inf();
    }
    if a < 0.0 {
        if fm_fmod(b, 1.0) != 0.0 { return fm_nan(); }
    }
    # 🔴 整数指数走**快速幂**，不走 exp(b·log a)。
    #    后者对 pow(2,3) 给出 8.000000000000002（log 的 1 ulp 经 exp 放大），
    #    而 libc 给精确的 8.0。整数指数是常见用法，必须精确。
    if b == fm_floor(b) {
        if fm_fabs(b) < 1024.0 {
            FMP = fint(b);
            let neg: i64 = 0;
            if FMP < 0 { neg = 1; FMP = 0 - FMP; }
            let base: f64 = a;
            let acc: f64 = 1.0;
            while FMP > 0 {
                if (FMP & 1) == 1 { acc = acc * base; }
                base = base * base;
                FMP = FMP >> 1;
            }
            if neg == 1 { return 1.0 / acc; }
            return acc;
        }
    }
    return fm_exp(b * fm_log(fm_fabs(a)));
}

# ── 三角 ────────────────────────────────────────────────────
# 范围规约：k = round(x/(π/2))，r = x − k·(π/2)_hi − k·(π/2)_lo
# 两段相减是为了让 k·(π/2) 的有效精度到 ~1e-33。
# ⚠️ 残留误差来自 **k·(π/2)_hi 这个乘积本身的舍入**，量级 ulp(x)/2 ∝ |x|，
#    所以 |x| 越大越不准 —— 这是本库的已知限制，实测见 docs/fmath.md。
fn fm_sin(x: f64) -> f64 {
    if fm_isnan(x) == 1 { return x; }
    if fm_isinf(x) == 1 { return fm_nan(); }
    FMK = fint(x * fm_2opi() + fm_copysign(0.5, x));
    let r: f64 = x - f64(FMK) * fm_pio2_hi();
    r = r - f64(FMK) * fm_pio2_lo();
    let w: f64 = r * r;
    # sin(r) = r·(1 − w/6 + w²/120 − ... )  取到 r^15
    # sin(r) = r·(1 − w/3! + w²/5! − ... )，逐步 Horner，到 17!
    #   15! = 13!·210   17! = 13!·57120
    let c15: f64 = 1.0 / 6227020800.0 / 210.0;
    let c17: f64 = 1.0 / 6227020800.0 / 57120.0;
    let ps: f64 = c17;
    ps = 0.0 - c15 + w * ps;
    ps = 1.0 / 6227020800.0 + w * ps;      # 1/13!
    ps = 0.0 - 1.0 / 39916800.0 + w * ps;  # −1/11!
    ps = 1.0 / 362880.0 + w * ps;          # 1/9!
    ps = 0.0 - 1.0 / 5040.0 + w * ps;      # −1/7!
    ps = 1.0 / 120.0 + w * ps;             # 1/5!
    ps = 0.0 - 1.0 / 6.0 + w * ps;         # −1/3!
    ps = 1.0 + w * ps;
    let sn: f64 = r * ps;
    # cos(r) = 1 − w/2 + w²/24 − ...  取到 r^16
    # cos(r) = 1 − w/2! + w²/4! − ... ，逐步 Horner，到 16!
    #   14! = 12!·182   16! = 12!·43680
    let d14: f64 = 1.0 / 479001600.0 / 182.0;
    let d16: f64 = 1.0 / 479001600.0 / 43680.0;
    let pc: f64 = d16;
    pc = 0.0 - d14 + w * pc;
    pc = 1.0 / 479001600.0 + w * pc;       # 1/12!
    pc = 0.0 - 1.0 / 3628800.0 + w * pc;   # −1/10!
    pc = 1.0 / 40320.0 + w * pc;           # 1/8!
    pc = 0.0 - 1.0 / 720.0 + w * pc;       # −1/6!
    pc = 1.0 / 24.0 + w * pc;              # 1/4!
    pc = 0.0 - 1.0 / 2.0 + w * pc;         # −1/2!
    pc = 1.0 + w * pc;
    let cs: f64 = pc;
    # 按 k mod 4 选象限
    let q: i64 = FMK & 3;
    if q == 0 { return sn; }
    if q == 1 { return cs; }
    if q == 2 { return 0.0 - sn; }
    return 0.0 - cs;
}
fn fm_cos(x: f64) -> f64 {
    if fm_isnan(x) == 1 { return x; }
    if fm_isinf(x) == 1 { return fm_nan(); }
    FMK = fint(x * fm_2opi() + fm_copysign(0.5, x));
    let r: f64 = x - f64(FMK) * fm_pio2_hi();
    r = r - f64(FMK) * fm_pio2_lo();
    let w: f64 = r * r;
    # sin(r) = r·(1 − w/3! + w²/5! − ... )，逐步 Horner，到 17!
    #   15! = 13!·210   17! = 13!·57120
    let c15: f64 = 1.0 / 6227020800.0 / 210.0;
    let c17: f64 = 1.0 / 6227020800.0 / 57120.0;
    let ps: f64 = c17;
    ps = 0.0 - c15 + w * ps;
    ps = 1.0 / 6227020800.0 + w * ps;      # 1/13!
    ps = 0.0 - 1.0 / 39916800.0 + w * ps;  # −1/11!
    ps = 1.0 / 362880.0 + w * ps;          # 1/9!
    ps = 0.0 - 1.0 / 5040.0 + w * ps;      # −1/7!
    ps = 1.0 / 120.0 + w * ps;             # 1/5!
    ps = 0.0 - 1.0 / 6.0 + w * ps;         # −1/3!
    ps = 1.0 + w * ps;
    let sn: f64 = r * ps;
    # cos(r) = 1 − w/2! + w²/4! − ... ，逐步 Horner，到 16!
    #   14! = 12!·182   16! = 12!·43680
    let d14: f64 = 1.0 / 479001600.0 / 182.0;
    let d16: f64 = 1.0 / 479001600.0 / 43680.0;
    let pc: f64 = d16;
    pc = 0.0 - d14 + w * pc;
    pc = 1.0 / 479001600.0 + w * pc;       # 1/12!
    pc = 0.0 - 1.0 / 3628800.0 + w * pc;   # −1/10!
    pc = 1.0 / 40320.0 + w * pc;           # 1/8!
    pc = 0.0 - 1.0 / 720.0 + w * pc;       # −1/6!
    pc = 1.0 / 24.0 + w * pc;              # 1/4!
    pc = 0.0 - 1.0 / 2.0 + w * pc;         # −1/2!
    pc = 1.0 + w * pc;
    let cs: f64 = pc;
    let q: i64 = FMK & 3;
    if q == 0 { return cs; }
    if q == 1 { return 0.0 - sn; }
    if q == 2 { return 0.0 - cs; }
    return sn;
}
fn fm_tan(x: f64) -> f64 { return fm_sin(x) / fm_cos(x); }

fn fm_hypot(a: f64, b: f64) -> f64 {
    if fm_isinf(a) == 1 { return fm_inf(); }
    if fm_isinf(b) == 1 { return fm_inf(); }
    let x: f64 = fm_fabs(a);
    let y: f64 = fm_fabs(b);
    if x < y {
        let t: f64 = x;
        x = y;
        y = t;
    }
    if x == 0.0 { return 0.0; }
    let r: f64 = y / x;
    return x * fm_sqrt(1.0 + r * r);
}
