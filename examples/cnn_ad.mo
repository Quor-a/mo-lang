# cnn_ad —— 用**自动微分**训练真正的 CNN（只写前向）
#
# 任务：8×8 二值图，分"横条 / 竖条"两类。
#
# 网络（全部只写前向，梯度由语言求）：
#   conv  1→4 通道，3×3 valid    → 4 × 6×6
#   + bias（广播到每个通道的所有位置）
#   relu
#   pool  2×2 max（逐通道）      → 4 × 3×3
#   flatten 36 → 2
#   sigmoid
#   mse
#
# 与 examples/cnn.mo（手写反向，lib/cnn.mo）的区别：这里没有一行反向代码。
import "autodiff.mo";

var IMG: [512] i64 = 0;      # 8 张 8×8
var LBL: [8] i64 = 0;
var NS: i64 = 8;

var KW: [36] i64 = 0;        # 4 核 × 9
var KB: [4] i64 = 0;
var FW: [72] i64 = 0;        # 36 → 2
var FB: [2] i64 = 0;

var SKW: i64 = 0;
var SKB: i64 = 0;
var SFW: i64 = 0;
var SFB: i64 = 0;
var SOUT: i64 = 0;

# ---------------------------------------------------------------- 数据
# 前 4 张横条（中间两行全 1），后 4 张竖条（中间两列全 1）
fn init_data() -> i64 {
    let s: i64 = 0;
    while s < 8 {
        let r: i64 = 0;
        while r < 8 {
            let c: i64 = 0;
            while c < 8 {
                let v: i64 = 0;
                if s < 4 {
                    if r == 3 { v = 65536; }
                    if r == 4 { v = 65536; }
                } else {
                    if c == 3 { v = 65536; }
                    if c == 4 { v = 65536; }
                }
                store64(&IMG + s * 512 + r * 64 + c * 8, v);
                c = c + 1;
            }
            r = r + 1;
        }
        if s < 4 { store64(&LBL + s * 8, 0); }
        else { store64(&LBL + s * 8, 65536); }
        s = s + 1;
    }
    return 0;
}

fn init_w() -> i64 {
    let i: i64 = 0;
    while i < 36 { store64(&KW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&KB + i * 8, 0); i = i + 1; }
    i = 0;
    while i < 72 { store64(&FW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&FB + i * 8, 0); i = i + 1; }
    return 0;
}

# ---------------------------------------------------------------- 前向（只写这一遍）
fn build(s: i64) -> i64 {
    ad_reset();

    let x: i64 = ad_block(64);
    let i: i64 = 0;
    while i < 64 {
        ad_set(x + i, load64(&IMG + s * 512 + i * 8));
        i = i + 1;
    }

    SKW = ad_wblock(36);
    i = 0;
    while i < 36 { ad_set(SKW + i, load64(&KW + i * 8)); i = i + 1; }
    SKB = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SKB + i, load64(&KB + i * 8)); i = i + 1; }

    # conv 1→4：输出布局 [ch][36]
    let c1: i64 = ad_conv_mc(x, SKW, 8, 8, 1, 4);
    # 偏置广播：a 是 4×36（nr=4, bs=36），b 是 4 个 → 每个通道加到自己 36 个位置
    let c2: i64 = ad_vadd_bcast(c1, SKB, 4, 36);
    let c3: i64 = ad_vrelu(c2, 144);

    # 多通道池化：6×6 → 3×3，一次性处理全部通道。
    #
    # ⚠️ 不能用"逐通道 ad_pool + ad_set 拷贝"：ad_set 不记 tape，
    # 梯度拷不过去，**卷积层收不到任何梯度**。
    # 第一版就是这么写的，结果 8/8 但卷积核从未更新过 ——
    # 那是全连接层单独学出来的，不是 CNN。
    let flat: i64 = ad_pool_mc(c3, 4, 6, 6);

    SFW = ad_wblock(72);
    i = 0;
    while i < 72 { ad_set(SFW + i, load64(&FW + i * 8)); i = i + 1; }
    SFB = ad_wblock(2);
    i = 0;
    while i < 2 { ad_set(SFB + i, load64(&FB + i * 8)); i = i + 1; }

    let z2: i64 = ad_matmul(SFW, flat, 2, 36);
    let y: i64 = ad_vsig(ad_vadd(z2, SFB, 2), 2);
    SOUT = y;

    let t: i64 = ad_block(2);
    let lb: i64 = load64(&LBL + s * 8);
    # 0 类 → [1,0]；1 类 → [0,1]
    if lb == 0 { ad_set(t + 0, 65536); ad_set(t + 1, 0); }
    else { ad_set(t + 0, 0); ad_set(t + 1, 65536); }
    return ad_mse_half(y, t, 2);
}

fn save_w() -> i64 {
    let i: i64 = 0;
    while i < 36 { store64(&KW + i * 8, ad_val(SKW + i)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&KB + i * 8, ad_val(SKB + i)); i = i + 1; }
    i = 0;
    while i < 72 { store64(&FW + i * 8, ad_val(SFW + i)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&FB + i * 8, ad_val(SFB + i)); i = i + 1; }
    return 0;
}

fn correct_n() -> i64 {
    let corr: i64 = 0;
    let s: i64 = 0;
    while s < 8 {
        build(s);
        let v0: i64 = ad_val(SOUT + 0);
        let v1: i64 = ad_val(SOUT + 1);
        let pred: i64 = 0;
        if v1 > v0 { pred = 1; }
        if pred * 65536 == load64(&LBL + s * 8) { corr = corr + 1; }
        s = s + 1;
    }
    return corr;
}

fn main() -> i64 {
    nn_srand(2024);
    init_data();
    init_w();

    print("=== 自动微分训练 CNN（8×8 横条/竖条分类）===\n");
    print("网络只有前向，没有一行反向传播\n\n");

    let lr: i64 = 32768;
    # 记录卷积核初值，用来验证**卷积层真的被训练了**
    let KW0: [36] i64 = 0;
    let qi: i64 = 0;
    while qi < 36 { store64(&KW0 + qi * 8, load64(&KW + qi * 8)); qi = qi + 1; }
    let ep: i64 = 0;
    ad_audit_reset();
    let ndead: i64 = 0;
    while ep < 200 {
        let s: i64 = 0;
        while s < 8 {
            let L: i64 = build(s);
            ad_backward(L);
            ad_step(lr);
            save_w();
            s = s + 1;
        }
        if ep == 0 {
            print("epoch   0  correct ");
            print_i64(correct_n());
            print(" / 8\n");
            ndead = ad_audit();
        }
        if ep == 199 {
            ndead = ad_audit();
            print("epoch 199 dead ");
            print_i64(ndead);
            print("\n");
        }
        ep = ep + 1;
    }

    # 统计有多少核元素被更新过。
    # ⚠️ 不能只看 KW[0]：它对应的 3×3 窗口在所有样本上都是全 0
    # （横条在第 3/4 行、竖条在第 3/4 列，窗口 r=0..2,c=0..2 恒空），
    # 所以它的梯度恒为 0 —— 那是**正确行为**，不是 bug。
    let changed: i64 = 0;
    let qj: i64 = 0;
    while qj < 36 {
        if load64(&KW + qj * 8) != load64(&KW0 + qj * 8) { changed = changed + 1; }
        qj = qj + 1;
    }
    print("conv kernel elements updated: ");
    print_i64(changed);
    print(" / 36\n");
    if changed == 0 { print("WARNING: conv weights never changed!\n"); return 1; }

    let c: i64 = correct_n();
    print("epoch 200  correct ");
    print_i64(c);
    print(" / 8\n");

    if c == 8 { print("CNN solved by autodiff\n"); return 0; }
    print("not fully solved\n");
    return 1;
}
