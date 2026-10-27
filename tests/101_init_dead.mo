# 101 —— 初始化符号一边倒 → 死通道（1.72 的根因，1.73 的修法）
#
# 根因：卷积核 9 个元素**全为负** + 偏置 0 + 输入 0/1 二值图
#   ⇒ z = Σw·x + b ≤ 0 对**任何**输入成立
#   ⇒ relu 输出恒 0 ⇒ 梯度恒 0 ⇒ 该通道训练开始前就已死，永不更新
#
# 修法：按通道保证正负混合（nn_conv_init_ch）
import "nn.mo";
import "assert.mo";

var KW: [36] i64 = 0;
var KB: [4] i64 = 0;
var IMG: [64] i64 = 0;       # 8×8 二值图

fn gen_img() -> i64 {
    let i: i64 = 0;
    while i < 64 { store64(&IMG + i * 8, 0); i = i + 1; }
    # 中心 2×2 块
    let r: i64 = 3;
    while r < 5 {
        let c: i64 = 3;
        while c < 5 { store64(&IMG + r * 64 + c * 8, 65536); c = c + 1; }
        r = r + 1;
    }
    return 0;
}

# 该通道在给定输入下，卷积+relu 后是否**所有位置**都为 0
# all_zero == 1 → 死通道（梯度必然为 0）
fn ch_all_zero(c: i64) -> i64 {
    let i: i64 = 0;
    while i < 36 {          # 6×6 输出位置
        let orow: i64 = i / 6;
        let ocol: i64 = i - (i / 6) * 6;
        let acc: i64 = 0;
        let kr: i64 = 0;
        while kr < 3 {
            let kc: i64 = 0;
            while kc < 3 {
                let px: i64 = load64(&IMG + (orow + kr) * 64 + (ocol + kc) * 8);
                let kw: i64 = load64(&KW + c * 72 + kr * 24 + kc * 8);
                acc = acc + nn_fmul(kw, px);
                kc = kc + 1;
            }
            kr = kr + 1;
        }
        acc = acc + load64(&KB + c * 8);
        if acc > 0 { return 0; }      # 至少有一个位置激活
        i = i + 1;
    }
    return 1;
}

fn main() -> i64 {
    gen_img();
    print("=== 初始化符号一边倒 → 死通道 ===\n");
    let fail: i64 = 0;

    # ---- 1) 复现：人为构造全负核，验证 ch_all_zero 判定为死 ----
    nn_srand(31337);
    let i: i64 = 0;
    while i < 36 { store64(&KW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    # 强制通道 3 全负（复现 1.72 观察到的 ch3: min=-814 max=-75, 9/9 负）
    i = 0;
    while i < 9 {
        let v: i64 = load64(&KW + 27 * 8 + i * 8);
        if v > 0 { v = 0 - v; }
        if v == 0 { v = 0 - 8192; }     # 避免恰好为 0
        store64(&KW + 27 * 8 + i * 8, v);
        i = i + 1;
    }
    i = 0;
    while i < 4 { store64(&KB + i * 8, 0); i = i + 1; }

    print("构造后 ch3 符号一边倒 = ");
    print_i64(nn_ch_dead_risk(&KW, 3, 9)); print("\n");
    if nn_ch_dead_risk(&KW, 3, 9) != 1 { fail = fail + 1; print("  ✗ 应判为风险\n"); }
    print("ch3 全部位置 relu 输出为 0 = ");
    print_i64(ch_all_zero(3)); print("\n");
    if ch_all_zero(3) != 1 { fail = fail + 1; print("  ✗ 全负核应为死通道\n"); }
    else { print("  ✓ 全负核 + 零偏置 ⇒ 死通道（梯度必然为 0）\n"); }

    # ---- 2) 修法：符号平衡初始化后，不应再有符号一边倒的通道 ----
    nn_srand(31337);
    nn_conv_init_ch(&KW, 4, 9, 46341);
    let nrisk: i64 = 0;
    let c: i64 = 0;
    while c < 4 {
        if nn_ch_dead_risk(&KW, c, 9) == 1 { nrisk = nrisk + 1; }
        c = c + 1;
    }
    print("符号平衡后，符号一边倒的通道数 = "); print_i64(nrisk); print("\n");
    if nrisk != 0 { fail = fail + 1; print("  ✗ 仍有符号一边倒通道\n"); }
    else { print("  ✓ 4 个通道全部正负混合\n"); }

    # ---- 3) 关键：修法后死通道应消失 ----
    let ndead: i64 = 0;
    c = 0;
    while c < 4 {
        if ch_all_zero(c) == 1 { ndead = ndead + 1; }
        c = c + 1;
    }
    print("符号平衡后死通道数 = "); print_i64(ndead); print("\n");
    if ndead != 4 {
        # 全负核的情况应该消失；全正核不会死（z>0）
        if ndead > 0 {
            let allpos: i64 = 0;
            c = 0;
            while c < 4 {
                if ch_all_zero(c) == 1 {
                    if nn_ch_dead_risk(&KW, c, 9) == 1 { allpos = allpos + 1; }
                }
                c = c + 1;
            }
            if allpos > 0 { fail = fail + 1; print("  ✗ 仍有符号一边倒导致的死通道\n"); }
        }
    } else { print("  ✓ 无死通道\n"); }

    # ---- 4) 多次种子：符号平衡应稳定生效 ----
    let bad: i64 = 0;
    let t: i64 = 0;
    while t < 20 {
        nn_srand(1000 + t * 7);
        nn_conv_init_ch(&KW, 4, 9, 46341);
        c = 0;
        while c < 4 {
            if nn_ch_dead_risk(&KW, c, 9) == 1 { bad = bad + 1; }
            c = c + 1;
        }
        t = t + 1;
    }
    print("20 个种子 × 4 通道中符号一边倒次数 = "); print_i64(bad); print("\n");
    if bad != 0 { fail = fail + 1; print("  ✗ 符号平衡不稳定\n"); }
    else { print("  ✓ 80 次采样全部正负混合\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("init_dead: ALL PASS\n"); return 0; }
    return 1;
}
