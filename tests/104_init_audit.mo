# 104 —— 初始化风险在**训练前**被发现（1.76）
#
# 核心：ad_audit() 在训练后调用，那时权重已被更新，事后检查初始化状态
# 在物理上不可能。所以必须在初始化那一刻记账，审计时读出来报。
import "autodiff.mo";
import "assert.mo";

fn main() -> i64 {
    print("=== 初始化风险：训练前发现 ===\n");
    let fail: i64 = 0;

    # ---- 1) 手工填充符号一边倒 → ad_init_note 应记账并报警 ----
    nn_srand(31337);
    ad_reset();
    ad_audit_reset();
    let w: i64 = ad_wblock(36);
    let i: i64 = 0;
    while i < 36 { ad_set(w + i, nn_rand_fp(65536)); i = i + 1; }
    # 人为把通道 2 全部改成负数
    i = 0;
    while i < 9 {
        let v: i64 = load64(&AD_VAL + (w + 18 + i) * 8);
        if v > 0 { v = 0 - v; }
        if v == 0 { v = 0 - 8192; }
        store64(&AD_VAL + (w + 18 + i) * 8, v);
        i = i + 1;
    }
    print("-- 手工构造全负通道后 ad_init_note(36, 9) --\n");
    let b1: i64 = ad_init_note(w, 36, 9);
    print("返回风险组数 = "); print_i64(b1); print("\n");
    if b1 != 1 { fail = fail + 1; print("  ✗ 应为 1\n"); }
    else { print("  ✓ 检出 1 个符号一边倒的组\n"); }

    let c1: i64 = ad_init_risk_count();
    print("累计 AD_AUD_INITN = "); print_i64(c1); print("\n");
    if c1 != 1 { fail = fail + 1; print("  ✗ 累计应为 1\n"); }
    else { print("  ✓ 记账生效\n"); }

    # ---- 2) ad_winit 自动记账：正常情况应为 0 ----
    nn_srand(4242);
    ad_reset();
    ad_audit_reset();
    let w2: i64 = ad_wblock(36);
    ad_wconv_init(w2, 4, 9);
    let c2: i64 = ad_init_risk_count();
    print("ad_wconv_init 后累计 = "); print_i64(c2); print("\n");
    if c2 != 0 { fail = fail + 1; print("  ✗ 应为 0（ad_winit 已做符号平衡）\n"); }
    else { print("  ✓ ad_winit 自动记账且为 0\n"); }

    # ---- 3) 关键：审计输出应包含初始化风险 ----
    # 构造一个"训练前就有风险"的场景，跑一次 ad_audit 看是否报出来
    nn_srand(555);
    ad_reset();
    ad_audit_reset();
    let x: i64 = ad_block(4);
    i = 0;
    while i < 4 { ad_set(x + i, 65536); i = i + 1; }
    let W: i64 = ad_wblock(4);
    # 全负权重 + 零偏置 + 非负输入 ⇒ relu 后恒 0 ⇒ 死单元
    i = 0;
    while i < 4 { ad_set(W + i, 0 - 30000); i = i + 1; }
    let B: i64 = ad_wblock(1);
    ad_bzero(B, 1);
    ad_init_note(W, 4, 4);          # ← 训练前记账：4 个权重全负
    let y: i64 = ad_vrelu(ad_vadd(ad_matmul(W, x, 1, 4), B, 1), 1);
    let t: i64 = ad_block(1);
    ad_set(t, 65536);
    let L: i64 = ad_mse_half(y, t, 1);
    ad_backward(L);

    print("-- 训练前的审计（应报初始化风险）--\n");
    let n: i64 = ad_audit();
    print("问题数 = "); print_i64(n); print("\n");
    if n < 1 { fail = fail + 1; print("  ✗ 审计应报出初始化风险\n"); }
    else { print("  ✓ 审计在训练前就报出了风险\n"); }

    # ---- 4) 反向验证：符号平衡后审计不报初始化风险 ----
    nn_srand(555);
    ad_reset();
    ad_audit_reset();
    let x2: i64 = ad_block(4);
    i = 0;
    while i < 4 { ad_set(x2 + i, 65536); i = i + 1; }
    let W2: i64 = ad_wblock(4);
    ad_winit_he(W2, 4, 4);          # ← 自动符号平衡 + 记账
    let B2: i64 = ad_wblock(1);
    ad_bzero(B2, 1);
    let y2: i64 = ad_vrelu(ad_vadd(ad_matmul(W2, x2, 1, 4), B2, 1), 1);
    let t2: i64 = ad_block(1);
    ad_set(t2, 65536);
    let L2: i64 = ad_mse_half(y2, t2, 1);
    ad_backward(L2);
    let g2: i64 = load64(&AD_GRAD + W2 * 8);
    print("-- 符号平衡后：W2 梯度 = "); print_i64(g2); print("\n");
    if ad_init_risk_count() != 0 { fail = fail + 1; print("  ✗ 应无初始化风险\n"); }
    else { print("  ✓ 无初始化风险\n"); }

    # ---- 5) ad_audit_reset 应清零 ----
    ad_audit_reset();
    let c5: i64 = ad_init_risk_count();
    print("reset 后累计 = "); print_i64(c5); print("\n");
    if c5 != 0 { fail = fail + 1; print("  ✗ reset 应清零\n"); }
    else { print("  ✓ reset 清零\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("init_audit: ALL PASS\n"); return 0; }
    return 1;
}
