# 113 —— 最优 Jacobian 累积：顶点消去序（1.86）
# expect: 0
#
# 概念来源：Griewank & Walther《Evaluating Derivatives》第 8 章；
#   Naumann (2008) "Optimal Jacobian accumulation is NP-complete"
#   —— 与稀疏 Cholesky 的 fill-in 最小化等价，NP-hard。
#
# 模型：顶点消去。消去 v 的代价 = |pred(v)|·|succ(v)|（块级用大小加权）。
#   拓扑序 = 前向模式；逆拓扑序 = 反向模式；其余 = 混合模式。
#
# 本测试的核心：等宽链（输入维度 ≈ 输出维度）上，混合序显著优于两端。
# 手工验算（m=8, k=6, n=8）：
#   拓扑序 = (k-1)·m + m·n = 5·8 + 64 = 104
#   逆序   = (k-1)·n + m·n = 5·8 + 64 = 104
#   混合   = 先消 a2..a5（各 1）+ a1（m）+ a6（m·n）= 4 + 8 + 64 = 76
import "autodiff.mo";

fn chain(m: i64, k: i64, n: i64) -> i64 {
    let i: i64 = 0;
    oa_reset(k + 2);
    oa_vsz(0, m);
    oa_in(0);
    i = 1;
    while i <= k { oa_vsz(i, 1); oa_edge(i, i - 1); i = i + 1; }
    oa_vsz(k + 1, n);
    oa_out(k + 1);
    oa_edge(k + 1, k);
    oa_snapshot();
    return 0;
}

# 真实 tape：6 层 MLP，标量 loss
fn mlp(n: i64) -> i64 {
    let w: i64 = ad_wblock(4);
    let h: i64 = ad_block(2);
    let nx: i64 = 0;
    let nb: i64 = 0;
    let i: i64 = 0;
    let t: i64 = 0;
    let l: i64 = 0;
    ad_set(w + 0, 16384);
    ad_set(w + 1, 0 - 8192);
    ad_set(w + 2, 8192);
    ad_set(w + 3, 24576);
    ad_set(h + 0, 131072);
    ad_set(h + 1, 0 - 65536);
    while i < n {
        nx = ad_matmul(w, h, 2, 2);
        nb = ad_vsig(nx, 2);
        h = nb;
        i = i + 1;
    }
    t = ad_block(2);
    ad_set(t + 0, 65536);
    ad_set(t + 1, 0);
    l = ad_mse(h, t, 2);
    return l;
}

fn main() -> i64 {
    print("=== 最优 Jacobian 累积：顶点消去序 ===\n\n");
    let fail: i64 = 0;
    let f: i64 = 0;
    let r: i64 = 0;
    let g: i64 = 0;
    let b: i64 = 0;
    let mn: i64 = 0;
    let l: i64 = 0;

    # ---- 1. 手工验算的绝对值（最关键：程序输出必须等于手算）----
    print("-- 等宽链 m=8 k=6 n=8（手算 104 / 104 / 76）--\n");
    chain(8, 6, 8);
    f = oa_run(0);
    r = oa_run(1);
    g = oa_run(2);
    b = oa_exhaustive();
    print("  拓扑序(前向)="); print_i64(f); print("\n");
    print("  逆序(反向)  ="); print_i64(r); print("\n");
    print("  贪心最小代价="); print_i64(g); print("\n");
    print("  穷举最优    ="); print_i64(b);
    print(" （枚举 "); print_i64(oa_nperm()); print(" 个排列）\n");
    if f != 104 { fail = fail + 1; print("  ✗ 前向应为 104\n"); }
    if r != 104 { fail = fail + 1; print("  ✗ 反向应为 104\n"); }
    if g != 76  { fail = fail + 1; print("  ✗ 混合应为 76\n"); }
    if b != 76  { fail = fail + 1; print("  ✗ 穷举最优应为 76\n"); }
    if oa_nperm() != 720 { fail = fail + 1; print("  ✗ 应枚举 720 个排列\n"); }
    # 核心结论：等宽时混合严格优于两端
    if g >= f { fail = fail + 1; print("  ✗ 混合未严格优于前向\n"); }
    if b >= f { fail = fail + 1; print("  ✗ 最优未严格优于两端\n"); }

    # ---- 2. 三种形态 ----
    print("\n-- 输入宽（m=16 n=1）：反向应最优 --\n");
    chain(16, 6, 1);
    f = oa_run(0); r = oa_run(1); g = oa_run(2); b = oa_exhaustive();
    print("  前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print(" 最优="); print_i64(b); print("\n");
    if r >= f { fail = fail + 1; print("  ✗ 输入宽时反向应优于前向\n"); }
    if g > r { fail = fail + 1; print("  ✗ 贪心不应劣于反向\n"); }
    if b > r { fail = fail + 1; print("  ✗ 最优不应劣于反向\n"); }

    print("\n-- 输出宽（m=1 n=16）：前向应最优 --\n");
    chain(1, 6, 16);
    f = oa_run(0); r = oa_run(1); g = oa_run(2); b = oa_exhaustive();
    print("  前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print(" 最优="); print_i64(b); print("\n");
    if f >= r { fail = fail + 1; print("  ✗ 输出宽时前向应优于反向\n"); }
    if g > f { fail = fail + 1; print("  ✗ 贪心不应劣于前向\n"); }
    if b > f { fail = fail + 1; print("  ✗ 最优不应劣于前向\n"); }

    print("\n-- 等宽（m=4 n=4）：混合应严格最优 --\n");
    chain(4, 6, 4);
    f = oa_run(0); r = oa_run(1); g = oa_run(2); b = oa_exhaustive();
    print("  前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print(" 最优="); print_i64(b); print("\n");
    if g >= f { fail = fail + 1; print("  ✗ 等宽时混合应严格优于两端\n"); }

    # ---- 3. 通用不变量：最优 ≤ 贪心，且都不劣于两端 ----
    print("\n-- 通用不变量（多组参数）--\n");
    chain(8, 3, 8);
    f = oa_run(0); r = oa_run(1); g = oa_run(2); b = oa_exhaustive();
    mn = f; if r < mn { mn = r; }
    print("  k=3: 前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print(" 最优="); print_i64(b); print("\n");
    if b > mn { fail = fail + 1; print("  ✗ 最优劣于两端\n"); }
    if g < b { fail = fail + 1; print("  ✗ 贪心优于穷举最优，不可能\n"); }
    chain(8, 7, 8);
    f = oa_run(0); r = oa_run(1); g = oa_run(2); b = oa_exhaustive();
    mn = f; if r < mn { mn = r; }
    print("  k=7: 前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print(" 最优="); print_i64(b); print("\n");
    if b > mn { fail = fail + 1; print("  ✗ 最优劣于两端\n"); }
    if g < b { fail = fail + 1; print("  ✗ 贪心优于穷举最优，不可能\n"); }

    # ---- 4. 真实 tape：标量 loss ⇒ 反向最优（模型与实际一致）----
    print("\n-- 真实 tape（6 层 MLP，标量 loss）--\n");
    ad_reset();
    l = mlp(6);
    oa_build();
    print("  块数="); print_i64(oa_nv()); print(" err="); print_i64(oa_err()); print("\n");
    if oa_nv() != 16 { fail = fail + 1; print("  ✗ 应为 16 个块\n"); }
    f = oa_run(0); r = oa_run(1); g = oa_run(2);
    print("  前向="); print_i64(f); print(" 反向="); print_i64(r);
    print(" 贪心="); print_i64(g); print("\n");
    # 标量 loss ⇒ 输出维度 1 << 输入维度，反向必须最优
    if r >= f { fail = fail + 1; print("  ✗ 标量 loss 时反向应最优（模型与实际不符）\n"); }
    if g < r { fail = fail + 1; print("  ✗ 贪心优于反向，与穷举结果矛盾\n"); }
    # 梯度仍然正确（改动不得破坏已有反向）
    ad_backward(l);
    print("  w0 梯度="); print_i64(ad_grad(0)); print("（非 0 表示反向仍正确）\n");
    if ad_grad(0) == 0 { fail = fail + 1; print("  ✗ 反向梯度为 0\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("optjac: ALL PASS\n"); return 0; }
    return 1;
}
