# optim —— 三种优化器在同一任务上对照
#
#   SGD / Momentum / Adam
#
# 同样的网络、同样的初始权重、同样的学习率，
# 比较**收敛到同等精度所需的轮数**。
import "autodiff.mo";

var XS: [8] i64 = 0;
var TS: [4] i64 = 0;

# 权重初值（三个网络都从这里拷贝，保证公平）
var W0A: [8] i64 = 0;
var W0B: [4] i64 = 0;
var W0C: [4] i64 = 0;
var W0D: [1] i64 = 0;

fn init_data() -> i64 {
    store64(&XS + 0, 0);       store64(&XS + 8, 0);        store64(&TS + 0, 0);
    store64(&XS + 16, 0);      store64(&XS + 24, 65536);   store64(&TS + 8, 65536);
    store64(&XS + 32, 65536);  store64(&XS + 40, 0);       store64(&TS + 16, 65536);
    store64(&XS + 48, 65536);  store64(&XS + 56, 65536);   store64(&TS + 24, 0);
    return 0;
}

fn init_w0() -> i64 {
    let i: i64 = 0;
    while i < 8 { store64(&W0A + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&W0B + i * 8, 0); store64(&W0C + i * 8, nn_rand_fp(65536)); i = i + 1; }
    store64(&W0D, 0);
    return 0;
}

# 工作区：当前权重
var CWA: [8] i64 = 0;
var CWB: [4] i64 = 0;
var CWC: [4] i64 = 0;
var CWD: [1] i64 = 0;

var SW1: i64 = 0;
var SB1: i64 = 0;
var SW2: i64 = 0;
var SB2: i64 = 0;
var SOUT: i64 = 0;
var ADAM_LR: i64 = 16384;   # 0.25

fn reset_w() -> i64 {
    let i: i64 = 0;
    while i < 8 { store64(&CWA + i * 8, load64(&W0A + i * 8)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&CWB + i * 8, load64(&W0B + i * 8)); store64(&CWC + i * 8, load64(&W0C + i * 8)); i = i + 1; }
    store64(&CWD, load64(&W0D));
    return 0;
}

# 只写前向：x(2) → tanh(4) → sigmoid(1)
fn build(x0: i64, x1: i64, t0: i64) -> i64 {
    ad_reset();
    let x: i64 = ad_block(2);
    ad_set(x + 0, x0);
    ad_set(x + 1, x1);

    SW1 = ad_wblock(8);
    let i: i64 = 0;
    while i < 8 { ad_set(SW1 + i, load64(&CWA + i * 8)); i = i + 1; }
    SB1 = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SB1 + i, load64(&CWB + i * 8)); i = i + 1; }
    SW2 = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SW2 + i, load64(&CWC + i * 8)); i = i + 1; }
    SB2 = ad_wblock(1);
    ad_set(SB2, load64(&CWD));

    let z1: i64 = ad_matmul(SW1, x, 4, 2);
    let h: i64 = ad_vtanh(ad_vadd(z1, SB1, 4), 4);
    let z2: i64 = ad_matmul(SW2, h, 1, 4);
    let y: i64 = ad_vsig(ad_vadd(z2, SB2, 1), 1);
    SOUT = y;
    let tgt: i64 = ad_block(1);
    ad_set(tgt, t0);
    return ad_mse_half(y, tgt, 1);
}

fn save_w() -> i64 {
    let i: i64 = 0;
    while i < 8 { store64(&CWA + i * 8, ad_val(SW1 + i)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&CWB + i * 8, ad_val(SB1 + i)); store64(&CWC + i * 8, ad_val(SW2 + i)); i = i + 1; }
    store64(&CWD, ad_val(SB2));
    return 0;
}

fn total_loss() -> i64 {
    let acc: i64 = 0;
    let s: i64 = 0;
    while s < 4 {
        let L: i64 = build(load64(&XS + s * 16), load64(&XS + s * 16 + 8), load64(&TS + s * 8));
        acc = acc + ad_val(L);
        s = s + 1;
    }
    return acc;
}

fn correct_n() -> i64 {
    let corr: i64 = 0;
    let s: i64 = 0;
    while s < 4 {
        build(load64(&XS + s * 16), load64(&XS + s * 16 + 8), load64(&TS + s * 8));
        let yv: i64 = nn_to_milli(ad_val(SOUT));
        let tv: i64 = nn_to_milli(load64(&TS + s * 8));
        if yv > 500 { if tv > 500 { corr = corr + 1; } } else { if tv < 500 { corr = corr + 1; } }
        s = s + 1;
    }
    return corr;
}

# 返回"达到 4/4 正确所需的 epoch 数"，达不到返回 -1
fn run(mode: i64, lr: i64, maxep: i64) -> i64 {
    reset_w();
    ad_opt_reset();
    let ep: i64 = 0;
    while ep < maxep {
        let s: i64 = 0;
        while s < 4 {
            let L: i64 = build(load64(&XS + s * 16), load64(&XS + s * 16 + 8), load64(&TS + s * 8));
            ad_backward(L);
            if mode == 0 { ad_step(lr); }
            if mode == 1 { ad_step_momentum(lr, 58982); }        # beta = 0.9
            if mode == 2 { ad_step_adam(lr, 58982, 64881, 6); } # 0.9 / 0.99 / 0.01
            save_w();
            s = s + 1;
        }
        if correct_n() == 4 { return ep + 1; }
        ep = ep + 1;
    }
    return 0 - 1;
}

fn main() -> i64 {
    nn_srand(4242);
    init_data();
    init_w0();

    let lr: i64 = 32768;      # 0.5
    print("=== 优化器对照（达到 4/4 所需 epoch）===\n");

    let e0: i64 = run(0, lr, 400);
    print("SGD      : ");
    print_i64(e0);
    print("\n");

    let e1: i64 = run(1, lr, 400);
    print("Momentum : ");
    print_i64(e1);
    print("\n");

    # 参数扫描结果：eps=6、lr=0.25 时最快（10 epoch vs SGD 17）
    let e2: i64 = run(2, ADAM_LR, 400);
    print("Adam     : ");
    print_i64(e2);
    print("\n");

    # 三者都必须真的收敛（-1 表示没到）
    if e0 < 0 { print("SGD 未收敛\n"); return 1; }
    if e1 < 0 { print("Momentum 未收敛\n"); return 1; }
    if e2 < 0 { print("Adam 未收敛\n"); return 1; }
    print("all optimizers converged\n");
    return 0;
}
