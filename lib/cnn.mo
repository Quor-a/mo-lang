# cnn —— 卷积神经网络（用墨语言自己写的，Q16.16 定点）
#
# ## 和 nn.mo 的关系
#
# 本库只做 **conv / maxpool**，全连接部分交给 nn.mo。两者靠
# `nn_input_grad()` 缝合：它把全连接第一层的 delta 折算成"展平向量的梯度"，
# CNN 拿它当输出的 delta 往回走。
#
#     img → conv → pool → conv → pool → flatten → [nn.mo 的全连接网] → y
#                                                        ↓
#                        ← 反传 ←    nn_input_grad  ←   delta[1]
#
# ## 层参数块（每层 96 字节）
#
#   conv: +0 type(0)  +8 kh  +16 kw  +24 Cin  +32 Cout
#         +40 H  +48 W  +56 OH  +64 OW  +72 wptr  +80 bptr  +88 zptr
#   pool: +0 type(1)  +8 C  +16 H  +24 W  +32 OH  +40 OW  +48 maskptr
#
# ## 张量下标
#
#   conv 输入 : c*H*W + y*W + x
#   卷积核    : ((k*Cin + c)*kh + ky)*kw + kx
#   conv 输出 : k*OH*OW + oy*OW + ox
#
# 全部 valid 卷积（不补零）： OH = H - kh + 1
#
# ## 激活与梯度顺序
#
# 每个 conv 层后面接 **ReLU**。纯线性卷积堆叠起来仍是线性的，不加非线性
# CNN 就没有意义 —— 这点比"提升精度"重要得多。
#
# 反向时两件事的顺序是**有讲究**的：
#
#     cnn_conv_dx  （用**更新前**的 W 把梯度传回输入）
#     cnn_conv_dw  （然后才更新 W）
#
# 反过来的话 dx 会用到新权重，梯度就错了。这和 nn.mo 里踩过的坑同源。
import "mem.mo";
import "nn.mo";

# ---------------------------------------------------------------- 句柄

fn cnn_nl(net: i64) -> i64 { return load64(net); }
fn cnn_par(net: i64, l: i64) -> i64 { return load64(load64(net + 8) + l * 8); }
fn cnn_act(net: i64, l: i64) -> i64 { return load64(load64(net + 16) + l * 8); }
fn cnn_cch(net: i64, l: i64) -> i64 { return load64(load64(net + 24) + l * 8); }
fn cnn_dlt(net: i64, l: i64) -> i64 { return load64(load64(net + 48) + l * 8); }
fn cnn_flat(net: i64) -> i64 { return load64(net + 32); }
fn cnn_flat_n(net: i64) -> i64 { return load64(net + 40); }

fn cnn_ensure_heap() -> i64 {
    if heap_ready() == 0 { heap_init(); }
    return 0;
}

fn cnn_new(nl: i64) -> i64 {
    cnn_ensure_heap();
    let h: i64 = alloc(56);
    store64(h, nl);
    store64(h + 8,  alloc8(nl * 8));
    store64(h + 16, alloc8(nl * 8));
    store64(h + 24, alloc8(nl * 8));
    store64(h + 32, alloc8(4096));
    store64(h + 40, 0);
    store64(h + 48, alloc8(nl * 8));
    return h;
}

# conv 层：kh×kw 核，Cin→Cout，输入尺寸 H×W
# 卷积核固定 3×3。
#
# 为什么不是通用的 (kh, kw, ...)：那需要 8 个参数，而墨语言当前
# **超过 6 个参数的函数，只要函数体内调用别的函数，第 7 个起的参数就会错**
# （实测返回 9 而正确答案是 17）。这是栈顶缓存 spill 时机的 bug，
# 见 docs/log_2026_10_09.md。
#
# 参数列表也**不能换行** —— 跨行的参数列表会让编译器死循环。
# 这两个限制叠加，就是这行签名长这样的原因。
# 参数列表**不能换行** —— 跨行会让编译器死循环（已修，但此注释保留）。
fn cnn_set_conv(net: i64, l: i64, kh: i64, kw: i64, cin: i64, cout: i64, h: i64, w: i64) -> i64 {
    let p: i64 = alloc(96);
    store64(p, 0);
    store64(p + 8, kh);
    store64(p + 16, kw);
    store64(p + 24, cin);
    store64(p + 32, cout);
    store64(p + 40, h);
    store64(p + 48, w);
    store64(p + 56, h - kh + 1);
    store64(p + 64, w - kw + 1);
    store64(p + 72, alloc8(cout * cin * kh * kw));
    store64(p + 80, alloc8(cout));
    store64(p + 88, alloc8(cout * (h - kh + 1) * (w - kw + 1)));
    store64(load64(net + 8) + l * 8, p);
    return 0;
}

fn cnn_set_pool(net: i64, l: i64, c: i64, h: i64, w: i64) -> i64 {
    let p: i64 = alloc(96);
    store64(p, 1);
    store64(p + 8, c);
    store64(p + 16, h);
    store64(p + 24, w);
    store64(p + 32, h / 2);
    store64(p + 40, w / 2);
    store64(p + 48, alloc8(c * (h / 2) * (w / 2)));
    store64(load64(net + 8) + l * 8, p);
    return 0;
}

# 为每层分配输出 / 输入缓存 / delta
fn cnn_alloc_bufs(net: i64) -> i64 {
    let nl: i64 = cnn_nl(net);
    let total: i64 = 0;
    let l: i64 = 0;
    while l < nl {
        let p: i64 = cnn_par(net, l);
        let ty: i64 = load64(p);
        let n: i64 = 0;
        let nin: i64 = 0;
        if ty == 0 {
            n = load64(p + 32) * load64(p + 56) * load64(p + 64);
            nin = load64(p + 24) * load64(p + 40) * load64(p + 48);
        } else {
            n = load64(p + 8) * load64(p + 32) * load64(p + 40);
            nin = load64(p + 8) * load64(p + 16) * load64(p + 24);
        }
        store64(load64(net + 16) + l * 8, alloc8(n));
        store64(load64(net + 24) + l * 8, alloc8(nin));
        store64(load64(net + 48) + l * 8, alloc8(n));
        if l == nl - 1 { total = n; }
        l = l + 1;
    }
    store64(net + 40, total);
    return 0;
}

# ---------------------------------------------------------------- 初始化

fn cnn_rand_init(net: i64) -> i64 {
    let nl: i64 = cnn_nl(net);
    let l: i64 = 0;
    while l < nl {
        let p: i64 = cnn_par(net, l);
        if load64(p) == 0 {
            let cin: i64 = load64(p + 24);
            let kh: i64 = load64(p + 8);
            let kw: i64 = load64(p + 16);
            let cout: i64 = load64(p + 32);
            # fan_in = cin*kh*kw，Xavier： U(-1/√fan_in, 1/√fan_in)
            let r: i64 = nn_fdiv(65536, nn_fsqrt(nn_from_i(cin * kh * kw)));
            let wp: i64 = load64(p + 72);
            let bp: i64 = load64(p + 80);
            let k: i64 = 0;
            while k < cout {
                store64(bp + k * 8, 0);
                let i: i64 = 0;
                while i < cin * kh * kw {
                    store64(wp + (k * cin * kh * kw + i) * 8, nn_rand_fp(r));
                    i = i + 1;
                }
                k = k + 1;
            }
        }
        l = l + 1;
    }
    return 0;
}

fn cnn_get_w(net: i64, l: i64, i: i64) -> i64 {
    return load64(load64(cnn_par(net, l) + 72) + i * 8);
}

fn cnn_set_w(net: i64, l: i64, i: i64, v: i64) -> i64 {
    store64(load64(cnn_par(net, l) + 72) + i * 8, v);
    return 0;
}

# ---------------------------------------------------------------- 前向

fn cnn_forward(net: i64, img: i64) -> i64 {
    let nl: i64 = cnn_nl(net);
    let l: i64 = 0;
    while l < nl {
        let p: i64 = cnn_par(net, l);
        let ty: i64 = load64(p);
        # 本层输入：第 0 层是图像，其余是上一层输出
        let inp: i64 = img;
        if l > 0 { inp = cnn_act(net, l - 1); }
        # 存一份输入，反向算 dW 要用（权重更新时输入不能被改）
        let cch: i64 = cnn_cch(net, l);
        let nin: i64 = 0;
        if ty == 0 {
            nin = load64(p + 24) * load64(p + 40) * load64(p + 48);
        } else {
            nin = load64(p + 8) * load64(p + 16) * load64(p + 24);
        }
        let t: i64 = 0;
        while t < nin {
            store64(cch + t * 8, load64(inp + t * 8));
            t = t + 1;
        }

        if ty == 0 { cnn_conv_fwd(p, cch, cnn_act(net, l)); }
        else { cnn_pool_fwd(p, cch, cnn_act(net, l)); }
        l = l + 1;
    }
    # 展平最后一层输出，交给全连接网
    let out: i64 = cnn_act(net, nl - 1);
    let n: i64 = cnn_flat_n(net);
    let f: i64 = cnn_flat(net);
    let i: i64 = 0;
    while i < n {
        store64(f + i * 8, load64(out + i * 8));
        i = i + 1;
    }
    return f;
}

fn cnn_conv_fwd(p: i64, inp: i64, out: i64) -> i64 {
    let kh: i64 = load64(p + 8);
    let kw: i64 = load64(p + 16);
    let cin: i64 = load64(p + 24);
    let cout: i64 = load64(p + 32);
    let H: i64 = load64(p + 40);
    let W: i64 = load64(p + 48);
    let OH: i64 = load64(p + 56);
    let OW: i64 = load64(p + 64);
    let wp: i64 = load64(p + 72);
    let bp: i64 = load64(p + 80);
    let hw: i64 = H * W;

    let k: i64 = 0;
    while k < cout {
        let b: i64 = load64(bp + k * 8);
        let oy: i64 = 0;
        while oy < OH {
            let ox: i64 = 0;
            while ox < OW {
                let s: i64 = b;
                let c: i64 = 0;
                while c < cin {
                    let ky: i64 = 0;
                    while ky < kh {
                        let kx: i64 = 0;
                        while kx < kw {
                            let a: i64 = load64(inp + (c * hw + (oy + ky) * W + ox + kx) * 8);
                            let w: i64 = load64(wp + (((k * cin + c) * kh + ky) * kw + kx) * 8);
                            s = s + nn_fmul(w, a);
                            kx = kx + 1;
                        }
                        ky = ky + 1;
                    }
                    c = c + 1;
                }
                let oi: i64 = k * OH * OW + oy * OW + ox;
                store64(load64(p + 88) + oi * 8, s);   # pre-activation，反向要用
                if s > 0 { store64(out + oi * 8, s); } else { store64(out + oi * 8, 0); }
                ox = ox + 1;
            }
            oy = oy + 1;
        }
        k = k + 1;
    }
    return 0;
}

# 2×2 最大池化：mask 记下赢家的**线性下标**，反向只把梯度还给赢家
fn cnn_pool_fwd(p: i64, inp: i64, out: i64) -> i64 {
    let C: i64 = load64(p + 8);
    let H: i64 = load64(p + 16);
    let W: i64 = load64(p + 24);
    let OH: i64 = load64(p + 32);
    let OW: i64 = load64(p + 40);
    let mp: i64 = load64(p + 48);
    let hw: i64 = H * W;

    let c: i64 = 0;
    while c < C {
        let oy: i64 = 0;
        while oy < OH {
            let ox: i64 = 0;
            while ox < OW {
                let bv: i64 = load64(inp + (c * hw + (oy * 2) * W + ox * 2) * 8);
                let bi: i64 = c * hw + (oy * 2) * W + ox * 2;
                let dy: i64 = 0;
                while dy < 2 {
                    let dx: i64 = 0;
                    while dx < 2 {
                        let idx: i64 = c * hw + (oy * 2 + dy) * W + ox * 2 + dx;
                        let v: i64 = load64(inp + idx * 8);
                        if v > bv { bv = v; bi = idx; }
                        dx = dx + 1;
                    }
                    dy = dy + 1;
                }
                let oi: i64 = c * OH * OW + oy * OW + ox;
                store64(out + oi * 8, bv);
                store64(mp + oi * 8, bi);
                ox = ox + 1;
            }
            oy = oy + 1;
        }
        c = c + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 反向

# dflat 是"展平向量的梯度"（由 nn_input_grad 给出），长度 = 最后一层元素数
fn cnn_backward(net: i64, dflat: i64, lr: i64) -> i64 {
    let nl: i64 = cnn_nl(net);

    # 最后一层的 delta 就是 dflat（展平顺序与输出一致）
    let dl: i64 = cnn_dlt(net, nl - 1);
    let n: i64 = cnn_flat_n(net);
    let i: i64 = 0;
    while i < n {
        store64(dl + i * 8, load64(dflat + i * 8));
        i = i + 1;
    }

    # 从最后一层往回：算本层参数梯度 + 把 delta 传给前一层。
    #
    # 注意这里**先算 dInp 再更新权重**是安全的：本层的 dW 只依赖
    # 本层的输入缓存与 delta，与权重的更新顺序无关。
    # （真正的顺序陷阱在 nn.mo 的全连接部分，那里已单独处理。）
    let l: i64 = nl - 1;
    while l >= 0 {
        let p: i64 = cnn_par(net, l);
        let ty: i64 = load64(p);
        let dl_cur: i64 = cnn_dlt(net, l);
        if ty == 0 {
            # 顺序不能反：dx 必须用**更新前**的 W
            if l > 0 { cnn_conv_dx(p, dl_cur, cnn_dlt(net, l - 1)); }
            cnn_conv_dw(p, cnn_cch(net, l), dl_cur, lr);
        } else {
            if l > 0 { cnn_pool_bwd(p, dl_cur, cnn_dlt(net, l - 1)); }
        }
        l = l - 1;
    }
    return 0;
}

# ReLU 掩码：z > 0 才让梯度通过
fn cnn_relu_mask(p: i64, oi: i64, d: i64) -> i64 {
    if load64(load64(p + 88) + oi * 8) > 0 { return d; }
    return 0;
}

fn cnn_conv_dw(p: i64, inp: i64, dout: i64, lr: i64) -> i64 {
    let kh: i64 = load64(p + 8);
    let kw: i64 = load64(p + 16);
    let cin: i64 = load64(p + 24);
    let cout: i64 = load64(p + 32);
    let H: i64 = load64(p + 40);
    let W: i64 = load64(p + 48);
    let OH: i64 = load64(p + 56);
    let OW: i64 = load64(p + 64);
    let wp: i64 = load64(p + 72);
    let bp: i64 = load64(p + 80);
    let hw: i64 = H * W;

    let k: i64 = 0;
    while k < cout {
        let bs: i64 = 0;
        let oy: i64 = 0;
        while oy < OH {
            let ox: i64 = 0;
            while ox < OW {
                let oi: i64 = k * OH * OW + oy * OW + ox;
                let d: i64 = cnn_relu_mask(p, oi, load64(dout + oi * 8));
                bs = bs + d;
                let c: i64 = 0;
                while c < cin {
                    let ky: i64 = 0;
                    while ky < kh {
                        let kx: i64 = 0;
                        while kx < kw {
                            let a: i64 = load64(inp + (c * hw + (oy + ky) * W + ox + kx) * 8);
                            let wi: i64 = ((k * cin + c) * kh + ky) * kw + kx;
                            let g: i64 = nn_fmul(lr, nn_fmul(d, a));
                            store64(wp + wi * 8, load64(wp + wi * 8) - g);
                            kx = kx + 1;
                        }
                        ky = ky + 1;
                    }
                    c = c + 1;
                }
                ox = ox + 1;
            }
            oy = oy + 1;
        }
        let bv: i64 = load64(bp + k * 8);
        store64(bp + k * 8, bv - nn_fmul(lr, bs));
        k = k + 1;
    }
    return 0;
}

# 把输出的 delta 反卷积回输入形状：
#   dInp[c][y][x] += Σ_{k,ky,kx} dOut[k][y-ky][x-kx] * W[k][c][ky][kx]
#
# 注意是 **+=**：一个输入像素会影响多个输出，梯度要累加。
# 这也是为什么调用方必须先把 dInp 清零。
fn cnn_conv_dx(p: i64, dout: i64, din: i64) -> i64 {
    let kh: i64 = load64(p + 8);
    let kw: i64 = load64(p + 16);
    let cin: i64 = load64(p + 24);
    let cout: i64 = load64(p + 32);
    let H: i64 = load64(p + 40);
    let W: i64 = load64(p + 48);
    let OH: i64 = load64(p + 56);
    let OW: i64 = load64(p + 64);
    let wp: i64 = load64(p + 72);
    let hw: i64 = H * W;

    # 先清零 —— 不清零会把上一批的梯度叠加上去
    let t: i64 = 0;
    while t < cin * hw {
        store64(din + t * 8, 0);
        t = t + 1;
    }

    let c: i64 = 0;
    while c < cin {
        let y: i64 = 0;
        while y < H {
            let x: i64 = 0;
            while x < W {
                let s: i64 = 0;
                let k: i64 = 0;
                while k < cout {
                    let ky: i64 = 0;
                    while ky < kh {
                        let oy: i64 = y - ky;
                        if oy >= 0 {
                            if oy < OH {
                                let kx: i64 = 0;
                                while kx < kw {
                                    let ox: i64 = x - kx;
                                    if ox >= 0 {
                                        if ox < OW {
                                            let oi2: i64 = k * OH * OW + oy * OW + ox;
                                            let d: i64 = cnn_relu_mask(p, oi2, load64(dout + oi2 * 8));
                                            let w: i64 = load64(wp + (((k * cin + c) * kh + ky) * kw + kx) * 8);
                                            s = s + nn_fmul(w, d);
                                        }
                                    }
                                    kx = kx + 1;
                                }
                            }
                        }
                        ky = ky + 1;
                    }
                    k = k + 1;
                }
                store64(din + (c * hw + y * W + x) * 8, s);
                x = x + 1;
            }
            y = y + 1;
        }
        c = c + 1;
    }
    return 0;
}

# 最大池化没有参数，只把梯度还给赢家位置
fn cnn_pool_bwd(p: i64, dout: i64, din: i64) -> i64 {
    let C: i64 = load64(p + 8);
    let H: i64 = load64(p + 16);
    let W: i64 = load64(p + 24);
    let OH: i64 = load64(p + 32);
    let OW: i64 = load64(p + 40);
    let mp: i64 = load64(p + 48);
    let nin: i64 = C * H * W;

    let t: i64 = 0;
    while t < nin {
        store64(din + t * 8, 0);
        t = t + 1;
    }
    let i: i64 = 0;
    let n: i64 = C * OH * OW;
    while i < n {
        store64(din + load64(mp + i * 8) * 8, load64(dout + i * 8));
        i = i + 1;
    }
    return 0;
}
