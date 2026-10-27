# expect: 0
# 145_sketch —— Bloom filter + Count-Min Sketch
#
# 判据分两类，这是本测试最要紧的设计：
#   ① **确定性**断言：Bloom 的假阴次数必须**恰好 0**；
#      CMS 的低估次数必须**恰好 0**。
#      这两条都是数学保证，不是"接近 0" —— 写成 == 0 才验得到。
#   ② **统计**断言：假阳率 / 误差上界对照闭式解，给区间不给定值。
#      期望一律**现算**（bloom_fp_theory / ε·N），不落仓库。
#
# 🔴 最关键的一条是「非空转守卫」：
#    CMS 的 query 取 **min over d 行**，所以只要 w 取得宽裕，
#    碰撞会被 min 消掉，误差恒为 0 —— 那时 "under==0"、
#    "maxerr ≤ ε·N" 全部**平凡成立**，25 项全绿却一条都没验到。
#    所以本测试特意取 w=20 < key 数 50，**逼出碰撞**，
#    并断言 nerr > 0（确实有 key 被碰撞影响）。

import "assert.mo";
import "bloom.mo";
import "cms.mo";
import "fmath.mo";

# ── 确定性 PRNG（xorshift64，不带库以免相互干扰）───────────
# ⚠️ 循环内不能声明 let（会累积栈帧），所以所有变量都在 main 顶部声明。
var SSEED: i64 = 0;
fn nx() -> i64 {
    SSEED = SSEED ^ (SSEED << 13);
    SSEED = SSEED ^ (SSEED >> 7);
    SSEED = SSEED ^ (SSEED << 17);
    if SSEED < 0 { SSEED = 0 - SSEED; }
    return SSEED;
}
fn nxr(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return nx() % n;
}

# ── 真实计数（CMS 的独立参照）─────────────────────────────
var TRU: [128] i64 = 0;

fn main() -> i64 {
    let i: i64 = 0;
    let ok: i64 = 0;
    let kk: i64 = 0;
    let q: i64 = 0;
    let e: i64 = 0;

    # ═══ Bloom：参数校验（负例）═════════════════════════════
    BLBAD = 0;
    let h0: i64 = bloom_new(0, 3);
    assert_eq("bloom m=0 rejected", h0, 0 - 1);
    assert_eq("bloom m=0 sets BLBAD", BLBAD, 1);

    BLBAD = 0;
    let h1: i64 = bloom_new(1000, 3);
    assert_eq("bloom m=1000 not pow2 rejected", h1, 0 - 1);
    assert_eq("bloom not-pow2 sets BLBAD", BLBAD, 1);

    # ═══ Bloom：永不假阴（确定性，核心保证）═════════════════
    let fa: i64 = bloom_new(1024, 3);
    let n: i64 = 200;
    i = 0;
    while i < n {
        bloom_add(fa, i + 1);
        i = i + 1;
    }
    let fn_: i64 = 0;
    i = 0;
    while i < n {
        if bloom_has(fa, i + 1) == 0 { fn_ = fn_ + 1; }
        i = i + 1;
    }
    assert_eq("bloom NO false negative", fn_, 0);

    # ═══ Bloom：空 filter 永不假阳（确定性）════════════════
    # 位数组全 0 ⟹ 任何查询必返回 0。不是"概率很小"，是**必然**。
    let fe: i64 = bloom_new(1024, 3);
    let fpe: i64 = 0;
    i = 0;
    while i < 2000 {
        if bloom_has(fe, 900000 + i) == 1 { fpe = fpe + 1; }
        i = i + 1;
    }
    assert_eq("bloom empty has NO false positive", fpe, 0);

    # ═══ Bloom：假阳率对照闭式解 p = (1−e^(−kn/m))^k ════════
    let trials: i64 = 20000;
    let fp3: i64 = 0;
    i = 0;
    while i < trials {
        if bloom_has(fa, 900000 + i) == 1 { fp3 = fp3 + 1; }
        i = i + 1;
    }
    let th3: f64 = bloom_fp_theory(200, 1024, 3) * f64(trials);
    ok = 0;
    if f64(fp3) >= th3 * 0.65 { if f64(fp3) <= th3 * 1.45 { ok = 1; } }
    assert_true("bloom fp rate matches closed form (k=3)", ok);

    # ═══ Bloom：最优 k 确实更优（k* = (m/n)ln2 ≈ 3.55 → 4）══
    let f1: i64 = bloom_new(1024, 1);
    let f4: i64 = bloom_new(1024, 4);
    i = 0;
    while i < n {
        bloom_add(f1, i + 1);
        bloom_add(f4, i + 1);
        i = i + 1;
    }
    let fp1: i64 = 0;
    let fp4: i64 = 0;
    i = 0;
    while i < trials {
        if bloom_has(f1, 900000 + i) == 1 { fp1 = fp1 + 1; }
        if bloom_has(f4, 900000 + i) == 1 { fp4 = fp4 + 1; }
        i = i + 1;
    }
    assert_true("bloom k=4 beats k=1", fp4 < fp1);
    let th1: f64 = bloom_fp_theory(200, 1024, 1) * f64(trials);
    ok = 0;
    if f64(fp1) >= th1 * 0.75 { if f64(fp1) <= th1 * 1.35 { ok = 1; } }
    assert_true("bloom k=1 matches closed form", ok);

    # ═══ Bloom：置位数对照 m(1−e^(−kn/m)) ═══════════════════
    let pc: i64 = bloom_count(f4);
    let expc: f64 = (1.0 - fm_exp(0.0 - f64(4) * 200.0 / 1024.0)) * 1024.0;
    ok = 0;
    if f64(pc) >= expc * 0.93 { if f64(pc) <= expc * 1.07 { ok = 1; } }
    assert_true("bloom popcount matches m(1-e^-kn/m)", ok);

    # ═══ Bloom：merge（逐位 OR）════════════════════════════
    let ma: i64 = bloom_new(1024, 3);
    let mb: i64 = bloom_new(1024, 3);
    i = 0;
    while i < 100 { bloom_add(ma, i + 1); i = i + 1; }
    i = 100;
    while i < 200 { bloom_add(mb, i + 1); i = i + 1; }
    assert_eq("bloom merge ok", bloom_merge(ma, mb), 0);
    let fnm: i64 = 0;
    i = 0;
    while i < 200 {
        if bloom_has(ma, i + 1) == 0 { fnm = fnm + 1; }
        i = i + 1;
    }
    assert_eq("bloom merge: NO false negative over A|B", fnm, 0);

    # ═══ CMS：参数校验（负例）═══════════════════════════════
    CMSBAD = 0;
    let c0: i64 = cms_new(0, 4);
    assert_eq("cms w=0 rejected", c0, 0 - 1);
    assert_eq("cms w=0 sets CMSBAD", CMSBAD, 1);

    # ═══ CMS：无碰撞时**精确**（确定性）═════════════════════
    let ce: i64 = cms_new(2048, 2);
    i = 0;
    while i < 10 { cms_add(ce, 7001, 1); i = i + 1; }
    i = 0;
    while i < 25 { cms_add(ce, 7002, 1); i = i + 1; }
    i = 0;
    while i < 7 { cms_add(ce, 7003, 1); i = i + 1; }
    assert_eq("cms exact when no collision (10)", cms_query(ce, 7001), 10);
    assert_eq("cms exact when no collision (25)", cms_query(ce, 7002), 25);
    assert_eq("cms exact when no collision (7)", cms_query(ce, 7003), 7);

    # ═══ CMS：永不低估（确定性）═════════════════════════════
    # 🔴 w=20 < 50 个 key ⟹ 每行**必然**碰撞。
    let cw: i64 = 20;
    let cd: i64 = 4;
    let cs: i64 = cms_new(cw, cd);
    let nk: i64 = 50;
    let nn: i64 = 500;
    SSEED = 88172645463325252;
    i = 0;
    while i < 128 { TRU[i] = 0; i = i + 1; }
    i = 0;
    while i < nn {
        kk = nxr(nk);
        cms_add(cs, kk, 1);
        TRU[kk] = TRU[kk] + 1;
        i = i + 1;
    }
    let under: i64 = 0;
    let sumerr: i64 = 0;
    let maxerr: i64 = 0;
    let nerr: i64 = 0;
    i = 0;
    while i < nk {
        q = cms_query(cs, i);
        if q < TRU[i] { under = under + 1; }
        if q > TRU[i] {
            e = q - TRU[i];
            sumerr = sumerr + e;
            nerr = nerr + 1;
            if e > maxerr { maxerr = e; }
        }
        i = i + 1;
    }
    assert_eq("cms NEVER underestimates", under, 0);
    assert_eq("cms total N tracked", cms_total(cs), nn);
    # 非空转守卫：碰撞必须真的发生，否则下面的上界断言是平凡的
    assert_true("cms collisions actually happen (non-vacuous)", nerr > 0);

    # ε·N：w = ⌈e/ε⌉ ⇒ ε = e/w ⇒ ε·N = 271828·N /(w·100000)
    let epsN: i64 = 271828 * nn / (cw * 100000);
    let avgerr: i64 = sumerr / nk;
    assert_true("cms max error within eps*N", maxerr <= epsN);
    assert_true("cms avg error well under eps*N", avgerr < epsN);

    # ═══ CMS：退化保护路径必须**真的被执行**（非空转守卫）════
    # 🔴 w 为**偶数**时该保护**不可达**：cm_h2 已 |1 ⟹ h2 恒为奇数，
    #    而 "h2 ≡ 0 (mod w)" 要求 h2 是 w 的倍数 —— 偶数 w 的倍数必为偶数。
    #    实测（key 0..49）：w=20/22/24 命中 0 次；w=15 命中 4 次、w=23 命中 4 次。
    #    所以这里必须挑一个**奇数** w，否则保护是死代码、断言是空转的
    #    —— 与 v1.141 SAM 的 SA_NCL=0（克隆分支从未进入）是同一类问题。
    let cw5: i64 = 15;
    let cs5: i64 = cms_new(cw5, 4);
    CMSDEG = 0;
    i = 0;
    while i < 128 { TRU[i] = 0; i = i + 1; }
    i = 0;
    while i < nn {
        kk = nxr(nk);
        cms_add(cs5, kk, 1);
        TRU[kk] = TRU[kk] + 1;
        i = i + 1;
    }
    assert_true("cms degenerate-guard path is exercised", CMSDEG > 0);
    let under5: i64 = 0;
    i = 0;
    while i < nk {
        if cms_query(cs5, i) < TRU[i] { under5 = under5 + 1; }
        i = i + 1;
    }
    assert_eq("cms(w odd) NEVER underestimates", under5, 0);

    # ═══ CMS：merge 是**加法**（线性，可分布式聚合）══════════
    let ga: i64 = cms_new(2048, 2);
    let gb: i64 = cms_new(2048, 2);
    i = 0;
    while i < 12 { cms_add(ga, 9001, 1); i = i + 1; }
    i = 0;
    while i < 30 { cms_add(gb, 9001, 1); i = i + 1; }
    assert_eq("cms merge ok", cms_merge(ga, gb), 0);
    assert_eq("cms merge is additive", cms_query(ga, 9001), 42);
    assert_eq("cms merge sums N", cms_total(ga), 42);

    # ═══ 打印实测数字（供 docs/sketch.md 引用）═══════════════
    print("  bloom fp/20000: k=1 ");
    print_i64(fp1);
    print("  k=3 ");
    print_i64(fp3);
    print("  k=4 ");
    print_i64(fp4);
    print(" | theory k=1 ");
    print_i64(f64_to_i(th1));
    print(" k=3 ");
    print_i64(f64_to_i(th3));
    print_nl();
    print("  bloom popcount ");
    print_i64(pc);
    print(" theory ");
    print_i64(f64_to_i(expc));
    print_nl();
    print("  cms(w=");
    print_i64(cw);
    print(",d=");
    print_i64(cd);
    print(") keys_overestimated=");
    print_i64(nerr);
    print(" avg_err=");
    print_i64(avgerr);
    print(" max_err=");
    print_i64(maxerr);
    print(" eps*N=");
    print_i64(epsN);
    print_nl();

    return test_done();
}

# f64 → i64（只用于打印，不参与断言）
fn f64_to_i(v: f64) -> i64 {
    let x: i64 = 0;
    while f64(x + 1) <= v { x = x + 1; }
    return x;
}
