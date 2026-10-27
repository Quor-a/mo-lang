# 106 —— 点积检验：前向模式 vs 反向模式（1.78）
#
# 来源：arXiv:2305.07546《Understanding Automatic Differentiation Pitfalls》
#   ψ = x̄·ẋ = ȳ·ẏ
#   取 ȳ = e_loss ⇒ ψ_forward = dot[loss]，ψ_reverse = Σ grad[i]·seed[i]
#   两者必须相等。
import "autodiff.mo";
import "assert.mo";

fn main() -> i64 {
    print("=== 点积检验（前向 vs 反向）===\n");
    let fail: i64 = 0;

    # ---- 1) 简单标量链：y = w*x，L = y*y ----
    ad_reset();
    ad_fseed_reset();
    let x: i64 = ad_weight(49152);      # 0.75
    let w: i64 = ad_weight(32768);      # 0.5
    let y: i64 = ad_mul(w, x);
    let L: i64 = ad_mul(y, y);
    ad_fseed(x, 16384);                 # ẋ = 0.25
    ad_fseed(w, 8192);                  # ẇ = 0.125
    ad_backward(L);
    ad_forward();
    print("-- y=w*x, L=y*y --\n");
    let r1: i64 = ad_dot_test(L);
    if r1 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过\n"); }

    # ---- 2) 混合算子链：加、减、sigmoid ----
    ad_reset();
    ad_fseed_reset();
    let a: i64 = ad_weight(40000);
    let b: i64 = ad_weight(20000);
    let s1: i64 = ad_add(a, b);
    let s2: i64 = ad_sub(s1, b);
    let sg: i64 = ad_sigmoid(s2);
    let L2: i64 = ad_mul(sg, sg);
    ad_fseed(a, 12000);
    ad_fseed(b, 7000);
    ad_backward(L2);
    ad_forward();
    print("-- 含 sigmoid 的链 --\n");
    let r2: i64 = ad_dot_test(L2);
    if r2 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过\n"); }

    # ---- 3) 块级：matmul + vadd_b + vsig + mse_half ----
    ad_reset();
    ad_fseed_reset();
    let inp: i64 = ad_block(4);
    let i: i64 = 0;
    while i < 4 { ad_set(inp + i, 32768); i = i + 1; }
    let W: i64 = ad_wblock(8);          # 2×4
    ad_wdense_init(W, 2, 4);
    let h: i64 = ad_matmul(W, inp, 2, 4);
    let B: i64 = ad_wblock(2);
    ad_bzero(B, 2);
    let z: i64 = ad_vadd_bcast(h, B, 2, 1);
    let act: i64 = ad_vsig(z, 2);
    let tgt: i64 = ad_block(2);
    ad_set(tgt, 65536);
    ad_set(tgt + 1, 0);
    let L3: i64 = ad_mse_half(act, tgt, 2);
    i = 0;
    while i < 8 { ad_fseed(W + i, 5000 + i * 137); i = i + 1; }
    ad_fseed(inp, 3000);
    ad_backward(L3);
    ad_forward();
    print("-- matmul+vadd_b+vsig+mse_half --\n");
    let r3: i64 = ad_dot_test(L3);
    if r3 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过\n"); }

    # ---- 4) relu / leaky relu（非光滑点）----
    ad_reset();
    ad_fseed_reset();
    let u: i64 = ad_weight(30000);
    let v: i64 = ad_weight(0 - 20000);      # 负 → relu 死
    let ru: i64 = ad_relu(u);
    let rv: i64 = ad_lrelu(v);
    let sm: i64 = ad_add(ru, rv);
    let L4: i64 = ad_mul(sm, sm);
    ad_fseed(u, 9000);
    ad_fseed(v, 9000);
    ad_backward(L4);
    ad_forward();
    print("-- relu(正) + lrelu(负) --\n");
    let r4: i64 = ad_dot_test(L4);
    if r4 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过（leaky 分支也一致）\n"); }

    # ---- 5) 多种子一致：随机方向 ----
    # 论文：高维参数不要逐个检查，用随机方向。这里换几组种子看是否都一致
    let bad: i64 = 0;
    let t: i64 = 0;
    while t < 5 {
        ad_reset();
        ad_fseed_reset();
        let p: i64 = ad_weight(30000);
        let q: i64 = ad_weight(45000);
        let m: i64 = ad_mul(p, q);
        let sm2: i64 = ad_sigmoid(m);
        let L5: i64 = ad_mul(sm2, sm2);
        nn_srand(1000 + t * 13);
        ad_fseed(p, nn_rand_fp(32768));
        ad_fseed(q, nn_rand_fp(32768));
        ad_backward(L5);
        ad_forward();
        if ad_dot_test(L5) != 0 { bad = bad + 1; }
        t = t + 1;
    }
    print("-- 5 组随机方向 --\n");
    print("不一致次数 = "); print_i64(bad); print("\n");
    if bad != 0 { fail = fail + 1; print("  ✗ 有方向不一致\n"); }
    else { print("  ✓ 全部一致\n"); }

    # ---- 6) 真正的 CNN：conv_mc + vadd_bcast + pool_mc + gmax + matmul ----
    #    1.78 补齐了 CONVMC / POOLMC / SCE 等的前向规则，这里验证全链路
    ad_reset();
    ad_fseed_reset();
    let img: i64 = ad_block(64);            # 1 通道 8×8
    i = 0;
    while i < 64 {
        ad_set(img + i, nn_rand_fp(32768));
        i = i + 1;
    }
    let KW: i64 = ad_wblock(36);            # 1→4 通道 3×3
    ad_wconv_init(KW, 4, 1);
    let KB: i64 = ad_wblock(4);
    ad_bzero(KB, 4);
    let c1: i64 = ad_conv_mc(img, KW, 8, 8, 1, 4);
    let c2: i64 = ad_vadd_bcast(c1, KB, 4, 36);
    let rel: i64 = ad_vrelu(c2, 144);
    let pl: i64 = ad_pool_mc(rel, 4, 6, 6);
    let gm: i64 = ad_gmax_mc(pl, 4, 9);
    let FW: i64 = ad_wblock(8);             # 2×4
    ad_wdense_init(FW, 2, 4);
    let FB: i64 = ad_wblock(2);
    ad_bzero(FB, 2);
    let lg: i64 = ad_vadd(ad_matmul(FW, gm, 2, 4), FB, 2);
    let tg2: i64 = ad_block(2);
    ad_set(tg2, 65536);
    ad_set(tg2 + 1, 0);
    let L6: i64 = ad_mse_half(lg, tg2, 2);
    nn_srand(99999);
    i = 0;
    while i < 36 { ad_fseed(KW + i, nn_rand_fp(20000)); i = i + 1; }
    i = 0;
    while i < 8 { ad_fseed(FW + i, nn_rand_fp(20000)); i = i + 1; }
    ad_fseed(img, 11000);
    ad_backward(L6);
    ad_forward();
    print("-- 真 CNN（conv_mc→pool_mc→gmax→matmul→mse）--\n");
    let r6: i64 = ad_dot_test(L6);
    if r6 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过（卷积前向规则正确）\n"); }

    # ---- 7) SCE + 单通道 conv/pool ----
    ad_reset();
    ad_fseed_reset();
    let im2: i64 = ad_block(36);            # 6×6
    i = 0;
    while i < 36 { ad_set(im2 + i, nn_rand_fp(30000)); i = i + 1; }
    let k2: i64 = ad_wblock(9);
    ad_wconv_init(k2, 1, 1);
    let cv: i64 = ad_conv(im2, k2, 6, 6);
    let pv: i64 = ad_pool(cv, 4, 4);
    let f3: i64 = ad_wblock(8);             # 2×4
    ad_wdense_init(f3, 2, 4);
    let lg3: i64 = ad_matmul(f3, pv, 2, 4);
    let L7: i64 = ad_sce(lg3, 2, 1);
    nn_srand(24680);
    i = 0;
    while i < 9 { ad_fseed(k2 + i, nn_rand_fp(20000)); i = i + 1; }
    i = 0;
    while i < 8 { ad_fseed(f3 + i, nn_rand_fp(20000)); i = i + 1; }
    ad_backward(L7);
    ad_forward();
    print("-- conv(单通道)+pool+sce --\n");
    let r7: i64 = ad_dot_test(L7);
    if r7 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else { print("  ✓ 通过（含 softmax 归一化）\n"); }

    # ---- 8) 隔离测试：只播种 KW，img 不播种 ----
    #
    # 🔴 为什么要隔离：在完整 CNN（第 6 项）里做变异测试时，删掉 CONVMC
    #    前向的 dK·Inp 项后 ψ **完全不变** —— 因为 relu 把卷积输出的
    #    方向导数切成了 0，dK 项根本传不到 loss。
    #    结论：完整链路容易被 relu/pool 稀释，**必须隔离各项**才能证明
    #    检验真的覆盖了某个算子。
    #
    # 隔离设计：img 全正常数 + KW 全正 + 不播种 img ⇒ dInp 项 = 0，
    #           ψ 完全来自 dK·Inp。删掉 dK 项 ψ 应变为 0。
    ad_reset();
    ad_fseed_reset();
    let im3: i64 = ad_block(64);
    i = 0;
    while i < 64 { ad_set(im3 + i, 20000); i = i + 1; }
    let KW3: i64 = ad_wblock(36);
    i = 0;
    while i < 36 { ad_set(KW3 + i, 10000); i = i + 1; }
    let c3: i64 = ad_conv_mc(im3, KW3, 8, 8, 1, 4);
    let tg3: i64 = ad_block(144);
    i = 0;
    while i < 144 { ad_set(tg3 + i, 65536); i = i + 1; }
    let L8: i64 = ad_mse_half(c3, tg3, 144);
    i = 0;
    while i < 36 { ad_fseed(KW3 + i, 5000); i = i + 1; }
    ad_backward(L8);
    ad_forward();
    print("-- 隔离：只播种 KW（ψ 全来自 dK·Inp）--\n");
    let r8: i64 = ad_dot_test(L8);
    if r8 != 0 { fail = fail + 1; print("  ✗ 点积检验失败\n"); }
    else {
        # ψ 必须**显著非零**，否则说明 dK 项没传到 loss（测试空转）
        let av: i64 = ad_dot_f();
        if av < 0 { av = 0 - av; }
        print("  |ψ| = "); print_i64(av); print("\n");
        if av < 1000 { fail = fail + 1; print("  ✗ ψ 太小，dK 项没传到 loss\n"); }
        else { print("  ✓ 通过且 ψ 显著非零\n"); }
    }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("dotproduct: ALL PASS\n"); return 0; }
    return 1;
}
