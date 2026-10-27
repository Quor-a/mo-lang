# 107 —— 有限差分：点积检验的第三方参照（1.79）
#
# 来源：arXiv:2305.07546
#   "the dot product test can be modified by replacing forward mode AD with
#    finite differences... allowing direct debugging of reverse mode AD"
#
# 🔴 为什么需要它：1.78 变异 B 实证了——反向与前向**同步**犯同样的错时
#    ψ_f = ψ_r，点积检验**通过**，但两者都错。只有与函数值对照的 FD 能发现。
#    PyTorch 的 gradcheck 正是这么做的。
import "autodiff.mo";
import "assert.mo";

# 🔴 两个必须遵守的规则（1.79 各踩过一次）：
#   1) 输入/权重**建一次**、槽号存全局；前向函数只引用不创建。
#      否则重算得到完全相同的图，ψ_fd 恒为 0。
#   2) build() 返回的是**槽号**，重算会覆盖同一槽。
#      所以 FD 必须立刻取 ad_val(...)，不能存槽号再读。
var GX: i64 = 0;
var GW: i64 = 0;

fn build_chain() -> i64 {
    let y: i64 = ad_mul(GW, GX);
    let s: i64 = ad_sigmoid(y);
    let L: i64 = ad_mul(s, s);
    return L;
}

var GA: i64 = 0;
var GB: i64 = 0;
var GT: i64 = 0;

fn build_mseh() -> i64 {
    let s1: i64 = ad_add(GA, GB);
    let sm: i64 = ad_sigmoid(s1);
    let L: i64 = ad_mse_half(sm, GT, 1);
    return L;
}

fn build_mse() -> i64 {
    let s1: i64 = ad_add(GA, GB);
    let sm: i64 = ad_sigmoid(s1);
    let L: i64 = ad_mse(sm, GT, 1);
    return L;
}

fn build_add() -> i64 {
    let s1: i64 = ad_add(GA, GB);
    let sm: i64 = ad_sigmoid(s1);
    let L: i64 = ad_mul(sm, sm);
    return L;
}

fn main() -> i64 {
    print("=== 有限差分三方对照 ===\n");
    let fail: i64 = 0;

    # ---- 1) 标量链：FD vs 前向 vs 反向 ----
    print("-- 链 w*x → sigmoid → 平方 --\n");
    ad_reset();
    ad_fseed_reset();
    GX = ad_weight(49152);
    GW = ad_weight(32768);
    ad_fd_mark();
    let L1: i64 = build_chain();
    ad_fseed(GX, 16384);
    ad_fseed(GW, 8192);
    ad_backward(L1);
    ad_forward();
    ad_dot_test(L1);

    ad_fd_save();
    let h: i64 = 65536 / 64;
    ad_fd_perturb(h, 1);
    AD_MODE = 1;
    let lp: i64 = ad_val(build_chain());     # ← 立刻取值
    ad_fd_perturb(h, 0 - 1);
    let lm: i64 = ad_val(build_chain());
    ad_fd_restore();
    AD_MODE = 0;
    let psi1: i64 = ad_fd_psi(lp, lm, h);
    if ad_fd_compare(L1, psi1) != 0 { fail = fail + 1; }
    else { print("  ✓ 三方一致\n"); }

    # ---- 1b) 步长扫描（仍在链 1 的快照上）----
    # 论文图 1：步长在截断误差（h 大）与舍入误差（h 小）之间权衡。
    # 定点下"舍入"是量化：h 太小 → (f+ − f−) 被抹成 0 或低位噪声。
    print("-- 步长扫描（链 1）--\n");
    let hh: i64 = 65536 / 4;        # 0.25 起步
    let sc: i64 = 0;
    while sc < 9 {
        ad_fd_perturb(hh, 1);
        AD_MODE = 1;
        let p1: i64 = ad_val(build_chain());
        ad_fd_perturb(hh, 0 - 1);
        let m1: i64 = ad_val(build_chain());
        let psih: i64 = ad_fd_psi(p1, m1, hh);
        print("  h="); print_i64(hh); print("  ψ_fd="); print_i64(psih); print("\n");
        hh = hh / 2;
        sc = sc + 1;
    }
    print("  （参考 ψ_forward=4104）\n");
    AD_MODE = 0;
    ad_fd_restore();

    # ---- 2) 加法链 ----
    print("-- 链 (a+b) → sigmoid → 平方 --\n");
    ad_reset();
    ad_fseed_reset();
    GA = ad_weight(40000);
    GB = ad_weight(20000);
    ad_fd_mark();
    let L2: i64 = build_add();
    ad_fseed(GA, 12000);
    ad_fseed(GB, 7000);
    ad_backward(L2);
    ad_forward();
    ad_dot_test(L2);
    ad_fd_save();
    ad_fd_perturb(h, 1);
    AD_MODE = 1;
    let lp2: i64 = ad_val(build_add());
    ad_fd_perturb(h, 0 - 1);
    let lm2: i64 = ad_val(build_add());
    ad_fd_restore();
    AD_MODE = 0;
    let psi2: i64 = ad_fd_psi(lp2, lm2, h);
    if ad_fd_compare(L2, psi2) != 0 { fail = fail + 1; }
    else { print("  ✓ 三方一致\n"); }

    # ---- 4) 🔴 核心：FD 能抓到点积检验**漏掉**的错误 ----
    #
    # ad_mse_half 是 1.71 记录的一个**已知不自洽**：
    #   报告的 loss 值 = Σe²/n
    #   反向用的梯度  = (y−t)/n   （对应 ½Σe²）
    # 于是真实导数是反向梯度的 **2 倍**。
    #
    # 前向模式是照抄反向的局部导数写的，所以：
    #   ψ_forward = ψ_reverse      → 点积检验 **通过**
    #   ψ_fd      = 2 × ψ_reverse  → **只有 FD 抓得到**
    #
    # 这正是 arXiv:2305.07546 的核心警告：两种模式一致地犯同样的错时，
    # 点积检验会放行。本项把这个性质**固化**下来。
    print("-- ad_mse_half：点积检验通过，但 FD 抓到 2 倍偏差 --\n");
    ad_reset();
    ad_fseed_reset();
    GA = ad_weight(40000);
    GB = ad_weight(20000);
    GT = ad_block(1);
    ad_set(GT, 32768);
    ad_fd_mark();
    let L4: i64 = build_mseh();
    ad_fseed(GA, 12000);
    ad_fseed(GB, 7000);
    ad_backward(L4);
    ad_forward();
    let dp4: i64 = ad_dot_test(L4);
    if dp4 != 0 { fail = fail + 1; print("  ✗ 点积检验竟失败（性质变了）\n"); }
    else { print("  ✓ 点积检验确实**通过**（两种模式同步错）\n"); }

    # loss 值小（Σe² 量级 0.008）→ 用更大的 h 压低量化误差占比
    let h2: i64 = 65536 / 8;
    ad_fd_save();
    ad_fd_perturb(h2, 1);
    AD_MODE = 1;
    let lp4: i64 = ad_val(build_mseh());
    ad_fd_perturb(h2, 0 - 1);
    let lm4: i64 = ad_val(build_mseh());
    ad_fd_restore();
    AD_MODE = 0;
    let psi4: i64 = ad_fd_psi(lp4, lm4, h2);
    let bad4: i64 = ad_fd_compare(L4, psi4);
    if bad4 == 0 { fail = fail + 1; print("  ✗ FD 没抓到（不该发生）\n"); }
    else {
        # 且偏差方向必须是**约 2 倍**
        let r: i64 = AD_DOT_R;
        if r < 0 { r = 0 - r; }
        let two: i64 = r + r;
        let dd: i64 = psi4 - two;
        if dd < 0 { dd = 0 - dd; }
        print("  ψ_fd="); print_i64(psi4);
        print("  2×ψ_reverse="); print_i64(two); print("\n");
        if dd > r / 8 { fail = fail + 1; print("  ✗ 偏差不是 2 倍\n"); }
        else { print("  ✓ FD 抓到，且偏差正是 2 倍\n"); }
    }

    # ---- 5) 对照：自洽的 ad_mse 三方一致 ----
    print("-- ad_mse（自洽版）：三方一致 --\n");
    ad_reset();
    ad_fseed_reset();
    GA = ad_weight(40000);
    GB = ad_weight(20000);
    GT = ad_block(1);
    ad_set(GT, 32768);
    ad_fd_mark();
    let L5: i64 = build_mse();
    ad_fseed(GA, 12000);
    ad_fseed(GB, 7000);
    ad_backward(L5);
    ad_forward();
    ad_dot_test(L5);
    ad_fd_save();
    ad_fd_perturb(h2, 1);
    AD_MODE = 1;
    let lp5: i64 = ad_val(build_mse());
    ad_fd_perturb(h2, 0 - 1);
    let lm5: i64 = ad_val(build_mse());
    ad_fd_restore();
    AD_MODE = 0;
    if ad_fd_compare(L5, ad_fd_psi(lp5, lm5, h2)) != 0 { fail = fail + 1; }
    else { print("  ✓ 三方一致\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("fdcheck: ALL PASS\n"); return 0; }
    return 1;
}
