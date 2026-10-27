# q16.mo —— Q16.16 定点算术原语（v1.234/235）
# 1.0 = 65536。乘除用 64 位中间积防溢出。

fn q16_mul(a: i64, b: i64) -> i64 {
    return (a * b + 32768) / 65536;
}

fn q16_div(a: i64, b: i64) -> i64 {
    if b == 0 { return 0; }
    return (a * 65536 + b / 2) / b;
}

fn q16_abs(a: i64) -> i64 {
    if a < 0 { return 0 - a; }
    return a;
}

fn q16_min(a: i64, b: i64) -> i64 {
    if a < b { return a; }
    return b;
}

fn q16_max(a: i64, b: i64) -> i64 {
    if a > b { return a; }
    return b;
}

# q16_sqrt(x)：Newton 迭代，x ≥ 0。初值 x+65536 收敛 ~20 轮。
fn q16_sqrt(x: i64) -> i64 {
    if x <= 0 { return 0; }
    let g: i64 = x + 65536;
    let i: i64 = 0;
    while i < 40 {
        let g2: i64 = q16_div(g + q16_div(x, g), 131072);   # g/2 定点
        if g2 == g { return g2; }
        g = g2;
        i = i + 1;
    }
    return g;
}

# ---------- v1.235 超越函数 ----------
# q16_exp(x)：e^x，x 以 1.0=65536 计。x 归约到 |x|<=0.5 后 Taylor 12 项；
#   e^x = 2^k * e^r。负 x 取倒数。x 上限 ±10（约 e^10=22026）。
var QX_T: i64 = 0;

fn q16_exp_small(r: i64) -> i64 {
    # e^r，|r| <= 32768 (0.5)。Taylor：1 + r + r²/2! + ...
    let term: i64 = 65536;
    let sum: i64 = 65536;
    let i: i64 = 1;
    while i < 13 {
        term = q16_mul(term, q16_div(r, i * 65536));
        sum = sum + term;
        i = i + 1;
    }
    return sum;
}

fn q16_exp(x: i64) -> i64 {
    let neg: i64 = 0;
    let v: i64 = x;
    if v < 0 { neg = 1; v = 0 - v; }
    if v > 655360 { if neg == 0 { return 2147483647; } return 0; }   # |x|>10 溢出护栏
    # 归约：v = k*ln2 + r，ln2≈0.693147=45426
    let k: i64 = (v * 2 + 45426) / 90852;    # round(v/ln2)
    let r: i64 = v - k * 45426;
    # e^r
    let er: i64 = q16_exp_small(r);
    # 乘 2^k
    while k > 0 {
        er = er * 2;
        k = k - 1;
    }
    if neg == 1 { return q16_div(65536, er); }
    return er;
}

# q16_log(x)：ln(x)，x>0。归约 x=2^k*m（m∈[1,2)），ln(x)=k*ln2+ln(m)；
#   ln(m) 用 atanh 级数：ln(m)=2*atanh((m-1)/(m+1))，8 项。
var QL_K: i64 = 0;

fn q16_log(x: i64) -> i64 {
    if x <= 0 { return 0 - 2147483647; }
    let v: i64 = x;
    let k: i64 = 0;
    while v >= 131072 { v = v / 2; k = k + 1; }        # v < 2.0
    while v < 65536 { v = v * 2; k = k - 1; }          # v >= 1.0
    # t = (v-1)/(v+1) ∈ [0, 1/3)
    let t: i64 = q16_div(v - 65536, v + 65536);
    let t2: i64 = q16_mul(t, t);
    # 2*atanh(t) = 2*(t + t³/3 + t⁵/5 + ...)
    let term: i64 = t;
    let sum: i64 = t;
    let i: i64 = 3;
    while i < 19 {
        term = q16_mul(term, t2);
        sum = sum + q16_div(term, i * 65536);
        i = i + 2;
    }
    sum = sum * 2;
    return k * 45426 + sum;
}

# q16_sin(x)：x 弧度。先 mod 2π，再 sin(a)=sin(π/2-a) 归约到 [0,π/4]，
#   Taylor 9 项。cos(x)=sin(x+π/2)。
var QS_PI2: i64 = 102944;    # π/2 ≈ 1.5708 → 102943.7
var QS_2PI: i64 = 411775;    # 2π ≈ 6.28319
var QS_PI4: i64 = 51472;     # π/4

fn q16_sin_small(a: i64) -> i64 {
    # a ∈ [0, π/2]。a>π/4 时 sin(a)=cos(π/2-a)。
    if a > QS_PI4 { return q16_cos_small(QS_PI2 - a); }
    let a2: i64 = q16_mul(a, a);
    # Taylor：a - a³/6 + a⁵/120 - a⁷/5040 + a⁹/362880
    let t: i64 = a;
    let sum: i64 = a;
    let sgn: i64 = 0 - 1;
    let f: i64 = 6;
    let i: i64 = 3;
    while i < 12 {
        t = q16_mul(t, a2);
        let term: i64 = q16_div(t, f * 65536);
        if sgn == 0 - 1 { sum = sum - term; } else { sum = sum + term; }
        sgn = 0 - sgn;
        f = f * (i + 1) * (i + 2);
        i = i + 2;
    }
    return sum;
}

fn q16_cos_small(a: i64) -> i64 {
    # a ∈ [0, π/4]：1 - a²/2 + a⁴/24 - a⁶/720 + a⁸/40320
    let a2: i64 = q16_mul(a, a);
    let t: i64 = 65536;
    let sum: i64 = 65536;
    let sgn: i64 = 0 - 1;
    let f: i64 = 2;
    let i: i64 = 2;
    while i < 11 {
        t = q16_mul(t, a2);
        let term: i64 = q16_div(t, f * 65536);
        if sgn == 0 - 1 { sum = sum - term; } else { sum = sum + term; }
        sgn = 0 - sgn;
        f = f * (i + 1) * (i + 2);
        i = i + 2;
    }
    return sum;
}

# ---------- v1.236 激活函数 ----------
# q16_sigmoid(x) = 1/(1+e^-x)
fn q16_sigmoid(x: i64) -> i64 {
    if x >= 0 {
        return q16_div(65536, 65536 + q16_exp(0 - x));
    }
    let e: i64 = q16_exp(x);
    return q16_div(e, 65536 + e);
}

# q16_tanh(x) = 2*sigmoid(2x) - 1
fn q16_tanh(x: i64) -> i64 {
    let e2: i64 = q16_exp(x * 2);
    if x > 327680 { return 65536; }          # |x|>5 饱和护栏
    if x < 0 - 327680 { return 0 - 65536; }
    return q16_div(e2 - 65536, e2 + 65536);
}

# q16_relu / leaky（斜率 0.01）
fn q16_relu(x: i64) -> i64 {
    if x < 0 { return 0; }
    return x;
}

fn q16_leaky_relu(x: i64) -> i64 {
    if x < 0 { return q16_mul(x, 655); }     # 0.01
    return x;
}

# q16_softmax1(x, exps, n)：对 n 元 Q16.16 数组就地算 softmax。
#   稳定化：减 max。exps 是全局数组地址（moc 数组只能全局）。
fn q16_softmax1(exps: ptr, n: i64, x: ptr) -> i64 {
    let mx: i64 = load64(x);
    let i: i64 = 1;
    while i < n {
        let xi: i64 = load64(x + i * 8);
        if xi > mx { mx = xi; }
        i = i + 1;
    }
    let sum: i64 = 0;
    i = 0;
    while i < n {
        let e: i64 = q16_exp(load64(x + i * 8) - mx);
        store64(exps + i * 8, e);
        sum = sum + e;
        i = i + 1;
    }
    i = 0;
    while i < n {
        store64(exps + i * 8, q16_div(load64(exps + i * 8), sum));
        i = i + 1;
    }
    return 0;
}

# ---------- v1.237 矩阵 / 全连接 ----------
# q16_mmul(c, a, b, m, k, n)：C[m×n] = A[m×k]·B[k×n]，Q16.16。
#   行主序；a/b/c 都必须是**全局数组**地址（ptr 字节语义统一 load64/store64）。
fn q16_mmul(c: ptr, a: ptr, b: ptr, m: i64, k: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < m {
        let j: i64 = 0;
        while j < n {
            let s: i64 = 0;
            let t: i64 = 0;
            while t < k {
                s = s + q16_mul(load64(a + (i * k + t) * 8), load64(b + (t * n + j) * 8));
                t = t + 1;
            }
            store64(c + (i * n + j) * 8, s);
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

# q16_linear(out, x, w, b, din, dout)：全连接 y = W·x + b（W[dout×din] 行主序，
#   b[dout]，x[din]，out[dout]）。
fn q16_linear(out: ptr, x: ptr, w: ptr, b: ptr, din: i64, dout: i64) -> i64 {
    let o: i64 = 0;
    while o < dout {
        let s: i64 = load64(b + o * 8);
        let i: i64 = 0;
        while i < din {
            s = s + q16_mul(load64(w + (o * din + i) * 8), load64(x + i * 8));
            i = i + 1;
        }
        store64(out + o * 8, s);
        o = o + 1;
    }
    return 0;
}

# q16_mse(pred, want, n)：均方误差（Q16.16 返回）。
fn q16_mse(pred: ptr, want: ptr, n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let d: i64 = load64(pred + i * 8) - load64(want + i * 8);
        s = s + q16_mul(d, d);
        i = i + 1;
    }
    return q16_div(s, n * 65536);
}

# ---------- v1.238 训练：linear 反向 + SGD ----------
# q16_linear_bwd(gw, gb, gx, x, w, dy, din, dout)：
#   给定 dY[dout]，算 dW=dY·xᵀ、db=dY、dX=Wᵀ·dY。gw[dout×din] gb[dout] gx[din]。
fn q16_linear_bwd(gw: ptr, gb: ptr, gx: ptr, x: ptr, w: ptr, dy: ptr, din: i64, dout: i64) -> i64 {
    let o: i64 = 0;
    while o < dout {
        let dyo: i64 = load64(dy + o * 8);
        store64(gb + o * 8, dyo);
        let i: i64 = 0;
        while i < din {
            # dW[o][i] = dY[o] * x[i]
            store64(gw + (o * din + i) * 8, q16_mul(dyo, load64(x + i * 8)));
            i = i + 1;
        }
        o = o + 1;
    }
    let i2: i64 = 0;
    while i2 < din {
        let s: i64 = 0;
        let o2: i64 = 0;
        while o2 < dout {
            s = s + q16_mul(load64(w + (o2 * din + i2) * 8), load64(dy + o2 * 8));
            o2 = o2 + 1;
        }
        store64(gx + i2 * 8, s);
        i2 = i2 + 1;
    }
    return 0;
}

# q16_sgd_step(p, g, n, lr)：p -= lr·g（lr Q16.16）。
fn q16_sgd_step(p: ptr, g: ptr, n: i64, lr: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store64(p + i * 8, load64(p + i * 8) - q16_mul(lr, load64(g + i * 8)));
        i = i + 1;
    }
    return 0;
}

# ---------- v1.240 二维卷积 ----------
# q16_conv2d(out, img, kern, ih, iw, kh, kw)：valid 卷积，stride 1，单通道。
#   out[(ih-kh+1)×(iw-kw+1)]；img/kern/out 行主序 Q16.16（全局数组）。
fn q16_conv2d(out: ptr, img: ptr, kern: ptr, ih: i64, iw: i64, kh: i64, kw: i64) -> i64 {
    let oh: i64 = ih - kh + 1;
    let ow: i64 = iw - kw + 1;
    let oy: i64 = 0;
    while oy < oh {
        let ox: i64 = 0;
        while ox < ow {
            let s: i64 = 0;
            let ky: i64 = 0;
            while ky < kh {
                let kx: i64 = 0;
                while kx < kw {
                    s = s + q16_mul(
                        load64(img + ((oy + ky) * iw + (ox + kx)) * 8),
                        load64(kern + (ky * kw + kx) * 8));
                    kx = kx + 1;
                }
                ky = ky + 1;
            }
            store64(out + (oy * ow + ox) * 8, s);
            ox = ox + 1;
        }
        oy = oy + 1;
    }
    return 0;
}

# q16_maxpool2(out, img, ih, iw)：2×2 max pool，stride 2，ih/iw 偶数。
fn q16_maxpool2(out: ptr, img: ptr, ih: i64, iw: i64) -> i64 {
    let oy: i64 = 0;
    while oy * 2 + 1 < ih {
        let ox: i64 = 0;
        while ox * 2 + 1 < iw {
            let a: i64 = load64(img + ((oy*2) * iw + (ox*2)) * 8);
            let b: i64 = load64(img + ((oy*2) * iw + (ox*2+1)) * 8);
            let c: i64 = load64(img + ((oy*2+1) * iw + (ox*2)) * 8);
            let d: i64 = load64(img + ((oy*2+1) * iw + (ox*2+1)) * 8);
            let m: i64 = q16_max(q16_max(a, b), q16_max(c, d));
            store64(out + (oy * (iw/2) + ox) * 8, m);
            ox = ox + 1;
        }
        oy = oy + 1;
    }
    return 0;
}

# q16_sin(x)：任意弧度 → 归约 [0, 2π) → sin_small；负角取 -sin(-x)。
fn q16_sin(x: i64) -> i64 {
    let neg: i64 = 0;
    let v: i64 = x;
    if v < 0 { neg = 1; v = 0 - v; }
    v = v % QS_2PI;
    let r: i64 = q16_sin_small(v);
    if neg == 1 { return 0 - r; }
    return r;
}

# q16_cos(x)：cos(x)=sin(x+π/2)
fn q16_cos(x: i64) -> i64 {
    return q16_sin(x + QS_PI2);
}
