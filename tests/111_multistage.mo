# 111 —— Multistage 两级 checkpointing（1.84）
# expect: 0
#
# 概念来源：Stumm & Walther 2009, "Multistage approaches for optimal
#   offline checkpointing", SIAM J. Sci. Comput. 31(3), 1946–1967
#
#   Revolve 假设所有快照同质；真实机器有 RAM 与磁盘两级。
#   把 1.83 发现的「顶层免费平铺」移到磁盘（容量无限、每次 IO 贵），
#   段内仍用 r 个 RAM 槽跑 Revolve。
#
# 验证三件事：
#   1) 磁盘往返：save→load 后 AD_VAL 逐槽一致
#   2) 正确性：任何 w 下梯度与完整反向逐值一致
#   3) 最优性：同 RAM 状态数下，Multistage 代价不高于纯 RAM Revolve；
#      w→∞ 时退化为 k=1（即纯 Revolve）
import "autodiff.mo";

var GR:   [512] i64 = 0;
var SNAP: [512] i64 = 0;

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
    print("=== Multistage 两级 checkpointing ===\n");
    let fail: i64 = 0;
    let l: i64 = 0;
    let bad: i64 = 0;
    let w: i64 = 0;
    let i: i64 = 0;
    let tms: i64 = 0;
    let trv: i64 = 0;
    let rcms: i64 = 0;

    # ---- 基准：完整反向（存全部中间值，重算 0）----
    ad_reset();
    l = build(8);
    ad_backward(l);
    save_ref();
    print("tape 步数 = "); print_i64(ad_ntape()); print("\n");

    # ---- 1) 磁盘往返一致性 ----
    print("\n-- 磁盘往返 --\n");
    ad_reset();
    l = build(8);
    i = 0;
    while i < AD_N { store64(&SNAP + i * 8, load64(&AD_VAL + i * 8)); i = i + 1; }
    ad_disk_save(7);
    # 故意破坏当前值，确认 load 真的把它覆盖回来
    i = 0;
    while i < AD_N { store64(&AD_VAL + i * 8, 0 - 999); i = i + 1; }
    ad_disk_load(7);
    bad = 0;
    i = 0;
    while i < AD_N {
        if load64(&AD_VAL + i * 8) != load64(&SNAP + i * 8) { bad = bad + 1; }
        i = i + 1;
    }
    print("  写="); print_i64(ad_ms_dw());
    print("  读="); print_i64(ad_ms_dr());
    print("  不一致="); print_i64(bad); print("\n");
    if bad != 0 { fail = fail + 1; print("  ✗ 磁盘往返丢数据\n"); }
    else { print("  ✓ 往返一致\n"); }

    # ---- 2) 各 w 下的正确性，并与纯 RAM Revolve 比代价 ----
    print("\n-- 与纯 RAM Revolve 对比（同为 r+1 个 RAM 状态）--\n");
    w = 1;
    while w <= 64 {
        ad_reset();
        l = build(8);
        ad_backward_multistage(l, 2, w);
        bad = cmp_ref();
        # 🔴 必须**立刻**取：下面 ad_backward_revolve 会把 AD_RC 覆盖掉
        rcms = ad_recompute_count();
        tms = ad_ms_time(ad_ntape(), 2, w);
        ad_reset();
        l = build(8);
        ad_backward_revolve(l, 2);
        trv = ad_recompute_count();
        print("  w="); print_i64(w);
        print("  N="); print_i64(ad_ms_n()); print("  j="); print_i64(ad_ms_j());
        print("  重算="); print_i64(rcms);
        print("  IO="); print_i64(ad_ms_dw() + ad_ms_dr());
        print("  Multistage="); print_i64(tms);
        print("  Revolve="); print_i64(trv);
        print("  不一致="); print_i64(bad);
        print("  err="); print_i64(ad_ckpt_err());
        print("\n");
        if bad != 0 { fail = fail + 1; }
        if ad_ckpt_err() != 0 { fail = fail + 1; }
        if tms > trv { fail = fail + 1; print("  ✗ 劣于纯 Revolve\n"); }
        w = w * 2;
    }

    # ---- 3) w 极大时应退化为 k=1（纯 Revolve）----
    print("\n-- w 极大 → 退化为纯 Revolve --\n");
    ad_reset();
    l = build(8);
    ad_backward_multistage(l, 2, 100000);
    print("  N="); print_i64(ad_ms_n()); print("  j="); print_i64(ad_ms_j());
    print("  重算="); print_i64(ad_recompute_count());
    print("  Revolve="); print_i64(trv); print("\n");
    # 退化判据：不用磁盘，且代价等于纯 RAM Revolve（具体 N/j 可有多个等价解）
    if ad_ms_io() != 0 { fail = fail + 1; print("  ✗ 应完全不用磁盘\n"); }
    else { print("  ✓ 退化为纯 RAM 方案（IO=0）\n"); }
    if ad_recompute_count() != trv { fail = fail + 1; print("  ✗ 应与纯 Revolve 同重算\n"); }
    if cmp_ref() != 0 { fail = fail + 1; }

    # ---- 4) w 小时应多分段 ----
    print("\n-- w 小 → 多分段 --\n");
    ad_reset();
    l = build(8);
    ad_backward_multistage(l, 2, 1);
    print("  w=1 时 N="); print_i64(ad_ms_n());
    print("  j="); print_i64(ad_ms_j());
    print("  IO="); print_i64(ad_ms_io()); print("\n");
    if ad_ms_io() == 0 { fail = fail + 1; print("  ✗ w 小时应用上磁盘\n"); }
    if cmp_ref() != 0 { fail = fail + 1; }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("multistage: ALL PASS\n"); return 0; }
    return 1;
}
