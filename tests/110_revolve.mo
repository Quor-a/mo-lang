# 110 —— Revolve 最优 checkpointing（1.83）
# expect: 0
#
# 概念来源：Griewank & Walther 2000, Algorithm 799: Revolve
#   给定 l 步与 c 个快照，求重算次数最少的反向调度。
#
# 本测试同时验证两件事：
#   1) 正确性：任何调度下的梯度，必须与不 checkpoint 的完整反向**逐值一致**
#   2) 最优性：在同一内存模型下，Revolve 应不多于均匀分段
import "autodiff.mo";

var GR:  [512] i64 = 0;
var RC2: i64 = 0;
var RC3: i64 = 0;

# 8 层 2→2 全连接 + sigmoid，最后接 MSE  ⇒ tape 17 步
fn build(n: i64) -> i64 {
    let w: i64 = ad_wblock(4);
    let h: i64 = ad_block(2);
    let nx: i64 = 0;
    let nb: i64 = 0;
    let i: i64 = 0;
    let t: i64 = 0;
    let l: i64 = 0;
    ad_set(w + 0, 65536);
    ad_set(w + 1, 0 - 32768);
    ad_set(w + 2, 32768);
    ad_set(w + 3, 98304);
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

fn save_ref() -> i64 {
    let i: i64 = 0;
    while i < AD_N { store64(&GR + i * 8, load64(&AD_GRAD + i * 8)); i = i + 1; }
    return 0;
}

fn cmp_ref() -> i64 {
    let i: i64 = 0;
    let bad: i64 = 0;
    while i < AD_N {
        if load64(&AD_GRAD + i * 8) != load64(&GR + i * 8) { bad = bad + 1; }
        i = i + 1;
    }
    return bad;
}

fn main() -> i64 {
    print("=== Revolve 最优 checkpointing ===\n");
    let fail: i64 = 0;
    let l: i64 = 0;
    let bad: i64 = 0;
    let c: i64 = 0;
    let rc: i64 = 0;
    let exp: i64 = 0;
    let prev: i64 = 0;
    let rcu: i64 = 0;

    # ---- 基准：完整反向（保存全部中间值，重算 0 次）----
    ad_reset();
    l = build(8);
    ad_backward(l);
    save_ref();
    print("tape 步数 = "); print_i64(ad_ntape()); print("\n");

    # ---- Revolve：内存只够 c 个快照 + 1 个当前状态 ----
    print("\n-- Revolve --\n");
    c = 0;
    prev = 0 - 1;
    while c <= 3 {
        ad_reset();
        l = build(8);
        ad_backward_revolve(l, c);
        bad = cmp_ref();
        rc = ad_recompute_count();
        exp = ad_rev_topcost(ad_ntape(), c);
        print("  c="); print_i64(c);
        print("  重算="); print_i64(rc);
        print("  DP="); print_i64(exp);
        print("  不一致="); print_i64(bad);
        print("  err="); print_i64(ad_ckpt_err());
        print("\n");
        if bad != 0 { fail = fail + 1; }
        if ad_ckpt_err() != 0 { fail = fail + 1; }
        if rc != exp { fail = fail + 1; }
        # 同槽数下不得劣于均匀分段（j=c 是 Revolve 的特例，故这是硬下界）
        ad_reset();
        l = build(8);
        ad_backward_uniform_tight(l, c + 1);
        rcu = ad_recompute_count();
        if rc > rcu { fail = fail + 1; print("  ✗ 劣于均匀 "); print_i64(rcu); print("\n"); }
        if prev >= 0 { if rc > prev { fail = fail + 1; } }
        prev = rc;
        if c == 2 { RC2 = rc; }
        c = c + 1;
    }

    # ---- 均匀分段 + 逐层重算：与 Revolve 同一内存模型 ----
    print("\n-- 均匀分段 + 逐层重算（同内存模型）--\n");
    c = 2;
    while c <= 5 {
        ad_reset();
        l = build(8);
        ad_backward_uniform_tight(l, c);
        bad = cmp_ref();
        rc = ad_recompute_count();
        print("  k="); print_i64(c);
        print("  重算="); print_i64(rc);
        print("  不一致="); print_i64(bad);
        print("\n");
        if bad != 0 { fail = fail + 1; }
        if c == 3 { RC3 = rc; }
        c = c + 1;
    }

    # ---- 均匀分段 + 段内保留（PyTorch 模型）----
    print("\n-- 均匀分段 + 段内保留（PyTorch 模型）--\n");
    c = 2;
    while c <= 5 {
        ad_reset();
        l = build(8);
        ad_backward_uniform(l, c);
        bad = cmp_ref();
        rc = ad_recompute_count();
        print("  k="); print_i64(c);
        print("  重算="); print_i64(rc);
        print("  不一致="); print_i64(bad);
        print("\n");
        if bad != 0 { fail = fail + 1; }
        c = c + 1;
    }

    # ---- 同样 2 个额外快照槽下的正面对比 ----
    print("\n同用 2 个额外快照槽：Revolve=" ); print_i64(RC2);
    print("  均匀逐层="); print_i64(RC3); print("\n");
    if RC2 > RC3 { fail = fail + 1; print("  ✗ Revolve 未优于均匀分段\n"); }
    else { print("  ✓ Revolve 更省\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("revolve: ALL PASS\n"); return 0; }
    return 1;
}
