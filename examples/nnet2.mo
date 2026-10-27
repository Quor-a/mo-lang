# nnet2 —— 用**语言级自动微分**训练多层网络（2-4-1 解 XOR）
#
# 与 examples/nnet.mo 的区别：
#   nnet.mo  手写反向传播（nn.mo）
#   nnet2.mo **只写前向**，梯度由墨语言自己求
#
# 下面是这个网络的全部代码 —— 没有一行反向传播：
#
#     h = relu(W1·x + b1)
#     y = sigmoid(W2·h + b2)
#     L = mse(y, t)
#
# 然后 ad_backward(L) 就有了全部梯度，ad_step(lr) 就完成了更新。
import "autodiff.mo";

var NH: i64 = 4;
var NIN: i64 = 2;

# 权重值存在全局数组里：数值梯度检查要"扰动后重建前向"，
# 而墨语言无闭包/函数指针，重建只能靠全局状态。
var PW1: [8] i64 = 0;
var PB1: [4] i64 = 0;
var PW2: [4] i64 = 0;
var PB2: [1] i64 = 0;

var XS: [8] i64 = 0;
var TS: [4] i64 = 0;

# build() 建出来的槽索引（供训练后把权重值拷回全局）
var SW1: i64 = 0;
var SB1: i64 = 0;
var SW2: i64 = 0;
var SB2: i64 = 0;
var SOUT: i64 = 0;
var LASTL: i64 = 0;

fn init_data() -> i64 {
    # XOR 四组样本，定点 1.0 = 65536
    store64(&XS + 0, 0);       store64(&XS + 8, 0);        store64(&TS + 0, 0);
    store64(&XS + 16, 0);      store64(&XS + 24, 65536);   store64(&TS + 8, 65536);
    store64(&XS + 32, 65536);  store64(&XS + 40, 0);       store64(&TS + 16, 65536);
    store64(&XS + 48, 65536);  store64(&XS + 56, 65536);   store64(&TS + 24, 0);
    return 0;
}

fn init_w() -> i64 {
    let i: i64 = 0;
    while i < 8 {
        store64(&PW1 + i * 8, nn_rand_fp(65536));
        i = i + 1;
    }
    i = 0;
    while i < 4 {
        store64(&PB1 + i * 8, 0);
        store64(&PW2 + i * 8, nn_rand_fp(65536));
        i = i + 1;
    }
    store64(&PB2 + 0, 0);
    return 0;
}

# **只写前向** —— 这是这个网络的定义，没有反向
fn build(x0: i64, x1: i64, t0: i64) -> i64 {
    ad_reset();
    let x: i64 = ad_block(2);
    ad_set(x + 0, x0);
    ad_set(x + 1, x1);

    SW1 = ad_wblock(8);
    let i: i64 = 0;
    while i < 8 {
        ad_set(SW1 + i, load64(&PW1 + i * 8));
        i = i + 1;
    }
    SB1 = ad_wblock(4);
    i = 0;
    while i < 4 {
        ad_set(SB1 + i, load64(&PB1 + i * 8));
        i = i + 1;
    }
    SW2 = ad_wblock(4);
    i = 0;
    while i < 4 {
        ad_set(SW2 + i, load64(&PW2 + i * 8));
        i = i + 1;
    }
    SB2 = ad_wblock(1);
    ad_set(SB2, load64(&PB2 + 0));

    let z1: i64 = ad_matmul(SW1, x, 4, 2);
    let a1: i64 = ad_vadd(z1, SB1, 4);
    # 隐藏层用 sigmoid 而不是 relu：
    # 定点下小初始化 + relu 会让 h 全为 0，梯度传不回 W1（"relu 死亡"）。
    # 实测用 relu 时 grad check 两边都是 0 —— 一致但**没验证到任何东西**。
    let h: i64 = ad_vsig(a1, 4);
    let z2: i64 = ad_matmul(SW2, h, 1, 4);
    let a2: i64 = ad_vadd(z2, SB2, 1);
    let y: i64 = ad_vsig(a2, 1);
    SOUT = y;

    let tgt: i64 = ad_block(1);
    ad_set(tgt, t0);
    let L: i64 = ad_mse(y, tgt, 1);
    return L;
}

# 把更新后的权重值拷回全局（下一次 build 要用）
fn save_w() -> i64 {
    let i: i64 = 0;
    while i < 8 {
        store64(&PW1 + i * 8, ad_val(SW1 + i));
        i = i + 1;
    }
    i = 0;
    while i < 4 {
        store64(&PB1 + i * 8, ad_val(SB1 + i));
        store64(&PW2 + i * 8, ad_val(SW2 + i));
        i = i + 1;
    }
    store64(&PB2 + 0, ad_val(SB2));
    return 0;
}

# 梯度比对：绝对差 + 相对容差
#
# ⚠️ 容差必须用**绝对值**：ag 为负时 `ag / 20` 在定点下向零截断成负数，
# 容差变成 3 + (-101) = -98，任何差都超限 → 恒为 FAIL。
# 这个 bug 表现为"梯度明明只差 1，却判定失败"，很难想到是负数除法。
fn grad_close(n: i64, a: i64) -> i64 {
    let d: i64 = n - a;
    if d < 0 { d = 0 - d; }
    let av: i64 = a;
    if av < 0 { av = 0 - av; }
    let tol: i64 = 3 + av / 20;
    if d > tol { return 0; }
    return 1;
}

fn main() -> i64 {
    nn_srand(12345);
    init_data();
    init_w();

    print("=== 墨语言自动微分训练 2-4-1（XOR）===\n");
    print("网络定义只有前向，梯度由语言求\n\n");

    # ---- 1) 梯度检查：数值梯度 vs 自动梯度 ----
    # 必须**先存下自动梯度**：下面要反复 build() 做数值检查，
    # 而 build() 里的 ad_reset() 会把梯度清零（踩过的坑）。
    # 用 x=(1,1)：两个分量都非零，否则 dW1[0] = gy·x[0] = 0，
    # 数值与自动都是 0 —— 一致，但**根本没验证到任何东西**。
    let L0: i64 = build(65536, 65536, 0);
    ad_backward(L0);
    let ag0: i64 = ad_grad(SW1 + 0);
    let ag1: i64 = ad_grad(SW1 + 1);
    let agw2: i64 = ad_grad(SW2 + 0);

    let h: i64 = 512;
    let fail: i64 = 0;

    let w0: i64 = load64(&PW1 + 0);
    store64(&PW1 + 0, w0 + h);
    let lp: i64 = ad_val(build(65536, 65536, 0));
    store64(&PW1 + 0, w0 - h);
    let lm: i64 = ad_val(build(65536, 65536, 0));
    store64(&PW1 + 0, w0);
    let n0: i64 = nn_fdiv(lp - lm, h + h);

    let w1: i64 = load64(&PW1 + 8);
    store64(&PW1 + 8, w1 + h);
    let lp2: i64 = ad_val(build(65536, 65536, 0));
    store64(&PW1 + 8, w1 - h);
    let lm2: i64 = ad_val(build(65536, 65536, 0));
    store64(&PW1 + 8, w1);
    let n1: i64 = nn_fdiv(lp2 - lm2, h + h);

    print("grad check W1[0]: numeric ");
    print_i64(nn_to_milli(n0));
    print("  auto ");
    print_i64(nn_to_milli(ag0));
    print("\ngrad check W1[1]: numeric ");
    print_i64(nn_to_milli(n1));
    print("  auto ");
    print_i64(nn_to_milli(ag1));
    print("\n");

    # 有限差分在定点下有舍入，用绝对差 3 + 5% 相对容差
    if grad_close(n0, ag0) == 0 { fail = fail + 1; }
    if grad_close(n1, ag1) == 0 { fail = fail + 1; }

    if fail == 0 {
        print("grad check: PASS\n");
    } else {
        print("grad check: FAIL\n");
        return 1;
    }

    # ---- 2) 训练 ----
    let lr: i64 = 32768;               # 0.5
    let epoch: i64 = 0;
    # 🔴 梯度流审计：EVER 按槽号记录，换模型前必须清零
    ad_audit_reset();
    let ndead: i64 = 0;
    while epoch < 3000 {
        let s: i64 = 0;
        while s < 4 {
            let L: i64 = build(load64(&XS + s * 16), load64(&XS + s * 16 + 8), load64(&TS + s * 8));
            LASTL = ad_val(L);
            ad_backward(L);
            ad_step(lr);
            save_w();
            s = s + 1;
        }
        if epoch == 0 {
            print("epoch   0  loss "); print_i64(nn_to_milli(LASTL)); print("\n");
            # 首轮审计：抓"从初始化起就是死的"单元
            ndead = ad_audit();
        }
        if epoch == 500 { print("epoch 500  loss "); print_i64(nn_to_milli(LASTL)); print("\n"); }
        if epoch == 2999 {
            ndead = ad_audit();
            print("训练结束审计问题数: "); print_i64(ndead); print("\n");
        }
        epoch = epoch + 1;
    }

    # ---- 3) 结果 ----
    print("\n--- 预测 ---\n");
    let corr: i64 = 0;
    let s2: i64 = 0;
    while s2 < 4 {
        let L2: i64 = build(load64(&XS + s2 * 16), load64(&XS + s2 * 16 + 8), load64(&TS + s2 * 8));
        let yv: i64 = nn_to_milli(ad_val(SOUT));
        let tv: i64 = nn_to_milli(load64(&TS + s2 * 8));
        print_i64(nn_to_milli(load64(&XS + s2 * 16)));
        print(" xor ");
        print_i64(nn_to_milli(load64(&XS + s2 * 16 + 8)));
        print(" -> ");
        print_i64(yv);
        print("  (want ");
        print_i64(tv);
        print(")\n");
        if yv > 500 { if tv > 500 { corr = corr + 1; } } else { if tv < 500 { corr = corr + 1; } }
        s2 = s2 + 1;
    }
    print("correct: ");
    print_i64(corr);
    print(" / 4\n");
    if corr == 4 { print("XOR solved by autodiff\n"); return 0; }
    return 1;
}
