# 103 —— autodiff 原生权重初始化：He 缩放 + 符号平衡（1.75）
#
# 1.73 在 nn.mo 里修了"初始化符号一边倒 → 死通道"，但 autodiff 的权重
# 在 AD_VAL 槽里，用户得自己填一遍才用得上那个修法 —— 容易忘。
# 这里提供直接操作**槽**的版本（ad_winit / ad_winit_he / ad_wconv_init），
# 并验证它确实消除了符号一边倒。
import "autodiff.mo";
import "assert.mo";

fn main() -> i64 {
    print("=== autodiff 原生权重初始化 ===\n");
    let fail: i64 = 0;

    # ---- 1) 对照：手工填充 vs ad_winit（nin=2，效果最明显）----
    nn_srand(31337);
    ad_reset();
    let w: i64 = ad_wblock(200);
    let i: i64 = 0;
    while i < 200 { ad_set(w + i, nn_rand_fp(65536)); i = i + 1; }
    let r_manual: i64 = ad_init_risk(w, 200, 2);

    nn_srand(31337);
    ad_reset();
    let w2: i64 = ad_wblock(200);
    ad_winit(w2, 200, 2, 65536);
    let r_auto: i64 = ad_init_risk(w2, 200, 2);

    print("手工 nn_rand_fp 填充 (nin=2, 100 组) 符号一边倒 = ");
    print_i64(r_manual); print("\n");
    print("ad_winit            (nin=2, 100 组) 符号一边倒 = ");
    print_i64(r_auto); print("\n");

    # 手工填充在 nin=2 时，全正/全负概率约 50%，必然有相当数量
    if r_manual < 20 { fail = fail + 1; print("  ✗ 手工填充应出现大量符号一边倒\n"); }
    else { print("  ✓ 手工填充确实会产生符号一边倒（对照组有效）\n"); }
    if r_auto != 0 { fail = fail + 1; print("  ✗ ad_winit 应全部平衡\n"); }
    else { print("  ✓ ad_winit 全部正负混合\n"); }

    # ---- 2) 真实场景：卷积核 4 通道 × 9，多种子稳定 ----
    let bad: i64 = 0;
    let t: i64 = 0;
    while t < 20 {
        nn_srand(1000 + t * 7);
        ad_reset();
        let k: i64 = ad_wblock(36);
        ad_wconv_init(k, 4, 9);
        if ad_init_risk(k, 36, 9) != 0 { bad = bad + 1; }
        t = t + 1;
    }
    print("20 种子 × 4 通道，符号一边倒次数 = "); print_i64(bad); print("\n");
    if bad != 0 { fail = fail + 1; print("  ✗ ad_wconv_init 不稳定\n"); }
    else { print("  ✓ 80 次采样全部正负混合\n"); }

    # ---- 3) He 缩放：|w| 应受 sqrt(2/nin) 约束 ----
    nn_srand(4242);
    ad_reset();
    let k2: i64 = ad_wblock(36);
    ad_wconv_init(k2, 4, 9);
    let mx: i64 = 0;
    i = 0;
    while i < 36 {
        let v: i64 = load64(&AD_VAL + (k2 + i) * 8);
        if v < 0 { v = 0 - v; }
        if v > mx { mx = v; }
        i = i + 1;
    }
    # sqrt(2/9) ≈ 0.4714 → 定点约 30894。我用的 92681/sqrt(9)=30894
    let lim: i64 = 92681 / 3;
    print("|w| 最大值 = "); print_i64(mx); print("   He 上界 = ");
    print_i64(lim); print("\n");
    if mx > lim + 1 { fail = fail + 1; print("  ✗ 超出 He 缩放范围\n"); }
    else { print("  ✓ He 缩放生效\n"); }

    # ---- 4) ad_init_risk 能检出人为构造的符号一边倒 ----
    nn_srand(777);
    ad_reset();
    let k3: i64 = ad_wblock(36);
    ad_wconv_init(k3, 4, 9);
    # 人为把通道 2 全部改成负数
    i = 0;
    while i < 9 {
        let v: i64 = load64(&AD_VAL + (k3 + 18 + i) * 8);
        if v > 0 { v = 0 - v; }
        if v == 0 { v = 0 - 8192; }
        store64(&AD_VAL + (k3 + 18 + i) * 8, v);
        i = i + 1;
    }
    let rk: i64 = ad_init_risk(k3, 36, 9);
    print("人为构造全负通道后，风险组数 = "); print_i64(rk); print("\n");
    if rk != 1 { fail = fail + 1; print("  ✗ 应检出 1 个风险组\n"); }
    else { print("  ✓ 自查能检出死单元风险\n"); }

    # ---- 5) 全连接便捷版 ----
    nn_srand(999);
    ad_reset();
    let d: i64 = ad_wblock(64);        # 8 × 8
    ad_wdense_init(d, 8, 8);
    let rd: i64 = ad_init_risk(d, 64, 8);
    print("全连接 8×8 风险组数 = "); print_i64(rd); print("\n");
    if rd != 0 { fail = fail + 1; print("  ✗ 全连接也应为 0\n"); }
    else { print("  ✓ ad_wdense_init 生效\n"); }

    # ---- 6) 偏置清零 ----
    ad_reset();
    let b: i64 = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(b + i, 32768); i = i + 1; }
    ad_bzero(b, 4);
    let nz: i64 = 0;
    i = 0;
    while i < 4 { if load64(&AD_VAL + (b + i) * 8) != 0 { nz = nz + 1; } i = i + 1; }
    print("ad_bzero 后非零个数 = "); print_i64(nz); print("\n");
    if nz != 0 { fail = fail + 1; print("  ✗ 应全部清零\n"); }
    else { print("  ✓ 偏置清零\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("winit: ALL PASS\n"); return 0; }
    return 1;
}
