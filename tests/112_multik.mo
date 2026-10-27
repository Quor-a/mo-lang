# 112 —— 多级 checkpointing：RAM / SSD / 网络三级容量分配（1.85）
# expect: 0
#
# 概念来源：Stumm & Walther 2009, SIAM J. Sci. Comput. 31(3), 1946–1967
#   （该论文的**主体是多级**；1.84 只做了两级）
#
# 🔴 多级有价值的**前提**是中间级容量有限：
#      level 0  RAM  容量 c0   IO 代价 0
#      level 1  SSD  容量 s1   IO 代价 w1
#      level 2  网络  容量 ∞    IO 代价 w2 > w1
#    便宜的 SSD 装不下时，溢出的快照才落到网络。
#    若所有非 RAM 级都无限，只用最便宜那级就够，多级毫无意义 —— 这条写成断言。
#
# 验证：
#   1) 三级 ≤ 两级 ≤ 一级（SSD 是网络的便宜替代）
#   2) s1 = 0 时三级实现退化为两级（不依赖于"是不是真的有第三级"）
#   3) DP 预测 == 实测（IO 计数与重算步数都对得上）
#   4) 各配置梯度与完整反向逐值一致
import "autodiff.mo";

var GR: [512] i64 = 0;

fn build(n: i64) -> i64 {
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

# 跑一个配置，打印并返回实测总代价；梯度不一致或 err != 0 时累加 fail
fn run1(c0: i64, s1: i64, w1: i64, w2: i64, tag: ptr) -> i64 {
    let l: i64 = 0;
    let bad: i64 = 0;
    let net: i64 = 0;
    let n: i64 = 0;
    let a0: i64 = 0;
    let a1: i64 = 0;
    let fail: i64 = 0;
    ad_reset();
    l = build(24);
    ad_mk_cfg(c0, s1, w1, w2);
    ad_backward_multik(l);
    bad = cmp_ref();
    n = ad_mk_n();
    a0 = ad_mk_a0();
    a1 = ad_mk_a1();
    net = n - a0 - a1;
    print("  "); print(tag); print(": N="); print_i64(n);
    print(" a0="); print_i64(a0);
    print(" a1="); print_i64(a1);
    print(" IO_ssd="); print_i64(ad_mk_io1());
    print(" IO_net="); print_i64(ad_mk_io2());
    print(" 重算="); print_i64(ad_recompute_count());
    print(" 预测="); print_i64(ad_mk_time());
    print(" 实测="); print_i64(ad_mk_total());
    print(" 不一致="); print_i64(bad);
    print(" err="); print_i64(ad_ckpt_err());
    print("\n");
    if bad != 0 { fail = fail + 1; print("  ✗ 梯度不一致\n"); }
    if ad_ckpt_err() != 0 { fail = fail + 1; print("  ✗ ckpt err\n"); }
    if ad_mk_total() != ad_mk_time() { fail = fail + 1; print("  ✗ DP 与实测不符\n"); }
    if ad_mk_io1() != 2 * a1 { fail = fail + 1; print("  ✗ SSD IO 次数不符\n"); }
    if ad_mk_io2() != 2 * net { fail = fail + 1; print("  ✗ 网络 IO 次数不符（σ_0 副本？）\n"); }
    return fail;
}

fn main() -> i64 {
    print("=== 多级 checkpointing（RAM / SSD / 网络）===\n");
    let fail: i64 = 0;
    let l: i64 = 0;
    let c1: i64 = 0;
    let c2: i64 = 0;
    let c3: i64 = 0;
    let c3b: i64 = 0;
    let nz: i64 = 0;
    let j: i64 = 0;

    ad_reset();
    l = build(24);
    ad_backward(l);
    save_ref();
    print("tape 步数 = "); print_i64(ad_ntape()); print("\n\n");
    # 参考梯度必须非全零：24 层后 sigmoid 若饱和，梯度会全 0，
    # 那后面所有「逐值一致」的比较都变成空转
    while j < AD_N {
        if load64(&GR + j * 8) != 0 { nz = nz + 1; }
        j = j + 1;
    }
    print("参考梯度非零个数 = "); print_i64(nz); print("\n");
    if nz < 10 { fail = fail + 1; print("✗ 梯度几乎全零（饱和），本测试无意义\n"); }

    print("-- 基线：只有 RAM（网络贵到不可能用）--\n");
    fail = fail + run1(4, 0, 1, 1000000, "一级(纯RAM)");
    c1 = ad_mk_total();

    print("\n-- 二级：RAM + 网络（w2=4）--\n");
    fail = fail + run1(4, 0, 1, 4, "二级(RAM+网络)");
    c2 = ad_mk_total();

    print("\n-- 三级：SSD 容量仅 2，装不下的溢出到网络（w1=1 w2=4）--\n");
    fail = fail + run1(4, 2, 1, 4, "三级(s1=2溢出)");
    c3 = ad_mk_total();
    # 溢出必须真的发生：SSD 用满 2 个，且网络 IO > 0
    if ad_mk_a1() != 2 { fail = fail + 1; print("  ✗ SSD 未用满\n"); }
    if ad_mk_io2() == 0 { fail = fail + 1; print("  ✗ 没有溢出到网络，三级的核心场景没测到\n"); }
    else { print("  ✓ 溢出发生：SSD 用满 2 个，其余走网络\n"); }

    print("\n-- 三级：SSD 容量放大到 8 --\n");
    fail = fail + run1(4, 8, 1, 4, "三级(s1=8)");
    c3b = ad_mk_total();

    print("\n-- 单调性：三级(s1=8) ≤ 三级(s1=2) ≤ 二级 ≤ 一级 --\n");
    print("  一级="); print_i64(c1);
    print("  二级="); print_i64(c2);
    print("  三级s1=2="); print_i64(c3);
    print("  三级s1=8="); print_i64(c3b); print("\n");
    if c2 > c1 { fail = fail + 1; print("  ✗ 二级劣于一级\n"); }
    if c3 > c2 { fail = fail + 1; print("  ✗ 三级劣于二级\n"); }
    if c3b > c3 { fail = fail + 1; print("  ✗ SSD 容量变大反而更差\n"); }

    print("\n-- s1=0 时三级实现应退化为两级 --\n");
    ad_reset();
    l = build(24);
    ad_mk_cfg(4, 0, 1, 4);
    ad_backward_multik(l);
    print("  s1=0: a1="); print_i64(ad_mk_a1());
    print("  IO_ssd="); print_i64(ad_mk_io1());
    print("  总="); print_i64(ad_mk_total()); print("\n");
    if ad_mk_io1() != 0 { fail = fail + 1; print("  ✗ 无 SSD 却有 SSD IO\n"); }
    if ad_mk_total() != c2 { fail = fail + 1; print("  ✗ 与两级结果不同\n"); }
    if cmp_ref() != 0 { fail = fail + 1; print("  ✗ 梯度不一致\n"); }

    print("\n-- SSD 太贵时应自动退回（w1=16 > 网络w2=4 的性价比）--\n");
    ad_reset();
    l = build(24);
    ad_mk_cfg(4, 8, 16, 4);
    ad_backward_multik(l);
    print("  w1=16: a1="); print_i64(ad_mk_a1());
    print("  IO_ssd="); print_i64(ad_mk_io1());
    print("  总="); print_i64(ad_mk_total()); print("\n");
    if cmp_ref() != 0 { fail = fail + 1; print("  ✗ 梯度不一致\n"); }
    if ad_mk_io1() != 0 { fail = fail + 1; print("  ✗ SSD 更贵却仍被使用\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("multik: ALL PASS\n"); return 0; }
    return 1;
}
