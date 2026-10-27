# ==========================================================================
#  nnad —— 用**自动微分**驱动 nn.mo 的网络
#
#  nn.mo 是手写反向传播。它踩过一个很阴的坑：
#
#    反向时"算完 delta[l] 就顺手更新 W[l]"—— 而下一轮算 delta[l-1]
#    还要用 W[l]，那时它已经被改过了。
#    XOR 照样收敛到 4/4，毫无异常，是 Python 定点参考实现逐轮比对
#    才揪出来的。
#
#  本库把训练路径换成 autodiff：**梯度由语言求**，上面那类 bug
#  从根上不可能发生 —— 因为根本没有人手写反向。
#
#  为什么独立成库而不是改 nn.mo：autodiff.mo 依赖 nn.mo（用它的
#  nn_fmul / nn_sigmoid / nn_tanh），反过来 import 会成环。
#
#  API 与 nn_train 一致：前向 → 算 loss，做完这一步权重已更新。
# ==========================================================================
import "nn.mo";
import "autodiff.mo";

# 每层权重块的起始槽（容量 8 层）
var NNAD_W: [8] i64 = 0;
var NNAD_B: [8] i64 = 0;

# 把 net 的权重值复制进 autodiff 的权重块
fn nnad_load(net: i64, m: i64, wblk: i64, bblk: i64) -> i64 {
    let nc: i64 = nn_size(net, m);
    let np: i64 = nn_size(net, m - 1);
    let j: i64 = 0;
    while j < nc {
        let k: i64 = 0;
        while k < np {
            ad_set(wblk + j * np + k, load64(nn_wref(net, m, j, k)));
            k = k + 1;
        }
        ad_set(bblk + j, load64(nn_bref(net, m, j)));
        j = j + 1;
    }
    return 0;
}

# 把 autodiff 的权重值写回 net
fn nnad_save(net: i64, m: i64, wblk: i64, bblk: i64) -> i64 {
    let nc: i64 = nn_size(net, m);
    let np: i64 = nn_size(net, m - 1);
    let j: i64 = 0;
    while j < nc {
        let k: i64 = 0;
        while k < np {
            store64(nn_wref(net, m, j, k), ad_val(wblk + j * np + k));
            k = k + 1;
        }
        store64(nn_bref(net, m, j), ad_val(bblk + j));
        j = j + 1;
    }
    return 0;
}

# 一步训练：**梯度由 autodiff 求**，不手写反向
#
# 返回 loss（与 nn_train 语义一致）
fn nnad_train(net: i64, x: i64, y: i64, lr: i64) -> i64 {
    let nl: i64 = nn_nl(net);
    let L: i64 = nl - 1;

    ad_reset();

    # ---- 建图（只写前向） ----
    let n0: i64 = nn_size(net, 0);
    let a0: i64 = ad_block(n0);
    let i: i64 = 0;
    while i < n0 {
        ad_set(a0 + i, load64(x + i * 8));
        i = i + 1;
    }

    let cur: i64 = a0;
    let m: i64 = 1;
    while m <= L {
        let nc: i64 = nn_size(net, m);
        let np: i64 = nn_size(net, m - 1);
        let wb: i64 = ad_wblock(nc * np);
        let bb: i64 = ad_wblock(nc);
        store64(&NNAD_W + m * 8, wb);
        store64(&NNAD_B + m * 8, bb);
        nnad_load(net, m, wb, bb);

        let z: i64 = ad_matmul(wb, cur, nc, np);
        let s: i64 = ad_vadd(z, bb, nc);
        let act: i64 = load64(load64(net + 56) + m * 8);
        # 1=relu 2=sigmoid 3=tanh
        if act == 1 { cur = ad_vrelu(s, nc); }
        if act == 2 { cur = ad_vsig(s, nc); }
        if act == 3 { cur = ad_vtanh(s, nc); }
        m = m + 1;
    }

    # ---- loss ----
    let nl_out: i64 = nn_size(net, L);
    let tgt: i64 = ad_block(nl_out);
    i = 0;
    while i < nl_out {
        ad_set(tgt + i, load64(y + i * 8));
        i = i + 1;
    }
    # 用 ½·MSE：与 nn.mo 手写反向的梯度约定一致，
    # 这样两条路径才能逐轮比对（用真·MSE 会因系数 2 发散）
    let loss: i64 = ad_mse_half(cur, tgt, nl_out);

    # ---- 梯度：语言求 ----
    ad_backward(loss);

    # ---- 更新 ----
    m = 1;
    while m <= L {
        let nc2: i64 = nn_size(net, m);
        let np2: i64 = nn_size(net, m - 1);
        let wb2: i64 = load64(&NNAD_W + m * 8);
        let bb2: i64 = load64(&NNAD_B + m * 8);
        let j: i64 = 0;
        while j < nc2 * np2 {
            let p: i64 = wb2 + j;
            store64(&AD_VAL + p * 8, ad_val(p) - nn_fmul(lr, ad_grad(p)));
            j = j + 1;
        }
        j = 0;
        while j < nc2 {
            let q: i64 = bb2 + j;
            store64(&AD_VAL + q * 8, ad_val(q) - nn_fmul(lr, ad_grad(q)));
            j = j + 1;
        }
        nnad_save(net, m, wb2, bb2);
        m = m + 1;
    }

    return ad_val(loss);
}

# 只做推理（不训练）：复用同一套建图
fn nnad_forward(net: i64, x: i64) -> i64 {
    let n0: i64 = nn_size(net, 0);
    let i: i64 = 0;
    while i < n0 {
        store64(nn_aref(net, 0, i), load64(x + i * 8));
        i = i + 1;
    }
    let m: i64 = 1;
    while m < nn_nl(net) {
        let nc: i64 = nn_size(net, m);
        let np: i64 = nn_size(net, m - 1);
        let j: i64 = 0;
        while j < nc {
            let acc: i64 = 0;
            let k: i64 = 0;
            while k < np {
                let wv: i64 = load64(nn_wref(net, m, j, k));
                let av: i64 = load64(nn_aref(net, m - 1, k));
                acc = acc + nn_fmul(wv, av);
                k = k + 1;
            }
            let bv: i64 = load64(nn_bref(net, m, j));
            let z: i64 = acc + bv;
            store64(nn_zref(net, m, j), z);
            let act: i64 = load64(load64(net + 56) + m * 8);
            store64(nn_aref(net, m, j), nn_act(act, z));
            j = j + 1;
        }
        m = m + 1;
    }
    return 0;
}
