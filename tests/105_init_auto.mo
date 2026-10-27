# 105 —— 分组自动推断：手工 ad_set 填的权重也能被检查（1.77）
#
# 1.76 的 ad_init_note 要用户传 nin。手工 ad_set 填权重（不走 ad_winit）
# 恰恰是最容易踩坑的场景，而那种情况下手动版根本不会被调用。
# 这里从 tape 结构推断 nin —— matmul 用 TXB(=nc)，conv_mc 用 ci*9。
import "autodiff.mo";
import "assert.mo";

fn main() -> i64 {
    print("=== 分组自动推断 ===\n");
    let fail: i64 = 0;

    # ---- 1) matmul 的 nin 推断：W[nr][nc]，nin = nc ----
    nn_srand(31337);
    ad_reset();
    ad_audit_reset();
    let x: i64 = ad_block(6);
    let i: i64 = 0;
    while i < 6 { ad_set(x + i, 65536); i = i + 1; }
    let W: i64 = ad_wblock(12);        # 2 × 6
    i = 0;
    while i < 12 { ad_set(W + i, nn_rand_fp(65536)); i = i + 1; }
    let y: i64 = ad_matmul(W, x, 2, 6);

    let nin: i64 = ad_infer_nin(W);
    print("matmul W(2x6) 推断 nin = "); print_i64(nin); print("\n");
    if nin != 6 { fail = fail + 1; print("  ✗ 应为 6\n"); }
    else { print("  ✓ nin = nc = 6\n"); }

    # ---- 2) conv_mc 的 nin 推断：ci*9（权重在 **b** 位）----
    nn_srand(4242);
    ad_reset();
    ad_audit_reset();
    let img: i64 = ad_block(64);       # 8×8
    i = 0;
    while i < 64 { ad_set(img + i, 0); i = i + 1; }
    let KW: i64 = ad_wblock(36);       # 1→4 通道，3×3
    i = 0;
    while i < 36 { ad_set(KW + i, nn_rand_fp(65536)); i = i + 1; }
    let c: i64 = ad_conv_mc(img, KW, 8, 8, 1, 4);

    let nin2: i64 = ad_infer_nin(KW);
    print("conv_mc K(1->4, 3x3) 推断 nin = "); print_i64(nin2); print("\n");
    if nin2 != 9 { fail = fail + 1; print("  ✗ 应为 ci*9 = 9\n"); }
    else { print("  ✓ nin = ci*9 = 9（权重在 b 位）\n"); }

    # ---- 3) 无法推断的槽应返回 -1 ----
    let lone: i64 = ad_block(4);
    let nin3: i64 = ad_infer_nin(lone);
    print("未参与任何 matmul/conv 的块推断 nin = "); print_i64(nin3); print("\n");
    if nin3 != 0 - 1 { fail = fail + 1; print("  ✗ 应为 -1\n"); }
    else { print("  ✓ 无法推断时返回 -1\n"); }

    # ---- 4) 手工填的**全负**权重：自动版应能检出 ----
    nn_srand(555);
    ad_reset();
    ad_audit_reset();
    let x2: i64 = ad_block(4);
    i = 0;
    while i < 4 { ad_set(x2 + i, 65536); i = i + 1; }
    let W2: i64 = ad_wblock(4);
    # 手工全负 —— 这正是 1.76 覆盖不到的场景
    i = 0;
    while i < 4 { ad_set(W2 + i, 0 - 30000); i = i + 1; }
    let y2: i64 = ad_matmul(W2, x2, 1, 4);

    print("-- 手工全负权重，ad_init_note_auto --\n");
    let b4: i64 = ad_init_note_auto(W2, 4);
    print("返回 = "); print_i64(b4); print("\n");
    if b4 != 1 { fail = fail + 1; print("  ✗ 应检出 1 个组\n"); }
    else { print("  ✓ 手工填的权重也被检出了\n"); }

    # ---- 5) ad_init_note_all：一次扫全图 ----
    nn_srand(666);
    ad_reset();
    ad_audit_reset();
    let a1: i64 = ad_block(4);
    i = 0;
    while i < 4 { ad_set(a1 + i, 65536); i = i + 1; }
    # 三层：W1(4x4 正常) → W2(1x4 全负)
    let W1: i64 = ad_wblock(16);
    ad_winit_he(W1, 16, 4);
    let h1: i64 = ad_matmul(W1, a1, 4, 4);
    let W2b: i64 = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(W2b + i, 0 - 30000); i = i + 1; }
    let o2: i64 = ad_matmul(W2b, h1, 1, 4);

    # 先清 SEE（ad_audit 会写它，这里独立用）
    i = 0;
    while i < 2048 { store64(&AD_AUD_SEE + i * 8, 0); i = i + 1; }
    AD_AUD_INITN = 0;
    let nc5: i64 = ad_init_note_all();
    print("ad_init_note_all 扫描的权重块数 = "); print_i64(nc5); print("\n");
    if nc5 != 2 { fail = fail + 1; print("  ✗ 应扫到 2 个权重块\n"); }
    else { print("  ✓ 扫到 2 个（W1, W2b）\n"); }
    let r5: i64 = ad_init_risk_count();
    print("其中符号一边倒的组数 = "); print_i64(r5); print("\n");
    # W1 已符号平衡 → 0；W2b 全负 → 4 组（nin=4, n=4 → ng=1 组）
    if r5 != 1 { fail = fail + 1; print("  ✗ W2b 全负应贡献 1 组\n"); }
    else { print("  ✓ W1 平衡(0) + W2b 全负(1)\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("init_auto: ALL PASS\n"); return 0; }
    return 1;
}
