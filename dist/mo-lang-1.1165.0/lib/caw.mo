# Code-as-Weights (CaW) —— 权重即代码
# ================================================================
# 核心思想
# ----------------------------------------------------------------
#   传统表示：权重是一个 nr×nc 的数值数组，O(nr·nc) 存储。
#
#   本表示：权重是一个**生成函数**
#
#       W[i][j] = Σ_k  a[k] · B_k(i, j)
#
#   其中 B_k 是**由代码定义的基函数**（类型 + 参数），a[k] 是可学习振幅。
#
#   - 存储从 O(nr·nc) 降到 O(K)  —— 只存 K 个振幅
#   - 梯度是线性的：∂L/∂a[k] = Σ_ij ∂L/∂W[i][j] · B_k(i,j)
#     （Frobenius 内积），不需要对基函数求导
#   - **结构先验写在代码里**：想让权重循环就用 CIRC 基，
#     想让它对称就用 SYM 基，想让它局部就用 BAND 基
#
# 为什么叫「代码就是权重」
# ----------------------------------------------------------------
#   权重不再是一堆看不出意义的浮点数，而是一段**可阅读、可检查、
#   可静态分析**的描述：「这个矩阵 = 0.3 的循环项 + 0.5 的傅里叶项
#   + 0.2 的带状项」。
#
#   由此带来数组表示做不到的事：**结构可以符号推断**。
#   判断一个权重矩阵是不是循环矩阵，数组表示要遍历 O(n²) 个元素；
#   这里只要看基函数的类型列表，O(K)。
#
# 与已有机制的关系
# ----------------------------------------------------------------
#   - autodiff (1.78+)：CaW 块是普通 ad 权重块，梯度从 tape 反传
#   - ASD (1.80)：ASD 靠「传播索引集」推断稀疏模式；CaW 的稀疏模式
#     可以直接从基函数代码**符号解出**，连传播都不需要
# ================================================================

import "nn.mo";
import "autodiff.mo";

# ---------------------------------------------------------------- 基函数类型
var CB_ONE:  i64 = 0;    # 常数 1
var CB_POLY: i64 = 1;    # (i/nr)^p1 · (j/nc)^p2
var CB_CIRC: i64 = 2;    # 1 if (i-j) mod nr == p1   —— 循环 / 平移不变
var CB_SYM:  i64 = 3;    # 1 if |i-j| == p1          —— 对称（径向）
var CB_SIN:  i64 = 4;    # sin(2π(p1·i/nr + p2·j/nc)) —— 傅里叶基
var CB_HASH: i64 = 5;    # 位混合伪随机（固定基底）
var CB_BAND: i64 = 6;    # 1 if |i-j| <= p1          —— 带状 / 局部连接
var CB_LOW:  i64 = 7;    # sin(p1·i) · sin(p2·j)      —— 低秩外积
var CB_CHIRP:i64 = 8;
var CB_ALT:  i64 = 9;    # 1 if j mod 2 == p1         —— 列交替条纹    # sin(2π·p1·i·(j+1)/(nr·nc)) —— 啁啾：频率随列增长

var CW_MAXL: i64 = 64;   # 最多层数（原 16：反编译扫描 K 时会把层表用光，
                          #  caw_layer 返回 -1 而下层不检查，症状是结果越来越乱）
var CW_MAXK: i64 = 16;   # 每层最多基函数数

# ---------------------------------------------------------------- 层表
var CW_NL: i64 = 0;
var CW_NR: [64]   i64 = 0;
var CW_NC: [64]   i64 = 0;
var CW_NK: [64]   i64 = 0;
var CW_BK: [1024] i64 = 0;    # 基函数类型 [L*16 + k]
var CW_B1: [1024] i64 = 0;    # 参数 1
var CW_B2: [1024] i64 = 0;    # 参数 2
var CW_AM: [1024] i64 = 0;    # 振幅 a[k]（可学习，Q16.16）
var CW_GM: [1024] i64 = 0;    # 梯度累积（Q16.16）
var CW_MO: [1024] i64 = 0;    # 动量
var CW_V2: [1024] i64 = 0;    # Adam 二阶矩

# sin 表：[0, π/2] 上 65 点，Q16.16
var CW_SIN: [320] i64 = 0;
var CW_SINI: i64 = 0;

# ---------------------------------------------------------------- sin 表

fn caw_sin_tbl() -> i64 {
    let q: i64 = 0;
    let x: i64 = 0;
    let x2: i64 = 0;
    let x3: i64 = 0;
    let x5: i64 = 0;
    let x7: i64 = 0;
    let s: i64 = 0;
    if CW_SINI == 1 { return 0; }
    # 泰勒：sin(x) = x - x³/6 + x⁵/120 - x⁷/5040，在 [0, π/2] 上误差 < 1e-6
    while q <= 64 {
        x = (102944 * q) / 64;               # π/2 · q/64，Q16.16
        x2 = nn_fmul(x, x);
        x3 = nn_fmul(x2, x);
        x5 = nn_fmul(x3, x2);
        x7 = nn_fmul(x5, x2);
        s = x - nn_fmul(x3, 10922) + nn_fmul(x5, 546) - nn_fmul(x7, 13);
        store64(&CW_SIN + q * 8, s);
        q = q + 1;
    }
    CW_SINI = 1;
    return 0;
}

# sin(2π·θ)，θ 为 Q16.16 的**小数部分**（0 ≤ θ < 65536 表示一圈）
fn caw_sin(q: i64) -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    i = (q >> 8) & 255;
    if i < 64 { return load64(&CW_SIN + i * 8); }
    if i < 128 { return load64(&CW_SIN + (128 - i) * 8); }
    if i < 192 { return 0 - load64(&CW_SIN + (i - 128) * 8); }
    return 0 - load64(&CW_SIN + (256 - i) * 8);
}

# ---------------------------------------------------------------- 层管理

fn caw_layer(nr: i64, nc: i64, nk: i64) -> i64 {
    let L: i64 = 0;
    let i: i64 = 0;
    caw_sin_tbl();
    L = CW_NL;
    if L >= CW_MAXL { return 0 - 1; }
    if nk > CW_MAXK { return 0 - 1; }
    CW_NR[L] = nr;
    CW_NC[L] = nc;
    CW_NK[L] = nk;
    while i < nk {
        store64(&CW_BK + (L * 16 + i) * 8, 0);
        store64(&CW_AM + (L * 16 + i) * 8, 0);
        store64(&CW_GM + (L * 16 + i) * 8, 0);
        store64(&CW_MO + (L * 16 + i) * 8, 0);
        store64(&CW_V2 + (L * 16 + i) * 8, 0);
        i = i + 1;
    }
    CW_NL = CW_NL + 1;
    return L;
}

fn caw_basis(L: i64, k: i64, kind: i64, p1: i64, p2: i64) -> i64 {
    store64(&CW_BK + (L * 16 + k) * 8, kind);
    store64(&CW_B1 + (L * 16 + k) * 8, p1);
    store64(&CW_B2 + (L * 16 + k) * 8, p2);
    return 0;
}

fn caw_amp(L: i64, k: i64, v: i64) -> i64 {
    store64(&CW_AM + (L * 16 + k) * 8, v);
    return 0;
}

fn caw_amp_rand(L: i64, r: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    n = load64(&CW_NK + L * 8);
    nn_srand(r);
    while k < n {
        store64(&CW_AM + (L * 16 + k) * 8, nn_rand_fp(r));
        k = k + 1;
    }
    return 0;
}

fn caw_nk(L: i64) -> i64 { return load64(&CW_NK + L * 8); }
fn caw_nr(L: i64) -> i64 { return load64(&CW_NR + L * 8); }
fn caw_nc(L: i64) -> i64 { return load64(&CW_NC + L * 8); }
fn caw_grad(L: i64, k: i64) -> i64 { return load64(&CW_GM + (L * 16 + k) * 8); }
fn caw_getamp(L: i64, k: i64) -> i64 { return load64(&CW_AM + (L * 16 + k) * 8); }

# ---------------------------------------------------------------- 基函数求值

fn caw_bval(L: i64, k: i64, i: i64, j: i64) -> i64 {
    let kind: i64 = 0;
    let p1: i64 = 0;
    let p2: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let d: i64 = 0;
    let m: i64 = 0;
    let h: i64 = 0;
    let t: i64 = 0;
    kind = load64(&CW_BK + (L * 16 + k) * 8);
    p1 = load64(&CW_B1 + (L * 16 + k) * 8);
    p2 = load64(&CW_B2 + (L * 16 + k) * 8);
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);

    if kind == CB_ONE { return 65536; }

    if kind == CB_POLY {
        # (i/nr)^p1 · (j/nc)^p2 —— p 为整数幂
        let a: i64 = 65536;
        let b: i64 = 65536;
        let q: i64 = 0;
        while q < p1 { a = nn_fmul(a, (i << 16) / nr); q = q + 1; }
        q = 0;
        while q < p2 { b = nn_fmul(b, (j << 16) / nc); q = q + 1; }
        return nn_fmul(a, b);
    }

    if kind == CB_CIRC {
        # 循环 / 平移不变：(i - j) mod nr == p1
        m = i - j;
        d = m % nr;
        if d < 0 { d = d + nr; }
        if d == p1 { return 65536; }
        return 0;
    }

    if kind == CB_SYM {
        # 对称：|i - j| == p1
        d = i - j;
        if d < 0 { d = 0 - d; }
        if d == p1 { return 65536; }
        return 0;
    }

    if kind == CB_BAND {
        # 带状 / 局部连接：|i - j| <= p1
        d = i - j;
        if d < 0 { d = 0 - d; }
        if d <= p1 { return 65536; }
        return 0;
    }

    if kind == CB_SIN {
        # 傅里叶基：sin(2π(p1·i/nr + p2·j/nc))
        let th: i64 = 0;
        th = ((p1 * i * 65536) / nr + (p2 * j * 65536) / nc) & 65535;
        return caw_sin(th);
    }

    if kind == CB_LOW {
        # 低秩外积：sin(p1·i) · sin(p2·j)
        let u: i64 = 0;
        let v: i64 = 0;
        u = caw_sin(((p1 * i * 65536) / nr) & 65535);
        v = caw_sin(((p2 * j * 65536) / nc) & 65535);
        return nn_fmul(u, v);
    }

    # 🔴 真实权重里有一大类「频率沿某一维变化」的结构，
    #    典型就是 Transformer 的正弦位置编码：每一列（维度）频率不同。
    #    可分离基 CB_SIN / CB_LOW 都表示不了，必须显式提供啁啾基。
    if kind == CB_CHIRP {
        let th: i64 = 0;
        th = ((p1 * i * (j + 1) * 65536) / (nr * nc)) & 65535;
        return caw_sin(th);
    }

    # 真实正弦位置编码的 sin/cos 在维度上是**交替**的：
    # 偶数列 sin、奇数列 cos。可分离基表示不了这种条纹，
    # 必须显式给出列交替基。
    if kind == CB_ALT {
        if j % 2 == p1 { return 65536; }
        return 0;
    }

    if kind == CB_HASH {
        # 位混合伪随机（固定基底，提供高频细节）
        h = i * 73856093 + j * 19349663 + p1 * 83492791;
        h = h ^ (h / 2048);
        h = h * 1274126177;
        h = h ^ (h / 1024);
        t = h % 131072;
        if t < 0 { t = 0 - t; }
        return t - 65536;
    }

    return 0;
}

# ---------------------------------------------------------------- 权重生成

fn caw_gen(L: i64, i: i64, j: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let acc: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        acc = acc + nn_fmul(load64(&CW_AM + (L * 16 + k) * 8), caw_bval(L, k, i, j));
        k = k + 1;
    }
    return acc;
}

# ---------------------------------------------------------------- 与 autodiff 对接

# 分配一个 ad 权重块（nr*nc 个槽）并用 CaW 填充
fn caw_block(L: i64) -> i64 {
    let s: i64 = 0;
    s = ad_wblock(caw_nr(L) * caw_nc(L));
    caw_refill(L, s);
    return s;
}

# 把当前振幅生成的权重写入已有块（不重新分配）
fn caw_refill(L: i64, s: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    nr = caw_nr(L);
    nc = caw_nc(L);
    while i < nr {
        j = 0;
        while j < nc {
            ad_set(s + i * nc + j, caw_gen(L, i, j));
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

# 反向之后：把块梯度投影回振幅梯度
#   ∂L/∂a[k] = Σ_ij  ∂L/∂W[i][j] · B_k(i,j)
# 注意：**基函数不求导**，因为 W 对 a 的偏导就是 B_k 本身。
fn caw_accum(L: i64, s: i64) -> i64 {
    let k: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let n: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let g: i64 = 0;
    n = load64(&CW_NK + L * 8);
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    while k < n {
        g = 0;
        i = 0;
        while i < nr {
            j = 0;
            while j < nc {
                g = g + nn_fmul(ad_grad(s + i * nc + j), caw_bval(L, k, i, j));
                j = j + 1;
            }
            i = i + 1;
        }
        store64(&CW_GM + (L * 16 + k) * 8, load64(&CW_GM + (L * 16 + k) * 8) + g);
        k = k + 1;
    }
    return 0;
}

fn caw_zero_grad(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        store64(&CW_GM + (L * 16 + k) * 8, 0);
        k = k + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 优化器（自己的训练框架）

# SGD：a -= lr · g
fn caw_step(L: i64, lr: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        a = load64(&CW_AM + (L * 16 + k) * 8);
        a = a - nn_fmul(lr, load64(&CW_GM + (L * 16 + k) * 8));
        store64(&CW_AM + (L * 16 + k) * 8, a);
        k = k + 1;
    }
    caw_zero_grad(L);
    return 0;
}

# SGD + 动量
fn caw_step_mom(L: i64, lr: i64, mo: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    let m: i64 = 0;
    let g: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        g = load64(&CW_GM + (L * 16 + k) * 8);
        m = nn_fmul(mo, load64(&CW_MO + (L * 16 + k) * 8)) + g;
        store64(&CW_MO + (L * 16 + k) * 8, m);
        a = load64(&CW_AM + (L * 16 + k) * 8);
        store64(&CW_AM + (L * 16 + k) * 8, a - nn_fmul(lr, m));
        k = k + 1;
    }
    caw_zero_grad(L);
    return 0;
}

# Adam（简化：只维护一阶/二阶矩，不做偏差校正）
fn caw_step_adam(L: i64, lr: i64, b1: i64, b2: i64, eps: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    let m: i64 = 0;
    let v: i64 = 0;
    let g: i64 = 0;
    let d: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        g = load64(&CW_GM + (L * 16 + k) * 8);
        m = nn_fmul(b1, load64(&CW_MO + (L * 16 + k) * 8)) + nn_fmul(65536 - b1, g);
        v = nn_fmul(b2, load64(&CW_V2 + (L * 16 + k) * 8)) + nn_fmul(65536 - b2, nn_fmul(g, g));
        store64(&CW_MO + (L * 16 + k) * 8, m);
        store64(&CW_V2 + (L * 16 + k) * 8, v);
        d = nn_fsqrt(v) + eps;
        a = load64(&CW_AM + (L * 16 + k) * 8);
        store64(&CW_AM + (L * 16 + k) * 8, a - nn_fmul(lr, nn_fdiv(m, d)));
        k = k + 1;
    }
    caw_zero_grad(L);
    return 0;
}

# ---------------------------------------------------------------- 静态结构分析
# 数组表示做不到、代码表示天生能做的一部分：
#   结构从**基函数类型列表**推断，O(K)，不需要遍历 O(nr·nc) 个数值。

fn caw_kind(L: i64, k: i64) -> i64 { return load64(&CW_BK + (L * 16 + k) * 8); }

# 是否循环矩阵（所有基都是 CIRC）⇒ 等价于一维卷积
fn caw_is_circ(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    n = load64(&CW_NK + L * 8);
    if n <= 0 { return 0; }
    while k < n {
        if load64(&CW_BK + (L * 16 + k) * 8) != CB_CIRC { return 0; }
        k = k + 1;
    }
    return 1;
}

# 是否对称（所有基都是 |i-j| 型，且方阵）
fn caw_is_sym(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let kd: i64 = 0;
    n = load64(&CW_NK + L * 8);
    if n <= 0 { return 0; }
    if load64(&CW_NR + L * 8) != load64(&CW_NC + L * 8) { return 0; }
    while k < n {
        kd = load64(&CW_BK + (L * 16 + k) * 8);
        if kd != CB_SYM { if kd != CB_BAND { return 0; } }
        k = k + 1;
    }
    return 1;
}

# 是否有界带宽（BAND 基 ⇒ 局部连接）
fn caw_bandwidth(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let bw: i64 = 0 - 1;
    let p: i64 = 0;
    n = load64(&CW_NK + L * 8);
    while k < n {
        if load64(&CW_BK + (L * 16 + k) * 8) == CB_BAND {
            p = load64(&CW_B1 + (L * 16 + k) * 8);
            if p > bw { bw = p; }
        } else {
            return 0 - 1;   # 有非带状基 ⇒ 不是稀疏结构
        }
        k = k + 1;
    }
    return bw;
}

# 参数量 vs 权重数量
fn caw_nparam(L: i64) -> i64 { return load64(&CW_NK + L * 8); }
fn caw_nweight(L: i64) -> i64 {
    return load64(&CW_NR + L * 8) * load64(&CW_NC + L * 8);
}

# 结构性零的个数（**符号推断**，不遍历数值）
# CIRC/SYM/BAND 基只在部分 (i,j) 非零；这里逐点求值是 O(n²·K)，
# 但对 CIRC/BAND 可以 O(1) 解析给出，留作接口便于对照数值统计。
fn caw_struct_zero(L: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let z: i64 = 0;
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    while i < nr {
        j = 0;
        while j < nc {
            if caw_gen(L, i, j) == 0 { z = z + 1; }
            j = j + 1;
        }
        i = i + 1;
    }
    return z;
}

# ================================================================
# 结构化快速矩阵-向量乘（1.90）
# ================================================================
#   y = W·x，其中 W[i][j] = Σ_k a[k]·B_k(i, j)
#
#   朴素做法：先把 n² 个元素生成出来（每元素 O(K)，共 O(K·n²)），
#   再做 n² 次乘加。
#
#   这里的关键：**(B_k · x) 怎么算，完全由 B_k 的类型决定，与振幅无关。**
#   所以只要读一遍类型列表（O(K)）就知道该走哪条路 —— 一个数都不用看。
#
#     CB_ONE    y[i] = a·Σ_j x[j]                       O(nc)
#     CB_ALT    y[i] = a·Σ_{j mod 2 = p1} x[j]          O(nc)
#     CB_CIRC   y[i] = a·Σ_{j ≡ i-p1 (mod nr)} x[j]     全表合计 O(nc)
#     CB_SYM    y[i] = a·(x[i-p1] + x[i+p1])            O(nr)
#     CB_BAND   y[i] = a·Σ_{|i-j| ≤ p1} x[j]            O(nr·(2p1+1))
#     CB_LOW    a·u_i·(v·x)                             O(nr+nc)
#     CB_POLY   a·(i/nr)^p1·(Σ_j (j/nc)^p2·x[j])        O(nr+nc)
#     CB_SIN    sin(θi+φj) = sinθi·cosφj + cosθi·sinφj   O(nr+nc)
#     CB_CHIRP / CB_HASH  不可分离                       O(nr·nc)，退回
#
#   九种基里只有两种是 O(n²)，其余全是 O(n)。
#
#   🔴 CIRC 不需要 FFT。c[d] = Σ_{p1_k = d} a[k] 最多只有 K 个非零，
#      所以循环卷积退化成「K 次移位取数」—— 比 FFT 更快，且是精确值，
#      没有定点 FFT 的舍入误差。
# ================================================================

fn caw_cos(q: i64) -> i64 {
    # cos(2π·q/65536) = sin(2π·(q + 1/4 圈)/65536)，π/2 = 16384
    return caw_sin(q + 16384);
}

# 复杂度类：0 = 结构化（O(n)）；1 = 不可分离（O(n²)，退回逐点求值）
fn caw_kind_class(kind: i64) -> i64 {
    if kind == CB_CHIRP { return 1; }
    if kind == CB_HASH { return 1; }
    return 0;
}

# 单个基对 y 的贡献：y += a[k] · (B_k · x)
fn caw_mv_base(L: i64, k: i64, x: ptr, y: ptr) -> i64 {
    let kind: i64 = 0;
    let p1: i64 = 0;
    let p2: i64 = 0;
    let a: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let j0: i64 = 0;
    let lo: i64 = 0;
    let hi: i64 = 0;
    let s: i64 = 0;
    let s2: i64 = 0;
    let v: i64 = 0;
    let q: i64 = 0;
    let pw: i64 = 0;
    kind = load64(&CW_BK + (L * 16 + k) * 8);
    p1 = load64(&CW_B1 + (L * 16 + k) * 8);
    p2 = load64(&CW_B2 + (L * 16 + k) * 8);
    a = load64(&CW_AM + (L * 16 + k) * 8);
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    if a == 0 { return 0; }

    if kind == CB_ONE {
        s = 0;
        j = 0;
        while j < nc { s = s + load64(x + j * 8); j = j + 1; }
        v = nn_fmul(a, s);
        i = 0;
        while i < nr { store64(y + i * 8, load64(y + i * 8) + v); i = i + 1; }
        return 0;
    }

    if kind == CB_ALT {
        s = 0;
        j = 0;
        while j < nc {
            if j % 2 == p1 { s = s + load64(x + j * 8); }
            j = j + 1;
        }
        v = nn_fmul(a, s);
        i = 0;
        while i < nr { store64(y + i * 8, load64(y + i * 8) + v); i = i + 1; }
        return 0;
    }

    # 循环：j ≡ i - p1 (mod nr)。对每行只有 nc/nr 个 j，全表合计 O(nc)。
    if kind == CB_CIRC {
        i = 0;
        while i < nr {
            j0 = (i - p1) % nr;
            if j0 < 0 { j0 = j0 + nr; }
            s = 0;
            j = j0;
            while j < nc { s = s + load64(x + j * 8); j = j + nr; }
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, s));
            i = i + 1;
        }
        return 0;
    }

    if kind == CB_SYM {
        i = 0;
        while i < nr {
            s = 0;
            j = i - p1;
            if j >= 0 { if j < nc { s = s + load64(x + j * 8); } }
            if p1 != 0 {
                j = i + p1;
                if j >= 0 { if j < nc { s = s + load64(x + j * 8); } }
            }
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, s));
            i = i + 1;
        }
        return 0;
    }

    if kind == CB_BAND {
        i = 0;
        while i < nr {
            lo = i - p1;
            if lo < 0 { lo = 0; }
            hi = i + p1;
            if hi >= nc { hi = nc - 1; }
            s = 0;
            j = lo;
            while j <= hi { s = s + load64(x + j * 8); j = j + 1; }
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, s));
            i = i + 1;
        }
        return 0;
    }

    # 低秩外积：u_i · (v · x)
    if kind == CB_LOW {
        s = 0;
        j = 0;
        while j < nc {
            v = caw_sin(((p2 * j * 65536) / nc) & 65535);
            s = s + nn_fmul(v, load64(x + j * 8));
            j = j + 1;
        }
        i = 0;
        while i < nr {
            v = caw_sin(((p1 * i * 65536) / nr) & 65535);
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, nn_fmul(v, s)));
            i = i + 1;
        }
        return 0;
    }

    # 多项式：可分离 A_i · B_j
    if kind == CB_POLY {
        s = 0;
        j = 0;
        while j < nc {
            pw = 65536;
            q = 0;
            while q < p2 { pw = nn_fmul(pw, (j << 16) / nc); q = q + 1; }
            s = s + nn_fmul(pw, load64(x + j * 8));
            j = j + 1;
        }
        i = 0;
        while i < nr {
            pw = 65536;
            q = 0;
            while q < p1 { pw = nn_fmul(pw, (i << 16) / nr); q = q + 1; }
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, nn_fmul(pw, s)));
            i = i + 1;
        }
        return 0;
    }

    # 傅里叶：sin(θi + φj) = sinθi·cosφj + cosθi·sinφj  —— 秩 2 可分离
    if kind == CB_SIN {
        s = 0;
        s2 = 0;
        j = 0;
        while j < nc {
            q = ((p2 * j * 65536) / nc) & 65535;
            s = s + nn_fmul(caw_cos(q), load64(x + j * 8));
            s2 = s2 + nn_fmul(caw_sin(q), load64(x + j * 8));
            j = j + 1;
        }
        i = 0;
        while i < nr {
            q = ((p1 * i * 65536) / nr) & 65535;
            v = nn_fmul(caw_sin(q), s) + nn_fmul(caw_cos(q), s2);
            store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, v));
            i = i + 1;
        }
        return 0;
    }

    # 不可分离（CHIRP / HASH）：逐点求值，O(nr·nc)
    i = 0;
    while i < nr {
        s = 0;
        j = 0;
        while j < nc {
            s = s + nn_fmul(caw_bval(L, k, i, j), load64(x + j * 8));
            j = j + 1;
        }
        store64(y + i * 8, load64(y + i * 8) + nn_fmul(a, s));
        i = i + 1;
    }
    return 0;
}

# 结构化快速乘：y = W·x
fn caw_mv(L: i64, x: ptr, y: ptr) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    let n: i64 = 0;
    let nr: i64 = 0;
    caw_sin_tbl();
    nr = load64(&CW_NR + L * 8);
    n = load64(&CW_NK + L * 8);
    i = 0;
    while i < nr { store64(y + i * 8, 0); i = i + 1; }
    k = 0;
    while k < n { caw_mv_base(L, k, x, y); k = k + 1; }
    return 0;
}

# 朴素参照：逐元素生成权重再乘（O(K·n²)）
fn caw_mv_dense(L: i64, x: ptr, y: ptr) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let s: i64 = 0;
    caw_sin_tbl();
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    i = 0;
    while i < nr {
        s = 0;
        j = 0;
        while j < nc {
            s = s + nn_fmul(caw_gen(L, i, j), load64(x + j * 8));
            j = j + 1;
        }
        store64(y + i * 8, s);
        i = i + 1;
    }
    return 0;
}

# 预测的乘加次数 —— **只读类型列表**，O(K)，不碰任何数值
fn caw_mv_cost(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let c: i64 = 0;
    let kind: i64 = 0;
    let p1: i64 = 0;
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    n = load64(&CW_NK + L * 8);
    k = 0;
    while k < n {
        kind = load64(&CW_BK + (L * 16 + k) * 8);
        p1 = load64(&CW_B1 + (L * 16 + k) * 8);
        if caw_kind_class(kind) == 1 {
            c = c + nr * nc;
        } else {
            if kind == CB_BAND {
                c = c + nr * (2 * p1 + 1);
            } else {
                if kind == CB_SIN { c = c + 2 * (nr + nc); } else { c = c + nr + nc; }
            }
        }
        k = k + 1;
    }
    return c;
}

# 朴素路径的代价：生成 n² 个元素（每元素 O(K)）+ n² 次乘加
fn caw_mv_cost_dense(L: i64) -> i64 {
    let nr: i64 = 0;
    let nc: i64 = 0;
    let n: i64 = 0;
    nr = load64(&CW_NR + L * 8);
    nc = load64(&CW_NC + L * 8);
    n = load64(&CW_NK + L * 8);
    return nr * nc * (n + 1);
}

# 有多少个基属于 O(n²) 类（0 表示整层都能走快路径）
fn caw_mv_ndense(L: i64) -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    let d: i64 = 0;
    n = load64(&CW_NK + L * 8);
    k = 0;
    while k < n {
        if caw_kind_class(load64(&CW_BK + (L * 16 + k) * 8)) == 1 { d = d + 1; }
        k = k + 1;
    }
    return d;
}
