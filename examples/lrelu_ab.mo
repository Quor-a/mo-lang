# lrelu_ab —— A/B 对照：relu vs leaky relu 对**死权重**的影响
#
# 起因：1.70 把梯度流审计接进 cnn_ad，查出 SFW（全连接层）有 20 个
#       权重**从头到尾**没收到过非零梯度 —— 此前无人察觉。
# 假说：这些权重死的直接原因是 relu 后 flat 的某些位置恒为 0，
#       于是 dSFW = gy·flat = 0。leaky relu 给负半轴一条细流，
#       能让它们重新参与训练。
#
# 本示例在**同一进程、同一种子、同一数据**下跑两个网络，
# 只换激活函数，对比：准确率 / 死权重数 / 卷积核更新数。
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






# USE_LEAKY: 0 = relu（对照），1 = leaky relu（实验）
var USE_LEAKY: i64 = 0;

fn act(a: i64, n: i64) -> i64 {
    if USE_LEAKY == 1 { return ad_vlrelu(a, n); }
    return ad_vrelu(a, n);
}

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

    let c1: i64 = ad_conv_mc(x, SKW, 8, 8, 1, 4);
    let c2: i64 = ad_vadd_bcast(c1, SKB, 4, 36);
    let c3: i64 = act(c2, 144);

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


# 跑一遍完整训练，返回：correct*1000000 + 死权重数
fn run_training(leaky: i64) -> i64 {
    USE_LEAKY = leaky;
    init_data();
    init_w();

    let KW0: [36] i64 = 0;
    let qi: i64 = 0;
    while qi < 36 { store64(&KW0 + qi * 8, load64(&KW + qi * 8)); qi = qi + 1; }

    let lr: i64 = 32768;
    ad_audit_reset();
    let ndead: i64 = 0;
    let ep: i64 = 0;
    while ep < 200 {
        let s: i64 = 0;
        while s < 8 {
            let L: i64 = build(s);
            ad_backward(L);
            ad_step(lr);
            save_w();
            s = s + 1;
        }
        ep = ep + 1;
    }
    ndead = ad_audit();

    let changed: i64 = 0;
    let qj: i64 = 0;
    while qj < 36 {
        if load64(&KW + qj * 8) != load64(&KW0 + qj * 8) { changed = changed + 1; }
        qj = qj + 1;
    }
    let c: i64 = correct_n();

    if leaky == 1 { print("leaky relu : "); } else { print("relu       : "); }
    print("correct "); print_i64(c); print(" / 8   卷积核更新 "); print_i64(changed);
    print(" / 36   死权重 "); print_i64(ndead); print("\n");
    return c * 1000000 + ndead;
}

fn main() -> i64 {
    nn_srand(2024);
    print("=== A/B 对照：relu vs leaky relu（同种子、同数据）===\n");
    print("假说：leaky 能让 relu 造成的死权重重新参与训练\n\n");

    # ⚠️ 必须先跑 relu 再跑 leaky，且各自 init_w 重置权重 ——
    # 否则第二个网络继承第一个的训练结果，对比毫无意义。
    let r_relu:  i64 = run_training(0);
    let r_leaky: i64 = run_training(1);

    let c_relu:  i64 = r_relu / 1000000;
    let d_relu:  i64 = r_relu - c_relu * 1000000;
    let c_leaky: i64 = r_leaky / 1000000;
    let d_leaky: i64 = r_leaky - c_leaky * 1000000;

    print("\n--- 结论 ---\n");
    print("死权重：relu "); print_i64(d_relu); print(" → leaky "); print_i64(d_leaky); print("\n");

    if c_leaky < c_relu {
        print("✗ leaky 准确率下降（"); print_i64(c_relu); print(" → "); print_i64(c_leaky); print("）\n");
        return 1;
    }
    print("准确率未下降："); print_i64(c_relu); print(" → "); print_i64(c_leaky); print("\n");
    if d_leaky >= d_relu {
        print("✗ leaky 未减少死权重\n");
        return 1;
    }
    print("✓ leaky relu 减少死权重 "); print_i64(d_relu - d_leaky); print(" 个\n");
    return 0;
}
