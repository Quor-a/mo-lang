# nn —— 定点神经网络（用墨语言自己写的）
#
# ## 为什么是定点
#
# 墨语言**没有浮点类型**，所以全程用 Q16.16 定点：
#
#     NN_SCALE = 65536    实数 x 存成 round(x * 65536)
#     乘法     (a*b + 32768) >> 16     ← 移位即除法，且四舍五入
#
# 选 2^16 而不是 matrix.mo 用的 1000，有三个理由：
#   1. 移位比除法快，还能四舍五入（除法的截断会累积偏差）
#   2. 精度 1/65536 ≈ 1.5e-5，神经网络够用
#   3. 值域 ±32768：权重与激活远小于此，两个数相乘最大 4.6e18 < i64 上限
#
# 注意：累加多个乘积时仍有溢出可能。若层宽度很大（>1000）应改用
# 更小的 SCALE 或分批累加。当前实现对宽度 256 以内安全。
#
# ## 激活函数
#
# 没有 exp，所以 sigmoid / tanh 用 **Padé 近似**：
#
#     tanh(x) ≈ x*(27 + x²) / (27 + 9x²)      |x| ≤ 3 内误差 < 1e-3
#
# 超出 ±3 直接饱和到 ±1 —— 这是必要的 clamp，否则 Padé 会发散
# （x=4 时算出 1.005，超过 1）。
#
#     sigmoid(x) = (1 + tanh(x/2)) / 2
import "mem.mo";
import "io.mo";

var NN_SCALE: i64 = 65536;
var NN_SHIFT: i64 = 16;
var NN_SEED: i64 = 12345;

# ---------------------------------------------------------------- 定点基础

fn nn_scale() -> i64 { return NN_SCALE; }

# 定点乘法： (a*b) / SCALE，四舍五入
fn nn_fmul(a: i64, b: i64) -> i64 {
    return (a * b + 32768) >> 16;
}

# 定点除法： (a/b) * SCALE
fn nn_fdiv(a: i64, b: i64) -> i64 {
    if b == 0 { return 0; }
    return (a * 65536) / b;
}

# 整数 → 定点
fn nn_from_i(x: i64) -> i64 { return x * 65536; }

# 定点 → 千分之一整数（0.5 → 500），只用于打印
fn nn_to_milli(x: i64) -> i64 {
    return (x * 1000 + 32768) >> 16;
}

# 整数平方根（牛顿法 + 收敛后夹逼修正）
#
# 为什么必须夹逼：只靠迭代会在边界差一。这个教训在 big.mo 的
# big_isqrt 里已经踩过一次，这里同样处理。
fn nn_isqrt(n: i64) -> i64 {
    if n <= 0 { return 0; }
    if n == 1 { return 1; }
    let x: i64 = n;
    let i: i64 = 0;
    while i < 64 {
        let y: i64 = (x + n / x) / 2;
        if y >= x { return nn_isqrt_fix(x, n); }
        x = y;
        i = i + 1;
    }
    return nn_isqrt_fix(x, n);
}

fn nn_isqrt_fix(x: i64, n: i64) -> i64 {
    while x * x > n { x = x - 1; }
    while (x + 1) * (x + 1) <= n { x = x + 1; }
    return x;
}

# 定点平方根： sqrt_fp(x) = isqrt(x * SCALE)
fn nn_fsqrt(x: i64) -> i64 {
    if x <= 0 { return 0; }
    return nn_isqrt(x * 65536);
}

# ------------------------------------------------------------ 激活函数

fn nn_tanh(x: i64) -> i64 {
    if x >= 196608 { return 65536; }        #  3.0 →  1.0
    if x <= -196608 { return -65536; }      # -3.0 → -1.0
    let xx: i64 = nn_fmul(x, x);
    let num: i64 = nn_fmul(x, 1769472 + xx);   # 27.0 = 1769472
    let den: i64 = 1769472 + 9 * xx;
    if den == 0 { return 0; }
    return nn_fdiv(num, den);
}

# ---------------------------------------------------------------- 定点 exp / log
#
# autodiff 的 softmax + 交叉熵需要它们，但没有浮点。
#
# nn_exp_neg(x)：**要求 x <= 0**，返回 exp(x) 的定点值。
# 用 Taylor 前 8 项，x∈[-∞,0] 上够用：
#   -x 很大时结果趋近 0（这正是 softmax 里要的行为）
#   不做范围检查 —— 调用方保证传负数（sce 里先减了 max）
#
# nn_log_approx(x)：**要求 x >= 1**，返回 log(x) 的定点值。
# 用 log(x) = log(m·2^e) = log(m) + e·log2 的分解，
# m∈[1,2) 上用多项式近似。
var LOG2: i64 = 45426;        # log(2) * 65536

fn nn_exp_neg(x: i64) -> i64 {
    # x <= 0。取 z = -x >= 0，算 exp(-z)
    let z: i64 = 0 - x;
    # z 超过 32 时 exp 已小于 1e-14，定点下就是 0
    if z > nn_from_i(32) { return 0; }
    # Taylor: 1 - z + z²/2 - z³/6 ...
    let t: i64 = nn_from_i(1);
    let s: i64 = nn_from_i(1);
    let i: i64 = 1;
    while i < 8 {
        t = 0 - nn_fdiv(nn_fmul(t, z), nn_from_i(i));
        s = s + t;
        i = i + 1;
    }
    if s < 0 { return 0; }
    return s;
}

fn nn_log_approx(x: i64) -> i64 {
    # x >= 65536（即 >= 1.0）
    if x < 65536 { return 0; }
    let e: i64 = 0;
    let m: i64 = x;
    while m >= 131072 {          # >= 2.0
        m = m / 2;
        e = e + 1;
    }
    # m ∈ [1, 2)，u = m - 1 ∈ [0, 1)
    let u: i64 = m - 65536;
    # log(1+u) ≈ u - u²/2 + u³/3 - u⁴/4
    let u2: i64 = nn_fmul(u, u);
    let u3: i64 = nn_fmul(u2, u);
    let u4: i64 = nn_fmul(u2, u2);
    let r: i64 = u - nn_fdiv(u2, nn_from_i(2)) + nn_fdiv(u3, nn_from_i(3)) - nn_fdiv(u4, nn_from_i(4));
    return r + nn_fmul(nn_from_i(e), LOG2);
}

fn nn_sigmoid(x: i64) -> i64 {
    let t: i64 = nn_tanh(x >> 1);           # tanh(x/2)
    return (65536 + t) >> 1;                # (1 + t) / 2
}

fn nn_relu(x: i64) -> i64 {
    if x > 0 { return x; }
    return 0;
}

# 对加权和 z 的导数（act 编码见下方常量）
fn nn_act(act: i64, z: i64) -> i64 {
    if act == 1 { return nn_relu(z); }
    if act == 2 { return nn_sigmoid(z); }
    if act == 3 { return nn_tanh(z); }
    return z;                                # 0 = 线性
}

fn nn_dact(act: i64, z: i64) -> i64 {
    if act == 1 {
        if z > 0 { return 65536; }
        return 0;
    }
    if act == 2 {
        let s: i64 = nn_sigmoid(z);
        return nn_fmul(s, 65536 - s);       # s * (1 - s)
    }
    if act == 3 {
        let t: i64 = nn_tanh(z);
        return 65536 - nn_fmul(t, t);       # 1 - t²
    }
    return 65536;                            # 线性
}

# ---------------------------------------------------------------- 随机数

# LCG：固定种子 → 可复现，测试才比对得了
fn nn_srand(s: i64) -> i64 { NN_SEED = s; return 0; }

fn nn_rand() -> i64 {
    NN_SEED = NN_SEED * 1103515245 + 12345;
    let v: i64 = (NN_SEED >> 8) & 16777215;    # 24 位
    return v - 8388608;
}

# 返回 [-r, r] 范围内的定点随机值
fn nn_rand_fp(r: i64) -> i64 {
    return nn_fmul(nn_rand() >> 7, r);        # rand>>7 ∈ [-1, 1)
}

# ------------------------------------------------------------ 网络存储

# 句柄布局（字节偏移）：
#   +0   NL   总层数（含输入层）
#   +8   SIZES 区   size[l]
#   +16  W          权重，层 l 的第 i 个输出对第 j 个输入 → woff[l] + i*size[l-1] + j
#   +24  B          偏置
#   +32  A          激活值（每层）
#   +40  Z          加权和（反向传播要用到）
#   +48  D          delta
#   +56  ACT        每层激活类型
#   +64  WOFF       每层权重起始下标
#   +72  BOFF
#   +80  AOFF

fn nn_nl(net: i64) -> i64 { return load64(net); }

fn nn_size(net: i64, l: i64) -> i64 {
    return load64(load64(net + 8) + l * 8);
}

fn nn_woff(net: i64, l: i64) -> i64 {
    return load64(load64(net + 64) + l * 8);
}

fn nn_boff(net: i64, l: i64) -> i64 {
    return load64(load64(net + 72) + l * 8);
}

fn nn_aoff(net: i64, l: i64) -> i64 {
    return load64(load64(net + 80) + l * 8);
}

fn nn_wref(net: i64, l: i64, i: i64, j: i64) -> i64 {
    return load64(net + 16) + (nn_woff(net, l) + i * nn_size(net, l - 1) + j) * 8;
}

fn nn_bref(net: i64, l: i64, i: i64) -> i64 {
    return load64(net + 24) + (nn_boff(net, l) + i) * 8;
}

fn nn_aref(net: i64, l: i64, i: i64) -> i64 {
    return load64(net + 32) + (nn_aoff(net, l) + i) * 8;
}

fn nn_zref(net: i64, l: i64, i: i64) -> i64 {
    return load64(net + 40) + (nn_aoff(net, l) + i) * 8;
}

fn nn_dref(net: i64, l: i64, i: i64) -> i64 {
    return load64(net + 48) + (nn_aoff(net, l) + i) * 8;
}

# sizes 是指向 i64 数组的指针（可直接传数组名，数组会退化为指针）
# 只在堆确实未初始化时才 init —— 重复 init 会把 hp 拉回 hb，
# 之后分配的块会覆盖掉别人已经拿到手的内存。
fn nn_ensure_heap() -> i64 {
    if heap_ready() == 0 { heap_init(); }
    return 0;
}

fn nn_new(sizes: i64, nl: i64) -> i64 {
    nn_ensure_heap();
    let nw: i64 = 0;
    let na: i64 = 0;
    let l: i64 = 0;
    while l < nl {
        let s: i64 = load64(sizes + l * 8);
        na = na + s;
        if l > 0 {
            nw = nw + load64(sizes + (l - 1) * 8) * s;
        }
        l = l + 1;
    }

    let h: i64 = alloc(88);
    if h == 0 { print("nn: alloc failed\n"); return 0; }
    store64(h, nl);
    store64(h + 8,  alloc8(nl * 8));
    store64(h + 16, alloc8(nw * 8));
    store64(h + 24, alloc8(na * 8));
    store64(h + 32, alloc8(na * 8));
    store64(h + 40, alloc8(na * 8));
    store64(h + 48, alloc8(na * 8));
    store64(h + 56, alloc8(nl * 8));
    store64(h + 64, alloc8(nl * 8));
    store64(h + 72, alloc8(nl * 8));
    store64(h + 80, alloc8(nl * 8));

    # 填 sizes 与三层偏移表
    let wacc: i64 = 0;
    let bacc: i64 = 0;
    let aacc: i64 = 0;
    let k: i64 = 0;
    while k < nl {
        let s: i64 = load64(sizes + k * 8);
        store64(load64(h + 8) + k * 8, s);
        store64(load64(h + 80) + k * 8, aacc);
        store64(load64(h + 72) + k * 8, bacc);
        store64(load64(h + 64) + k * 8, wacc);
        if k > 0 {
            wacc = wacc + load64(sizes + (k - 1) * 8) * s;
            bacc = bacc + s;
        } else {
            bacc = s;
        }
        aacc = aacc + s;
        k = k + 1;
    }
    return h;
}

fn nn_set_act(net: i64, l: i64, a: i64) -> i64 {
    store64(load64(net + 56) + l * 8, a);
    return 0;
}

# Xavier 风格初始化： w ~ U(-1/sqrt(n_in), 1/sqrt(n_in))
fn nn_rand_init(net: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let l: i64 = 1;
    while l < nl {
        let np: i64 = nn_size(net, l - 1);
        let nc: i64 = nn_size(net, l);
        let r: i64 = nn_fdiv(65536, nn_fsqrt(nn_from_i(np)));
        let i: i64 = 0;
        while i < nc {
            store64(nn_bref(net, l, i), 0);
            let j: i64 = 0;
            while j < np {
                store64(nn_wref(net, l, i, j), nn_rand_fp(r));
                j = j + 1;
            }
            i = i + 1;
        }
        l = l + 1;
    }
    return 0;
}

fn nn_set_w(net: i64, l: i64, i: i64, j: i64, v: i64) -> i64 {
    store64(nn_wref(net, l, i, j), v);
    return 0;
}

fn nn_get_w(net: i64, l: i64, i: i64, j: i64) -> i64 {
    return load64(nn_wref(net, l, i, j));
}

fn nn_set_b(net: i64, l: i64, i: i64, v: i64) -> i64 {
    store64(nn_bref(net, l, i), v);
    return 0;
}

fn nn_get_b(net: i64, l: i64, i: i64) -> i64 {
    return load64(nn_bref(net, l, i));
}

# ---------------------------------------------------------------- 前向

# 返回输出层激活值的**地址**（调用方按需读取）
fn nn_forward(net: i64, inp: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let n0: i64 = nn_size(net, 0);
    let i: i64 = 0;
    while i < n0 {
        store64(nn_aref(net, 0, i), load64(inp + i * 8));
        i = i + 1;
    }

    let l: i64 = 1;
    while l < nl {
        let np: i64 = nn_size(net, l - 1);
        let nc: i64 = nn_size(net, l);
        let act: i64 = load64(load64(net + 56) + l * 8);
        let j: i64 = 0;
        while j < nc {
            let s: i64 = load64(nn_bref(net, l, j));
            let k: i64 = 0;
            while k < np {
                let w: i64 = load64(nn_wref(net, l, j, k));
                let a: i64 = load64(nn_aref(net, l - 1, k));
                s = s + nn_fmul(w, a);
                k = k + 1;
            }
            store64(nn_zref(net, l, j), s);
            store64(nn_aref(net, l, j), nn_act(act, s));
            j = j + 1;
        }
        l = l + 1;
    }
    return load64(net + 32) + nn_aoff(net, nl - 1) * 8;
}

# ---------------------------------------------------------------- 反向

# 反向传播，**必须分两个阶段**。
#
# 曾经写成一个循环：算完 delta[l] 就顺手更新 W[l]。那是错的 ——
# 下一轮算 delta[l-1] 时还要用 W[l]，而它已经被改过了。
# 标准反向传播要求**所有 delta 都用同一份（更新前的）权重**算出。
#
# 这个 bug 很阴：XOR 照样收敛到 4/4，看不出任何异常。
# 是 Python 参考实现的逐轮 loss 比对把它揪出来的（见 tools/nnref.py）。
#
# 返回 MSE 损失（定点）
fn nn_backward_deltas(net: i64, target: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let L: i64 = nl - 1;
    let loss: i64 = 0;

    # ---- 第一阶段：从输出层往回算所有 delta（权重此刻还没动过） ----
    let l: i64 = L;
    while l >= 1 {
        let nc: i64 = nn_size(net, l);
        let act: i64 = load64(load64(net + 56) + l * 8);
        let i: i64 = 0;
        while i < nc {
            let d: i64 = 0;
            if l == L {
                let a: i64 = load64(nn_aref(net, L, i));
                let y: i64 = load64(target + i * 8);
                let e: i64 = a - y;
                loss = loss + nn_fmul(e, e);
                d = nn_fmul(e, nn_dact(act, load64(nn_zref(net, L, i))));
            } else {
                let s: i64 = 0;
                let nk: i64 = nn_size(net, l + 1);
                let k: i64 = 0;
                while k < nk {
                    let w: i64 = load64(nn_wref(net, l + 1, k, i));
                    let dk: i64 = load64(nn_dref(net, l + 1, k));
                    s = s + nn_fmul(w, dk);
                    k = k + 1;
                }
                d = nn_fmul(nn_dact(act, load64(nn_zref(net, l, i))), s);
            }
            store64(nn_dref(net, l, i), d);
            i = i + 1;
        }
        l = l - 1;
    }

    return loss;
}

# 用已算好的 delta 做一步纯 SGD 更新（nn_backward 的第二阶段抽出来，
# 供 nnx.mo 的优化器复用：先算 delta，再按自己的规则更新）
fn nn_sgd_step(net: i64, lr: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let L: i64 = nl - 1;
    let m: i64 = 1;
    while m <= L {
        let nc: i64 = nn_size(net, m);
        let np: i64 = nn_size(net, m - 1);
        let j: i64 = 0;
        while j < nc {
            let dj: i64 = load64(nn_dref(net, m, j));
            let k: i64 = 0;
            while k < np {
                let a: i64 = load64(nn_aref(net, m - 1, k));
                let g: i64 = nn_fmul(lr, nn_fmul(dj, a));
                let p: i64 = nn_wref(net, m, j, k);
                store64(p, load64(p) - g);
                k = k + 1;
            }
            let bp: i64 = nn_bref(net, m, j);
            store64(bp, load64(bp) - nn_fmul(lr, dj));
            j = j + 1;
        }
        m = m + 1;
    }
    return 0;
}

fn nn_backward(net: i64, target: i64, lr: i64) -> i64 {
    let loss: i64 = nn_backward_deltas(net, target);
    nn_sgd_step(net, lr);
    return loss;
}

# 一步训练：前向 → 反向，返回损失
fn nn_train(net: i64, x: i64, y: i64, lr: i64) -> i64 {
    nn_forward(net, x);
    return nn_backward(net, y, lr);
}

fn nn_out(net: i64, i: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    return load64(nn_aref(net, nl - 1, i));
}

# 取输出层最大值的下标（分类用）
fn nn_argmax(net: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let n: i64 = nn_size(net, nl - 1);
    let best: i64 = 0;
    let bv: i64 = load64(nn_aref(net, nl - 1, 0));
    let i: i64 = 1;
    while i < n {
        let v: i64 = load64(nn_aref(net, nl - 1, i));
        if v > bv { bv = v; best = i; }
        i = i + 1;
    }
    return best;
}

# ------------------------------------------------- 把梯度传回输入（接 CNN）

# 第一层（隐藏层）的 delta 已知，算出**输入层**每个单元的梯度：
#
#     g[i] = Σ_k W[1][k][i] * delta[1][k]
#
# 这是把全连接部分的梯度交还给卷积部分所必需的 —— CNN 的反向传播
# 要从"展平后那一段的梯度"开始往回走，没有它就连不起来。
#
# 结果写入 out（调用方提供的数组，长度 = 输入层大小）。
fn nn_input_grad(net: i64, out: i64) -> i64 {
    let n0: i64 = nn_size(net, 0);
    let n1: i64 = nn_size(net, 1);
    let i: i64 = 0;
    while i < n0 {
        let s: i64 = 0;
        let k: i64 = 0;
        while k < n1 {
            let w: i64 = load64(nn_wref(net, 1, k, i));
            let d: i64 = load64(nn_dref(net, 1, k));
            s = s + nn_fmul(w, d);
            k = k + 1;
        }
        store64(out + i * 8, s);
        i = i + 1;
    }
    return 0;
}

# ============================================================================
#  卷积核初始化：符号平衡（1.73）
# ============================================================================
#
# 🔴 为什么需要它：1.72 发现 cnn_shift 的通道 3 有 9/9 死权重，
# 根因是**初始化时该通道的 9 个核元素全为负**（-0.814 ~ -0.075），
# 而偏置为 0、输入是 0/1 二值图 —— 于是
#
#       z = Σ w·x + b ≤ 0     对**任何**输入成立
#
# relu 输出恒 0 → 梯度恒 0 → 该通道永远不会被更新，1/4 的容量浪费掉。
#
# 注意这不是"训练不好"，是**训练开始前就已经死了**。改用 leaky relu
# （1.71）或平均池化（1.72）都救不回来 —— 它们改的是梯度怎么传，
# 而这里的问题是"根本没有梯度可传"。
#
# 修法：按通道保证正负混合。全正/全负的核直接翻转一半符号。
#
# 这不是 He/Xavier 的替代品（它们管方差），而是**正交于方差**的约束：
# 方差再对，符号一边倒照样死。
fn nn_conv_init_ch(dst: ptr, nch: i64, ksz: i64, scale: i64) -> i64 {
    let c: i64 = 0;
    while c < nch {
        let i: i64 = 0;
        let nneg: i64 = 0;
        while i < ksz {
            let v: i64 = nn_rand_fp(scale);
            store64(dst + (c * ksz + i) * 8, v);
            if v < 0 { nneg = nneg + 1; }
            i = i + 1;
        }
        # 符号一边倒 → 翻转偶数下标（约一半）的符号
        if nneg == ksz { nn_flip_half(dst + c * ksz * 8, ksz); }
        if nneg == 0 { nn_flip_half(dst + c * ksz * 8, ksz); }
        c = c + 1;
    }
    return 0;
}

fn nn_flip_half(dst: ptr, n: i64) -> i64 {
    let j: i64 = 0;
    while j < n {
        if j - (j / 2) * 2 == 0 {
            let v: i64 = load64(dst + j * 8);
            store64(dst + j * 8, 0 - v);
        }
        j = j + 1;
    }
    return 0;
}

# 诊断：某通道的核是否符号一边倒（全正或全负）—— 死通道的预警指标
fn nn_ch_dead_risk(kern: ptr, c: i64, ksz: i64) -> i64 {
    let i: i64 = 0;
    let nneg: i64 = 0;
    while i < ksz {
        if load64(kern + (c * ksz + i) * 8) < 0 { nneg = nneg + 1; }
        i = i + 1;
    }
    if nneg == 0 { return 1; }
    if nneg == ksz { return 1; }
    return 0;
}
