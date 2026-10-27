# ==========================================================================
#  autodiff —— 语言级权重架构系统（可微编程）
#
#  这不是"用墨语言写个神经网络库"，而是**给墨语言装上可微性**：
#
#    用户只写前向，语言自动求导。
#
#  机制是 tape（磁带）：每个运算把 (out, a, b, op) 记下来，
#  backward 时倒着走一遍，按链式法则累积梯度。
#
#  -------------------------------------------------------------------
#  为什么这件事在墨语言上是**创新**而不是移植
#  -------------------------------------------------------------------
#  1. 全定点（Q16.16）autodiff
#     浮点 autodiff 在不同架构/编译选项下会有末位差异，
#     梯度检查只能用容差。定点 autodiff 是**逐位确定**的，
#     梯度检查可以用"精确相等或差 1"。
#
#  2. 没有 AST 也能做
#     墨语言是边解析边发射，没有中间表示。tape 是**运行时**结构，
#     绕开了"必须先有 IR 才能做自动微分"这个前提。
#
#  3. 权重是一等实体
#     W() 声明的槽自带梯度槽与"可训练"标记，
#     ad_step() 只更新被标记的槽 —— 不需要用户维护参数列表。
#
#  -------------------------------------------------------------------
#  用法
#  -------------------------------------------------------------------
#    let x: i64 = ad_input(65536);          # 输入（常量）
#    let w: i64 = ad_weight(32768);         # 权重（可训练）
#    let y: i64 = ad_mul(w, x);             # 前向，自动记 tape
#    let s: i64 = ad_sigmoid(y);
#    ad_backward(s);                        # 自动反向
#    let g: i64 = ad_grad(w);               # 拿梯度
#    ad_step(6553);                         # 一步更新（lr≈0.1）
# ==========================================================================
import "nn.mo";
import "str.mo";
import "fs.mo";

var AD_N:    i64 = 0;      # 已用值槽数
var AD_TN:   i64 = 0;      # tape 条数
var AD_MODE: i64 = 0;      # 0=前向记录 1=前向不记录（用于数值梯度）

var AD_VAL:  [2048] i64 = 0;   # 值（定点）
var AD_GRAD: [2048] i64 = 0;   # 梯度（定点）
var AD_ISW:  [2048] i64 = 0;   # 1 = 可训练权重
var AD_PAT:  [2048] i64 = 0;   # 稀疏模式：位 j = 输入 j 影响该槽（ASD，1.80）
var AD_COL:  [64]   i64 = 0;   # 列 → 颜色（ASD）
var AD_CFL:  [64]   i64 = 0;   # 列 j → 冲突列的位集（ASD）
var AD_CJC:  [64]   i64 = 0;   # 压缩 Jacobian：AD_CJC[color*nout + o]（ASD）
var AD_SNAP: [2048] i64 = 0;   # 值快照（有限差分用，1.79）
var AD_DOT:  [2048] i64 = 0;   # 前向模式的方向导数 ẋ（点积检验用，1.78）
var AD_SEED: [2048] i64 = 0;   # 种子备份（ψ_reverse = Σ grad·seed）
var AD_MOM:  [2048] i64 = 0;   # 一阶矩（动量 / Adam 的 m）
var AD_VEL:  [2048] i64 = 0;   # 二阶矩（Adam 的 v）

# 优化器状态
var AD_T:    i64 = 0;          # 步数（Adam 偏差修正用）
var AD_BC1:  i64 = 65536;      # (1-b1^t) 的递推值，初始 = 1
var AD_BC2:  i64 = 65536;      # (1-b2^t) 的递推值

var AD_TA:   [4096] i64 = 0;
var AD_TB:   [4096] i64 = 0;
var AD_TO:   [4096] i64 = 0;
var AD_TOP:  [4096] i64 = 0;
var AD_POOLPOS: [2048] i64 = 0;   # 池化选中的位置（必须在最前面声明）

var AD_TFB:  [4096] i64 = 0;   # tape 条目：b 是否为有效槽（0 = 一元算子的占位）
var AD_BID:  [2048] i64 = 0;   # 槽 → 块 id
var AD_BST:  [512]  i64 = 0;   # 块 id → 起点槽
var AD_BSZ:  [512]  i64 = 0;   # 块 id → 大小
var AD_BN:   i64 = 0;          # 块数
var AD_TXA:  [4096] i64 = 0;   # 辅助：行数 / 长度
var AD_TXB:  [4096] i64 = 0;   # 辅助：列数

# 运算编码
var OP_ADD: i64 = 1;
var OP_MUL: i64 = 2;
var OP_SUB: i64 = 3;
var OP_RELU: i64 = 4;
var OP_SIG: i64 = 5;
var OP_TANH: i64 = 6;
var OP_MATMUL: i64 = 7;
var OP_VADD: i64 = 8;
var OP_VSIG: i64 = 9;
var OP_VREL: i64 = 10;
var OP_MSE: i64 = 11;
var OP_SCE: i64 = 12;
var OP_CONV: i64 = 13;
var OP_POOL: i64 = 14;
var OP_VTAN: i64 = 15;
var OP_MMBA: i64 = 16;
var OP_MBAT: i64 = 17;
var OP_MSEH: i64 = 18;
var OP_VADD_B: i64 = 19;
var OP_CONVMC: i64 = 20;
var OP_POOLMC: i64 = 21;
var OP_GMAX: i64 = 22;
var OP_LREL: i64 = 23;
var OP_VLRL: i64 = 24;
var OP_GAVG: i64 = 25;

# leaky relu 的负半轴斜率（定点）：4096 = 1/16
# 为什么不是 0：见 1.39/1.34 —— 定点下 relu 的死区比浮点宽得多，
# 一旦某个单元的输入恒为负，它就**永远**收不到梯度，成为死权重。
# 审计在 cnn_ad 里查出 SFW 有 20 个这样的死权重（此前无人察觉）。
var AD_LRELU_NEG: i64 = 4096;

fn ad_reset() -> i64 {
    let i: i64 = 0;
    AD_N = 0;
    AD_TN = 0;
    AD_BN = 0;
    while i < 2048 { store64(&AD_BID + i * 8, 0 - 1); i = i + 1; }
    return 0;
}

fn ad_nval() -> i64 { return AD_N; }
fn ad_ntape() -> i64 { return AD_TN; }

# ---------------------------------------------------------------- 槽

fn ad_val(s: i64) -> i64 { return load64(&AD_VAL + s * 8); }
fn ad_grad(s: i64) -> i64 { return load64(&AD_GRAD + s * 8); }
fn ad_set(s: i64, v: i64) -> i64 { store64(&AD_VAL + s * 8, v); return 0; }

# 常量/输入：不可训练
fn ad_input(v: i64) -> i64 {
    let s: i64 = AD_N;
    AD_N = AD_N + 1;
    store64(&AD_VAL + s * 8, v);
    store64(&AD_GRAD + s * 8, 0);
    store64(&AD_ISW + s * 8, 0);
    return s;
}

# 权重：可训练
fn ad_weight(v: i64) -> i64 {
    let s: i64 = AD_N;
    AD_N = AD_N + 1;
    store64(&AD_VAL + s * 8, v);
    store64(&AD_GRAD + s * 8, 0);
    store64(&AD_ISW + s * 8, 1);
    return s;
}

# ---------------------------------------------------------------- 记 tape

# 只在前向记录模式下记 tape。数值梯度检查时要关掉，
# 否则每做一次扰动就往 tape 里塞一堆，会把 tape 撑爆。
fn ad_emit(op: i64, a: i64, b: i64, out: i64) -> i64 {
    if AD_MODE == 1 { return 0; }
    let t: i64 = AD_TN;
    AD_TN = AD_TN + 1;
    store64(&AD_TOP + t * 8, op);
    store64(&AD_TA + t * 8, a);
    store64(&AD_TB + t * 8, b);
    store64(&AD_TO + t * 8, out);
    store64(&AD_TXA + t * 8, 0);
    store64(&AD_TXB + t * 8, 0);
    return 0;
}

fn ad_emit2(op: i64, a: i64, b: i64, out: i64, xa: i64, xb: i64) -> i64 {
    if AD_MODE == 1 { return 0; }
    let t: i64 = AD_TN;
    AD_TN = AD_TN + 1;
    store64(&AD_TOP + t * 8, op);
    store64(&AD_TA + t * 8, a);
    store64(&AD_TB + t * 8, b);
    store64(&AD_TO + t * 8, out);
    store64(&AD_TXA + t * 8, xa);
    store64(&AD_TXB + t * 8, xb);
    # b 是否为有效槽：一元算子在调用点传 b=0，若不区分会把「槽 0」误当操作数，
    # 在计算图里凭空长出一条假边。这里集中判定，新增一元算子只需改这一处。
    store64(&AD_TFB + t * 8, 1);
    if op == OP_VSIG  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_VREL  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_VLRL  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_VTAN  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_POOLMC{ store64(&AD_TFB + t * 8, 0); }
    if op == OP_GMAX  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_GAVG  { store64(&AD_TFB + t * 8, 0); }
    if op == OP_SCE   { store64(&AD_TFB + t * 8, 0); }
    if op == OP_POOL  { store64(&AD_TFB + t * 8, 0); }
    return 0;
}

fn ad_newslot(v: i64) -> i64 {
    let s: i64 = AD_N;
    AD_N = AD_N + 1;
    store64(&AD_VAL + s * 8, v);
    store64(&AD_GRAD + s * 8, 0);
    store64(&AD_ISW + s * 8, 0);
    if AD_BN < 512 {
        store64(&AD_BID + s * 8, AD_BN);
        store64(&AD_BST + AD_BN * 8, s);
        store64(&AD_BSZ + AD_BN * 8, 1);
    }
    AD_BN = AD_BN + 1;
    return s;
}

# ---------------------------------------------------------------- 运算（前向 + 记 tape）

fn ad_add(a: i64, b: i64) -> i64 {
    let va: i64 = ad_val(a);
    let vb: i64 = ad_val(b);
    let o: i64 = ad_newslot(va + vb);
    ad_emit(OP_ADD, a, b, o);
    return o;
}

fn ad_sub(a: i64, b: i64) -> i64 {
    let va: i64 = ad_val(a);
    let vb: i64 = ad_val(b);
    let o: i64 = ad_newslot(va - vb);
    ad_emit(OP_SUB, a, b, o);
    return o;
}

fn ad_mul(a: i64, b: i64) -> i64 {
    let va: i64 = ad_val(a);
    let vb: i64 = ad_val(b);
    let o: i64 = ad_newslot(nn_fmul(va, vb));
    ad_emit(OP_MUL, a, b, o);
    return o;
}

fn ad_relu(a: i64) -> i64 {
    let va: i64 = ad_val(a);
    let o: i64 = ad_newslot(nn_relu(va));
    ad_emit(OP_RELU, a, 0, o);
    return o;
}

fn ad_sigmoid(a: i64) -> i64 {
    let va: i64 = ad_val(a);
    let o: i64 = ad_newslot(nn_sigmoid(va));
    ad_emit(OP_SIG, a, 0, o);
    return o;
}

fn ad_tanh(a: i64) -> i64 {
    let va: i64 = ad_val(a);
    let o: i64 = ad_newslot(nn_tanh(va));
    ad_emit(OP_TANH, a, 0, o);
    return o;
}

# ==========================================================================
#  梯度流审计状态（必须在 ad_backward 之前声明：符号先定义后使用）
# ==========================================================================
var AD_AUD_N:   i64 = 0;                 # 上一轮审计的问题数
var AD_AUD_SEE: [2048] i64 = 0;          # 该槽是否在 tape 里出现过
var AD_AUD_EVER: [2048] i64 = 0;         # 该槽是否**历史上**收到过非零梯度
var AD_AUD_INITN: i64 = 0;               # 初始化时符号一边倒的**组数**（1.76）

# ---------------------------------------------------------------- 反向

fn ad_zero_grad() -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        store64(&AD_GRAD + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 块槽
#
# 块 = 连续 n 个值槽，返回起始索引。矩阵按**行主序**展平在里面。
# 这样 matmul 的梯度就是纯下标算术，不需要任何 AST 或 IR ——
# tape 里只存索引，反向时按下标算术走一遍即可。

fn ad_block(n: i64) -> i64 {
    let s: i64 = AD_N;
    let i: i64 = 0;
    while i < n {
        store64(&AD_VAL + (s + i) * 8, 0);
        store64(&AD_GRAD + (s + i) * 8, 0);
        store64(&AD_ISW + (s + i) * 8, 0);
        if AD_BN < 512 { store64(&AD_BID + (s + i) * 8, AD_BN); }
        i = i + 1;
    }
    if AD_BN < 512 {
        store64(&AD_BST + AD_BN * 8, s);
        store64(&AD_BSZ + AD_BN * 8, n);
    }
    AD_BN = AD_BN + 1;
    AD_N = AD_N + n;
    return s;
}

fn ad_wblock(n: i64) -> i64 {
    let s: i64 = AD_N;
    let i: i64 = 0;
    while i < n {
        store64(&AD_VAL + (s + i) * 8, 0);
        store64(&AD_GRAD + (s + i) * 8, 0);
        store64(&AD_ISW + (s + i) * 8, 1);
        if AD_BN < 512 { store64(&AD_BID + (s + i) * 8, AD_BN); }
        i = i + 1;
    }
    if AD_BN < 512 {
        store64(&AD_BST + AD_BN * 8, s);
        store64(&AD_BSZ + AD_BN * 8, n);
    }
    AD_BN = AD_BN + 1;
    AD_N = AD_N + n;
    return s;
}

# ---------------------------------------------------------------- 块级算子

# y(nr) = W(nr*nc) · x(nc)
fn ad_matmul(w: i64, x: i64, nr: i64, nc: i64) -> i64 {
    let o: i64 = ad_block(nr);
    let i: i64 = 0;
    while i < nr {
        let acc: i64 = 0;
        let j: i64 = 0;
        while j < nc {
            let wv: i64 = ad_val(w + i * nc + j);
            let xv: i64 = ad_val(x + j);
            acc = acc + nn_fmul(wv, xv);
            j = j + 1;
        }
        ad_set(o + i, acc);
        i = i + 1;
    }
    ad_emit2(OP_MATMUL, w, x, o, nr, nc);
    return o;
}

# 逐元素相加：y(i) = a(i) + b(i)
fn ad_vadd(a: i64, b: i64, n: i64) -> i64 {
    let o: i64 = ad_block(n);
    let i: i64 = 0;
    while i < n {
        ad_set(o + i, ad_val(a + i) + ad_val(b + i));
        i = i + 1;
    }
    ad_emit2(OP_VADD, a, b, o, n, 0);
    return o;
}

# Leaky ReLU（标量）：x>0 走原值，x<=0 走 AD_LRELU_NEG·x
#
# 与 ad_relu 的区别只有负半轴导数：relu 是 0（梯度完全阻断），
# leaky 是 AD_LRELU_NEG（保留一条细流）。这条细流足以让
# 死权重重新参与训练，代价是引入一点点非线性偏差。
fn ad_lrelu(a: i64) -> i64 {
    let o: i64 = ad_block(1);
    if ad_val(a) > 0 { ad_set(o, ad_val(a)); }
    else { ad_set(o, nn_fmul(AD_LRELU_NEG, ad_val(a))); }
    ad_emit(OP_LREL, a, 0, o);
    return o;
}

fn ad_slope(s: i64) -> i64 {
    AD_LRELU_NEG = s;
    return s;
}

fn ad_vsig(a: i64, n: i64) -> i64 {
    let o: i64 = ad_block(n);
    let i: i64 = 0;
    while i < n {
        ad_set(o + i, nn_sigmoid(ad_val(a + i)));
        i = i + 1;
    }
    ad_emit2(OP_VSIG, a, 0, o, n, 0);
    return o;
}

fn ad_vrelu(a: i64, n: i64) -> i64 {
    let o: i64 = ad_block(n);
    let i: i64 = 0;
    while i < n {
        ad_set(o + i, nn_relu(ad_val(a + i)));
        i = i + 1;
    }
    ad_emit2(OP_VREL, a, 0, o, n, 0);
    return o;
}

# Leaky ReLU（块级）
fn ad_vlrelu(a: i64, n: i64) -> i64 {
    let o: i64 = ad_block(n);
    let i: i64 = 0;
    while i < n {
        if ad_val(a + i) > 0 { ad_set(o + i, ad_val(a + i)); }
        else { ad_set(o + i, nn_fmul(AD_LRELU_NEG, ad_val(a + i))); }
        i = i + 1;
    }
    ad_emit2(OP_VLRL, a, 0, o, n, 0);
    return o;
}

# 均方误差：loss = Σ(y-t)² / n，返回**标量**槽
fn ad_mse(y: i64, tgt: i64, n: i64) -> i64 {
    let acc: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let d: i64 = ad_val(y + i) - ad_val(tgt + i);
        acc = acc + nn_fmul(d, d);
        i = i + 1;
    }
    let o: i64 = ad_newslot(nn_fdiv(acc, nn_from_i(n)));
    ad_emit2(OP_MSE, y, tgt, o, n, 0);
    return o;
}

fn ad_vtanh(a: i64, n: i64) -> i64 {
    let o: i64 = ad_block(n);
    let i: i64 = 0;
    while i < n {
        ad_set(o + i, nn_tanh(ad_val(a + i)));
        i = i + 1;
    }
    ad_emit2(OP_VTAN, a, 0, o, n, 0);
    return o;
}

# ½·MSE：dL/dy = (y-t)/n
#
# 为什么要有这个：nn.mo 的手写反向用的是 e·act'（= ½Σe² 的梯度），
# 但它**报告的 loss 是 Σe²**。两者不自洽 —— 用 ad_mse（真·MSE，
# 梯度带 2）去比，两条训练路径必然发散，正是这个不自洽暴露出来的。
#
# ad_mse_half 与 nn.mo 的约定一致，用来做**逐轮等价性**比对。
fn ad_mse_half(y: i64, tgt: i64, n: i64) -> i64 {
    let acc: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let d: i64 = ad_val(y + i) - ad_val(tgt + i);
        acc = acc + nn_fmul(d, d);
        i = i + 1;
    }
    # loss 报告为 Σe²/n（与 ad_mse 一样的数值），
    # 但反向用 (y-t)/n —— 对应 ½Σe² 的梯度。
    let o: i64 = ad_newslot(nn_fdiv(acc, nn_from_i(n)));
    ad_emit2(OP_MSEH, y, tgt, o, n, 0);
    return o;
}

# ---------------------------------------------------------------- batch
#
# 约定：X 是 **nc × bs** 矩阵（列主样本），即 X[feature][sample]。
# 这样 W 的每一项在整个 batch 上只需更新一次。
#
#   Z(nr × bs) = W(nr × nc) · X(nc × bs)
#
# 反向：
#   dW[i][j] = Σ_b gy[i][b] · X[j][b]
#   dX[j][b] = Σ_i gy[i][b] · W[i][j]
#
# 与单样本相比，建图次数从 bs 次降到 1 次。

fn ad_matmul_batch(w: i64, x: i64, nr: i64, nc: i64, bs: i64) -> i64 {
    let o: i64 = ad_block(nr * bs);
    let i: i64 = 0;
    while i < nr {
        let b: i64 = 0;
        while b < bs {
            let acc: i64 = 0;
            let j: i64 = 0;
            while j < nc {
                acc = acc + nn_fmul(ad_val(w + i * nc + j), ad_val(x + j * bs + b));
                j = j + 1;
            }
            ad_set(o + i * bs + b, acc);
            b = b + 1;
        }
        i = i + 1;
    }
    # aux: nr, nc, bs（三项，用 TXA/TXB 存 nr/nc，bs 由 nr*bs 反推不够，
    # 所以改用约定：TXA=nr*1000+nc，TXB=bs —— 太脏，改为存 op 时同时记）
    ad_emit2(OP_MMBA, w, x, o, nr * 1000 + nc, bs);
    return o;
}

# 转置乘：Y(nr × nc) = A(nr × bs) · B(nc × bs)ᵀ
# 用于 dW = gy · Xᵀ，也用于一次性算 batch 的输出
fn ad_matmul_at(a: i64, b: i64, nr: i64, bs: i64, nc: i64) -> i64 {
    let o: i64 = ad_block(nr * nc);
    let i: i64 = 0;
    while i < nr {
        let j: i64 = 0;
        while j < nc {
            let acc: i64 = 0;
            let k: i64 = 0;
            while k < bs {
                acc = acc + nn_fmul(ad_val(a + i * bs + k), ad_val(b + j * bs + k));
                k = k + 1;
            }
            ad_set(o + i * nc + j, acc);
            j = j + 1;
        }
        i = i + 1;
    }
    ad_emit2(OP_MBAT, a, b, o, nr * 1000 + bs, nc);
    return o;
}

# ---------------------------------------------------------------- 广播 + 多通道卷积

# 偏置广播：Y(nr × bs) = A(nr × bs) + b(nr)
#
# 没有这个就得手工把偏置复制 bs 份填进一个块（batch.mo 里就是这么绕的），
# 既啰嗦又容易错。广播是 batch 训练的必需品。
fn ad_vadd_bcast(a: i64, b: i64, nr: i64, bs: i64) -> i64 {
    let o: i64 = ad_block(nr * bs);
    let i: i64 = 0;
    while i < nr {
        let j: i64 = 0;
        while j < bs {
            ad_set(o + i * bs + j, ad_val(a + i * bs + j) + ad_val(b + i));
            j = j + 1;
        }
        i = i + 1;
    }
    ad_emit2(OP_VADD_B, a, b, o, nr, bs);
    return o;
}

# 多通道卷积（valid 3×3，无 stride、无 padding）
#
#   输入 inp: ci 通道，每通道 h×w       布局 [ci][h*w]
#   核   k  : co 个核，每个 ci×3×3      布局 [co][ci][9]
#   输出 o  : co 通道，每通道 oh×ow     布局 [co][oh*ow]
#
#   单通道卷积只能描述"一个特征图"，做不了真正的图像网络 ——
#   多通道才是 CNN 的实质。
fn ad_conv_mc(inp: i64, k: i64, h: i64, w: i64, ci: i64, co: i64) -> i64 {
    let oh: i64 = h - 2;
    let ow: i64 = w - 2;
    let o: i64 = ad_block(co * oh * ow);
    let oc: i64 = 0;
    while oc < co {
        let i: i64 = 0;
        while i < oh {
            let j: i64 = 0;
            while j < ow {
                let acc: i64 = 0;
                let c: i64 = 0;
                while c < ci {
                    let ki: i64 = 0;
                    while ki < 3 {
                        let kj: i64 = 0;
                        while kj < 3 {
                            let iv: i64 = ad_val(inp + c * h * w + (i + ki) * w + (j + kj));
                            let kv: i64 = ad_val(k + oc * ci * 9 + c * 9 + ki * 3 + kj);
                            acc = acc + nn_fmul(iv, kv);
                            kj = kj + 1;
                        }
                        ki = ki + 1;
                    }
                    c = c + 1;
                }
                ad_set(o + oc * oh * ow + i * ow + j, acc);
                j = j + 1;
            }
            i = i + 1;
        }
        oc = oc + 1;
    }
    # aux 编码：nr = h*1000 + w，nc = ci*1000 + co（都 < 1000）
    ad_emit2(OP_CONVMC, inp, k, o, h * 1000 + w, ci * 1000 + co);
    return o;
}

# 多通道 2×2 最大池化：inp 布局 [co][h*w] → out 布局 [co][(h/2)*(w/2)]
#
# 为什么必须有这个（而不是逐通道调 ad_pool）：
#   逐通道调用时，我得先把 c3 的切片**用 ad_set 拷进一个新块**，
#   而 ad_set 不记 tape —— 梯度到拷贝出的块就断了，
#   **卷积层根本收不到梯度**，训练的全是后面几层。
#   结果看上去能收敛（8/8），但卷积核从未被更新过。
#
#   所以这里一次性处理全部通道，tape 直接连回 inp。
fn ad_pool_mc(inp: i64, co: i64, h: i64, w: i64) -> i64 {
    let oh: i64 = h / 2;
    let ow: i64 = w / 2;
    let o: i64 = ad_block(co * oh * ow);
    let c: i64 = 0;
    while c < co {
        let i: i64 = 0;
        while i < oh {
            let j: i64 = 0;
            while j < ow {
                let v0: i64 = ad_val(inp + c * h * w + (i*2)*w + (j*2));
                let v1: i64 = ad_val(inp + c * h * w + (i*2)*w + (j*2+1));
                let v2: i64 = ad_val(inp + c * h * w + (i*2+1)*w + (j*2));
                let v3: i64 = ad_val(inp + c * h * w + (i*2+1)*w + (j*2+1));
                let mv: i64 = v0;
                let pos: i64 = 0;
                if v1 > mv { mv = v1; pos = 1; }
                if v2 > mv { mv = v2; pos = 2; }
                if v3 > mv { mv = v3; pos = 3; }
                let oi: i64 = o + c * oh * ow + i * ow + j;
                ad_set(oi, mv);
                store64(&AD_POOLPOS + oi * 8, pos);
                j = j + 1;
            }
            i = i + 1;
        }
        c = c + 1;
    }
    ad_emit2(OP_POOLMC, inp, 0, o, co * 1000 + h, w);
    return o;
}

# 全局最大池化：inp 布局 [co][h*w] → out 布局 [co]，每通道取最大值
#
# **为什么需要它**：
#   pool → flatten → FC 这条老路，flatten 出来接全连接是**位置相关**的，
#   平移不变性被后面的全连接破坏掉了。实测 conv+pool+FC(36→2) 在
#   "未见位置"上只有 15/24，跟纯全连接的 13/24 几乎没差别。
#
#   全局池化把每个通道压成一个数 —— 无论特征出现在图像的哪个位置，
#   这一通道的最大值都一样。**这才是真正的平移不变性**。
fn ad_gmax_mc(inp: i64, co: i64, n: i64) -> i64 {
    let o: i64 = ad_block(co);
    let c: i64 = 0;
    while c < co {
        let mv: i64 = ad_val(inp + c * n);
        let mp: i64 = 0;
        let i: i64 = 1;
        while i < n {
            if ad_val(inp + c * n + i) > mv {
                mv = ad_val(inp + c * n + i);
                mp = i;
            }
            i = i + 1;
        }
        let oi: i64 = o + c;
        ad_set(oi, mv);
        store64(&AD_POOLPOS + oi * 8, mp);
        c = c + 1;
    }
    ad_emit2(OP_GMAX, inp, 0, o, co, n);
    return o;
}

# 全局平均池化（多通道）：每通道 n 个位置取平均。
#
# 与 gmax 的**梯度行为**完全不同：gmax 只把梯度传给每通道的最大值位置
# （n 个里 1 个），gavg 平均传给全部 n 个。
#
# 动机：1.71 的审计显示 cnn_shift 的卷积核有 13/36 是死权重，而换 leaky
# relu 只减到 13（少 3 个）—— 说明瓶颈不在激活，怀疑在池化的稀疏梯度。
# 这个算子就是用来做那个对照实验的。
fn ad_gavg_mc(inp: i64, co: i64, n: i64) -> i64 {
    let o: i64 = ad_block(co);
    let c: i64 = 0;
    while c < co {
        let acc: i64 = 0;
        let i: i64 = 0;
        while i < n {
            acc = acc + ad_val(inp + c * n + i);
            i = i + 1;
        }
        ad_set(o + c, nn_fdiv(acc, nn_from_i(n)));
        c = c + 1;
    }
    ad_emit2(OP_GAVG, inp, 0, o, co, n);
    return o;
}

# ---------------------------------------------------------------- 分类头

# L = -log(softmax(logits)[t])
#
# **为什么不先算 softmax 再取 log**：exp(x) 很容易溢出
# （x > 45 时定点直接爆）。
# 用 -x[t] + logsumexp(x) 这个等价形式，内部先减去最大值，
# 数值上是稳定的 —— 这在浮点里是标准做法，定点下更重要。
fn ad_sce(logits: i64, n: i64, t: i64) -> i64 {
    # mx = max(x)
    let mx: i64 = ad_val(logits + 0);
    let i: i64 = 1;
    while i < n {
        if ad_val(logits + i) > mx { mx = ad_val(logits + i); }
        i = i + 1;
    }
    # lse = log Σ exp(x[i] - mx)
    let ssum: i64 = 0;
    i = 0;
    while i < n {
        ssum = ssum + nn_exp_neg(ad_val(logits + i) - mx);
        i = i + 1;
    }
    let lse: i64 = mx + nn_log_approx(ssum);
    let o: i64 = ad_newslot(lse - ad_val(logits + t));
    ad_emit2(OP_SCE, logits, 0, o, n, t);
    return o;
}

# ---------------------------------------------------------------- 卷积

# 单通道 3×3 valid 卷积，输出 (H-2)×(W-2)
fn ad_conv(inp: i64, k: i64, h: i64, w: i64) -> i64 {
    let oh: i64 = h - 2;
    let ow: i64 = w - 2;
    let o: i64 = ad_block(oh * ow);
    let i: i64 = 0;
    while i < oh {
        let j: i64 = 0;
        while j < ow {
            let acc: i64 = 0;
            let ki: i64 = 0;
            while ki < 3 {
                let kj: i64 = 0;
                while kj < 3 {
                    let iv: i64 = ad_val(inp + (i + ki) * w + (j + kj));
                    let kv: i64 = ad_val(k + ki * 3 + kj);
                    acc = acc + nn_fmul(iv, kv);
                    kj = kj + 1;
                }
                ki = ki + 1;
            }
            ad_set(o + i * ow + j, acc);
            j = j + 1;
        }
        i = i + 1;
    }
    ad_emit2(OP_CONV, inp, k, o, h, w);
    return o;
}

# 2×2 最大池化。位置记在 AD_POOLPOS（见文件顶部声明）。
fn ad_pool(inp: i64, h: i64, w: i64) -> i64 {
    let oh: i64 = h / 2;
    let ow: i64 = w / 2;
    let o: i64 = ad_block(oh * ow);
    let i: i64 = 0;
    while i < oh {
        let j: i64 = 0;
        while j < ow {
            let v0: i64 = ad_val(inp + (i*2)*w + (j*2));
            let v1: i64 = ad_val(inp + (i*2)*w + (j*2+1));
            let v2: i64 = ad_val(inp + (i*2+1)*w + (j*2));
            let v3: i64 = ad_val(inp + (i*2+1)*w + (j*2+1));
            let mv: i64 = v0;
            let pos: i64 = 0;
            if v1 > mv { mv = v1; pos = 1; }
            if v2 > mv { mv = v2; pos = 2; }
            if v3 > mv { mv = v3; pos = 3; }
            ad_set(o + i * ow + j, mv);
            store64(&AD_POOLPOS + (o + i * ow + j) * 8, pos);
            j = j + 1;
        }
        i = i + 1;
    }
    ad_emit2(OP_POOL, inp, 0, o, h, w);
    return o;
}

# ---------------------------------------------------------------- 反向
#
# 每个 op 用**独立的 if**而不是 else-if 链：op 互斥所以语义等价，
# 但加新算子只需追加一个 if，不用往深嵌套里塞。

fn ad_backward(loss: i64) -> i64 {
    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));

    # 所有循环变量在**循环外**声明：墨语言的 let 在循环体内会累积栈帧
    let t: i64 = AD_TN - 1;
    let op: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let o: i64 = 0;
    let go: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let va: i64 = 0;
    let vb: i64 = 0;
    let acc: i64 = 0;
    let d: i64 = 0;
    let gi: i64 = 0;

    while t >= 0 {
        op = load64(&AD_TOP + t * 8);
        a = load64(&AD_TA + t * 8);
        b = load64(&AD_TB + t * 8);
        o = load64(&AD_TO + t * 8);
        go = load64(&AD_GRAD + o * 8);
        nr = load64(&AD_TXA + t * 8);
        nc = load64(&AD_TXB + t * 8);

        # ---- 标量 ----
        if op == OP_ADD {
            store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + go);
            store64(&AD_GRAD + b * 8, load64(&AD_GRAD + b * 8) + go);
        }
        if op == OP_SUB {
            store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + go);
            store64(&AD_GRAD + b * 8, load64(&AD_GRAD + b * 8) - go);
        }
        if op == OP_MUL {
            va = ad_val(a);
            vb = ad_val(b);
            store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + nn_fmul(go, vb));
            store64(&AD_GRAD + b * 8, load64(&AD_GRAD + b * 8) + nn_fmul(go, va));
        }
        if op == OP_RELU {
            if ad_val(a) > 0 {
                store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + go);
            }
        }
        if op == OP_LREL {
            if ad_val(a) > 0 {
                store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + go);
            } else {
                store64(&AD_GRAD + a * 8,
                        load64(&AD_GRAD + a * 8) + nn_fmul(go, AD_LRELU_NEG));
            }
        }
        if op == OP_SIG {
            va = ad_val(o);
            d = nn_fmul(va, nn_from_i(1) - va);
            store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + nn_fmul(go, d));
        }
        if op == OP_TANH {
            va = ad_val(o);
            d = nn_from_i(1) - nn_fmul(va, va);
            store64(&AD_GRAD + a * 8, load64(&AD_GRAD + a * 8) + nn_fmul(go, d));
        }

        # ---- 块 ----
        # matmul: y = W·x
        #   dW[i][j] += gy[i] * x[j]
        #   dx[j]    += Σ_i gy[i] * W[i][j]
        if op == OP_MATMUL {
            i = 0;
            while i < nr {
                gi = load64(&AD_GRAD + (o + i) * 8);
                j = 0;
                while j < nc {
                    va = ad_val(a + i * nc + j);        # W[i][j]：**更新前**的值
                    vb = ad_val(b + j);                 # x[j]
                    store64(&AD_GRAD + (a + i * nc + j) * 8,
                            load64(&AD_GRAD + (a + i * nc + j) * 8) + nn_fmul(gi, vb));
                    store64(&AD_GRAD + (b + j) * 8,
                            load64(&AD_GRAD + (b + j) * 8) + nn_fmul(gi, va));
                    j = j + 1;
                }
                i = i + 1;
            }
        }
        if op == OP_VADD {
            i = 0;
            while i < nr {
                store64(&AD_GRAD + (a + i) * 8,
                        load64(&AD_GRAD + (a + i) * 8) + load64(&AD_GRAD + (o + i) * 8));
                store64(&AD_GRAD + (b + i) * 8,
                        load64(&AD_GRAD + (b + i) * 8) + load64(&AD_GRAD + (o + i) * 8));
                i = i + 1;
            }
        }
        if op == OP_VSIG {
            i = 0;
            while i < nr {
                va = ad_val(o + i);
                d = nn_fmul(va, nn_from_i(1) - va);
                store64(&AD_GRAD + (a + i) * 8,
                        load64(&AD_GRAD + (a + i) * 8) + nn_fmul(load64(&AD_GRAD + (o + i) * 8), d));
                i = i + 1;
            }
        }
        if op == OP_VREL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 {
                    store64(&AD_GRAD + (a + i) * 8,
                            load64(&AD_GRAD + (a + i) * 8) + load64(&AD_GRAD + (o + i) * 8));
                }
                i = i + 1;
            }
        }
        if op == OP_VLRL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 {
                    store64(&AD_GRAD + (a + i) * 8,
                            load64(&AD_GRAD + (a + i) * 8) + load64(&AD_GRAD + (o + i) * 8));
                } else {
                    store64(&AD_GRAD + (a + i) * 8,
                            load64(&AD_GRAD + (a + i) * 8)
                            + nn_fmul(load64(&AD_GRAD + (o + i) * 8), AD_LRELU_NEG));
                }
                i = i + 1;
            }
        }
        # 分类头
        # L = -x[t] + lse  →  dL/dx[i] = softmax(x)[i] - (i==t)
        if op == OP_SCE {
            let mx2: i64 = ad_val(a + 0);
            let p: i64 = 1;
            while p < nr {
                if ad_val(a + p) > mx2 { mx2 = ad_val(a + p); }
                p = p + 1;
            }
            let zz: i64 = 0;
            p = 0;
            while p < nr {
                zz = zz + nn_exp_neg(ad_val(a + p) - mx2);
                p = p + 1;
            }
            p = 0;
            while p < nr {
                # softmax(x)[p]
                let sm: i64 = nn_fdiv(nn_exp_neg(ad_val(a + p) - mx2), zz);
                let ind: i64 = sm;
                if p == nc { ind = sm - 65536; }
                store64(&AD_GRAD + (a + p) * 8,
                        load64(&AD_GRAD + (a + p) * 8) + nn_fmul(go, ind));
                p = p + 1;
            }
        }
        # conv: dIn 累加、dK 累加（与 cnn.mo 同样的"顺序无关但必须全算"）
        if op == OP_CONV {
            let oh2: i64 = nr - 2;
            let ow2: i64 = nc - 2;
            let ci: i64 = 0;
            while ci < oh2 {
                let cj: i64 = 0;
                while cj < ow2 {
                    gi = load64(&AD_GRAD + (o + ci * ow2 + cj) * 8);
                    let ki2: i64 = 0;
                    while ki2 < 3 {
                        let kj2: i64 = 0;
                        while kj2 < 3 {
                            let ioff: i64 = (ci + ki2) * nc + (cj + kj2);
                            va = ad_val(a + ioff);
                            vb = ad_val(b + ki2 * 3 + kj2);
                            store64(&AD_GRAD + (a + ioff) * 8,
                                    load64(&AD_GRAD + (a + ioff) * 8) + nn_fmul(gi, vb));
                            store64(&AD_GRAD + (b + ki2 * 3 + kj2) * 8,
                                    load64(&AD_GRAD + (b + ki2 * 3 + kj2) * 8) + nn_fmul(gi, va));
                            kj2 = kj2 + 1;
                        }
                        ki2 = ki2 + 1;
                    }
                    cj = cj + 1;
                }
                ci = ci + 1;
            }
        }
        if op == OP_VTAN {
            let qi: i64 = 0;
            while qi < nr {
                va = ad_val(o + qi);
                d = nn_from_i(1) - nn_fmul(va, va);
                store64(&AD_GRAD + (a + qi) * 8,
                        load64(&AD_GRAD + (a + qi) * 8) + nn_fmul(load64(&AD_GRAD + (o + qi) * 8), d));
                qi = qi + 1;
            }
        }
        # batch matmul：Z = W·X
        if op == OP_MMBA {
            let bn: i64 = nr / 1000;
            let bc: i64 = nr - bn * 1000;
            let bs2: i64 = nc;
            let bi: i64 = 0;
            while bi < bn {
                let bj: i64 = 0;
                while bj < bc {
                    let gacc: i64 = 0;
                    let bb2: i64 = 0;
                    while bb2 < bs2 {
                        gacc = gacc + nn_fmul(load64(&AD_GRAD + (o + bi * bs2 + bb2) * 8),
                                              ad_val(b + bj * bs2 + bb2));
                        bb2 = bb2 + 1;
                    }
                    store64(&AD_GRAD + (a + bi * bc + bj) * 8,
                            load64(&AD_GRAD + (a + bi * bc + bj) * 8) + gacc);
                    bj = bj + 1;
                }
                bi = bi + 1;
            }
            # dX[j][b] = Σ_i gy[i][b] · W[i][j]
            let bj2: i64 = 0;
            while bj2 < bc {
                let bb3: i64 = 0;
                while bb3 < bs2 {
                    let sacc: i64 = 0;
                    let bi3: i64 = 0;
                    while bi3 < bn {
                        sacc = sacc + nn_fmul(load64(&AD_GRAD + (o + bi3 * bs2 + bb3) * 8),
                                              ad_val(a + bi3 * bc + bj2));
                        bi3 = bi3 + 1;
                    }
                    store64(&AD_GRAD + (b + bj2 * bs2 + bb3) * 8,
                            load64(&AD_GRAD + (b + bj2 * bs2 + bb3) * 8) + sacc);
                    bb3 = bb3 + 1;
                }
                bj2 = bj2 + 1;
            }
        }
        # Y = A·Bᵀ
        if op == OP_MBAT {
            let an: i64 = nr / 1000;
            let abs2: i64 = nr - an * 1000;
            let an2: i64 = nc;
            let ai: i64 = 0;
            while ai < an {
                let aj: i64 = 0;
                while aj < an2 {
                    let gij: i64 = load64(&AD_GRAD + (o + ai * an2 + aj) * 8);
                    let ak: i64 = 0;
                    while ak < abs2 {
                        store64(&AD_GRAD + (a + ai * abs2 + ak) * 8,
                                load64(&AD_GRAD + (a + ai * abs2 + ak) * 8)
                                + nn_fmul(gij, ad_val(b + aj * abs2 + ak)));
                        store64(&AD_GRAD + (b + aj * abs2 + ak) * 8,
                                load64(&AD_GRAD + (b + aj * abs2 + ak) * 8)
                                + nn_fmul(gij, ad_val(a + ai * abs2 + ak)));
                        ak = ak + 1;
                    }
                    aj = aj + 1;
                }
                ai = ai + 1;
            }
        }
        # 广播加：db[i] = Σ_b gy[i][b]（**累加**，不是赋值）
        if op == OP_VADD_B {
            let bn2: i64 = nr;
            let bs3: i64 = nc;
            let bi2: i64 = 0;
            while bi2 < bn2 {
                let bj3: i64 = 0;
                while bj3 < bs3 {
                    store64(&AD_GRAD + (a + bi2 * bs3 + bj3) * 8,
                            load64(&AD_GRAD + (a + bi2 * bs3 + bj3) * 8)
                            + load64(&AD_GRAD + (o + bi2 * bs3 + bj3) * 8));
                    bj3 = bj3 + 1;
                }
                bi2 = bi2 + 1;
            }
            let bi3: i64 = 0;
            while bi3 < bn2 {
                let bj4: i64 = 0;
                while bj4 < bs3 {
                    store64(&AD_GRAD + (b + bi3) * 8,
                            load64(&AD_GRAD + (b + bi3) * 8)
                            + load64(&AD_GRAD + (o + bi3 * bs3 + bj4) * 8));
                    bj4 = bj4 + 1;
                }
                bi3 = bi3 + 1;
            }
        }
        # 多通道卷积
        #   dK[oc][c][ki][kj] += Σ_{i,j} gy[oc][i][j] · In[c][i+ki][j+kj]
        #   dIn[c][i+ki][j+kj] += Σ_{oc} gy[oc][i][j] · K[oc][c][ki][kj]
        if op == OP_CONVMC {
            let mh: i64 = nr / 1000;
            let mw: i64 = nr - mh * 1000;
            let mci: i64 = nc / 1000;
            let mco: i64 = nc - mci * 1000;
            let moh: i64 = mh - 2;
            let mow: i64 = mw - 2;
            let oc2: i64 = 0;
            while oc2 < mco {
                let ci2: i64 = 0;
                while ci2 < mci {
                    let mi: i64 = 0;
                    while mi < moh {
                        let mj: i64 = 0;
                        while mj < mow {
                            let gv: i64 = load64(&AD_GRAD + (o + oc2 * moh * mow + mi * mow + mj) * 8);
                            let ki3: i64 = 0;
                            while ki3 < 3 {
                                let kj3: i64 = 0;
                                while kj3 < 3 {
                                    let iidx: i64 = ci2 * mh * mw + (mi + ki3) * mw + (mj + kj3);
                                    let kidx: i64 = oc2 * mci * 9 + ci2 * 9 + ki3 * 3 + kj3;
                                    va = ad_val(a + iidx);
                                    vb = ad_val(b + kidx);
                                    store64(&AD_GRAD + (a + iidx) * 8,
                                            load64(&AD_GRAD + (a + iidx) * 8) + nn_fmul(gv, vb));
                                    store64(&AD_GRAD + (b + kidx) * 8,
                                            load64(&AD_GRAD + (b + kidx) * 8) + nn_fmul(gv, va));
                                    kj3 = kj3 + 1;
                                }
                                ki3 = ki3 + 1;
                            }
                            mj = mj + 1;
                        }
                        mi = mi + 1;
                    }
                    ci2 = ci2 + 1;
                }
                oc2 = oc2 + 1;
            }
        }
        # 多通道池化：梯度只回传到每个窗口被选中的位置
        if op == OP_POOLMC {
            let pco: i64 = nr / 1000;
            let ph2: i64 = nr - pco * 1000;
            let pw2: i64 = nc;
            let poh: i64 = ph2 / 2;
            let pow2: i64 = pw2 / 2;
            let pc: i64 = 0;
            while pc < pco {
                let pi2: i64 = 0;
                while pi2 < poh {
                    let pj2: i64 = 0;
                    while pj2 < pow2 {
                        let oi2: i64 = o + pc * poh * pow2 + pi2 * pow2 + pj2;
                        let ps2: i64 = load64(&AD_POOLPOS + oi2 * 8);
                        let di2: i64 = pc * ph2 * pw2 + (pi2 * 2 + ps2 / 2) * pw2 + (pj2 * 2 + ps2 & 1);
                        store64(&AD_GRAD + (a + di2) * 8,
                                load64(&AD_GRAD + (a + di2) * 8) + load64(&AD_GRAD + oi2 * 8));
                        pj2 = pj2 + 1;
                    }
                    pi2 = pi2 + 1;
                }
                pc = pc + 1;
            }
        }
        # 全局最大池化：梯度只给每通道的最大值位置
        if op == OP_GAVG {
            let gc: i64 = 0;
            while gc < nr {
                # 梯度平均分摊到该通道全部 n 个位置
                let pg: i64 = nn_fdiv(load64(&AD_GRAD + (o + gc) * 8), nn_from_i(nc));
                let pi: i64 = 0;
                while pi < nc {
                    store64(&AD_GRAD + (a + gc * nc + pi) * 8,
                            load64(&AD_GRAD + (a + gc * nc + pi) * 8) + pg);
                    pi = pi + 1;
                }
                gc = gc + 1;
            }
        }
        if op == OP_GMAX {
            let gc: i64 = 0;
            while gc < nr {
                let gp: i64 = load64(&AD_POOLPOS + (o + gc) * 8);
                store64(&AD_GRAD + (a + gc * nc + gp) * 8,
                        load64(&AD_GRAD + (a + gc * nc + gp) * 8)
                        + load64(&AD_GRAD + (o + gc) * 8));
                gc = gc + 1;
            }
        }
        # ½·MSE：dy[i] = (y[i]-t[i])/n（NN 的约定，梯度不含 2）
        if op == OP_MSEH {
            let hi: i64 = 0;
            while hi < nr {
                d = ad_val(a + hi) - ad_val(b + hi);
                acc = nn_fdiv(d, nn_from_i(nr));
                store64(&AD_GRAD + (a + hi) * 8,
                        load64(&AD_GRAD + (a + hi) * 8) + nn_fmul(go, acc));
                hi = hi + 1;
            }
        }
        # pool: 梯度只回传到被选中的那个位置
        if op == OP_POOL {
            let oh3: i64 = nr / 2;
            let ow3: i64 = nc / 2;
            let pi: i64 = 0;
            while pi < oh3 {
                let pj: i64 = 0;
                while pj < ow3 {
                    let oi: i64 = o + pi * ow3 + pj;
                    let ps: i64 = load64(&AD_POOLPOS + oi * 8);
                    let di: i64 = (pi * 2 + ps / 2) * nc + (pj * 2 + ps & 1);
                    store64(&AD_GRAD + (a + di) * 8,
                            load64(&AD_GRAD + (a + di) * 8) + load64(&AD_GRAD + oi * 8));
                    pj = pj + 1;
                }
                pi = pi + 1;
            }
        }
        # mse: loss = Σ(y-t)²/n  →  dy[i] = 2(y[i]-t[i])/n
        if op == OP_MSE {
            i = 0;
            while i < nr {
                d = ad_val(a + i) - ad_val(b + i);
                acc = nn_fmul(nn_from_i(2), d);
                acc = nn_fdiv(acc, nn_from_i(nr));
                store64(&AD_GRAD + (a + i) * 8,
                        load64(&AD_GRAD + (a + i) * 8) + nn_fmul(go, acc));
                i = i + 1;
            }
        }
        t = t - 1;
    }
    ad_ever_mark();
    return 0;
}

# 🔴 EVER 必须**每步**更新，不能只在 ad_audit() 里采一次。
#
# 第一版把 EVER 的更新放在 ad_audit() 里，结果 cnn_ad 报出
# "卷积核几乎全部从未收到过非零梯度" —— 可它明明更新了 23/36。
# 原因：训练跑了 1600 步，而 audit 只在 epoch 0 和 199 调了两次，
# EVER 只采样到那两个瞬间。某个权重在采样那一刻梯度为 0，就被
# 永久判成"从未"。
#
# 这是**验证工具自身的 bug**，且它表现为"被测代码有问题"。
# 和 1.42 那轮 ppc64 脚本字节序错、把正确产物判成失败，是同一类。
# 教训：验证工具报错时，先怀疑工具，再怀疑被测对象。
# 该槽是否**历史上**收到过非零梯度（供诊断脚本使用）
fn ad_ever_nz(i: i64) -> i64 { return load64(&AD_AUD_EVER + i * 8); }

# 区间 [lo, lo+n) 内"从未收到过非零梯度"的权重数。
# 用它按**层 / 通道**分组统计，能把"整体死权重数"拆成可定位的信号 ——
# 1.72 就是靠它发现"整个通道 3 全死"的（比单个死权重严重得多）。
fn ad_dead_in(lo: i64, n: i64) -> i64 {
    let c: i64 = 0;
    let i: i64 = 0;
    while i < n {
        if load64(&AD_ISW + (lo + i) * 8) == 1 {
            if load64(&AD_AUD_EVER + (lo + i) * 8) == 0 { c = c + 1; }
        }
        i = i + 1;
    }
    return c;
}

fn ad_ever_mark() -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 {
            if load64(&AD_GRAD + i * 8) != 0 {
                store64(&AD_AUD_EVER + i * 8, 1);
            }
        }
        i = i + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 优化

# 梯度下降：只更新被标记为权重的槽
# ---------------------------------------------------------------- 优化器
#
# 有了 autodiff，优化器只需要**读 ad_grad() 再写值**，
# 完全不碰反向代码 —— 这正是可微编程带来的自由度。
#
# Adam 需要偏差修正：m̂ = m/(1-b1^t)、v̂ = v/(1-b2^t)。
# 墨语言没有 pow，所以用**递推**：每步 bc *= b，
# 得到 (1-b^t) 而不用算幂。
#
# 步长 = lr · m̂ / (√v̂ + eps)，其中 √ 用 nn_fsqrt（牛顿 + 夹逼修正）。

# ⚠️ 必须清**整个数组**，不能只清到 AD_N。
#
# AD_N 是"当前图用了多少槽"，而 MOM/VEL 是跨步累积的状态。
# 用 `while i < AD_N` 时，ad_reset() 之后 AD_N=0，一个都不清；
# 下一次建图复用同样的槽号，就拿到**上一步残留的动量**。
# 表现是优化器行为诡异（我实测 Adam 首步就偏到 -1.5）。
fn ad_opt_reset() -> i64 {
    AD_T = 0;
    AD_BC1 = 65536;
    AD_BC2 = 65536;
    let i: i64 = 0;
    while i < 2048 {
        store64(&AD_MOM + i * 8, 0);
        store64(&AD_VEL + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

# 纯 SGD（原 ad_step）
fn ad_step(lr: i64) -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 {
            let v: i64 = ad_val(i);
            let g: i64 = ad_grad(i);
            let d: i64 = nn_fmul(lr, g);
            store64(&AD_VAL + i * 8, v - d);
        }
        i = i + 1;
    }
    return 0;
}

# 动量：v = beta·v + g ；w -= lr·v
fn ad_step_momentum(lr: i64, beta: i64) -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 {
            let g: i64 = ad_grad(i);
            let mv: i64 = nn_fmul(beta, load64(&AD_MOM + i * 8)) + g;
            store64(&AD_MOM + i * 8, mv);
            store64(&AD_VAL + i * 8, ad_val(i) - nn_fmul(lr, mv));
        }
        i = i + 1;
    }
    return 0;
}

# Adam
fn ad_step_adam(lr: i64, b1: i64, b2: i64, eps: i64) -> i64 {
    # 偏差修正系数递推：bc *= b  （每次调用算一步）
    AD_T = AD_T + 1;
    AD_BC1 = nn_fmul(AD_BC1, b1);
    AD_BC2 = nn_fmul(AD_BC2, b2);
    let c1: i64 = 65536 - AD_BC1;      # 1 - b1^t
    let c2: i64 = 65536 - AD_BC2;      # 1 - b2^t
    #
    # ⚠️ 不要在这里 clamp！
    # t=1 时 c1 = 1-b1 = 0.1，而 m = (1-b1)·g = 0.1g，
    # m̂ = m/c1 = g —— **正好抵消**，这正是 Adam 偏差修正的设计意图。
    # 我第一版把 c clamp 到 0.5，等于把首步放大了 5 倍，
    # 表现是"Adam 收敛更慢"（17 → 23 epoch）。
    # 只在极端情况（b 非常接近 1 导致 c 过小）才保护。
    if c1 < 655 { c1 = 655; }
    if c2 < 655 { c2 = 655; }

    let i: i64 = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 {
            let g: i64 = ad_grad(i);
            let m: i64 = nn_fmul(b1, load64(&AD_MOM + i * 8)) + nn_fmul(65536 - b1, g);
            let v: i64 = nn_fmul(b2, load64(&AD_VEL + i * 8)) + nn_fmul(65536 - b2, nn_fmul(g, g));
            store64(&AD_MOM + i * 8, m);
            store64(&AD_VEL + i * 8, v);
            let mh: i64 = nn_fdiv(m, c1);
            let vh: i64 = nn_fdiv(v, c2);
            let den: i64 = nn_fsqrt(vh) + eps;
            let dv: i64 = nn_fdiv(mh, den);
            store64(&AD_VAL + i * 8, ad_val(i) - nn_fmul(lr, dv));
        }
        i = i + 1;
    }
    return 0;
}

# 取当前 Adam 的修正分母（调试/测试用）
fn ad_bc1() -> i64 { return AD_BC1; }
fn ad_bc2() -> i64 { return AD_BC2; }
fn ad_t() -> i64 { return AD_T; }
fn ad_mom(s: i64) -> i64 { return load64(&AD_MOM + s * 8); }
fn ad_vel(s: i64) -> i64 { return load64(&AD_VEL + s * 8); }

fn ad_nweight() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

# ==========================================================================
#  梯度流审计（gradient flow audit）—— AD 正确性 tooling
# ==========================================================================
#
# 为什么需要它 —— 本项目 1.39 那轮踩过的坑：
#   ad_set() 不记 tape。用它拼装的多通道池化，让卷积层**收不到任何梯度**，
#   而结果**照样 8/8，毫无异常**。是"卷积核是否被更新"的诊断才发现的。
#
# 社区观点与之一致（arXiv:2007.05282v2 的解读）：
#   "AD correctness is a semantics problem, not a compiler trick."
#   不能把 AD 当宏挂在语言上就完事。tape 方案要求**每个算子都有反向
#   公式**，没有的算子被当作零导数 —— **静默**得到错误梯度。
#   （三路径对比：An op with no rule ... is treated as having zero
#    derivative unless you supply one.）
#
# 所以审计**不自动判定正确与否**，而是把可疑之处全部报出来由人判断。
# 这正是"语义问题"该有的处理方式 —— 工具报异常，人做判断。


fn ad_audit_count() -> i64 { return AD_AUD_N; }

# op 编码是否已知。tape 里出现未知 op（如 0 = 未初始化）时，
# backward 会静默跳过 —— 梯度断在这里且毫无提示。
#
# ⚠️ 新增算子编码后**必须同步改这里的上界**（当前最大 = OP_GAVG = 25）。
#
# 🔴 1.71 的教训：加了 leaky relu（OP_VLRL=24）却没改这里，
# 于是审计自己报出"未知算子 op=24"。虽然是审计按设计抓到了它，
# 但更该做的是**别让这个上限靠人记**—— 现在改成引用 OP_VLRL 常量，
# 新增算子时只改一处（常量定义），这里自动跟上。
fn ad_known_op(op: i64) -> i64 {
    if op < 1 { return 0; }
    if op > OP_GAVG { return 0; }
    return 1;
}

# 返回本轮发现的问题数，并打印报告。0 = 没发现问题。
#
# 检查四类：
#   1. tape 里出现未知算子（backward 静默跳过 → 梯度为 0）
#   2. 权重从未进入计算图（不会被更新）
#   3. 权重进了图但梯度为 0（梯度流断裂，或数学上恰为 0 —— 由人判断）
#   4. 权重或梯度接近 i64 溢出界（定点反传的真实风险，见下）
#
# 关于第 4 条：PocketNN 指出纯整数反传的溢出上界随层数**指数增长**
#   O(2^(e+kw))（e=误差位宽，w=权重位宽，k=距输出的层数）。墨语言用
#   i64 定点，位宽大得多，但深层网络仍可能撞界 —— 所以显式检测。
#   相对浮点的一个优势：整数没有 NaN/Inf 传播，一旦溢出是可检测的。
# 🔴 关键区分：**"本轮梯度为 0"不等于"梯度流断裂"**。
#
# 第一版按"本轮梯度为 0"报，结果一个**已经正确解出 XOR** 的网络
# 稳定报 6 个问题 —— 因为训练后期若干 sigmoid 单元饱和，导数≈0。
# 那是**正常的数学现象**，不是 bug。这样报下去人没法判断。
#
# 真正的断裂（1.39 那种）特征是：该权重**从头到尾**都没收到过非零梯度。
# 所以用 AD_AUD_EVER 记录"历史上是否收到过非零梯度"：
#   EVER==0 → 高危，结构性断裂
#   EVER==1 且本轮为 0 → 数值饱和，只汇总不计数

# 换模型时必须调用：EVER 是按槽号记的，新模型复用槽号会串味。
fn ad_audit_reset() -> i64 {
    let i: i64 = 0;
    while i < 2048 { store64(&AD_AUD_EVER + i * 8, 0); i = i + 1; }
    AD_AUD_N = 0;
    AD_AUD_INITN = 0;
    return 0;
}

fn ad_audit() -> i64 {
    let n: i64 = 0;
    let sat: i64 = 0;
    let i: i64 = 0;
    let t: i64 = 0;
    let op: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let o: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let span: i64 = 0;
    let k: i64 = 0;
    let g: i64 = 0;
    let v: i64 = 0;
    let lim: i64 = 4611686018427387904;   # 2^62

    i = 0;
    while i < 2048 { store64(&AD_AUD_SEE + i * 8, 0); i = i + 1; }

    # ---- 扫 tape：标记出现过的槽，同时找未知算子 ----
    t = 0;
    while t < AD_TN {
        op = load64(&AD_TOP + t * 8);
        a = load64(&AD_TA + t * 8);
        b = load64(&AD_TB + t * 8);
        o = load64(&AD_TO + t * 8);
        nr = load64(&AD_TXA + t * 8);
        nc = load64(&AD_TXB + t * 8);
        if ad_known_op(op) == 0 {
            print("  [!!] tape[");
            print_i64(t);
            print("] 未知算子 op=");
            print_i64(op);
            print(" —— backward 会静默跳过，梯度为 0\n");
            n = n + 1;
        }
        # 块展开长度：nr*nc 优先，其次 nr，最小 1。
        # 这是**近似** —— conv/pool 的输出长度不等于 nr。只影响
        # "是否进图"判定的宽松度，不影响基于 EVER 的硬检查。
        span = nr * nc;
        if span < nr { span = nr; }
        if span < 1 { span = 1; }
        k = 0;
        while k < span {
            if a + k < 2048 { store64(&AD_AUD_SEE + (a + k) * 8, 1); }
            if b + k < 2048 { store64(&AD_AUD_SEE + (b + k) * 8, 1); }
            if o + k < 2048 { store64(&AD_AUD_SEE + (o + k) * 8, 1); }
            k = k + 1;
        }
        t = t + 1;
    }

    # EVER 由 ad_backward() 逐步维护，这里只读不写
    # ---- 逐个可训练权重检查 ----
    i = 0;
    while i < AD_N {
        if load64(&AD_ISW + i * 8) == 1 {
            g = load64(&AD_GRAD + i * 8);
            v = load64(&AD_VAL + i * 8);
            if load64(&AD_AUD_SEE + i * 8) == 0 {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 从未进入计算图 —— 永远不会被更新\n");
                n = n + 1;
            }
            if load64(&AD_AUD_EVER + i * 8) == 0 {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 从未收到过非零梯度 —— 梯度流结构性断裂\n");
                n = n + 1;
            }
            if g == 0 {
                if load64(&AD_AUD_EVER + i * 8) == 1 { sat = sat + 1; }
            }
            if v > lim {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 的值接近溢出上界\n");
                n = n + 1;
            }
            if v < 0 - lim {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 的值接近溢出下界\n");
                n = n + 1;
            }
            if g > lim {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 的梯度接近溢出上界\n");
                n = n + 1;
            }
            if g < 0 - lim {
                print("  [!!] 权重槽 ");
                print_i64(i);
                print(" 的梯度接近溢出下界\n");
                n = n + 1;
            }
        }
        i = i + 1;
    }

    if n == 0 {
        print("gradient audit: PASS");
    } else {
        print("gradient audit: ");
        print_i64(n);
        print(" 个问题");
    }
    print("（另有 "); print_i64(sat); print(" 个权重本轮梯度为 0，历史上有过，属饱和非断裂）\n");

    # 初始化风险（1.76）：训练后权重已被更新，无法回溯初始化状态，
    # 所以必须在**初始化那一刻**记账（ad_init_note / ad_winit 自动调用），
    # 这里只读出来报。这样问题能在训练开始前就被发现。
    if AD_AUD_INITN > 0 {
        print("gradient audit: [!!] 初始化时有 ");
        print_i64(AD_AUD_INITN);
        print(" 个组符号一边倒 —— 这些单元可能在训练开始前就已死亡\n");
        n = n + AD_AUD_INITN;
    } else {
        print("gradient audit: 初始化符号分布正常（无一边倒的组）\n");
    }
    AD_AUD_N = n;
    AD_AUD_N = n;
    return n;
}

# ============================================================================
#  权重初始化（1.75）—— 把 1.73 的修法推广到 autodiff 原生接口
# ============================================================================
#
# 🔴 为什么 autodiff 需要自己的初始化：
# 1.73 发现 cnn_shift 的通道 3 有 9/9 死权重，根因是初始化符号一边倒。
# 但修法 `nn_conv_init_ch` 在 nn.mo 里、操作的是**普通数组**，
# 而 autodiff 的权重在 AD_VAL 槽里 —— 用户得自己填一遍，很容易忘。
#
# 于是这里提供直接操作**槽**的版本，让"不容易踩到死单元"成为默认路径。
#
# 组（group）= 一个输出单元的输入扇入 nin：
#   卷积核：一个通道的 ksz 个元素（3×3 = 9）
#   全连接：行主序 W[nr][nc] 的第 i 行 nc 个元素（第 i 个输出单元）
#
# ⚠️ 符号平衡只在"输入非负"（图像、relu 后的激活、one-hot…）且后接 relu
#    时才是必要的。若输入本身有正有负，符号一边倒不必然致死亡 ——
#    但符号平衡也不会有害（分布仍是对称的），所以默认开着。

fn ad_flip_half(s: i64, n: i64) -> i64 {
    let j: i64 = 0;
    while j < n {
        if j - (j / 2) * 2 == 0 {
            let v: i64 = load64(&AD_VAL + (s + j) * 8);
            store64(&AD_VAL + (s + j) * 8, 0 - v);
        }
        j = j + 1;
    }
    return 0;
}

# 随机初始化权重块 [s, s+n)，按 nin 为一组做符号平衡
fn ad_winit(s: i64, n: i64, nin: i64, scale: i64) -> i64 {
    let ng: i64 = n / nin;
    let g: i64 = 0;
    while g < ng {
        let i: i64 = 0;
        let nneg: i64 = 0;
        while i < nin {
            let v: i64 = nn_rand_fp(scale);
            store64(&AD_VAL + (s + g * nin + i) * 8, v);
            if v < 0 { nneg = nneg + 1; }
            i = i + 1;
        }
        # 全正或全负 → 翻转偶数下标（约一半）
        if nneg == nin { ad_flip_half(s + g * nin, nin); }
        if nneg == 0 { ad_flip_half(s + g * nin, nin); }
        g = g + 1;
    }
    # 翻转后仍全同号？理论不会，但**记账**让审计能兜底。
    # 注意这里不打印（正常情况应为 0），只累加计数。
    ad_init_note_quiet(s, n, nin);
    return 0;
}

# 静默版记账：不打印，只累加（供 ad_winit 内部用，正常应为 0）
fn ad_init_note_quiet(s: i64, n: i64, nin: i64) -> i64 {
    let ng: i64 = n / nin;
    let g: i64 = 0;
    let bad: i64 = 0;
    while g < ng {
        let i: i64 = 0;
        let nneg: i64 = 0;
        while i < nin {
            if load64(&AD_VAL + (s + g * nin + i) * 8) < 0 { nneg = nneg + 1; }
            i = i + 1;
        }
        if nneg == nin { bad = bad + 1; }
        if nneg == 0 { bad = bad + 1; }
        g = g + 1;
    }
    AD_AUD_INITN = AD_AUD_INITN + bad;
    return bad;
}

# He 缩放：scale = sqrt(2 / nin)，relu 的标准方差
fn ad_winit_he(s: i64, n: i64, nin: i64) -> i64 {
    let sc: i64 = nn_fdiv(92681, nn_fsqrt(nn_from_i(nin)));   # sqrt(2)=1.414
    return ad_winit(s, n, nin, sc);
}

# 卷积核便捷版：nch 个通道 × ksz 个元素（如 4 × 9）
fn ad_wconv_init(s: i64, nch: i64, ksz: i64) -> i64 {
    return ad_winit_he(s, nch * ksz, ksz);
}

# 全连接便捷版：行主序 W[nr][nc]
fn ad_wdense_init(s: i64, nr: i64, nc: i64) -> i64 {
    return ad_winit_he(s, nr * nc, nc);
}

# 初始化后自查：符号一边倒的**组数**（= 死单元风险数）
#
# 应在建图后、训练前调用。返回 > 0 说明有单元可能训练开始前就已死。
# 这是 1.73 的 `nn_ch_dead_risk` 对槽的推广版本。
fn ad_init_risk(s: i64, n: i64, nin: i64) -> i64 {
    let ng: i64 = n / nin;
    let g: i64 = 0;
    let bad: i64 = 0;
    while g < ng {
        let i: i64 = 0;
        let nneg: i64 = 0;
        while i < nin {
            if load64(&AD_VAL + (s + g * nin + i) * 8) < 0 { nneg = nneg + 1; }
            i = i + 1;
        }
        if nneg == nin { bad = bad + 1; }
        if nneg == 0 { bad = bad + 1; }
        g = g + 1;
    }
    return bad;
}

# 初始化风险**记账**（1.76）
#
# 🔴 为什么必须"记账"而不是"事后检查"：
# ad_audit() 在训练**后**调用，那时权重已被更新，符号分布早就变了 ——
# 事后检查初始化状态在物理上不可能。所以只能在初始化那一刻扫描，
# 把结果记进 AD_AUD_INITN，等 ad_audit() 时读出来报。
#
# 这样问题能在**训练开始前**就被发现，而不是等 120 个 epoch 跑完。
fn ad_init_note(s: i64, n: i64, nin: i64) -> i64 {
    let ng: i64 = n / nin;
    let g: i64 = 0;
    let bad: i64 = 0;
    while g < ng {
        let i: i64 = 0;
        let nneg: i64 = 0;
        while i < nin {
            if load64(&AD_VAL + (s + g * nin + i) * 8) < 0 { nneg = nneg + 1; }
            i = i + 1;
        }
        if nneg == nin {
            bad = bad + 1;
            print("  [!!] 权重块 "); print_i64(s + g * nin);
            print(" 起的 "); print_i64(nin);
            print(" 个权重全为负 —— 若接 relu 且输入非负则恒死\n");
        }
        if nneg == 0 {
            bad = bad + 1;
            print("  [!!] 权重块 "); print_i64(s + g * nin);
            print(" 起的 "); print_i64(nin);
            print(" 个权重全为正 —— 偏置为负时可能恒死\n");
        }
        g = g + 1;
    }
    AD_AUD_INITN = AD_AUD_INITN + bad;
    return bad;
}

# 读回：初始化时符号一边倒的组数（供外部断言）
fn ad_init_risk_count() -> i64 { return AD_AUD_INITN; }

# ----------------------------------------------------------------------------
#  分组**自动推断**（1.77）
# ----------------------------------------------------------------------------
#
# 1.76 的 ad_init_note(s, n, nin) 要用户传 nin。若权重是手工 ad_set 填的
# （没走 ad_winit 系列），就检查不到 —— 而手工填恰恰是最容易踩坑的场景。
#
# 分组（= 一个输出单元的输入扇入 nin）其实**能从 tape 推断**：
#
#   OP_MATMUL : a = 权重块, TXA = nr, TXB = nc
#               → 行主序 W[nr][nc]，第 i 行 nc 个 = 第 i 个输出单元扇入
#               → nin = nc
#
#   OP_CONVMC : b = 核（注意权重在 **b** 位，a 是输入！）
#               TXA = h*1000 + w, TXB = ci*1000 + co
#               → 每个输出通道的扇入 = ci * 9
#
# ⚠️ OP_CONVMC 的权重在 **b** 位、OP_MATMUL 在 **a** 位 —— 两者相反。
#    第一版我把 conv 也按 a 位找，结果一个都匹配不上（返回 -1）。
#
# 返回推断出的 nin；无法推断返回 0 - 1。
fn ad_infer_nin(s: i64) -> i64 {
    let t: i64 = 0;
    while t < AD_TN {
        let op: i64 = load64(&AD_TOP + t * 8);
        let a: i64 = load64(&AD_TA + t * 8);
        let b: i64 = load64(&AD_TB + t * 8);
        if op == OP_MATMUL {
            if a == s {
                return load64(&AD_TXB + t * 8);        # nc
            }
        }
        if op == OP_CONVMC {
            if b == s {
                let txb: i64 = load64(&AD_TXB + t * 8);
                let ci: i64 = txb / 1000;
                return ci * 9;
            }
        }
        t = t + 1;
    }
    return 0 - 1;
}

# 便捷版：自动推断 nin 后记账
fn ad_init_note_auto(s: i64, n: i64) -> i64 {
    let nin: i64 = ad_infer_nin(s);
    if nin < 1 { return 0 - 1; }
    return ad_init_note(s, n, nin);
}

# 扫 tape 中**所有**参与 matmul / conv 的权重块，逐个自动记账。
# 用 AD_AUD_SEE 去重（同一权重块可能被多个算子引用）。
#
# 🔴 为什么值得做：手工 ad_set 填权重（不走 ad_winit）正是最容易踩坑的
#    场景，而 1.76 的手动版在这种场景下根本不会被调用 —— 等于没保护。
fn ad_init_note_all() -> i64 {
    let t: i64 = 0;
    let cnt: i64 = 0;
    while t < AD_TN {
        let op: i64 = load64(&AD_TOP + t * 8);
        let a: i64 = load64(&AD_TA + t * 8);
        let b: i64 = load64(&AD_TB + t * 8);
        let ws: i64 = 0 - 1;
        let wn: i64 = 0;
        let nin: i64 = 0;
        if op == OP_MATMUL {
            ws = a;
            nin = load64(&AD_TXB + t * 8);
            wn = load64(&AD_TXA + t * 8) * nin;
        }
        if op == OP_CONVMC {
            ws = b;
            let txa: i64 = load64(&AD_TXA + t * 8);
            let txb: i64 = load64(&AD_TXB + t * 8);
            let ci: i64 = txb / 1000;
            let co: i64 = txb - ci * 1000;
            nin = ci * 9;
            wn = co * nin;
        }
        if ws >= 0 {
            if load64(&AD_AUD_SEE + ws * 8) == 0 {
                store64(&AD_AUD_SEE + ws * 8, 1);
                ad_init_note_quiet(ws, wn, nin);
                cnt = cnt + 1;
            }
        }
        t = t + 1;
    }
    return cnt;
}

# 偏置清零（配合上面的初始化用 —— 偏置为 0 时符号一边倒的危害最大）
fn ad_bzero(s: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store64(&AD_VAL + (s + i) * 8, 0);
        i = i + 1;
    }
    return 0;
}

# ============================================================================
#  前向模式（1.78）—— 点积检验的另一半
# ============================================================================
#
# 来源观念：arXiv:2305.07546《Understanding Automatic Differentiation Pitfalls》
#
#   y = f(g(x))，Jacobian 为 F, G。给定 ẋ 和 ȳ：
#     前向模式：ẏ = F G ẋ
#     反向模式：x̄ = ȳ G F
#   两者满足   ψ = x̄·ẋ = (ȳ G F)ẋ = ȳ·(F G ẋ) = ȳ·ẏ
#
# 取 ȳ = e_loss（对 loss 的导数为 1，其余为 0），则：
#     ψ_forward = dot[loss]          （前向模式算出的方向导数）
#     ψ_reverse = Σᵢ grad[i]·seed[i] （反向梯度 与 种子 的点积）
#   **两者必须相等** —— 这就是点积检验。
#
# 🔴 论文的警告：pitfalls I/II/III 会让两种模式**一致地**产生同样的错误
#    导数，此时点积检验会通过但结果仍是错的。所以对未知算子/可疑算子，
#    必须配合有限差分（FD）作为第三方参照 —— 见 ad_dot_test 的 f64 模式。
#
# 🔴 实现纪律：前向规则必须与反向的**局部导数**逐字一致。
#    例如 OP_MSE 反向用 2(y-t)/n，前向也必须用 2(y-t)/n；
#    OP_MSEH 反向用 (y-t)/n，前向也必须用 (y-t)/n。
#    差一个系数，点积检验立刻失败 —— 这正是 1.36 那个"系数 2 不自洽"
#    能被自动检出的原因。

# 🔴 导数公式必须与 ad_backward 里的**逐字一致**，否则点积检验会失败
#    （这不是 bug，正是检验的设计意图 —— 它专门抓这类不一致）。
#    OP_SIG  反向： d = v[o] * (1 - v[o])
#    OP_TANH 反向： d = 1 - v[o]*v[o]
fn ad_dsig(v: i64) -> i64 { return nn_fmul(v, nn_from_i(1) - v); }
fn ad_dtanh(v: i64) -> i64 { return nn_from_i(1) - nn_fmul(v, v); }

var AD_DOT_F:   i64 = 0;   # 上一次检验的 ψ_forward
var AD_DOT_R:   i64 = 0;   # 上一次检验的 ψ_reverse
var AD_DOT_REL: i64 = 0;   # 上一次检验的相对差（定点）

fn ad_dot(i: i64) -> i64 { return load64(&AD_DOT + i * 8); }

# 播种：给槽 i 设方向导数 ẋᵢ
fn ad_fseed(i: i64, v: i64) -> i64 {
    store64(&AD_DOT + i * 8, v);
    store64(&AD_SEED + i * 8, v);
    return 0;
}

fn ad_fseed_reset() -> i64 {
    let i: i64 = 0;
    while i < 2048 {
        store64(&AD_DOT + i * 8, 0);
        store64(&AD_SEED + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

# 前向传播：正序遍历 tape，算每个槽的方向导数
#
# 🔴 未知算子**明确报错**，绝不静默当 0。
#    论文 pitfall：tape 方案里没有反向公式的算子被当作零导数，
#    **静默**得到错误梯度 —— 1.39 的 ad_set 事件就是这么发生的。
fn ad_forward() -> i64 {
    let t: i64 = 0;
    let op: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let o: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let acc: i64 = 0;
    let d: i64 = 0;

    while t < AD_TN {
        op = load64(&AD_TOP + t * 8);
        a = load64(&AD_TA + t * 8);
        b = load64(&AD_TB + t * 8);
        o = load64(&AD_TO + t * 8);
        nr = load64(&AD_TXA + t * 8);
        nc = load64(&AD_TXB + t * 8);

        # ---- 标量 ----
        if op == OP_ADD {
            store64(&AD_DOT + o * 8,
                    load64(&AD_DOT + a * 8) + load64(&AD_DOT + b * 8));
        }
        if op == OP_SUB {
            store64(&AD_DOT + o * 8,
                    load64(&AD_DOT + a * 8) - load64(&AD_DOT + b * 8));
        }
        if op == OP_MUL {
            acc = nn_fmul(load64(&AD_DOT + a * 8), ad_val(b));
            acc = acc + nn_fmul(load64(&AD_DOT + b * 8), ad_val(a));
            store64(&AD_DOT + o * 8, acc);
        }
        if op == OP_RELU {
            if ad_val(a) > 0 { store64(&AD_DOT + o * 8, load64(&AD_DOT + a * 8)); }
            else { store64(&AD_DOT + o * 8, 0); }
        }
        if op == OP_LREL {
            if ad_val(a) > 0 { store64(&AD_DOT + o * 8, load64(&AD_DOT + a * 8)); }
            else {
                store64(&AD_DOT + o * 8,
                        nn_fmul(load64(&AD_DOT + a * 8), AD_LRELU_NEG));
            }
        }
        if op == OP_SIG {
            # 反向用 ad_val(o) 查表（sigmoid 输出），前向必须一致
            store64(&AD_DOT + o * 8,
                    nn_fmul(load64(&AD_DOT + a * 8), ad_dsig(ad_val(o))));
        }
        if op == OP_TANH {
            store64(&AD_DOT + o * 8,
                    nn_fmul(load64(&AD_DOT + a * 8), ad_dtanh(ad_val(o))));
        }

        # ---- 块级 ----
        if op == OP_MATMUL {
            i = 0;
            while i < nr {
                acc = 0;
                j = 0;
                while j < nc {
                    # d(W·x)_i = dW_ij·x_j + W_ij·dx_j
                    acc = acc + nn_fmul(load64(&AD_DOT + (a + i * nc + j) * 8),
                                        ad_val(b + j));
                    acc = acc + nn_fmul(ad_val(a + i * nc + j),
                                        load64(&AD_DOT + (b + j) * 8));
                    j = j + 1;
                }
                store64(&AD_DOT + (o + i) * 8, acc);
                i = i + 1;
            }
        }
        if op == OP_VADD {
            i = 0;
            while i < nr {
                store64(&AD_DOT + (o + i) * 8,
                        load64(&AD_DOT + (a + i) * 8) + load64(&AD_DOT + (b + i) * 8));
                i = i + 1;
            }
        }
        if op == OP_VSIG {
            i = 0;
            while i < nr {
                store64(&AD_DOT + (o + i) * 8,
                        nn_fmul(load64(&AD_DOT + (a + i) * 8), ad_dsig(ad_val(o + i))));
                i = i + 1;
            }
        }
        if op == OP_VTAN {
            i = 0;
            while i < nr {
                store64(&AD_DOT + (o + i) * 8,
                        nn_fmul(load64(&AD_DOT + (a + i) * 8), ad_dtanh(ad_val(o + i))));
                i = i + 1;
            }
        }
        if op == OP_VREL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 {
                    store64(&AD_DOT + (o + i) * 8, load64(&AD_DOT + (a + i) * 8));
                } else { store64(&AD_DOT + (o + i) * 8, 0); }
                i = i + 1;
            }
        }
        if op == OP_VLRL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 {
                    store64(&AD_DOT + (o + i) * 8, load64(&AD_DOT + (a + i) * 8));
                } else {
                    store64(&AD_DOT + (o + i) * 8,
                            nn_fmul(load64(&AD_DOT + (a + i) * 8), AD_LRELU_NEG));
                }
                i = i + 1;
            }
        }
        # 🔴 系数必须与反向一致：MSE 用 2/n，MSEH 用 1/n
        if op == OP_MSE {
            acc = 0;
            i = 0;
            while i < nr {
                d = ad_val(a + i) - ad_val(b + i);
                acc = acc + nn_fmul(nn_fmul(nn_from_i(2), d),
                                    load64(&AD_DOT + (a + i) * 8));
                i = i + 1;
            }
            store64(&AD_DOT + o * 8, nn_fdiv(acc, nn_from_i(nr)));
        }
        if op == OP_MSEH {
            acc = 0;
            i = 0;
            while i < nr {
                d = ad_val(a + i) - ad_val(b + i);
                acc = acc + nn_fmul(d, load64(&AD_DOT + (a + i) * 8));
                i = i + 1;
            }
            store64(&AD_DOT + o * 8, nn_fdiv(acc, nn_from_i(nr)));
        }
        if op == OP_VADD_B {
            # o[i][j] = a[i][j] + b[i]
            i = 0;
            while i < nr {
                j = 0;
                while j < nc {
                    store64(&AD_DOT + (o + i * nc + j) * 8,
                            load64(&AD_DOT + (a + i * nc + j) * 8)
                            + load64(&AD_DOT + (b + i) * 8));
                    j = j + 1;
                }
                i = i + 1;
            }
        }
        if op == OP_POOLMC {
            # 🔴 所有 let 必须在**循环外**：墨语言的 let 在循环体内会累积栈帧
            let pco: i64 = nr / 1000;
            let ph2: i64 = nr - pco * 1000;
            let pw2: i64 = nc;
            let poh: i64 = ph2 / 2;
            let pow2: i64 = pw2 / 2;
            let pc: i64 = 0;
            let oi2: i64 = 0;
            let ps2: i64 = 0;
            let di2: i64 = 0;
            while pc < pco {
                i = 0;
                while i < poh {
                    j = 0;
                    while j < pow2 {
                        oi2 = o + pc * poh * pow2 + i * pow2 + j;
                        ps2 = load64(&AD_POOLPOS + oi2 * 8);
                        di2 = pc * ph2 * pw2
                            + (i * 2 + ps2 / 2) * pw2 + (j * 2 + ps2 & 1);
                        store64(&AD_DOT + oi2 * 8, load64(&AD_DOT + (a + di2) * 8));
                        j = j + 1;
                    }
                    i = i + 1;
                }
                pc = pc + 1;
            }
        }
        if op == OP_GMAX {
            # o[c] = max over 位置：dot 取该位置处输入的 dot
            let gc: i64 = 0;
            while gc < nr {
                let gp: i64 = load64(&AD_POOLPOS + (o + gc) * 8);
                store64(&AD_DOT + (o + gc) * 8,
                        load64(&AD_DOT + (a + gc * nc + gp) * 8));
                gc = gc + 1;
            }
        }
        if op == OP_CONVMC {
            # 🔴 卷积的权重在 **b** 位、输入在 a 位（与 matmul 相反）
            # 前向：dotO = Σ (dK·Inp + K·dInp)，与反向的局部导数逐字一致
            let mh: i64 = nr / 1000;
            let mw: i64 = nr - mh * 1000;
            let mci: i64 = nc / 1000;
            let mco: i64 = nc - mci * 1000;
            let moh: i64 = mh - 2;
            let mow: i64 = mw - 2;
            let oc2: i64 = 0;
            let ci2: i64 = 0;
            let ki3: i64 = 0;
            let kj3: i64 = 0;
            let iidx: i64 = 0;
            let kidx: i64 = 0;
            while oc2 < mco {
                ci2 = 0;
                while ci2 < mci {
                    i = 0;
                    while i < moh {
                        j = 0;
                        while j < mow {
                            ki3 = 0;
                            while ki3 < 3 {
                                kj3 = 0;
                                while kj3 < 3 {
                                    iidx = ci2 * mh * mw + (i + ki3) * mw + (j + kj3);
                                    kidx = oc2 * mci * 9 + ci2 * 9 + ki3 * 3 + kj3;
                                    acc = nn_fmul(load64(&AD_DOT + (b + kidx) * 8),
                                                  ad_val(a + iidx));
                                    acc = acc + nn_fmul(ad_val(b + kidx),
                                                  load64(&AD_DOT + (a + iidx) * 8));
                                    store64(&AD_DOT + (o + oc2 * moh * mow + i * mow + j) * 8,
                                            load64(&AD_DOT + (o + oc2 * moh * mow + i * mow + j) * 8)
                                            + acc);
                                    kj3 = kj3 + 1;
                                }
                                ki3 = ki3 + 1;
                            }
                            j = j + 1;
                        }
                        i = i + 1;
                    }
                    ci2 = ci2 + 1;
                }
                oc2 = oc2 + 1;
            }
        }
        if op == OP_MMBA {
            # A[bn][bc] × B[bc][bs] → O[bn][bs]；nr = bn*1000+bc, nc = bs
            let bn: i64 = nr / 1000;
            let bc: i64 = nr - bn * 1000;
            let bs2: i64 = nc;
            let bi: i64 = 0;
            let bj: i64 = 0;
            let bk: i64 = 0;
            while bi < bn {
                bj = 0;
                while bj < bs2 {
                    acc = 0;
                    bk = 0;
                    while bk < bc {
                        acc = acc
                            + nn_fmul(load64(&AD_DOT + (a + bi * bc + bk) * 8),
                                      ad_val(b + bk * bs2 + bj));
                        acc = acc
                            + nn_fmul(ad_val(a + bi * bc + bk),
                                      load64(&AD_DOT + (b + bk * bs2 + bj) * 8));
                        bk = bk + 1;
                    }
                    store64(&AD_DOT + (o + bi * bs2 + bj) * 8, acc);
                    bj = bj + 1;
                }
                bi = bi + 1;
            }
        }
        if op == OP_MBAT {
            # A[an][bs] × B[an2][bs]^T → O[an][an2]；nr = an*1000+bs, nc = an2
            let an: i64 = nr / 1000;
            let abs2: i64 = nr - an * 1000;
            let an2: i64 = nc;
            let ai: i64 = 0;
            let aj: i64 = 0;
            let ak: i64 = 0;
            while ai < an {
                aj = 0;
                while aj < an2 {
                    acc = 0;
                    ak = 0;
                    while ak < abs2 {
                        acc = acc
                            + nn_fmul(load64(&AD_DOT + (a + ai * abs2 + ak) * 8),
                                      ad_val(b + aj * abs2 + ak));
                        acc = acc
                            + nn_fmul(ad_val(a + ai * abs2 + ak),
                                      load64(&AD_DOT + (b + aj * abs2 + ak) * 8));
                        ak = ak + 1;
                    }
                    store64(&AD_DOT + (o + ai * an2 + aj) * 8, acc);
                    aj = aj + 1;
                }
                ai = ai + 1;
            }
        }
        if op == OP_CONV {
            # 单通道 3×3 valid：nr = h, nc = w
            let oh2: i64 = nr - 2;
            let ow2: i64 = nc - 2;
            let ki2: i64 = 0;
            let kj2: i64 = 0;
            let ioff: i64 = 0;
            i = 0;
            while i < oh2 {
                j = 0;
                while j < ow2 {
                    acc = 0;
                    ki2 = 0;
                    while ki2 < 3 {
                        kj2 = 0;
                        while kj2 < 3 {
                            ioff = (i + ki2) * nc + (j + kj2);
                            acc = acc
                                + nn_fmul(load64(&AD_DOT + (b + ki2 * 3 + kj2) * 8),
                                          ad_val(a + ioff));
                            acc = acc
                                + nn_fmul(ad_val(b + ki2 * 3 + kj2),
                                          load64(&AD_DOT + (a + ioff) * 8));
                            kj2 = kj2 + 1;
                        }
                        ki2 = ki2 + 1;
                    }
                    store64(&AD_DOT + (o + i * ow2 + j) * 8, acc);
                    j = j + 1;
                }
                i = i + 1;
            }
        }
        if op == OP_POOL {
            # 单通道 max pool：梯度/方向导数走 AD_POOLPOS 记录的胜出位置
            let oh3: i64 = nr / 2;
            let ow3: i64 = nc / 2;
            let pi: i64 = 0;
            let pj: i64 = 0;
            let oi: i64 = 0;
            let ps: i64 = 0;
            let di: i64 = 0;
            while pi < oh3 {
                pj = 0;
                while pj < ow3 {
                    oi = o + pi * ow3 + pj;
                    ps = load64(&AD_POOLPOS + oi * 8);
                    di = (pi * 2 + ps / 2) * nc + (pj * 2 + ps & 1);
                    store64(&AD_DOT + oi * 8, load64(&AD_DOT + (a + di) * 8));
                    pj = pj + 1;
                }
                pi = pi + 1;
            }
        }
        if op == OP_SCE {
            # L = lse(x) - x[t]；dL = Σ_p (softmax_p - onehot_t)·dx_p
            # 注意：max 项在正规点是局部常数，其导数与 lse 抵消，
            #      所以直接用 softmax 即可（与反向实现一致）
            let mx2: i64 = ad_val(a + 0);
            let p: i64 = 1;
            let zz: i64 = 0;
            let sm: i64 = 0;
            let ind: i64 = 0;
            while p < nr {
                if ad_val(a + p) > mx2 { mx2 = ad_val(a + p); }
                p = p + 1;
            }
            p = 0;
            while p < nr {
                zz = zz + nn_exp_neg(ad_val(a + p) - mx2);
                p = p + 1;
            }
            acc = 0;
            p = 0;
            while p < nr {
                sm = nn_fdiv(nn_exp_neg(ad_val(a + p) - mx2), zz);
                ind = sm;
                if p == nc { ind = sm - 65536; }
                acc = acc + nn_fmul(ind, load64(&AD_DOT + (a + p) * 8));
                p = p + 1;
            }
            store64(&AD_DOT + o * 8, acc);
        }
        if ad_known_op(op) == 0 {
            print("  [!!] ad_forward: 未知算子 op=");
            print_i64(op);
            print(" —— 绝不静默当 0\n");
            return 0 - 1;
        }
        t = t + 1;
    }
    return 0;
}

# 点积检验（1.78）
#
# 用法：
#   建图 → 播种 ad_fseed → ad_backward(loss) → ad_dot_test(loss)
#
# 返回 0 = 通过；非 0 = 不一致（两种模式算出了不同的 ψ）
fn ad_dot_test(loss: i64) -> i64 {
    # ψ_forward：前向模式算出的 loss 方向导数
    let pf: i64 = load64(&AD_DOT + loss * 8);
    # ψ_reverse：Σ grad[i] · seed[i]
    let pr: i64 = 0;
    let i: i64 = 0;
    while i < AD_N {
        let sd: i64 = load64(&AD_SEED + i * 8);
        if sd != 0 {
            pr = pr + nn_fmul(load64(&AD_GRAD + i * 8), sd);
        }
        i = i + 1;
    }
    AD_DOT_F = pf;
    AD_DOT_R = pr;

    # 定点下允许一定误差：用相对误差判据（论文建议同时看绝对与相对）
    let diff: i64 = pf - pr;
    if diff < 0 { diff = 0 - diff; }
    let scale: i64 = pr;
    if scale < 0 { scale = 0 - scale; }
    let base: i64 = pf;
    if base < 0 { base = 0 - base; }
    if base > scale { scale = base; }
    if scale < 1 { scale = 1; }
    AD_DOT_REL = nn_fdiv(diff, scale);

    print("dot product test: ψ_forward=");
    print_i64(pf);
    print("  ψ_reverse=");
    print_i64(pr);
    print("  相对差=");
    print_i64(AD_DOT_REL);
    print("\n");

    # 相对差 > 1/256（≈0.004）判失败。定点有量化误差，不能要求位级相等。
    if AD_DOT_REL > 256 {
        print("  [!!] 点积检验失败：前向与反向不一致\n");
        return 1;
    }
    return 0;
}


# ============================================================================
#  有限差分（FD）—— 点积检验的第三方参照（1.79）
# ============================================================================
#
# 来源：arXiv:2305.07546
#   "the dot product test can be modified by replacing forward mode AD with
#    finite differences... allowing direct debugging of reverse mode AD"
#
# 🔴 为什么必须有它：1.78 的**变异 B** 实证了——
#    反向与前向**同步地**犯同样的错时，ψ_f = ψ_r，点积检验**通过**，
#    但两者都错。此时唯一能发现问题的，是与**函数值**直接对照的 FD。
#    PyTorch 的 gradcheck 正是这么做的。
#
# ψ_fd = (f(x + h·v) − f(x − h·v)) / (2h)     中心差分，二阶精度
#
# 定点下的步长选择（🔴 与浮点不同）：
#   h 太小 → 定点量化把 (f+ − f−) 抹成 0
#   h 太大 → 高阶项不可忽略（截断误差）
#   默认 h = 65536/64 ≈ 0.0156；见 ad_fd_scan 的实测

var AD_SNAP_N:  i64 = 0;
var AD_SNAP_TN: i64 = 0;
var AD_FD_BASE: i64 = 0;   # 重算起点槽号（输入建好、前向函数之前调用 ad_fd_mark）

# 🔴 必须在「输入/权重建好之后、调用前向函数之前」调用。
#    前向函数每次重算都从 AD_FD_BASE 之后**覆盖**分配，否则 2048 个槽
#    几次重算就耗尽。
# 🔴 另一个必须注意的：前向函数**不能自己创建输入**
#    （`let x = ad_weight(49152)` 写在里面就是每次新建常量）。
#    那样扰动旧槽完全没有效果 —— FD 会算出 ψ=0，这是 1.79 踩到的第一个坑。
#    正确做法：输入/权重在建图阶段建一次，槽号存全局变量，前向函数只引用。
fn ad_fd_mark() -> i64 {
    AD_FD_BASE = AD_N;
    return 0;
}

fn ad_fd_save() -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        store64(&AD_SNAP + i * 8, ad_val(i));
        i = i + 1;
    }
    AD_SNAP_N = AD_N;
    AD_SNAP_TN = AD_TN;
    return 0;
}

# 恢复快照并按种子方向扰动：VAL[i] = snap[i] + sgn * h * seed[i]
#
# 🔴 同时把 AD_N / AD_TN 回滚到快照点 —— 这样重跑 build() 会**覆盖**原有
#    槽而不是不断往后分配（否则 2048 个槽几次重算就耗尽）
fn ad_fd_perturb(h: i64, sgn: i64) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let sd: i64 = 0;
    while i < AD_SNAP_N {
        v = load64(&AD_SNAP + i * 8);
        sd = load64(&AD_SEED + i * 8);
        if sd != 0 { v = v + nn_fmul(sgn * h, sd); }
        store64(&AD_VAL + i * 8, v);
        i = i + 1;
    }
    if AD_FD_BASE > 0 { AD_N = AD_FD_BASE; } else { AD_N = AD_SNAP_N; }
    AD_TN = AD_SNAP_TN;
    return 0;
}

fn ad_fd_restore() -> i64 {
    let i: i64 = 0;
    while i < AD_SNAP_N {
        store64(&AD_VAL + i * 8, load64(&AD_SNAP + i * 8));
        i = i + 1;
    }
    AD_N = AD_SNAP_N;
    AD_TN = AD_SNAP_TN;
    return 0;
}

# ψ_fd = (lp − lm) / (2h)   —— 全定点
fn ad_fd_psi(lp: i64, lm: i64, h: i64) -> i64 {
    return nn_fdiv(lp - lm, h + h);
}

# 三方对照：ψ_fd / ψ_forward / ψ_reverse
# 返回不一致的个数（0 = 三者一致）
#
# 判据用相对误差（定点不能要求位级相等）：
#   |ψ_a − ψ_b| / max(|ψ_a|,|ψ_b|,1) ≤ 1/32（≈0.03）视为一致
fn ad_fd_compare(loss: i64, fd: i64) -> i64 {
    let pf: i64 = AD_DOT_F;
    let pr: i64 = AD_DOT_R;
    let bad: i64 = 0;
    let d: i64 = 0;
    let sc: i64 = 0;
    let t: i64 = 0;

    print("三方对照: ψ_fd=");
    print_i64(fd);
    print("  ψ_forward=");
    print_i64(pf);
    print("  ψ_reverse=");
    print_i64(pr);
    print("\n");

    # fd vs forward
    d = fd - pf;
    if d < 0 { d = 0 - d; }
    sc = fd;
    if sc < 0 { sc = 0 - sc; }
    t = pf;
    if t < 0 { t = 0 - t; }
    if t > sc { sc = t; }
    if sc < 1 { sc = 1; }
    if nn_fdiv(d, sc) > 2048 {
        bad = bad + 1;
        print("  [!!] FD 与前向模式不一致\n");
    }
    # fd vs reverse
    d = fd - pr;
    if d < 0 { d = 0 - d; }
    sc = fd;
    if sc < 0 { sc = 0 - sc; }
    t = pr;
    if t < 0 { t = 0 - t; }
    if t > sc { sc = t; }
    if sc < 1 { sc = 1; }
    if nn_fdiv(d, sc) > 2048 {
        bad = bad + 1;
        print("  [!!] FD 与反向模式不一致\n");
    }
    return bad;
}


# ============================================================================
#  ASD —— 自动稀疏微分（1.80）
# ============================================================================
#
# 概念来源（"还在 PDF 里躺着"的技术）：
#   Gebremedhin, Manne & Pothen, "What Color Is Your Jacobian? Graph
#     Coloring for Computing Derivatives" SIAM Review 2005
#   Griewank & Walther, "Evaluating Derivatives" 第 8 章
#
# 🔴 核心悖论（ICLR 2025 blogpost "An Illustrated Guide to Automatic
#    Sparse Differentiation" 明确指出）：
#      要判断哪些列"结构正交"（可合并成一次传播），得先知道稀疏模式；
#      可要用传统 AD 把矩阵算出来才知道模式 —— 那 ASD 就没意义了。
#    解法：**只传播索引集，不做数值计算**。
#
# 四步流水线：Detection → Coloring → Compressed AD → Decompression
#
# 🔴 为什么墨语言能做：它有 tape（AD_TOP/TA/TB/TO 记录了每个算子的
#    操作数），所以稀疏模式**可以静态推出**，不需要先算数值。
#    主流框架（PyTorch/JAX）默认把 Jacobian 当稠密的算，不做这件事。
#
# 位集表示：i64 的 64 位 ⇒ 输入数 ≤ 64。

var AD_ASD_IN:   i64 = 0;   # 输入起始槽
var AD_ASD_NI:   i64 = 0;   # 输入个数
var AD_ASD_OUT:  i64 = 0;   # 输出起始槽
var AD_ASD_NO:   i64 = 0;   # 输出个数
var AD_ASD_NC:   i64 = 0;   # 颜色数（= 压缩 AD 的次数）
var AD_ASD_NZ:   i64 = 0;   # 检测到的非零个数
var AD_ASD_FULL: i64 = 0;   # 稠密时（nin）的传播次数

# 槽 → 输入下标（不在输入范围返回 -1）
fn ad_asd_idx(sl: i64) -> i64 {
    if sl < AD_ASD_IN { return 0 - 1; }
    if sl >= AD_ASD_IN + AD_ASD_NI { return 0 - 1; }
    return sl - AD_ASD_IN;
}

# 取某槽的位集（输入槽返回自己的位，否则返回已算出的模式）
fn ad_asd_pat(sl: i64) -> i64 {
    let k: i64 = ad_asd_idx(sl);
    if k >= 0 { return 1 << k; }
    return load64(&AD_PAT + sl * 8);
}

# ---- 第 1 步：Detection ----
#
# 🔴 必须**逐元素精确**。若图省事对所有算子都用"并集"，卷积会把
#    全部输入连到全部输出 ⇒ 模式是全 1 ⇒ 压缩率退化成 1，ASD 白做。
#    所以 matmul / conv_mc / pool_mc / gmax 都按元素逐个算。
fn ad_asd_detect(sin: i64, nin: i64, sout: i64, nout: i64) -> i64 {
    AD_ASD_IN = sin;
    AD_ASD_NI = nin;
    AD_ASD_OUT = sout;
    AD_ASD_NO = nout;
    AD_ASD_FULL = nin;

    let i: i64 = 0;
    while i < 2048 { store64(&AD_PAT + i * 8, 0); i = i + 1; }

    let t: i64 = 0;
    while t < AD_TN {
        let op: i64 = load64(&AD_TOP + t * 8);
        let a: i64 = load64(&AD_TA + t * 8);
        let b: i64 = load64(&AD_TB + t * 8);
        let o: i64 = load64(&AD_TO + t * 8);
        let nr: i64 = load64(&AD_TXA + t * 8);
        let nc: i64 = load64(&AD_TXB + t * 8);

        # 标量一元：out = pat(a)
        if op == OP_SIG {
            store64(&AD_PAT + o * 8, ad_asd_pat(a));
        }
        if op == OP_TANH {
            store64(&AD_PAT + o * 8, ad_asd_pat(a));
        }
        if op == OP_RELU {
            store64(&AD_PAT + o * 8, ad_asd_pat(a));
        }
        if op == OP_LREL {
            store64(&AD_PAT + o * 8, ad_asd_pat(a));
        }
        # 标量二元：out = pat(a) | pat(b)
        if op == OP_ADD {
            store64(&AD_PAT + o * 8, ad_asd_pat(a) | ad_asd_pat(b));
        }
        if op == OP_SUB {
            store64(&AD_PAT + o * 8, ad_asd_pat(a) | ad_asd_pat(b));
        }
        if op == OP_MUL {
            store64(&AD_PAT + o * 8, ad_asd_pat(a) | ad_asd_pat(b));
        }
        # 逐元素向量算子
        if op == OP_VADD {
            i = 0;
            while i < nr {
                let pa: i64 = ad_asd_pat(a + i);
                let pb: i64 = ad_asd_pat(b + i);
                store64(&AD_PAT + (o + i) * 8, pa | pb);
                i = i + 1;
            }
        }
        if op == OP_VADD_B {
            # b 是长度为 nc 的偏置，广播到 nr*nc：out[i*nc+j] = a[...] | b[j]
            i = 0;
            while i < nr {
                let j: i64 = 0;
                while j < nc {
                    # 🔴 偏置按**通道 i** 索引，不是元素 j（与 ad_vadd_bcast 的
                    #    ad_val(b + i) 一致）。写成 b + j 会读到 c1 的元素，
                    #    把通道 0 的模式混进所有通道 —— 静默地毁掉稀疏性。
                    store64(&AD_PAT + (o + i * nc + j) * 8,
                            ad_asd_pat(a + i * nc + j) | ad_asd_pat(b + i));
                    j = j + 1;
                }
                i = i + 1;
            }
        }
        if op == OP_VSIG {
            i = 0;
            while i < nr { store64(&AD_PAT + (o + i) * 8, ad_asd_pat(a + i)); i = i + 1; }
        }
        if op == OP_VREL {
            i = 0;
            while i < nr { store64(&AD_PAT + (o + i) * 8, ad_asd_pat(a + i)); i = i + 1; }
        }
        if op == OP_VTAN {
            i = 0;
            while i < nr { store64(&AD_PAT + (o + i) * 8, ad_asd_pat(a + i)); i = i + 1; }
        }
        if op == OP_VLRL {
            i = 0;
            while i < nr { store64(&AD_PAT + (o + i) * 8, ad_asd_pat(a + i)); i = i + 1; }
        }
        # matmul: O[nr] = A[nr][nc] × B[nc]  ⇒  o[i] 依赖 A[i][*] 和 B[*]
        if op == OP_MATMUL {
            i = 0;
            while i < nr {
                let acc: i64 = 0;
                let k: i64 = 0;
                while k < nc {
                    acc = acc | ad_asd_pat(a + i * nc + k);
                    acc = acc | ad_asd_pat(b + k);
                    k = k + 1;
                }
                store64(&AD_PAT + (o + i) * 8, acc);
                i = i + 1;
            }
        }
        # conv_mc: nr = h*1000+w, nc = ci*1000+co
        #   o[oc][i][j] 依赖 k[oc][c][*] 和 inp[c][窗口]
        if op == OP_CONVMC {
            let mh: i64 = nr / 1000;
            let mw: i64 = nr - mh * 1000;
            let mci: i64 = nc / 1000;
            let mco: i64 = nc - mci * 1000;
            let moh: i64 = mh - 2;
            let mow: i64 = mw - 2;
            let oc: i64 = 0;
            while oc < mco {
                let ci: i64 = 0;
                while ci < mci {
                    let mi: i64 = 0;
                    while mi < moh {
                        let mj: i64 = 0;
                        while mj < mow {
                            let ki: i64 = 0;
                            while ki < 3 {
                                let kj: i64 = 0;
                                while kj < 3 {
                                    let src: i64 = ad_asd_pat(a + ci * mh * mw
                                                   + (mi + ki) * mw + (mj + kj));
                                    let kv: i64 = ad_asd_pat(b + oc * mci * 9
                                                   + ci * 9 + ki * 3 + kj);
                                    let oi2: i64 = o + oc * moh * mow + mi * mow + mj;
                                    store64(&AD_PAT + oi2 * 8,
                                            load64(&AD_PAT + oi2 * 8) | src | kv);
                                    kj = kj + 1;
                                }
                                ki = ki + 1;
                            }
                            mj = mj + 1;
                        }
                        mi = mi + 1;
                    }
                    ci = ci + 1;
                }
                oc = oc + 1;
            }
        }
        # pool_mc: nr = co*1000+h, nc = w；2×2 窗口取 POOLPOS
        if op == OP_POOLMC {
            let pco: i64 = nr / 1000;
            let ph: i64 = nr - pco * 1000;
            let pw: i64 = nc;
            let poh: i64 = ph / 2;
            let pow2: i64 = pw / 2;
            # 🔴 保守：四个候选位置都算（POOLPOS 依赖数值，静态推不出来）
            let pc: i64 = 0;
            while pc < pco {
                let pi: i64 = 0;
                while pi < poh {
                    let pj: i64 = 0;
                    while pj < pow2 {
                        let acc2: i64 = 0;
                        let q: i64 = 0;
                        while q < 4 {
                            acc2 = acc2 | ad_asd_pat(a + pc * ph * pw
                                        + (pi * 2 + q / 2) * pw + pj * 2 + (q & 1));
                            q = q + 1;
                        }
                        store64(&AD_PAT + (o + pc * poh * pow2 + pi * pow2 + pj) * 8, acc2);
                        pj = pj + 1;
                    }
                    pi = pi + 1;
                }
                pc = pc + 1;
            }
        }
        # gmax_mc / gavg_mc: o[c] = pool(通道 c 的所有位置)
        if op == OP_GMAX {
            let gc: i64 = 0;
            while gc < nr {
                let acc3: i64 = 0;
                let gp: i64 = 0;
                while gp < nc {
                    acc3 = acc3 | ad_asd_pat(a + gc * nc + gp);
                    gp = gp + 1;
                }
                store64(&AD_PAT + (o + gc) * 8, acc3);
                gc = gc + 1;
            }
        }
        if op == OP_GAVG {
            let gc2: i64 = 0;
            while gc2 < nr {
                let acc4: i64 = 0;
                let gp2: i64 = 0;
                while gp2 < nc {
                    acc4 = acc4 | ad_asd_pat(a + gc2 * nc + gp2);
                    gp2 = gp2 + 1;
                }
                store64(&AD_PAT + (o + gc2) * 8, acc4);
                gc2 = gc2 + 1;
            }
        }
        t = t + 1;
    }

    # 统计非零个数（只看输出块）
    AD_ASD_NZ = 0;
    i = 0;
    while i < nout {
        let pp: i64 = load64(&AD_PAT + (sout + i) * 8);
        let j2: i64 = 0;
        while j2 < nin {
            let b2: i64 = pp >> j2;
            b2 = b2 & 1;
            if b2 == 1 { AD_ASD_NZ = AD_ASD_NZ + 1; }
            j2 = j2 + 1;
        }
        i = i + 1;
    }
    return AD_ASD_NZ;
}

# ---- 第 2 步：Coloring ----
#
# 结构正交：两列 j1,j2 可同色 ⟺ **不存在**行 i 使 J[i][j1]、J[i][j2] 都非零。
# 用检测出的模式：遍历每个输出行的位集，把其中所有位两两标为冲突。
fn ad_asd_color() -> i64 {
    let nin: i64 = AD_ASD_NI;
    let nout: i64 = AD_ASD_NO;
    let i: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;

    i = 0;
    while i < 64 { store64(&AD_CFL + i * 8, 0); store64(&AD_COL + i * 8, 0 - 1); i = i + 1; }

    # 冲突矩阵
    i = 0;
    while i < nout {
        let pp: i64 = load64(&AD_PAT + (AD_ASD_OUT + i) * 8);
        a = 0;
        while a < nin {
            let ba: i64 = pp >> a;
            ba = ba & 1;
            if ba == 1 {
                b = 0;
                while b < nin {
                    let bb: i64 = pp >> b;
                    bb = bb & 1;
                    if bb == 1 {
                        if a != b {
                            store64(&AD_CFL + a * 8,
                                    load64(&AD_CFL + a * 8) | (1 << b));
                        }
                    }
                    b = b + 1;
                }
            }
            a = a + 1;
        }
        i = i + 1;
    }

    # 贪心：给每列分配最小的、不与已用列冲突的颜色
    # 🔴 不能维护"已被占用的颜色"集合：同一颜色本来就该被多个不冲突的
    #    列共用。第一版加了 used 标记，每列只能拿新颜色 ⇒ 颜色数 = nin，
    #    压缩率退化成 1 —— ASD **静默失效**（结果仍正确，只是没省）。
    let ncol: i64 = 0;
    a = 0;
    while a < nin {
        let c: i64 = 0;
        while c < 64 {
            if load64(&AD_COL + a * 8) < 0 {
                let ok: i64 = 1;
                b = 0;
                while b < a {
                    if load64(&AD_COL + b * 8) == c {
                        let cb: i64 = load64(&AD_CFL + a * 8) >> b;
                        cb = cb & 1;
                        if cb == 1 { ok = 0; }
                    }
                    b = b + 1;
                }
                if ok == 1 {
                    store64(&AD_COL + a * 8, c);
                    if c + 1 > ncol { ncol = c + 1; }
                }
            }
            c = c + 1;
        }
        a = a + 1;
    }
    AD_ASD_NC = ncol;
    return ncol;
}

# ---- 第 3、4 步：Compressed AD + Decompression ----
#
# 对每个颜色 c，设 seed[j] = 1（该颜色的所有列），跑一次前向模式，
# 得到压缩 Jacobian 的第 c 行；解压时 J[o][j] = JC[c(j)][o]。
#
# 🔴 前向模式**累加**到 AD_DOT，所以每次传播前必须清零 AD_DOT。
fn ad_asd_jac() -> i64 {
    let nin: i64 = AD_ASD_NI;
    let nout: i64 = AD_ASD_NO;
    let ncol: i64 = AD_ASD_NC;
    let c: i64 = 0;
    let j: i64 = 0;
    let i: i64 = 0;

    while c < ncol {
        # 清零并设种子
        i = 0;
        while i < AD_N { store64(&AD_DOT + i * 8, 0); i = i + 1; }
        j = 0;
        while j < nin {
            if load64(&AD_COL + j * 8) == c {
                store64(&AD_DOT + (AD_ASD_IN + j) * 8, 65536);
            } else {
                store64(&AD_DOT + (AD_ASD_IN + j) * 8, 0);
            }
            j = j + 1;
        }
        # 🔴 非输入的槽：dot 必须清零（前向会从输入传播，但常量槽是 0）
        ad_forward();
        i = 0;
        while i < nout {
            store64(&AD_CJC + (c * nout + i) * 8,
                    load64(&AD_DOT + (AD_ASD_OUT + i) * 8));
            i = i + 1;
        }
        c = c + 1;
    }
    return ncol;
}

# 取解压后的 J[o][j]
#
# 🔴 JC[c][o] 是颜色 c 里**所有列**在输出 o 上的导数之和。
#    只有 j 是其中那个"唯一非零"的列时才能直接取。
#    所以必须先用稀疏模式过滤：模式说 J[o][j]=0 就返回 0。
#    这正是论文里的 recovery matrix R（Gebremedhin et al.）。
fn ad_asd_get(o: i64, j: i64) -> i64 {
    let c: i64 = load64(&AD_COL + j * 8);
    if c < 0 { return 0; }
    let pb: i64 = load64(&AD_PAT + (AD_ASD_OUT + o) * 8) >> j;
    pb = pb & 1;
    if pb == 0 { return 0; }
    return load64(&AD_CJC + (c * AD_ASD_NO + o) * 8);
}

fn ad_asd_ncol() -> i64 { return AD_ASD_NC; }
fn ad_asd_nnz()  -> i64 { return AD_ASD_NZ; }
fn ad_asd_patof(sl: i64) -> i64 { return load64(&AD_PAT + sl * 8); }
fn ad_asd_colof(j: i64) -> i64 { return load64(&AD_COL + j * 8); }

fn ad_dot_f()   -> i64 { return AD_DOT_F; }
fn ad_dot_r()   -> i64 { return AD_DOT_R; }
fn ad_dot_rel() -> i64 { return AD_DOT_REL; }


# ================================================================
# Revolve 最优 checkpointing（1.83）
# ----------------------------------------------------------------
# 概念来源：Griewank & Walther 2000, Algorithm 799: Revolve（ACM TOMS 26(1)）
#
#   给定 l 步前向与 c 个 checkpoint，求**重算次数最少**的反向调度。
#   策略族是 binomial 式递归分割：先把区间切开、在切点存快照，
#   做完右半再回收这个快照槽去做左半。
#
#   PyTorch / 传统做法 = **均匀分段**：每段重算一次，额外整整一次前向。
#   Revolve 的关键差异在下面递归式的最后一项——
#   右半做完后，切点的快照槽被**释放**，左半因此仍持有全部 c 个槽。
#
# 记号：
#   σ_t      = 执行完 tape 前 t 步之后的所有 AD_VAL
#   反向第 t 步（即 tape[t-1]）需要 σ_{t-1}
#   checkpoint = 某个 σ 的快照
#
# 最优性模型（本实现所用）：
#   cost(1, c) = 0
#   cost(m, 0) = m(m-1)/2                     # 逐个从段首重算
#   cost(m, c) = min_{1<=k<m} [ k + cost(m-k, c-1) + cost(k, c) ]
#                                ^   ^^^^^^^^^^^^^^^   ^^^^^^^^^^
#                      建快照的 k 步   右半（占 1 槽）   左半（槽已归还，仍 c 个）
# ================================================================

var AD_CKV:   [12288] i64 = 0;    # checkpoint 值：AD_CKV[k*2048 + s]
var AD_CKP:   [16]    i64 = 0;    # 槽 k → 位置
var AD_CKOF:  [512]   i64 = 0;    # 位置 → 槽+1（0 = 该位置无快照）
var AD_CKN:   i64 = 1;            # 已用槽数（槽 0 恒为 σ_0）
var AD_CKMAX: i64 = 6;
var AD_CKMEM: [2048]  i64 = 0;    # DP：cost(m,c)+1（0 = 未算）
var AD_CKS:   [2048]  i64 = 0;    # DP：最优切点
var AD_RC:    i64 = 0;            # 重算步数（重复执行的前向操作数）
var AD_RN:    i64 = 0;            # 反向步数
var AD_CKERR: i64 = 0;            # 0=ok 1=不支持的算子 2=槽耗尽 3=规模超限 4=快照缺失

fn ad_gadd(s: i64, v: i64) -> i64 {
    store64(&AD_GRAD + s * 8, load64(&AD_GRAD + s * 8) + v);
    return 0;
}

# ---------------------------------------------------------------- 快照

fn ad_ckpt_save(k: i64, pos: i64) -> i64 {
    let i: i64 = 0;
    if k >= AD_CKMAX { AD_CKERR = 2; return -1; }
    if AD_N > 2048 { AD_CKERR = 3; return -1; }
    while i < AD_N {
        store64(&AD_CKV + (k * 2048 + i) * 8, load64(&AD_VAL + i * 8));
        i = i + 1;
    }
    store64(&AD_CKP + k * 8, pos);
    store64(&AD_CKOF + pos * 8, k + 1);
    return 0;
}

fn ad_ckpt_restore(k: i64) -> i64 {
    let i: i64 = 0;
    while i < AD_N {
        store64(&AD_VAL + i * 8, load64(&AD_CKV + (k * 2048 + i) * 8));
        i = i + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 重算

# 重放 tape [t0, t1)：按记录重算 AD_VAL
fn ad_replay_core(t0: i64, t1: i64) -> i64 {
    let t: i64 = t0;
    let op: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let o: i64 = 0;
    let nr: i64 = 0;
    let nc: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let acc: i64 = 0;
    let d: i64 = 0;
    while t < t1 {
        op = load64(&AD_TOP + t * 8);
        a  = load64(&AD_TA + t * 8);
        b  = load64(&AD_TB + t * 8);
        o  = load64(&AD_TO + t * 8);
        nr = load64(&AD_TXA + t * 8);
        nc = load64(&AD_TXB + t * 8);

        if op == OP_ADD  { store64(&AD_VAL + o * 8, ad_val(a) + ad_val(b)); }
        if op == OP_SUB  { store64(&AD_VAL + o * 8, ad_val(a) - ad_val(b)); }
        if op == OP_MUL  { store64(&AD_VAL + o * 8, nn_fmul(ad_val(a), ad_val(b))); }
        if op == OP_RELU {
            if ad_val(a) > 0 { store64(&AD_VAL + o * 8, ad_val(a)); }
            else { store64(&AD_VAL + o * 8, 0); }
        }
        if op == OP_LREL {
            if ad_val(a) > 0 { store64(&AD_VAL + o * 8, ad_val(a)); }
            else { store64(&AD_VAL + o * 8, nn_fmul(AD_LRELU_NEG, ad_val(a))); }
        }
        if op == OP_SIG  { store64(&AD_VAL + o * 8, nn_sigmoid(ad_val(a))); }
        if op == OP_TANH { store64(&AD_VAL + o * 8, nn_tanh(ad_val(a))); }

        if op == OP_VADD {
            i = 0;
            while i < nr {
                store64(&AD_VAL + (o + i) * 8, ad_val(a + i) + ad_val(b + i));
                i = i + 1;
            }
        }
        if op == OP_VSIG {
            i = 0;
            while i < nr { store64(&AD_VAL + (o + i) * 8, nn_sigmoid(ad_val(a + i))); i = i + 1; }
        }
        if op == OP_VTAN {
            i = 0;
            while i < nr { store64(&AD_VAL + (o + i) * 8, nn_tanh(ad_val(a + i))); i = i + 1; }
        }
        if op == OP_VREL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 { store64(&AD_VAL + (o + i) * 8, ad_val(a + i)); }
                else { store64(&AD_VAL + (o + i) * 8, 0); }
                i = i + 1;
            }
        }
        if op == OP_VLRL {
            i = 0;
            while i < nr {
                if ad_val(a + i) > 0 { store64(&AD_VAL + (o + i) * 8, ad_val(a + i)); }
                else { store64(&AD_VAL + (o + i) * 8, nn_fmul(AD_LRELU_NEG, ad_val(a + i))); }
                i = i + 1;
            }
        }
        if op == OP_VADD_B {
            i = 0;
            while i < nr {
                j = 0;
                while j < nc {
                    # 🔴 偏置按通道 i 索引（与 ad_vadd_bcast 一致），不是元素 j
                    store64(&AD_VAL + (o + i * nc + j) * 8,
                            ad_val(a + i * nc + j) + ad_val(b + i));
                    j = j + 1;
                }
                i = i + 1;
            }
        }
        if op == OP_MATMUL {
            i = 0;
            while i < nr {
                acc = 0;
                j = 0;
                while j < nc {
                    acc = acc + nn_fmul(ad_val(a + i * nc + j), ad_val(b + j));
                    j = j + 1;
                }
                store64(&AD_VAL + (o + i) * 8, acc);
                i = i + 1;
            }
        }
        if op == OP_MSE {
            acc = 0;
            i = 0;
            while i < nr { d = ad_val(a + i) - ad_val(b + i); acc = acc + nn_fmul(d, d); i = i + 1; }
            store64(&AD_VAL + o * 8, nn_fdiv(acc, nn_from_i(nr)));
        }
        if op == OP_MSEH {
            # 与 OP_MSE 的**值**相同，差别只在反向差一个 2 倍因子（见 1.79）
            acc = 0;
            i = 0;
            while i < nr { d = ad_val(a + i) - ad_val(b + i); acc = acc + nn_fmul(d, d); i = i + 1; }
            store64(&AD_VAL + o * 8, nn_fdiv(acc, nn_from_i(nr)));
        }

        # 不支持重算的算子：明确报错，绝不静默跳过
        if op == OP_CONV   { AD_CKERR = 1; return -1; }
        if op == OP_CONVMC { AD_CKERR = 1; return -1; }
        if op == OP_POOL   { AD_CKERR = 1; return -1; }
        if op == OP_POOLMC { AD_CKERR = 1; return -1; }
        if op == OP_GMAX   { AD_CKERR = 1; return -1; }
        if op == OP_GAVG   { AD_CKERR = 1; return -1; }
        if op == OP_SCE    { AD_CKERR = 1; return -1; }
        if op == OP_MMBA   { AD_CKERR = 1; return -1; }
        if op == OP_MBAT   { AD_CKERR = 1; return -1; }

        t = t + 1;
    }
    return 0;
}

fn ad_replay(t0: i64, t1: i64) -> i64 {
    AD_RC = AD_RC + (t1 - t0);
    return ad_replay_core(t0, t1);
}

# 不计入预算的重算（用于「主前向中免费存快照」的建模）
fn ad_replay_quiet(t0: i64, t1: i64) -> i64 { return ad_replay_core(t0, t1); }

# ---------------------------------------------------------------- 反向单步

fn ad_rev_step(t: i64) -> i64 {
    let op: i64 = load64(&AD_TOP + t * 8);
    let a: i64 = load64(&AD_TA + t * 8);
    let b: i64 = load64(&AD_TB + t * 8);
    let o: i64 = load64(&AD_TO + t * 8);
    let nr: i64 = load64(&AD_TXA + t * 8);
    let nc: i64 = load64(&AD_TXB + t * 8);
    let go: i64 = load64(&AD_GRAD + o * 8);
    let i: i64 = 0;
    let j: i64 = 0;
    let d: i64 = 0;
    AD_RN = AD_RN + 1;

    if op == OP_ADD  { ad_gadd(a, go); ad_gadd(b, go); }
    if op == OP_SUB  { ad_gadd(a, go); ad_gadd(b, 0 - go); }
    if op == OP_MUL  { ad_gadd(a, nn_fmul(go, ad_val(b))); ad_gadd(b, nn_fmul(go, ad_val(a))); }
    if op == OP_RELU { if ad_val(a) > 0 { ad_gadd(a, go); } }
    if op == OP_LREL {
        if ad_val(a) > 0 { ad_gadd(a, go); }
        else { ad_gadd(a, nn_fmul(go, AD_LRELU_NEG)); }
    }
    if op == OP_SIG  { d = nn_fmul(ad_val(o), nn_from_i(1) - ad_val(o)); ad_gadd(a, nn_fmul(go, d)); }
    if op == OP_TANH { d = nn_from_i(1) - nn_fmul(ad_val(o), ad_val(o)); ad_gadd(a, nn_fmul(go, d)); }

    if op == OP_VADD {
        i = 0;
        while i < nr { ad_gadd(a + i, load64(&AD_GRAD + (o + i) * 8)); ad_gadd(b + i, load64(&AD_GRAD + (o + i) * 8)); i = i + 1; }
    }
    if op == OP_VSIG {
        i = 0;
        while i < nr {
            d = nn_fmul(ad_val(o + i), nn_from_i(1) - ad_val(o + i));
            ad_gadd(a + i, nn_fmul(load64(&AD_GRAD + (o + i) * 8), d));
            i = i + 1;
        }
    }
    if op == OP_VTAN {
        i = 0;
        while i < nr {
            d = nn_from_i(1) - nn_fmul(ad_val(o + i), ad_val(o + i));
            ad_gadd(a + i, nn_fmul(load64(&AD_GRAD + (o + i) * 8), d));
            i = i + 1;
        }
    }
    if op == OP_VREL {
        i = 0;
        while i < nr { if ad_val(a + i) > 0 { ad_gadd(a + i, load64(&AD_GRAD + (o + i) * 8)); } i = i + 1; }
    }
    if op == OP_VLRL {
        i = 0;
        while i < nr {
            if ad_val(a + i) > 0 { ad_gadd(a + i, load64(&AD_GRAD + (o + i) * 8)); }
            else { ad_gadd(a + i, nn_fmul(load64(&AD_GRAD + (o + i) * 8), AD_LRELU_NEG)); }
            i = i + 1;
        }
    }
    if op == OP_VADD_B {
        i = 0;
        while i < nr {
            j = 0;
            while j < nc {
                ad_gadd(a + i * nc + j, load64(&AD_GRAD + (o + i * nc + j) * 8));
                j = j + 1;
            }
            ad_gadd(b + i, load64(&AD_GRAD + (o + i * nc) * 8));
            i = i + 1;
        }
    }
    if op == OP_MATMUL {
        i = 0;
        while i < nr {
            j = 0;
            while j < nc {
                ad_gadd(a + i * nc + j, nn_fmul(load64(&AD_GRAD + (o + i) * 8), ad_val(b + j)));
                ad_gadd(b + j, nn_fmul(load64(&AD_GRAD + (o + i) * 8), ad_val(a + i * nc + j)));
                j = j + 1;
            }
            i = i + 1;
        }
    }
    if op == OP_MSE {
        i = 0;
        while i < nr {
            d = nn_fmul(nn_from_i(2), ad_val(a + i) - ad_val(b + i));
            ad_gadd(a + i, nn_fmul(go, nn_fdiv(d, nn_from_i(nr))));
            i = i + 1;
        }
    }
    if op == OP_MSEH {
        # 🔴 有意与 OP_MSE 差 2 倍：loss 报 Σe²/n，反向用 (y-t)/n（见 1.79）
        i = 0;
        while i < nr {
            d = ad_val(a + i) - ad_val(b + i);
            ad_gadd(a + i, nn_fmul(go, nn_fdiv(d, nn_from_i(nr))));
            i = i + 1;
        }
    }
    if op == OP_CONV   { AD_CKERR = 1; return -1; }
    if op == OP_CONVMC { AD_CKERR = 1; return -1; }
    if op == OP_POOL   { AD_CKERR = 1; return -1; }
    if op == OP_POOLMC { AD_CKERR = 1; return -1; }
    if op == OP_GMAX   { AD_CKERR = 1; return -1; }
    if op == OP_GAVG   { AD_CKERR = 1; return -1; }
    if op == OP_SCE    { AD_CKERR = 1; return -1; }
    if op == OP_MMBA   { AD_CKERR = 1; return -1; }
    if op == OP_MBAT   { AD_CKERR = 1; return -1; }
    return 0;
}

# ---------------------------------------------------------------- DP：最优切点

fn ad_rev_cost(m: i64, c: i64) -> i64 {
    if m <= 1 { return 0; }
    if m > 255 { AD_CKERR = 3; return 0; }
    if c > 7 { c = 7; }
    let memo: i64 = load64(&AD_CKMEM + (m * 8 + c) * 8);
    if memo > 0 { return memo - 1; }
    let best: i64 = 0;
    let bk: i64 = 0;
    let k: i64 = 1;
    let v: i64 = 0;
    if c <= 0 {
        v = m * (m - 1) / 2;
        store64(&AD_CKMEM + (m * 8 + c) * 8, v + 1);
        return v;
    }
    best = 0 - 1;
    while k < m {
        v = k + ad_rev_cost(m - k, c - 1) + ad_rev_cost(k, c);
        if best < 0 { best = v; bk = k; }
        else { if v < best { best = v; bk = k; } }
        k = k + 1;
    }
    store64(&AD_CKMEM + (m * 8 + c) * 8, best + 1);
    store64(&AD_CKS + (m * 8 + c) * 8, bk);
    return best;
}

fn ad_rev_split(m: i64, c: i64) -> i64 {
    let k: i64 = 0;
    if m <= 1 { return 1; }
    if c > 7 { c = 7; }
    # ad_rev_cost 的副作用是填 AD_CKMEM/AD_CKS 缓存；返回值这里用不上，
    # 原先把返回值存进 v 却再没读过（tools/unused.py 报出来的死变量）。
    ad_rev_cost(m, c);
    k = load64(&AD_CKS + (m * 8 + c) * 8);
    if k <= 0 { k = m / 2; }
    if k <= 0 { k = 1; }
    if k >= m { k = m - 1; }
    return k;
}

# ---------------------------------------------------------------- 调度执行

# 恢复 σ_s，重放 [s, t)  →  得到 σ_t
fn ad_rev_pre(s: i64, t: i64) -> i64 {
    let slot: i64 = 0;
    if s > 0 {
        slot = load64(&AD_CKOF + s * 8) - 1;
        if slot < 0 { AD_CKERR = 4; return -1; }
        if load64(&AD_CKP + slot * 8) != s { AD_CKERR = 6; return -1; }
        ad_ckpt_restore(slot);
    } else {
        if load64(&AD_CKP + 0 * 8) != 0 { AD_CKERR = 6; return -1; }
        ad_ckpt_restore(0);
    }
    if t > s { return ad_replay(s, t); }
    return 0;
}

fn ad_rev_run(l: i64, s: i64, c: i64) -> i64 {
    let t: i64 = 0;
    let k: i64 = 0;
    let m: i64 = 0;
    let slot: i64 = 0;
    if AD_CKERR != 0 { return -1; }
    if l <= s { return 0; }
    if l == s + 1 {
        ad_rev_pre(s, l - 1);
        ad_rev_step(l - 1);
        return 0;
    }
    if c <= 0 {
        t = l;
        while t > s {
            ad_rev_pre(s, t - 1);
            ad_rev_step(t - 1);
            t = t - 1;
        }
        return 0;
    }
    k = ad_rev_split(l - s, c);
    m = s + k;
    ad_rev_pre(s, m);
    slot = AD_CKN;
    if slot >= AD_CKMAX { AD_CKERR = 2; return -1; }
    AD_CKN = slot + 1;
    ad_ckpt_save(slot, m);
    ad_rev_run(l, m, c - 1);
    AD_CKN = slot;
    ad_rev_run(m, s, c);
    return 0;
}

# ---------------------------------------------------------------- 对外入口

fn ad_backward_revolve(loss: i64, c: i64) -> i64 {
    let i: i64 = 0;
    AD_CKERR = 0;
    AD_RC = 0;
    AD_RN = 0;
    AD_CKN = 1;
    while i < 512 { store64(&AD_CKOF + i * 8, 0); i = i + 1; }
    while i < 2048 { store64(&AD_CKMEM + i * 8, 0); store64(&AD_CKS + i * 8, 0); i = i + 1; }
    if AD_TN > 255 { AD_CKERR = 3; return -1; }
    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));
    # σ_0：叶子（输入/权重）在前向中不被覆盖，中间槽随后会被重放覆盖，
    #      所以「当前值」就是合法的 σ_0
    ad_ckpt_save(0, 0);
    ad_rev_top(AD_TN, c);
    return 0;
}

# 均匀分段 baseline（PyTorch 的做法）：k 段，每段重算一次
fn ad_backward_uniform(loss: i64, k: i64) -> i64 {
    let l: i64 = AD_TN;
    let i: i64 = 0;
    let t: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    AD_CKERR = 0;
    AD_RC = 0;
    AD_RN = 0;
    AD_CKN = 1;
    i = 0;
    while i < 512 { store64(&AD_CKOF + i * 8, 0); i = i + 1; }
    if k < 1 { k = 1; }
    if k > l { k = l; }
    if k >= AD_CKMAX { AD_CKERR = 2; return -1; }
    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));
    ad_ckpt_save(0, 0);
    # 段边界快照：建模为「主前向中顺带保存」，不计入重算预算
    i = 1;
    while i < k {
        p = i * l / k;
        ad_ckpt_restore(0);
        ad_replay_quiet(0, p);
        ad_ckpt_save(i, p);
        i = i + 1;
    }
    i = k;
    while i >= 1 {
        p = (i - 1) * l / k;
        q = i * l / k;
        ad_rev_pre(p, q);
        t = q - 1;
        while t >= p {
            ad_rev_step(t);
            t = t - 1;
        }
        i = i - 1;
    }
    return 0;
}

fn ad_recompute_count() -> i64 { return AD_RC; }
fn ad_reverse_count()   -> i64 { return AD_RN; }
fn ad_ckpt_err()        -> i64 { return AD_CKERR; }
fn ad_rev_cost_of(m: i64, c: i64) -> i64 { return ad_rev_cost(m, c); }

# 均匀分段 + 段内**逐层**重算。
# 与 Revolve 处在同一内存模型：只保留「当前状态」+ c 个快照，
# 重算走过就覆盖，不保留段内历史 —— 这才是公平对比。
fn ad_backward_uniform_tight(loss: i64, k: i64) -> i64 {
    let l: i64 = AD_TN;
    let i: i64 = 0;
    let t: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    AD_CKERR = 0;
    AD_RC = 0;
    AD_RN = 0;
    AD_CKN = 1;
    i = 0;
    while i < 512 { store64(&AD_CKOF + i * 8, 0); i = i + 1; }
    if k < 1 { k = 1; }
    if k > l { k = l; }
    if k >= AD_CKMAX { AD_CKERR = 2; return -1; }
    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));
    ad_ckpt_save(0, 0);
    i = 1;
    while i < k {
        p = i * l / k;
        ad_ckpt_restore(0);
        ad_replay_quiet(0, p);
        ad_ckpt_save(i, p);
        i = i + 1;
    }
    i = k;
    while i >= 1 {
        p = (i - 1) * l / k;
        q = i * l / k;
        t = q - 1;
        while t >= p {
            ad_rev_pre(p, t);
            ad_rev_step(t);
            t = t - 1;
        }
        i = i - 1;
    }
    return 0;
}

# 🔴 修正（实测发现）：c=3 时 Revolve 30 步，反而多于同槽数均匀分段的 28 步。
#
# 原因：初始前向 l 步**本来就要走完**（否则算不出 loss），
# 所以途中顺手存快照是**免费**的。原模型把第一次建快照的 k 步也算成重算，
# 于是「平铺 c 个快照、每段逐层」这个候选根本不在搜索空间里。
#
# 修正：顶层允许平铺 j 个免费快照（0 <= j <= c），分成 j+1 段；
#       段内递归仍可用剩下的 c-j 个槽。j=c 时即退化为均匀分段，
#       所以新实现**不劣于**均匀分段 —— 这是可断言的下界。
#
# 段长按「前 r 段 +1」均分（cost 对段长凸，均分最优）。

fn ad_rev_topj(m: i64, c: i64) -> i64 {
    let best: i64 = 0 - 1;
    let bj: i64 = 0;
    let j: i64 = 0;
    let seg: i64 = 0;
    let r: i64 = 0;
    let v: i64 = 0;
    while j <= c {
        seg = m / (j + 1);
        r = m - seg * (j + 1);
        v = 0;
        if r > 0 { v = v + r * ad_rev_cost(seg + 1, c - j); }
        v = v + (j + 1 - r) * ad_rev_cost(seg, c - j);
        if best < 0 { best = v; bj = j; }
        else { if v < best { best = v; bj = j; } }
        j = j + 1;
    }
    store64(&AD_CKMEM + 8, best + 1);      # 存总代价，供自洽检验读取
    return bj;
}

fn ad_rev_topcost(m: i64, c: i64) -> i64 {
    let v: i64 = ad_rev_topj(m, c);
    return load64(&AD_CKMEM + 8) - 1;
}

# 顶层：免费平铺 j 个快照，段内递归
fn ad_rev_top(l: i64, c: i64) -> i64 {
    let j: i64 = ad_rev_topj(l, c);
    let i: i64 = 1;
    let p: i64 = 0;
    let q: i64 = 0;
    while i <= j {
        p = i * l / (j + 1);
        ad_ckpt_restore(0);
        ad_replay_quiet(0, p);
        ad_ckpt_save(i, p);
        i = i + 1;
    }
    AD_CKN = j + 1;
    i = j + 1;
    while i >= 1 {
        p = (i - 1) * l / (j + 1);
        q = i * l / (j + 1);
        ad_rev_run(q, p, c - j);
        i = i - 1;
    }
    return 0;
}


# ================================================================
# Multistage 两级 checkpointing（1.84）
# ----------------------------------------------------------------
# 概念来源：Stumm, P. & Walther, A. (2009) "Multistage approaches for
#   optimal offline checkpointing", SIAM J. Sci. Comput. 31(3), 1946–1967
#
#   Revolve（1.83）假设所有快照**同质**（同成本、同层级）。
#   真实机器有 RAM 与磁盘两级：磁盘容量不限，但一次 IO 贵得多。
#   Multistage 把快照分配到两级，最小化 重算 + IO 的总代价。
#
# 统一模型（本实现）—— 把 1.83 的 RAM 顶层平铺纳入同一个搜索空间：
#
#   把 l 步切成 N 段，段起点 BK[0..N-1]（BK[0] = 0）：
#     前 j+1 个起点（BK[0..j]）存 **RAM** 槽 0..j      —— 主前向中顺手，免费
#     其余起点存 **磁盘**                              —— 每次写+读各 w
#   段内用剩下的 r-j 个 RAM 槽做 Revolve 递归。
#
#   RAM 状态数恒为 (j+1) + (r-j) = r+1，与 1.83 的纯 RAM Revolve 相同。
#
#   disks = 0                 若 N-1 <= j（起点全在 RAM，无需磁盘）
#         = N - j             否则（含 σ_0 的一份磁盘副本）
#
#   T(N,j) = disks·2w + Σ_{i=1..N} cost(seg_i, r-j)
#
#   j = N-1 时 disks=0，恰好退化为 1.83 的纯 RAM Revolve
#   ⇒ Multistage 的最优值必然 ≤ 纯 RAM Revolve。这是可断言的硬下界。
# ================================================================

var CKPATH: [64] byte = 0;
var AD_MS_W:  i64 = 0;    # 磁盘单次 IO 代价
var AD_MS_N:  i64 = 0;    # 选中的段数
var AD_MS_J:  i64 = 0;    # 选中的 RAM 起点数 - 1
var AD_MS_DW: i64 = 0;    # 磁盘写次数
var AD_MS_DR: i64 = 0;    # 磁盘读次数
var AD_MS_BK: [512] i64 = 0;   # 段起点（长度 N+1）

fn ckpath(id: i64) -> i64 {
    store8(&CKPATH + 0, 0);
    strcat(&CKPATH, "/tmp/mock_ck_");
    strcat_i64(&CKPATH, id);
    strcat(&CKPATH, ".bin");
    return &CKPATH;
}

fn ad_disk_save(id: i64) -> i64 {
    let fd: i64 = fopen(ckpath(id), 577, 420);
    AD_MS_DW = AD_MS_DW + 1;
    if fd < 0 { AD_CKERR = 5; return -1; }
    fwrite(fd, &AD_VAL, AD_N * 8);
    fclose(fd);
    return 0;
}

fn ad_disk_load(id: i64) -> i64 {
    let fd: i64 = fopen(ckpath(id), 0, 0);
    AD_MS_DR = AD_MS_DR + 1;
    if fd < 0 { AD_CKERR = 5; return -1; }
    fread(fd, &AD_VAL, AD_N * 8);
    fclose(fd);
    return 0;
}

# 段长按「前 rr 段 +1」均分（代价对段长凸，均分最优）
fn ad_ms_seg(m: i64, n: i64, i: i64) -> i64 {
    let s: i64 = m / n;
    let r: i64 = m - s * n;
    if i < r { return s + 1; }
    return s;
}

fn ad_ms_disks(n: i64, j: i64) -> i64 {
    if n - 1 <= j { return 0; }
    return n - j;
}

fn ad_ms_cost(l: i64, r: i64, n: i64, j: i64, w: i64) -> i64 {
    let t: i64 = ad_ms_disks(n, j) * 2 * w;
    let i: i64 = 0;
    if n < 1 { n = 1; }
    if n > l { n = l; }
    if j > r { j = r; }
    if j > n - 1 { j = n - 1; }
    while i < n {
        t = t + ad_rev_cost(ad_ms_seg(l, n, i), r - j);
        i = i + 1;
    }
    return t;
}

# 返回 n*64 + j 编码的最优 (n, j)
fn ad_ms_best(l: i64, r: i64, w: i64) -> i64 {
    let n: i64 = 1;
    let j: i64 = 0;
    let best: i64 = 0 - 1;
    let bn: i64 = 1;
    let bj: i64 = 0;
    let v: i64 = 0;
    while n <= l {
        j = 0;
        while j <= r {
            if j <= n - 1 {
                v = ad_ms_cost(l, r, n, j, w);
                if best < 0 { best = v; bn = n; bj = j; }
                else { if v < best { best = v; bn = n; bj = j; } }
            }
            j = j + 1;
        }
        n = n + 1;
    }
    return bn * 64 + bj;
}

fn ad_ms_time(l: i64, r: i64, w: i64) -> i64 {
    let e: i64 = ad_ms_best(l, r, w);
    let n: i64 = e / 64;
    let j: i64 = e - n * 64;
    return ad_ms_cost(l, r, n, j, w);
}

fn ad_backward_multistage(loss: i64, r: i64, w: i64) -> i64 {
    let l: i64 = AD_TN;
    let n: i64 = 0;
    let j: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let dk: i64 = 0;
    let e: i64 = 0;
    AD_CKERR = 0;
    AD_RC = 0;
    AD_RN = 0;
    AD_CKN = 1;
    AD_MS_W = w;
    AD_MS_DW = 0;
    AD_MS_DR = 0;
    i = 0;
    while i < 512 {
        store64(&AD_CKOF + i * 8, 0);
        store64(&AD_MS_BK + i * 8, 0);
        i = i + 1;
    }
    while i < 2048 { store64(&AD_CKMEM + i * 8, 0); store64(&AD_CKS + i * 8, 0); i = i + 1; }
    if l > 255 { AD_CKERR = 3; return -1; }
    if r > AD_CKMAX - 1 { r = AD_CKMAX - 1; }
    e = ad_ms_best(l, r, w);
    n = e / 64;
    j = e - n * 64;
    AD_MS_N = n;
    AD_MS_J = j;
    dk = ad_ms_disks(n, j);

    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));

    # ---- 主前向中顺手存起点快照：RAM 免费，磁盘每次 w ----
    ad_ckpt_save(0, 0);
    ad_ckpt_restore(0);
    if dk > 0 { ad_disk_save(0); }
    p = 0;
    i = 0;
    while i < n - 1 {
        q = p + ad_ms_seg(l, n, i);
        ad_replay_quiet(p, q);
        store64(&AD_MS_BK + (i + 1) * 8, q);
        if i + 1 <= j { ad_ckpt_save(i + 1, q); }
        else { ad_disk_save(i + 1); }
        p = q;
        i = i + 1;
    }
    store64(&AD_MS_BK + n * 8, l);

    # ---- 反向：倒序遍历段，段内用 r-j 个 RAM 槽递归 ----
    i = n;
    while i >= 1 {
        p = load64(&AD_MS_BK + (i - 1) * 8);
        q = load64(&AD_MS_BK + i * 8);
        if i == 1 {
            if dk > 0 { ad_disk_load(0); }
            else { ad_ckpt_restore(0); }
            ad_ckpt_save(0, 0);
        } else {
            if i - 1 <= j { ad_ckpt_restore(i - 1); }
            else {
                ad_disk_load(i - 1);
                ad_ckpt_save(0, p);
            }
        }
        AD_CKN = j + 1;
        ad_rev_run(q, p, r - j);
        i = i - 1;
    }
    return 0;
}

fn ad_ms_n()  -> i64 { return AD_MS_N; }
fn ad_ms_j()  -> i64 { return AD_MS_J; }
fn ad_ms_dw() -> i64 { return AD_MS_DW; }
fn ad_ms_dr() -> i64 { return AD_MS_DR; }
fn ad_ms_io() -> i64 { return AD_MS_DW + AD_MS_DR; }


# ================================================================
# 多级 checkpointing（1.85）：RAM / SSD / 网络 三级容量分配
# ----------------------------------------------------------------
# 概念来源：Stumm, P. & Walther, A. (2009) "Multistage approaches for
#   optimal offline checkpointing", SIAM J. Sci. Comput. 31(3), 1946–1967
#
#   1.84 做了两级（RAM + 磁盘）。那篇论文的**主体是多级**：
#   各级有各自的容量与 IO 代价，快照要按容量与代价分配到各级。
#
#   🔴 多级有价值的前提是**中间级容量有限**：
#          level 0  RAM   容量 c0（小）  IO 代价 0（主前向顺手存）
#          level 1  SSD   容量 s1（中）  IO 代价 w1
#          level 2  网络  容量 ∞         IO 代价 w2 > w1
#      便宜的 SSD 装不下时，溢出的快照才落到网络。
#      若所有非 RAM 级都无限，只用最便宜那一级就够 —— 多级毫无意义。
#
#   Firedrake 的 checkpoint_schedules 只实现了两级；PyTorch / JAX
#   连一级的 Revolve 都没有。
#
# ----------------------------------------------------------------
# 模型
# ----------------------------------------------------------------
#   把 l 步分成 N 段，段起点 BK[0..N-1]（BK[0] = 0），按索引分配：
#       i <  a0          → RAM 槽 i   （免费，占 c0 中 a0 个）
#       a0 <= i < a0+a1  → SSD        （代价 2·w1，容量 s1）
#       i >= a0+a1       → 网络       （代价 2·w2，容量 ∞）
#   段内用剩下的 RAM 槽做 Revolve 递归。
#
#   🔴 临时槽：只要 N > a0，反向要处理「起点不在 RAM」的段，
#      这些段的起点加载后需要落到一个 RAM 槽（ad_rev_run 靠
#      AD_CKOF[位置] 找快照）。第一版把它存进槽 0，于是**覆盖 σ_0**，
#      被迫再往网络存一份 σ_0 副本（+2·w2）—— 这笔开销大到让所有
#      外部存储方案都输给纯 RAM，多级看起来毫无用处。
#
#      正解：另给一个临时槽 a0。σ_0 的槽 0 永不覆盖，副本根本不需要。
#      代价是段内少一个槽：
#          c = MK_C0 - a0 - (N > a0 ? 1 : 0)
#
#   T(N, a0, a1) = 2·a1·w1 + 2·(N-a0-a1)·w2 + Σ_i cost(seg_i(l,N), c)
# ================================================================

var MSPATH: [64] byte = 0;
var MK_C0:  i64 = 4;      # level 0（RAM）快照槽总数
var MK_S1:  i64 = 0;      # level 1（SSD）容量（0 = 无此级）
var MK_W1:  i64 = 0;      # level 1 单次 IO 代价
var MK_W2:  i64 = 0;      # level 2（网络，容量无限）单次 IO 代价
var MK_A0:  i64 = 1;      # 选中的 RAM 起点数
var MK_A1:  i64 = 0;      # 选中的 SSD 起点数
var MK_AN:  i64 = 1;      # 选中的段数
var MK_IO1: i64 = 0;      # 实际 SSD IO 次数
var MK_IO2: i64 = 0;      # 实际网络 IO 次数
var MK_BK:  [512] i64 = 0;
var MK_TOT: i64 = 0;      # DP 预测总代价

fn mk_seg(m: i64, n: i64, i: i64) -> i64 {
    let s: i64 = m / n;
    let r: i64 = m - s * n;
    if i < r { return s + 1; }
    return s;
}

fn mk_net(n: i64, a0: i64, a1: i64) -> i64 {
    let a2: i64 = n - a0 - a1;
    if a2 < 0 { return 0 - 1; }
    return a2;
}

# 段内可用 RAM 槽数：N > a0 时要留一个临时槽给外部加载的段起点
fn mk_slot(a0: i64, n: i64) -> i64 {
    let c: i64 = MK_C0 - a0;
    if n > a0 { c = c - 1; }
    if c < 0 { return 0 - 1; }
    return c;
}

# 给定 (N, a0, a1) 的总代价；非法返回 -1
fn mk_eval(l: i64, a0: i64, a1: i64, n: i64) -> i64 {
    let a2: i64 = mk_net(n, a0, a1);
    let c: i64 = mk_slot(a0, n);
    let t: i64 = 0;
    let i: i64 = 0;
    if a2 < 0 { return 0 - 1; }
    if c < 0 { return 0 - 1; }
    t = 2 * a1 * MK_W1 + 2 * a2 * MK_W2;
    while i < n {
        t = t + ad_rev_cost(mk_seg(l, n, i), c);
        i = i + 1;
    }
    return t;
}

# 搜索最优 (N, a0, a1)
fn mk_plan(l: i64) -> i64 {
    let best: i64 = 0 - 1;
    let ba0: i64 = 1;
    let ba1: i64 = 0;
    let bn: i64 = 1;
    let n: i64 = 1;
    let a0: i64 = 1;
    let a1: i64 = 0;
    let v: i64 = 0;
    if l > 255 { AD_CKERR = 3; return 0 - 1; }
    while n <= l {
        a0 = 1;
        while a0 <= MK_C0 {
            if a0 <= n {
                a1 = 0;
                while a1 <= MK_S1 {
                    if a0 + a1 <= n {
                        v = mk_eval(l, a0, a1, n);
                        if v >= 0 {
                            if best < 0 { best = v; ba0 = a0; ba1 = a1; bn = n; }
                            else { if v < best { best = v; ba0 = a0; ba1 = a1; bn = n; } }
                        }
                    }
                    a1 = a1 + 1;
                }
            }
            a0 = a0 + 1;
        }
        n = n + 1;
    }
    MK_A0 = ba0;
    MK_A1 = ba1;
    MK_AN = bn;
    MK_TOT = best;
    return best;
}

# ---------------------------------------------------------------- 各级存储

fn mk_path(k: i64, id: i64) -> i64 {
    store8(&MSPATH + 0, 0);
    strcat(&MSPATH, "/tmp/mock_mk_");
    strcat_i64(&MSPATH, k);
    strcat(&MSPATH, "_");
    strcat_i64(&MSPATH, id);
    strcat(&MSPATH, ".bin");
    return &MSPATH;
}

fn mk_slow_save(k: i64, id: i64) -> i64 {
    let fd: i64 = fopen(mk_path(k, id), 577, 420);
    if k == 1 { MK_IO1 = MK_IO1 + 1; } else { MK_IO2 = MK_IO2 + 1; }
    if fd < 0 { AD_CKERR = 5; return -1; }
    fwrite(fd, &AD_VAL, AD_N * 8);
    fclose(fd);
    return 0;
}

fn mk_slow_load(k: i64, id: i64) -> i64 {
    let fd: i64 = fopen(mk_path(k, id), 0, 0);
    if k == 1 { MK_IO1 = MK_IO1 + 1; } else { MK_IO2 = MK_IO2 + 1; }
    if fd < 0 { AD_CKERR = 5; return -1; }
    fread(fd, &AD_VAL, AD_N * 8);
    fclose(fd);
    return 0;
}

# ---------------------------------------------------------------- 执行

fn mk_run(l: i64) -> i64 {
    let n: i64 = MK_AN;
    let a0: i64 = MK_A0;
    let a1: i64 = MK_A1;
    let c: i64 = mk_slot(a0, n);
    let i: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let oldmax: i64 = 0;
    if AD_CKERR != 0 { return -1; }
    if c < 0 { AD_CKERR = 2; return -1; }
    if n < 1 { n = 1; }
    # 强制 RAM 槽预算：段内递归只能用槽 0..MK_C0-1。
    # 没有这条，「少留一个槽」的写法会悄悄用满 AD_CKMAX 而看起来更优。
    oldmax = AD_CKMAX;
    AD_CKMAX = MK_C0;
    # 段边界
    p = 0;
    i = 0;
    while i <= n {
        store64(&MK_BK + i * 8, p);
        if i < n { p = p + mk_seg(l, n, i); }
        i = i + 1;
    }
    # ---- 主前向穿越，途中顺手存段起点（重算不计预算）----
    # σ_0 是叶子值，前向中不被覆盖，当前 AD_VAL 就是合法的 σ_0
    ad_ckpt_save(0, 0);
    i = 1;
    while i < n {
        p = load64(&MK_BK + i * 8);
        ad_ckpt_restore(0);
        ad_replay_quiet(0, p);
        if i < a0 { ad_ckpt_save(i, p); }
        else { if i < a0 + a1 { mk_slow_save(1, i - a0); } else { mk_slow_save(2, i); } }
        i = i + 1;
    }
    # ---- 反向 ----
    # 槽 0..a0-1 是段起点；槽 a0 是临时槽（放外部加载的起点），
    # 于是 σ_0 的槽 0 永不覆盖 —— 不需要往慢级存副本
    AD_CKN = a0;
    i = n;
    while i >= 1 {
        p = load64(&MK_BK + (i - 1) * 8);
        q = load64(&MK_BK + i * 8);
        if i - 1 < a0 {
            ad_ckpt_restore(i - 1);
            AD_CKN = a0;
        } else {
            if i - 1 < a0 + a1 { mk_slow_load(1, i - 1 - a0); }
            else { mk_slow_load(2, i - 1); }
            ad_ckpt_save(a0, p);
            # 槽 a0 现在放着 σ_p，段内递归必须避开它
            AD_CKN = a0 + 1;
        }
        ad_rev_run(q, p, c);
        i = i - 1;
    }
    AD_CKMAX = oldmax;
    return 0;
}

# ---------------------------------------------------------------- 对外

fn ad_mk_cfg(c0: i64, s1: i64, w1: i64, w2: i64) -> i64 {
    MK_C0 = c0;
    MK_S1 = s1;
    MK_W1 = w1;
    MK_W2 = w2;
    return 0;
}

fn ad_backward_multik(loss: i64) -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    AD_CKERR = 0;
    AD_RC = 0;
    AD_RN = 0;
    AD_CKN = 1;
    MK_IO1 = 0;
    MK_IO2 = 0;
    while i < 512 { store64(&AD_CKOF + i * 8, 0); store64(&MK_BK + i * 8, 0); i = i + 1; }
    while i < 2048 { store64(&AD_CKMEM + i * 8, 0); store64(&AD_CKS + i * 8, 0); i = i + 1; }
    if AD_TN > 255 { AD_CKERR = 3; return -1; }
    if MK_C0 > AD_CKMAX { MK_C0 = AD_CKMAX; }
    t = mk_plan(AD_TN);
    if t < 0 { AD_CKERR = 3; return -1; }
    # DP 阶段反复调用 ad_rev_cost 会写满 memo；执行前清空，让执行期重算
    i = 0;
    while i < 2048 { store64(&AD_CKMEM + i * 8, 0); store64(&AD_CKS + i * 8, 0); i = i + 1; }
    ad_zero_grad();
    store64(&AD_GRAD + loss * 8, nn_from_i(1));
    mk_run(AD_TN);
    return 0;
}

fn ad_mk_time()  -> i64 { return MK_TOT; }
fn ad_mk_total() -> i64 { return AD_RC + MK_IO1 * MK_W1 + MK_IO2 * MK_W2; }
fn ad_mk_io1()   -> i64 { return MK_IO1; }
fn ad_mk_io2()   -> i64 { return MK_IO2; }
fn ad_mk_n()     -> i64 { return MK_AN; }
fn ad_mk_a0()    -> i64 { return MK_A0; }
fn ad_mk_a1()    -> i64 { return MK_A1; }
fn ad_mk_plan(l: i64) -> i64 { return mk_plan(l); }


# ================================================================
# 最优 Jacobian 累积（1.86）：顶点消去序
# ----------------------------------------------------------------
# 概念来源：
#   Griewank & Walther《Evaluating Derivatives》第 8 章；
#   Naumann, U. (2008) "Optimal Jacobian accumulation is NP-complete"
#     —— 与稀疏 Cholesky 的 fill-in 最小化等价，是 NP-hard。
#
#   两种极端策略：
#     前向 = 按拓扑序消去    代价 ∝ 输入维数 × 运算数
#     反向 = 按逆拓扑序消去  代价 ∝ 输出维数 × 运算数
#   混合序落在两者之间，**某些图上显著优于两端**。
#
#   实践现状：所有主流框架只实现了两个极端（forward / reverse）。
#   没有任何一个提供混合序 —— 求最优序是 NP-hard，已有实现只有
#   ADOL-C / ColPack 里的启发式实验代码。
#
# ----------------------------------------------------------------
# 模型：顶点消去（vertex elimination）
# ----------------------------------------------------------------
#   计算图 G：顶点 = 块，边 j→i 表示 i 依赖 j。
#   消去顶点 v：
#       P = pred(v)，S = succ(v)
#       代价 += |P|·|S|        （块级用大小加权：Σ|P大小| · Σ|S大小|）
#       连边：对每对 (p, s) ∈ P×S 加边 p→s；原本不存在的边 = fill-in
#       删除 v
#   总代价 = Σ 各步代价。fill-in 总数衡量 Jacobian 被稠密化的程度。
#
#   🔴 序决定模式：拓扑序 = 前向，逆拓扑序 = 反向，其余 = 混合。
# ================================================================

var OA_ADJ:  [16384] byte = 0;   # 128×128 邻接（OA_ADJ[i*128+j] = 1 ⇒ i 依赖 j）
var OA_ADJ0: [16384] byte = 0;   # 初始图副本（每次 oa_run 前恢复）
var OA_LIV0: [256]   byte = 0;   # 初始活跃集副本
var OA_VSZ:  [256]   i64 = 0;    # 顶点大小
var OA_LIVE: [256]   byte = 0;   # 未消去
var OA_PIN:  [256]   byte = 0;   # 输入（不消去）
var OA_POUT: [256]   byte = 0;   # 输出（不消去）
var OA_NV:   i64 = 0;
var OA_VMAX: i64 = 128;
var OA_COST: i64 = 0;
var OA_FILL: i64 = 0;
var OA_ERR:  i64 = 0;            # 1=顶点过多 2=图为空

fn oa_adj(i: i64, j: i64) -> i64 { return load8(&OA_ADJ + i * OA_VMAX + j); }

fn oa_clear() -> i64 {
    let i: i64 = 0;
    while i < OA_VMAX * OA_VMAX { store8(&OA_ADJ + i, 0); i = i + 1; }
    i = 0;
    while i < OA_VMAX {
        store64(&OA_VSZ + i * 8, 1);
        store8(&OA_LIVE + i, 0);
        store8(&OA_PIN + i, 0);
        store8(&OA_POUT + i, 0);
        i = i + 1;
    }
    OA_COST = 0;
    OA_FILL = 0;
    OA_ERR = 0;
    return 0;
}

# ---------------------------------------------------------------- 手工建图

fn oa_reset(nv: i64) -> i64 {
    let i: i64 = 0;
    oa_clear();
    if nv > OA_VMAX { OA_ERR = 1; return -1; }
    OA_NV = nv;
    if OA_NV <= 0 { OA_ERR = 2; return -1; }
    while i < nv { store8(&OA_LIVE + i, 1); i = i + 1; }
    return 0;
}

fn oa_edge(i: i64, j: i64) -> i64 {
    if i == j { return 0; }
    if load8(&OA_ADJ + i * OA_VMAX + j) != 0 { return 0; }
    store8(&OA_ADJ + i * OA_VMAX + j, 1);
    return 1;
}


fn oa_snapshot() -> i64 {
    let i: i64 = 0;
    while i < OA_VMAX * OA_VMAX {
        store8(&OA_ADJ0 + i, load8(&OA_ADJ + i));
        i = i + 1;
    }
    i = 0;
    while i < OA_VMAX {
        store8(&OA_LIV0 + i, load8(&OA_LIVE + i));
        i = i + 1;
    }
    return 0;
}

fn oa_vsz(i: i64, n: i64) -> i64 { store64(&OA_VSZ + i * 8, n); return 0; }
fn oa_in(i: i64)  -> i64 { store8(&OA_PIN + i, 1); return 0; }
fn oa_out(i: i64) -> i64 { store8(&OA_POUT + i, 1); return 0; }

# ---------------------------------------------------------------- 度数与大小

fn oa_predn(v: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if load8(&OA_ADJ + v * OA_VMAX + i) != 0 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn oa_succn(v: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if load8(&OA_ADJ + i * OA_VMAX + v) != 0 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn oa_predsz(v: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if load8(&OA_ADJ + v * OA_VMAX + i) != 0 { n = n + load64(&OA_VSZ + i * 8); }
        i = i + 1;
    }
    return n;
}

fn oa_succsz(v: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if load8(&OA_ADJ + i * OA_VMAX + v) != 0 { n = n + load64(&OA_VSZ + i * 8); }
        i = i + 1;
    }
    return n;
}

fn oa_step_cost(v: i64) -> i64 { return oa_predsz(v) * oa_succsz(v); }

# ---------------------------------------------------------------- 消去一步

fn oa_elim(v: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    OA_COST = OA_COST + oa_step_cost(v);
    while i < OA_NV {
        if load8(&OA_ADJ + i * OA_VMAX + v) != 0 {
            j = 0;
            while j < OA_NV {
                if load8(&OA_ADJ + v * OA_VMAX + j) != 0 {
                    if i != j {
                        if oa_edge(i, j) == 1 { OA_FILL = OA_FILL + 1; }
                    }
                }
                j = j + 1;
            }
        }
        i = i + 1;
    }
    # 删除 v
    i = 0;
    while i < OA_NV {
        store8(&OA_ADJ + v * OA_VMAX + i, 0);
        store8(&OA_ADJ + i * OA_VMAX + v, 0);
        i = i + 1;
    }
    store8(&OA_LIVE + v, 0);
    return 0;
}

fn oa_active(v: i64) -> i64 {
    if load8(&OA_LIVE + v) == 0 { return 0; }
    if load8(&OA_PIN + v) == 1 { return 0; }
    if load8(&OA_POUT + v) == 1 { return 0; }
    return 1;
}

fn oa_nactive() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if oa_active(i) == 1 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

# ---------------------------------------------------------------- 三种序

# mode 0 = 拓扑序（前向）  1 = 逆拓扑序（反向）  2 = 贪心最小代价
#      3 = 最小填充        4 = 最小度
fn oa_run(mode: i64) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let bv: i64 = 0;
    let bc: i64 = 0;
    let bf: i64 = 0;
    let bd: i64 = 0;
    let c: i64 = 0;
    let f: i64 = 0;
    let d: i64 = 0;
    let first: i64 = 1;
    let guard: i64 = 0;
    # 从初始图重新开始：否则第二次调用时顶点已被上一次消完，代价恒为 0
    oa_restore();
    OA_COST = 0;
    OA_FILL = 0;
    while oa_nactive() > 0 {
        bv = 0 - 1;
        bc = 0;
        bf = 0;
        bd = 0;
        first = 1;
        if mode == 0 {
            # 拓扑序 = 前向：取编号最小（编号按创建顺序）
            i = 0;
            while i < OA_NV {
                if oa_active(i) == 1 { bv = i; i = OA_NV; } else { i = i + 1; }
            }
        } else {
            if mode == 1 {
                # 逆拓扑序 = 反向
                i = OA_NV - 1;
                while i >= 0 {
                    if oa_active(i) == 1 { bv = i; i = 0 - 1; } else { i = i - 1; }
                }
            } else {
                i = 0;
                while i < OA_NV {
                    if oa_active(i) == 1 {
                        c = oa_step_cost(i);
                        f = oa_fill_of(i);
                        d = oa_predn(i) + oa_succn(i);
                        if first == 1 {
                            bv = i; bc = c; bf = f; bd = d; first = 0;
                        } else {
                            if mode == 2 {
                                # 最小代价（Markowitz 型），平局取填充少
                                if c < bc { bv = i; bc = c; bf = f; bd = d; }
                                else { if c == bc { if f < bf { bv = i; bf = f; bd = d; } } }
                            } else {
                                if mode == 3 {
                                    # 最小填充，平局取代价小
                                    if f < bf { bv = i; bf = f; bc = c; bd = d; }
                                    else { if f == bf { if c < bc { bv = i; bc = c; bd = d; } } }
                                } else {
                                    # 最小度，平局取填充少
                                    if d < bd { bv = i; bd = d; bc = c; bf = f; }
                                    else { if d == bd { if f < bf { bv = i; bf = f; bc = c; } } }
                                }
                            }
                        }
                    }
                    i = i + 1;
                }
            }
        }
        if bv < 0 { return OA_COST; }
        oa_elim(bv);
        guard = guard + 1;
        if guard > OA_NV + 4 { return OA_COST; }
    }
    return OA_COST;
}

# 消去 v 会新增多少条边
fn oa_fill_of(v: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if load8(&OA_ADJ + i * OA_VMAX + v) != 0 {
            j = 0;
            while j < OA_NV {
                if load8(&OA_ADJ + v * OA_VMAX + j) != 0 {
                    if i != j {
                        if load8(&OA_ADJ + i * OA_VMAX + j) == 0 { n = n + 1; }
                    }
                }
                j = j + 1;
            }
        }
        i = i + 1;
    }
    return n;
}

# ---------------------------------------------------------------- 从 tape 建图

fn oa_build() -> i64 {
    let t: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let o: i64 = 0;
    let ia: i64 = 0;
    let ib: i64 = 0;
    let io: i64 = 0;
    let i: i64 = 0;
    oa_clear();
    if AD_BN > OA_VMAX { OA_ERR = 1; return -1; }
    if AD_BN <= 0 { OA_ERR = 2; return -1; }
    OA_NV = AD_BN;
    while i < OA_NV {
        store8(&OA_LIVE + i, 1);
        store64(&OA_VSZ + i * 8, load64(&AD_BSZ + i * 8));
        store8(&OA_PIN + i, 1);
        store8(&OA_POUT + i, 0);
        i = i + 1;
    }
    while t < AD_TN {
        a = load64(&AD_TA + t * 8);
        b = load64(&AD_TB + t * 8);
        o = load64(&AD_TO + t * 8);
        ia = load64(&AD_BID + a * 8);
        io = load64(&AD_BID + o * 8);
        if ia >= 0 { if ia < OA_NV { oa_edge(io, ia); } }
        if load64(&AD_TFB + t * 8) == 1 {
            ib = load64(&AD_BID + b * 8);
            if ib >= 0 { if ib < OA_NV { oa_edge(io, ib); } }
        }
        # o 有前驱 ⇒ 不是输入；o 是所有后续条目的输出候选
        if io >= 0 { if io < OA_NV { store8(&OA_PIN + io, 0); } }
        t = t + 1;
    }
    # 输出 = 最后一条 tape 条目的输出块
    o = load64(&AD_TO + (AD_TN - 1) * 8);
    io = load64(&AD_BID + o * 8);
    if io >= 0 { if io < OA_NV { store8(&OA_POUT + io, 1); } }
    oa_snapshot();
    return OA_NV;
}

fn oa_restore() -> i64 {
    let i: i64 = 0;
    while i < OA_VMAX * OA_VMAX {
        store8(&OA_ADJ + i, load8(&OA_ADJ0 + i));
        i = i + 1;
    }
    i = 0;
    while i < OA_VMAX {
        store8(&OA_LIVE + i, load8(&OA_LIV0 + i));
        i = i + 1;
    }
    OA_COST = 0;
    OA_FILL = 0;
    return 0;
}

# ---------------------------------------------------------------- 穷举最优
# 可消去顶点 ≤ 7 时枚举全部排列。这是 NP-hard 问题的精确解，
# 用来检验启发式离最优有多远。

var OA_ORD:   [16]  i64 = 0;
var OA_ON:    i64 = 0;
var OA_BESTC: i64 = 0;
var OA_BESTF: i64 = 0;
var OA_NPERM: i64 = 0;

fn oa_collect() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while i < OA_NV {
        if oa_active(i) == 1 { store64(&OA_ORD + n * 8, i); n = n + 1; }
        i = i + 1;
    }
    OA_ON = n;
    return n;
}

# 字典序下一个排列；返回 0 表示已是最后一个
fn oa_perm_next() -> i64 {
    let n: i64 = OA_ON;
    let i: i64 = 0;
    let j: i64 = 0;
    let t: i64 = 0;
    let p: i64 = 0 - 1;
    let q: i64 = 0;
    i = n - 2;
    while i >= 0 {
        if load64(&OA_ORD + i * 8) < load64(&OA_ORD + (i + 1) * 8) { p = i; i = 0 - 1; }
        else { i = i - 1; }
    }
    if p < 0 { return 0; }
    q = n - 1;
    j = n - 1;
    while j > p {
        if load64(&OA_ORD + j * 8) > load64(&OA_ORD + p * 8) { q = j; j = p; }
        else { j = j - 1; }
    }
    t = load64(&OA_ORD + p * 8);
    store64(&OA_ORD + p * 8, load64(&OA_ORD + q * 8));
    store64(&OA_ORD + q * 8, t);
    i = p + 1;
    j = n - 1;
    while i < j {
        t = load64(&OA_ORD + i * 8);
        store64(&OA_ORD + i * 8, load64(&OA_ORD + j * 8));
        store64(&OA_ORD + j * 8, t);
        i = i + 1;
        j = j - 1;
    }
    return 1;
}

fn oa_exhaustive() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let best: i64 = 0 - 1;
    let bestf: i64 = 0;
    let more: i64 = 1;
    let cnt: i64 = 0;
    oa_restore();
    n = oa_collect();
    if n > 7 { OA_ERR = 3; return 0 - 1; }
    if n <= 0 { OA_ERR = 2; return 0 - 1; }
    while more == 1 {
        oa_restore();
        i = 0;
        while i < n { oa_elim(load64(&OA_ORD + i * 8)); i = i + 1; }
        cnt = cnt + 1;
        if best < 0 { best = OA_COST; bestf = OA_FILL; }
        else { if OA_COST < best { best = OA_COST; bestf = OA_FILL; } }
        if oa_perm_next() == 0 { more = 0; }
    }
    OA_BESTC = best;
    OA_BESTF = bestf;
    OA_NPERM = cnt;
    return best;
}

fn oa_bestc()  -> i64 { return OA_BESTC; }
fn oa_bestf()  -> i64 { return OA_BESTF; }
fn oa_nperm()  -> i64 { return OA_NPERM; }
fn oa_nact()   -> i64 { return OA_ON; }

fn oa_nv()    -> i64 { return OA_NV; }
fn oa_cost()  -> i64 { return OA_COST; }
fn oa_fill()  -> i64 { return OA_FILL; }
fn oa_err()   -> i64 { return OA_ERR; }
fn oa_nblk()  -> i64 { return AD_BN; }
