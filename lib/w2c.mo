# W2C —— Weight-to-Code 反编译器（1.88）
# ================================================================
# caw.mo 做的是**正向**：权重由代码生成（W = Σ a_k·B_k），
# 训练的是振幅 a。
#
# 本库做的是**逆向**：给定一张**已经存在**的权重矩阵 W
# （来自开源社区的模型、自己训练产物、或任何来源），
# 把它**反编译**成同一套基函数表示：
#
#       W  ──反编译──▶  { (kind_k, p1_k, p2_k), a_k }  k = 0..K-1
#
# 于是这张权重从「O(nr·nc) 个数」变成「K 行代码 + K 个振幅」。
# ================================================================
#
# 为什么这是「转换」而不是「压缩」
# ----------------------------------------------------------------
#   量化（PTQ）压缩后仍是 O(nr·nc) 个数，只是每个数变短。
#   反编译改变的是**表示的维度**：参数个数从 nr·nc 降到 K。
#   而且转换结果**可读**：「这张权重 = 0.8 的循环项 + 0.3 的傅里叶项」
#   是可以打印出来给人看的，量化做不到这一点。
#
# 算法：OMP（正交匹配追踪）
# ----------------------------------------------------------------
#   基函数之间**不正交**，所以不能逐个独立投影。做法是：
#
#     每一轮从候选池里挑一个基，使残差下降最多
#     然后**重新求解全部振幅**（正规方程 G·a = b）
#
#   只挑不重解是错误的：新加入的基会改变已有基的最优振幅。
#
#   正规方程来自 ∂/∂a ‖W − Σ a_k B_k‖²_F = 0：
#
#       G[k][l] = ⟨B_k, B_l⟩ = Σ_ij B_k(i,j)·B_l(i,j)
#       b[k]    = ⟨W,   B_k⟩ = Σ_ij W(i,j)·B_k(i,j)
#
#   **基函数不求导** —— 与 caw.mo 的正向一致，这是同一条性质的两面。
#
# ================================================================

import "nn.mo";
import "caw.mo";

# ---------------------------------------------------------------- 工作区
var W2C_NR: i64 = 0;
var W2C_NC: i64 = 0;

var W2C_W: [1024] i64 = 0;      # 原权重（输入）
var W2C_R: [1024] i64 = 0;      # 残差 R = W − Σ a_k B_k
var W2C_Q: [1024] i64 = 0;      # 当前重建值 Σ a_k B_k

var W2C_G:  [256]  i64 = 0;     # Gram 矩阵（K×K，K ≤ 16）
var W2C_X:  [16]   i64 = 0;     # 右端项 → 解 a
var W2C_KD: [16]   i64 = 0;     # 已选基 kind
var W2C_P1: [16]   i64 = 0;
var W2C_P2: [16]   i64 = 0;
var W2C_N:  i64 = 0;            # 已选基个数

# 候选池
var W2C_CK: [512] i64 = 0;
var W2C_C1: [512] i64 = 0;
var W2C_C2: [512] i64 = 0;
var W2C_CN: [512] i64 = 0;      # ‖b‖² = ⟨b,b⟩，预计算
var W2C_CS: [512] i64 = 0;      # 已选标记
var W2C_NP: i64 = 0;            # 候选池大小（不能叫 W2C_NC，那是列数）

var W2C_LAST: i64 = 0;
var W2C_SEP:  i64 = 0;   # 1 = 只允许可分离（O(n)）基          # 最近一次反编译的残差能量（ΣR²）

# ---------------------------------------------------------------- 基函数求值
# 与 caw_bval 同一套定义，但参数直接传入（不经过层表），
# 这样候选池里的基不必先写进层表就能评估。

fn w2c_bv(kind: i64, p1: i64, p2: i64, i: i64, j: i64) -> i64 {
    let d: i64 = 0;
    let m: i64 = 0;
    let h: i64 = 0;
    let t: i64 = 0;

    if kind == CB_ONE { return 65536; }

    if kind == CB_CIRC {
        m = i - j;
        d = m % W2C_NR;
        if d < 0 { d = d + W2C_NR; }
        if d == p1 { return 65536; }
        return 0;
    }

    if kind == CB_SYM {
        d = i - j;
        if d < 0 { d = 0 - d; }
        if d == p1 { return 65536; }
        return 0;
    }

    if kind == CB_BAND {
        d = i - j;
        if d < 0 { d = 0 - d; }
        if d <= p1 { return 65536; }
        return 0;
    }

    if kind == CB_SIN {
        let th: i64 = 0;
        th = ((p1 * i * 65536) / W2C_NR + (p2 * j * 65536) / W2C_NC) & 65535;
        return caw_sin(th);
    }

    if kind == CB_LOW {
        let u: i64 = 0;
        let v: i64 = 0;
        u = caw_sin(((p1 * i * 65536) / W2C_NR) & 65535);
        v = caw_sin(((p2 * j * 65536) / W2C_NC) & 65535);
        return nn_fmul(u, v);
    }

    if kind == CB_CHIRP {
        let th: i64 = 0;
        th = ((p1 * i * (j + 1) * 65536) / (W2C_NR * W2C_NC)) & 65535;
        return caw_sin(th);
    }

    if kind == CB_ALT {
        if j % 2 == p1 { return 65536; }
        return 0;
    }

    if kind == CB_POLY {
        let a: i64 = 65536;
        let b: i64 = 65536;
        let q: i64 = 0;
        while q < p1 { a = nn_fmul(a, (i << 16) / W2C_NR); q = q + 1; }
        q = 0;
        while q < p2 { b = nn_fmul(b, (j << 16) / W2C_NC); q = q + 1; }
        return nn_fmul(a, b);
    }

    if kind == CB_HASH {
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

# ---------------------------------------------------------------- 载入

fn w2c_set(nr: i64, nc: i64) -> i64 {
    let n: i64 = 0;
    if nr * nc > 1024 { return 0 - 1; }
    W2C_NR = nr;
    W2C_NC = nc;
    n = nr * nc;
    while n > 0 {
        n = n - 1;
        W2C_W[n] = 0;
        W2C_R[n] = 0;
        W2C_Q[n] = 0;
    }
    W2C_N = 0;
    W2C_NP = 0;
    W2C_LAST = 0;
    return 0;
}

fn w2c_w(i: i64, j: i64, v: i64) -> i64 {
    W2C_W[i * W2C_NC + j] = v;
    return 0;
}

fn w2c_getw(i: i64, j: i64) -> i64 {
    return W2C_W[i * W2C_NC + j];
}

# ---------------------------------------------------------------- 从训练产物直接载入
# 训练后的权重住在 autodiff 的权重块里（nr*nc 个槽，行主序）。
# 这一步把「训练产物」接到「反编译器」上，中间不需要用户手工搬运数组。
#
# 顺序很重要：必须先 ad_val 读出来，再 w2c_set 清零。
# 反着做会把待读的值先清成 0 —— 不报错，只是反编译出一张全零权重。

fn w2c_from_block(s: i64, nr: i64, nc: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let v: i64 = 0;
    if nr * nc > 1024 { return 0 - 1; }
    i = 0;
    while i < nr {
        j = 0;
        while j < nc {
            v = ad_val(s + i * nc + j);
            W2C_W[i * nc + j] = v;
            j = j + 1;
        }
        i = i + 1;
    }
    W2C_NR = nr;
    W2C_NC = nc;
    W2C_N = 0;
    W2C_NP = 0;
    W2C_LAST = 0;
    return 0;
}

# ---------------------------------------------------------------- 内积
# 所有内积都在遍历时即时求值基函数，不物化基矩阵 —— 省内存也省一遍写入。

fn w2c_ip_wb(kind: i64, p1: i64, p2: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let s: i64 = 0;
    while i < W2C_NR {
        j = 0;
        while j < W2C_NC {
            s = s + nn_fmul(W2C_W[i * W2C_NC + j], w2c_bv(kind, p1, p2, i, j));
            j = j + 1;
        }
        i = i + 1;
    }
    return s;
}

fn w2c_ip_rb(kind: i64, p1: i64, p2: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let s: i64 = 0;
    while i < W2C_NR {
        j = 0;
        while j < W2C_NC {
            s = s + nn_fmul(W2C_R[i * W2C_NC + j], w2c_bv(kind, p1, p2, i, j));
            j = j + 1;
        }
        i = i + 1;
    }
    return s;
}

# 两个基之间的内积（Gram 元素）
fn w2c_ip_bb(k1: i64, a1: i64, a2: i64, k2: i64, b1: i64, b2: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let s: i64 = 0;
    while i < W2C_NR {
        j = 0;
        while j < W2C_NC {
            s = s + nn_fmul(w2c_bv(k1, a1, a2, i, j), w2c_bv(k2, b1, b2, i, j));
            j = j + 1;
        }
        i = i + 1;
    }
    return s;
}

# ---------------------------------------------------------------- 候选池

fn w2c_pool_add(kind: i64, p1: i64, p2: i64) -> i64 {
    if W2C_NP >= 512 { return 0 - 1; }
    W2C_CK[W2C_NP] = kind;
    W2C_C1[W2C_NP] = p1;
    W2C_C2[W2C_NP] = p2;
    W2C_CS[W2C_NP] = 0;
    W2C_NP = W2C_NP + 1;
    return 0;
}

# 池的规模直接决定 OMP 的搜索质量与耗时。
# 覆盖：常数 / 循环 / 对称 / 带状 / 傅里叶 / 低秩外积 / 多项式 / 伪随机高频
fn w2c_pool() -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let n: i64 = 0;
    W2C_NP = 0;
    w2c_pool_add(CB_ONE, 0, 0);

    n = W2C_NR;
    a = 0;
    while a < n { w2c_pool_add(CB_CIRC, a, 0); a = a + 1; }
    a = 0;
    while a < n { w2c_pool_add(CB_SYM, a, 0); a = a + 1; }

    w2c_pool_add(CB_BAND, 0, 0);
    w2c_pool_add(CB_BAND, 1, 0);
    w2c_pool_add(CB_BAND, 2, 0);
    w2c_pool_add(CB_BAND, 4, 0);
    w2c_pool_add(CB_BAND, 8, 0);

    a = 0 - 8;
    while a <= 8 {
        b = 0 - 8;
        while b <= 8 {
            if a != 0 {
                w2c_pool_add(CB_SIN, a, b);
            }
            if a == 0 {
                if b != 0 { w2c_pool_add(CB_SIN, 0, b); }
            }
            b = b + 1;
        }
        a = a + 1;
    }

    a = 1;
    while a <= 4 {
        b = 1;
        while b <= 4 {
            w2c_pool_add(CB_LOW, a, b);
            b = b + 1;
        }
        a = a + 1;
    }

    a = 0;
    while a <= 3 {
        b = 0;
        while b <= 3 {
            w2c_pool_add(CB_POLY, a, b);
            b = b + 1;
        }
        a = a + 1;
    }

    a = 1;
    while a <= 8 {
        w2c_pool_add(CB_CHIRP, a, 0);
        a = a + 1;
    }

    w2c_pool_add(CB_ALT, 0, 0);
    w2c_pool_add(CB_ALT, 1, 0);

    a = 0;
    while a < 8 { w2c_pool_add(CB_HASH, a, 0); a = a + 1; }
    return W2C_NP;
}

# 预计算 ‖b‖² —— 每轮 OMP 都要用，算一次即可
fn w2c_pool_norm() -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    while i < W2C_NP {
        v = w2c_ip_bb(W2C_CK[i], W2C_C1[i], W2C_C2[i],
                      W2C_CK[i], W2C_C1[i], W2C_C2[i]);
        if v < 65536 { v = 65536; }
        W2C_CN[i] = v;
        i = i + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 正规方程

fn w2c_gram() -> i64 {
    let k: i64 = 0;
    let l: i64 = 0;
    let n: i64 = 0;
    let v: i64 = 0;
    n = W2C_N;
    while k < n {
        l = k;
        while l < n {
            v = w2c_ip_bb(W2C_KD[k], W2C_P1[k], W2C_P2[k],
                          W2C_KD[l], W2C_P1[l], W2C_P2[l]);
            W2C_G[k * 16 + l] = v;
            W2C_G[l * 16 + k] = v;
            l = l + 1;
        }
        # 不加岭正则：正则会让解有偏，已知结构的精确反编译就差在这里
        # （2.0 解成 1.9929）。线性相关的基在 solve 里被检出并回退。
        k = k + 1;
    }
    return 0;
}

fn w2c_rhs() -> i64 {
    let k: i64 = 0;
    let n: i64 = 0;
    n = W2C_N;
    while k < n {
        W2C_X[k] = w2c_ip_wb(W2C_KD[k], W2C_P1[k], W2C_P2[k]);
        k = k + 1;
    }
    return 0;
}

# 高斯消元（原地）：G·a = X，解写回 X。全 Q16.16。
fn w2c_solve() -> i64 {
    let n: i64 = 0;
    let c: i64 = 0;
    let r: i64 = 0;
    let k: i64 = 0;
    let f: i64 = 0;
    let s: i64 = 0;
    let pv: i64 = 0;
    n = W2C_N;
    c = 0;
    while c < n {
        pv = W2C_G[c * 16 + c];
        if pv < 0 { pv = 0 - pv; }
        if pv < 4096 { return 0 - 1; }      # 奇异，明确报错而非给出垃圾解
        r = c + 1;
        while r < n {
            f = (W2C_G[r * 16 + c] << 16) / W2C_G[c * 16 + c];
            k = c;
            while k < n {
                W2C_G[r * 16 + k] = W2C_G[r * 16 + k] - nn_fmul(f, W2C_G[c * 16 + k]);
                k = k + 1;
            }
            W2C_X[r] = W2C_X[r] - nn_fmul(f, W2C_X[c]);
            r = r + 1;
        }
        c = c + 1;
    }
    c = n - 1;
    while c >= 0 {
        s = W2C_X[c];
        k = c + 1;
        while k < n {
            s = s - nn_fmul(W2C_G[c * 16 + k], W2C_X[k]);
            k = k + 1;
        }
        W2C_X[c] = (s << 16) / W2C_G[c * 16 + c];
        c = c - 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 重建与残差

fn w2c_rebuild() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let k: i64 = 0;
    let s: i64 = 0;
    while i < W2C_NR {
        j = 0;
        while j < W2C_NC {
            s = 0;
            k = 0;
            while k < W2C_N {
                s = s + nn_fmul(W2C_X[k], w2c_bv(W2C_KD[k], W2C_P1[k], W2C_P2[k], i, j));
                k = k + 1;
            }
            W2C_Q[i * W2C_NC + j] = s;
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

# R = W − Q，同时累加残差能量（用于误差报告）
fn w2c_resid() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let d: i64 = 0;
    let e: i64 = 0;
    n = W2C_NR * W2C_NC;
    while i < n {
        d = W2C_W[i] - W2C_Q[i];
        W2C_R[i] = d;
        e = e + nn_fmul(d, d);
        i = i + 1;
    }
    W2C_LAST = e;
    return e;
}

# ---------------------------------------------------------------- OMP 主循环

fn w2c_pick() -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let sc: i64 = 0;
    let best: i64 = 0;
    let bs: i64 = 0;
    let found: i64 = 0;
    let ok: i64 = 0;
    # 🔴 不能写 continue：这里用 ok 标志代替。
    while i < W2C_NP {
        ok = 1;
        if W2C_SEP == 1 {
            # 1.91：部署约束 —— 只允许可分离（O(n)）基。
            #   拟合最好的基未必跑得最快：HASH/CHIRP 残差下降快，
            #   但它们是 O(n²) 且要逐点求值，实测比物化好的稠密还慢。
            if caw_kind_class(W2C_CK[i]) == 1 { ok = 0; }
        }
        if W2C_CS[i] != 0 { ok = 0; }
        if ok == 1 {
            v = w2c_ip_rb(W2C_CK[i], W2C_C1[i], W2C_C2[i]);
            if v < 0 { v = 0 - v; }
            # 🔴 正确的 OMP 准则：残差下降量 = |<R,b>|² / ‖b‖²
            #    早期版本用 |<R,b>| / ‖b‖²（振幅估计），会系统性地
            #    偏好**范数小**的基 —— 循环基 ‖b‖² 远小于傅里叶基，
            #    于是傅里叶基永远选不上，真实正弦权重拟合不动。
            sc = (((v * v) >> 16) << 16) / W2C_CN[i];
            if found == 0 {
                found = 1;
                bs = sc;
                best = i;
            }
            if sc > bs {
                bs = sc;
                best = i;
            }
        }
        i = i + 1;
    }
    if found == 0 { return 0 - 1; }
    W2C_CS[best] = 1;
    return best;
}

# 反编译：K 个基
# 返回残差能量；失败返回 -1
# 只允许可分离基的反编译（部署 / 快速推理场景）
fn w2c_fit_sep(K: i64) -> i64 {
    W2C_SEP = 1;
    return w2c_fit(K);
}

fn w2c_fit(K: i64) -> i64 {
    let t: i64 = 0;
    let c: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    if K > 16 { return 0 - 1; }
    W2C_N = 0;
    W2C_NP = w2c_pool();
    w2c_pool_norm();
    i = 0;
    while i < W2C_NP { W2C_CS[i] = 0; i = i + 1; }

    # 初始残差 = W（还没有任何基）
    n = W2C_NR * W2C_NC;
    i = 0;
    while i < n { W2C_R[i] = W2C_W[i]; W2C_Q[i] = 0; i = i + 1; }

    t = 0;
    while t < K {
        c = w2c_pick();
        if c < 0 { return 0 - 1; }
        W2C_KD[W2C_N] = W2C_CK[c];
        W2C_P1[W2C_N] = W2C_C1[c];
        W2C_P2[W2C_N] = W2C_C2[c];
        W2C_N = W2C_N + 1;
        # 🔴 新基加入后必须**重解全部振幅**：基之间不正交
        w2c_gram();
        w2c_rhs();
        if w2c_solve() < 0 {
            # 与已选基线性相关 —— 丢弃它重试下一个，不要整体失败。
            # （CIRC(0) 与 SYM(0) 在方阵上是同一个矩阵，必然遇到）
            W2C_N = W2C_N - 1;
            t = t - 1;
        }
        w2c_rebuild();
        w2c_resid();
        t = t + 1;
    }
    W2C_SEP = 0;
    return W2C_LAST;
}

# ---------------------------------------------------------------- 误差报告

fn w2c_energy() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let e: i64 = 0;
    let v: i64 = 0;
    n = W2C_NR * W2C_NC;
    while i < n {
        v = W2C_W[i];
        e = e + nn_fmul(v, v);
        i = i + 1;
    }
    return e;
}

# 相对残差 ‖R‖/‖W‖ 的**平方**（能量比），Q16.16
fn w2c_relsq() -> i64 {
    let e: i64 = 0;
    e = w2c_energy();
    if e < 1 { return 0; }
    return (W2C_LAST << 16) / e;
}

fn w2c_maxerr() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let d: i64 = 0;
    let m: i64 = 0;
    n = W2C_NR * W2C_NC;
    while i < n {
        d = W2C_R[i];
        if d < 0 { d = 0 - d; }
        if d > m { m = d; }
        i = i + 1;
    }
    return m;
}

# 残差按**列**的能量分布 —— 反编译不下来时，用它定位缺哪一类基
fn w2c_colerr(j: i64) -> i64 {
    let i: i64 = 0;
    let e: i64 = 0;
    let v: i64 = 0;
    while i < W2C_NR {
        v = W2C_R[i * W2C_NC + j];
        e = e + nn_fmul(v, v);
        i = i + 1;
    }
    return e;
}

fn w2c_amp_k(k: i64) -> i64 { return W2C_X[k]; }
fn w2c_kind_k(k: i64) -> i64 { return W2C_KD[k]; }
fn w2c_p1_k(k: i64) -> i64 { return W2C_P1[k]; }
fn w2c_p2_k(k: i64) -> i64 { return W2C_P2[k]; }
fn w2c_n() -> i64 { return W2C_N; }

# ---------------------------------------------------------------- 输出为 CaW 层
# 反编译结果落成 caw 层，于是可以直接用 caw_gen / caw_block 走原路径。
# 这一步把「逆向」与「正向」接成一个环。

fn w2c_emit() -> i64 {
    let L: i64 = 0;
    let k: i64 = 0;
    L = caw_layer(W2C_NR, W2C_NC, W2C_N);
    if L < 0 { return 0 - 1; }
    while k < W2C_N {
        caw_basis(L, k, W2C_KD[k], W2C_P1[k], W2C_P2[k]);
        caw_amp(L, k, W2C_X[k]);
        k = k + 1;
    }
    return L;
}

# 用 caw 的正向生成器重建，与原权重比较
# —— 验证「反编译 → 编译」闭环：两条独立实现必须给出同一个矩阵
fn w2c_roundtrip(L: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let d: i64 = 0;
    let m: i64 = 0;
    while i < W2C_NR {
        j = 0;
        while j < W2C_NC {
            d = caw_gen(L, i, j) - W2C_Q[i * W2C_NC + j];
            if d < 0 { d = 0 - d; }
            if d > m { m = d; }
            j = j + 1;
        }
        i = i + 1;
    }
    return m;
}

# ---------------------------------------------------------------- 压缩比

fn w2c_ratio() -> i64 {
    let nw: i64 = 0;
    nw = W2C_NR * W2C_NC;
    # 每个基 = 1 个类型码 + 2 个参数 + 1 个振幅 = 4 个数
    return (nw << 16) / (W2C_N * 4);
}
