# mclass —— 用自动微分做多分类（softmax + 交叉熵）
#
# 4 类、2 维输入，网络 2→4→4。
# **全部只写前向**，梯度和更新由墨语言完成。
import "autodiff.mo";

var NC: i64 = 4;
var PW1: [8] i64 = 0;
var PB1: [4] i64 = 0;
var PW2: [16] i64 = 0;
var PB2: [4] i64 = 0;

# 四个象限 → 四个类别
var XS: [8] i64 = 0;
var TS: [4] i64 = 0;

var SL2: i64 = 0;
var LASTL: i64 = 0;

fn init_data() -> i64 {
    store64(&XS + 0, 0 - 65536);  store64(&XS + 8, 0 - 65536);   store64(&TS + 0, 0);
    store64(&XS + 16, 0 - 65536); store64(&XS + 24, 65536);       store64(&TS + 8, 1);
    store64(&XS + 32, 65536);     store64(&XS + 40, 0 - 65536);   store64(&TS + 16, 2);
    store64(&XS + 48, 65536);     store64(&XS + 56, 65536);       store64(&TS + 24, 3);
    return 0;
}

fn init_w() -> i64 {
    let i: i64 = 0;
    while i < 8 { store64(&PW1 + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&PB1 + i * 8, 0); i = i + 1; }
    i = 0;
    while i < 16 { store64(&PW2 + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&PB2 + i * 8, 0); i = i + 1; }
    return 0;
}

var SW1m: i64 = 0;
var SB1m: i64 = 0;
var SW2m: i64 = 0;
var SB2m: i64 = 0;

# 只写前向
fn build(x0: i64, x1: i64, t: i64) -> i64 {
    ad_reset();
    let x: i64 = ad_block(2);
    ad_set(x + 0, x0);
    ad_set(x + 1, x1);

    SW1m = ad_wblock(8);
    let i: i64 = 0;
    while i < 8 { ad_set(SW1m + i, load64(&PW1 + i * 8)); i = i + 1; }
    SB1m = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SB1m + i, load64(&PB1 + i * 8)); i = i + 1; }
    SW2m = ad_wblock(16);
    i = 0;
    while i < 16 { ad_set(SW2m + i, load64(&PW2 + i * 8)); i = i + 1; }
    SB2m = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SB2m + i, load64(&PB2 + i * 8)); i = i + 1; }

    let z1: i64 = ad_matmul(SW1m, x, 4, 2);
    let h: i64 = ad_vsig(ad_vadd(z1, SB1m, 4), 4);
    let z2: i64 = ad_matmul(SW2m, h, 4, 4);
    SL2 = z2;
    let L: i64 = ad_sce(z2, 4, t);
    return L;
}

fn save_w() -> i64 {
    let i: i64 = 0;
    while i < 8 { store64(&PW1 + i * 8, ad_val(SW1m + i)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&PB1 + i * 8, ad_val(SB1m + i)); i = i + 1; }
    i = 0;
    while i < 16 { store64(&PW2 + i * 8, ad_val(SW2m + i)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&PB2 + i * 8, ad_val(SB2m + i)); i = i + 1; }
    return 0;
}

# 数值/自动梯度比对，容差取绝对值（负梯度会让 ag/20 变负）
fn grad_close(n: i64, a: i64) -> i64 {
    let d: i64 = n - a;
    if d < 0 { d = 0 - d; }
    let av: i64 = a;
    if av < 0 { av = 0 - av; }
    if d > 4 + av / 20 { return 0; }
    return 1;
}

fn main() -> i64 {
    nn_srand(777);
    init_data();
    init_w();

    print("=== 自动微分多分类（softmax + 交叉熵）===\n");

    # ---- 梯度检查 ----
    let L0: i64 = build(65536, 65536, 3);
    ad_backward(L0);
    let ag: i64 = ad_grad(SW2m + 0);
    let ag2: i64 = ad_grad(SW1m + 0);

    let h: i64 = 512;
    let w0: i64 = load64(&PW2 + 0);
    store64(&PW2 + 0, w0 + h);
    let lp: i64 = ad_val(build(65536, 65536, 3));
    store64(&PW2 + 0, w0 - h);
    let lm: i64 = ad_val(build(65536, 65536, 3));
    store64(&PW2 + 0, w0);
    let n0: i64 = nn_fdiv(lp - lm, h + h);

    let v0: i64 = load64(&PW1 + 0);
    store64(&PW1 + 0, v0 + h);
    let lp2: i64 = ad_val(build(65536, 65536, 3));
    store64(&PW1 + 0, v0 - h);
    let lm2: i64 = ad_val(build(65536, 65536, 3));
    store64(&PW1 + 0, v0);
    let n1: i64 = nn_fdiv(lp2 - lm2, h + h);

    print("W2[0]: numeric ");
    print_i64(nn_to_milli(n0));
    print("  auto ");
    print_i64(nn_to_milli(ag));
    print("\nW1[0]: numeric ");
    print_i64(nn_to_milli(n1));
    print("  auto ");
    print_i64(nn_to_milli(ag2));
    print("\n");

    let fail: i64 = 0;
    if grad_close(n0, ag) == 0 { fail = fail + 1; }
    if grad_close(n1, ag2) == 0 { fail = fail + 1; }
    if fail == 0 { print("grad check: PASS\n"); }
    else { print("grad check: FAIL\n"); return 1; }

    # ---- 训练 ----
    print("\n--- 训练 ---\n");
    let lr: i64 = 32768;
    let epoch: i64 = 0;
    while epoch < 800 {
        let s: i64 = 0;
        while s < 4 {
            let L: i64 = build(load64(&XS + s * 16), load64(&XS + s * 16 + 8), load64(&TS + s * 8));
            LASTL = ad_val(L);
            ad_backward(L);
            ad_step(lr);
            save_w();
            s = s + 1;
        }
        if epoch == 0 { print("epoch   0  loss "); print_i64(nn_to_milli(LASTL)); print("\n"); }
        if epoch == 400 { print("epoch 400  loss "); print_i64(nn_to_milli(LASTL)); print("\n"); }
        epoch = epoch + 1;
    }

    # ---- 预测 ----
    print("\n--- 预测 ---\n");
    let corr: i64 = 0;
    let s2: i64 = 0;
    while s2 < 4 {
        build(load64(&XS + s2 * 16), load64(&XS + s2 * 16 + 8), load64(&TS + s2 * 8));
        # argmax
        let best: i64 = 0;
        let bi: i64 = 0;
        let i: i64 = 1;
        while i < 4 {
            if ad_val(SL2 + i) > ad_val(SL2 + best) { best = i; }
            i = i + 1;
        }
        bi = best;
        print_i64(nn_to_milli(load64(&XS + s2 * 16)));
        print(",");
        print_i64(nn_to_milli(load64(&XS + s2 * 16 + 8)));
        print(" -> class ");
        print_i64(bi);
        print("  (want ");
        print_i64(load64(&TS + s2 * 8));
        print(")\n");
        if bi == load64(&TS + s2 * 8) { corr = corr + 1; }
        s2 = s2 + 1;
    }
    print("correct: ");
    print_i64(corr);
    print(" / 4\n");
    if corr == 4 { print("classification solved by autodiff\n"); return 0; }
    return 1;
}
