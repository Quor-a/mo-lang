# expect: 0
# 147_cbfcu —— Counting Bloom Filter + Conservative Update
#
# 本测试针对 v1.144 明确记下的两条**已知限制**：
#   ① "Bloom 不支持删除"        → CBF（lib/cbf.mo）
#   ② CMS 只做了普通 add        → CU（cms_cu_add，lib/cms.mo）
#
# ── 判据设计（本测试最要紧的部分）──────────────────────────
#   ① **确定性**断言：
#        · CBF 插入后回查 ⟹ 假阴**恰好 0**
#        · 同一元素插入 20 次（> 15）⟹ query 仍真、est **恰好 15**
#          （不饱和则 4-bit 回绕成 0 ⟹ 假阴，Bloom 家族唯一硬保证当场破）
#        · 只插入 A 再删 A ⟹ query(A) 为假，且 CBFNEG **恰好 0**
#        · 插入 A、B 再删 A ⟹ query(B) **恒真**（共享处 2→1>0）
#   ② **受控场景**（不是撞运气）：
#        删一批**没插入过**的元素 ⟹ 假阴 > 0。这是 CBF 的真实代价，
#        用 m=64 的小表**逼出碰撞**，否则这条路径可能一次都不触发。
#   ③ **非空转守卫**：CBFSAT > 0、nerr > 0。
#        全绿但守卫为 0 ⟹ 断言恒真、一条没验到。
#   ④ **CU 的对照**：普通 CMS 与 CU 用**同一批哈希、同一条插入序列**，
#        所以差异只可能来自更新策略。断言 sumB **严格小于** sumA。
#
# ── 🔴 一条"同是合并、结果相反"的对照 ──────────────────────
#      普通 CMS 的 merge ⟹ 与直接构造**逐格相等**（加法交换律，确定性）
#      CU     的 merge ⟹ 与直接构造**不等**（CU 依赖当前状态）
#    同一次 merge，两种策略给出**相反的结论** —— 这就是 CU 换误差的账单。

import "assert.mo";
import "bloom.mo";
import "cbf.mo";
import "cms.mo";
import "fmath.mo";

# ── 确定性 PRNG（xorshift64，不带库以免相互干扰）───────────
# ⚠️ 循环内不能声明 let（会累积栈帧），所有变量都在 main 顶部声明。
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

var TRU: [128] i64 = 0;

fn main() -> i64 {
    let i: i64 = 0;
    let x: i64 = 0;
    let fa: i64 = 0;
    let fb: i64 = 0;
    let fs: i64 = 0;
    let fe: i64 = 0;
    let fd: i64 = 0;
    let fd2: i64 = 0;
    let fx: i64 = 0;
    let fy: i64 = 0;
    let fn_: i64 = 0;
    let fn2: i64 = 0;
    let fp: i64 = 0;
    let fpb: i64 = 0;
    let th_i: i64 = 0;
    let lo: i64 = 0;
    let hi: i64 = 0;
    let c1: i64 = 0;
    let w: i64 = 20;
    let d: i64 = 4;
    let keys: i64 = 50;
    let N: i64 = 500;
    let A: i64 = 0;
    let B: i64 = 0;
    let ea: i64 = 0;
    let eb: i64 = 0;
    let sumA: i64 = 0;
    let sumB: i64 = 0;
    let maxA: i64 = 0;
    let maxB: i64 = 0;
    let underA: i64 = 0;
    let underB: i64 = 0;
    let nerrA: i64 = 0;
    let nerrB: i64 = 0;
    let A1: i64 = 0;
    let A2: i64 = 0;
    let C: i64 = 0;
    let B1: i64 = 0;
    let B2: i64 = 0;
    let D: i64 = 0;
    let dplain: i64 = 0;
    let dcu: i64 = 0;

    # ═══ 一、CBF 参数校验（负例）══════════════════════════════
    CBFBAD = 0;
    assert_eq("cbf m=0 rejected", cbf_new(0, 3), 0 - 1);
    assert_eq("cbf m=0 sets CBFBAD", CBFBAD, 1);

    CBFBAD = 0;
    assert_eq("cbf m=1000 not pow2 rejected", cbf_new(1000, 3), 0 - 1);
    assert_eq("cbf not-pow2 sets CBFBAD", CBFBAD, 1);

    CBFBAD = 0;
    assert_eq("cbf k=0 rejected", cbf_new(1024, 0), 0 - 1);
    assert_eq("cbf k=0 sets CBFBAD", CBFBAD, 1);

    CBFBAD = 0;
    assert_eq("cbf k=17 rejected", cbf_new(1024, 17), 0 - 1);
    assert_eq("cbf k>16 sets CBFBAD", CBFBAD, 1);

    # ═══ 二、永不假阴（核心保证，确定性）══════════════════════
    fa = cbf_new(1024, 3);
    i = 0;
    while i < 200 {
        cbf_add(fa, i + 1);
        i = i + 1;
    }
    fn_ = 0;
    i = 0;
    while i < 200 {
        if cbf_query(fa, i + 1) == 0 { fn_ = fn_ + 1; }
        i = i + 1;
    }
    assert_eq("cbf no false negative", fn_, 0);

    # ── 假阳率对照 Bloom 闭式解 ──────────────────────────────
    # 同一个 1024/3/200 下建一个 bloom 做**同参数对照**：
    # CBF 的"计数器 > 0"与 Bloom 的"bit = 1"等价 ⟹ 假阳率应同量级。
    fb = bloom_new(1024, 3);
    i = 0;
    while i < 200 {
        bloom_add(fb, i + 1);
        i = i + 1;
    }
    fp = 0;
    fpb = 0;
    i = 0;
    while i < 20000 {
        if cbf_query(fa, 1000000 + i) == 1 { fp = fp + 1; }
        if bloom_has(fb, 1000000 + i) == 1 { fpb = fpb + 1; }
        i = i + 1;
    }
    th_i = f64_to_i(bloom_fp_theory(200, 1024, 3) * 20000.0);
    lo = th_i / 2;
    hi = th_i * 2;
    c1 = 0;
    if fp >= lo { c1 = 1; }
    assert_eq("cbf fp >= theory/2", c1, 1);
    c1 = 0;
    if fp <= hi { c1 = 1; }
    assert_eq("cbf fp <= theory*2", c1, 1);
    c1 = 0;
    if fpb >= lo { c1 = 1; }
    assert_eq("bloom fp >= theory/2 (control)", c1, 1);
    c1 = 0;
    if fpb <= hi { c1 = 1; }
    assert_eq("bloom fp <= theory*2 (control)", c1, 1);

    # ═══ 三、饱和（🔴 不做饱和 ⟹ 假阴）════════════════════════
    fs = cbf_new(1024, 3);
    CBFSAT = 0;
    i = 0;
    while i < 20 {
        cbf_add(fs, 999);
        i = i + 1;
    }
    assert_eq("cbf query still true after 20 inserts", cbf_query(fs, 999), 1);
    assert_eq("cbf est saturates at 15", cbf_est(fs, 999), 15);
    c1 = 0;
    if CBFSAT > 0 { c1 = 1; }
    assert_eq("cbf saturation branch executed", c1, 1);

    # ═══ 四、est 在无碰撞时精确 ═══════════════════════════════
    fe = cbf_new(1024, 3);
    i = 0;
    while i < 3 {
        cbf_add(fe, 777);
        i = i + 1;
    }
    assert_eq("cbf est exact when no collision", cbf_est(fe, 777), 3);

    # ═══ 五、删除已插入（确定性）══════════════════════════════
    fd = cbf_new(1024, 3);
    CBFNEG = 0;
    cbf_add(fd, 555);
    assert_eq("cbf query A after add", cbf_query(fd, 555), 1);
    cbf_remove(fd, 555);
    assert_eq("cbf query A after remove", cbf_query(fd, 555), 0);
    assert_eq("cbf removing inserted sets no CBFNEG", CBFNEG, 0);

    # ═══ 六、删 A 不影响 B（确定性，与是否共享无关）═══════════
    # 共享处计数 2→1 仍 >0；不共享则 B 的位根本没被动。**恒真**。
    fd2 = cbf_new(1024, 3);
    cbf_add(fd2, 11);
    cbf_add(fd2, 22);
    CBFNEG = 0;
    cbf_remove(fd2, 11);
    assert_eq("cbf remove A keeps B", cbf_query(fd2, 22), 1);
    assert_eq("cbf remove A no CBFNEG", CBFNEG, 0);

    # ═══ 七、删**没插入过**的元素 ⟹ 假阴（CBF 的真实代价）════
    # m=64 是刻意的：小表强制碰撞，否则 200 次减可能一次都打不中 S。
    fx = cbf_new(64, 2);
    i = 0;
    while i < 8 {
        cbf_add(fx, i + 1);
        i = i + 1;
    }
    fn_ = 0;
    i = 0;
    while i < 8 {
        if cbf_query(fx, i + 1) == 0 { fn_ = fn_ + 1; }
        i = i + 1;
    }
    assert_eq("cbf small table no false negative before", fn_, 0);

    CBFNEG = 0;
    i = 0;
    while i < 100 {
        cbf_remove(fx, 5000 + i);      # 🔴 这批元素**从未插入过**
        i = i + 1;
    }
    c1 = 0;
    if CBFNEG > 0 { c1 = 1; }
    assert_eq("cbf removing absent sets CBFNEG", c1, 1);

    fn2 = 0;
    i = 0;
    while i < 8 {
        if cbf_query(fx, i + 1) == 0 { fn2 = fn2 + 1; }
        i = i + 1;
    }
    c1 = 0;
    if fn2 > 0 { c1 = 1; }
    assert_eq("cbf removing absent introduces false negative", c1, 1);

    # ═══ 八、safe remove 挡住"完全没插入过"这一类 ═════════════
    fy = cbf_new(1024, 3);
    cbf_add(fy, 33);
    CBFNEG = 0;
    cbf_remove_safe(fy, 8888);         # 未插入 ⟹ 一步不动
    assert_eq("cbf safe remove absent sets no CBFNEG", CBFNEG, 0);
    assert_eq("cbf safe remove absent keeps inserted", cbf_query(fy, 33), 1);

    # ═══ 九、CU vs 普通 CMS（同一条插入序列）══════════════════
    i = 0;
    while i < keys {
        TRU[i] = 0;
        i = i + 1;
    }
    A = cms_new(w, d);
    B = cms_new(w, d);
    SSEED = 12345;
    i = 0;
    while i < N {
        x = nxr(keys);
        TRU[x] = TRU[x] + 1;
        cms_add(A, x, 1);
        cms_cu_add(B, x, 1);
        i = i + 1;
    }
    sumA = 0;
    sumB = 0;
    maxA = 0;
    maxB = 0;
    underA = 0;
    underB = 0;
    nerrA = 0;
    nerrB = 0;
    i = 0;
    while i < keys {
        ea = cms_query(A, i) - TRU[i];
        eb = cms_query(B, i) - TRU[i];
        if ea < 0 { underA = underA + 1; }
        if eb < 0 { underB = underB + 1; }
        if ea > 0 { nerrA = nerrA + 1; }
        if eb > 0 { nerrB = nerrB + 1; }
        sumA = sumA + ea;
        sumB = sumB + eb;
        if ea > maxA { maxA = ea; }
        if eb > maxB { maxB = eb; }
        i = i + 1;
    }
    assert_eq("cms never underestimates", underA, 0);
    assert_eq("cms-cu never underestimates", underB, 0);
    c1 = 0;
    if nerrA > 0 { c1 = 1; }
    assert_eq("cms overestimate guard (non-vacuous)", c1, 1);
    c1 = 0;
    if sumB < sumA { c1 = 1; }
    assert_eq("cms-cu total error strictly smaller", c1, 1);
    c1 = 0;
    if maxB <= maxA { c1 = 1; }
    assert_eq("cms-cu max error not worse", c1, 1);

    # ═══ 十、线性性对照：同一次 merge，两种策略结论相反 ═══════
    # 普通 CMS：merge 与直接构造**等价**（加法交换律）
    A1 = cms_new(w, d);
    A2 = cms_new(w, d);
    C = cms_new(w, d);
    SSEED = 999;
    i = 0;
    while i < 250 {
        x = nxr(keys);
        cms_add(A1, x, 1);
        cms_add(C, x, 1);
        i = i + 1;
    }
    i = 0;
    while i < 250 {
        x = nxr(keys);
        cms_add(A2, x, 1);
        cms_add(C, x, 1);
        i = i + 1;
    }
    cms_merge(A1, A2);
    dplain = 0;
    i = 0;
    while i < keys {
        if cms_query(A1, i) != cms_query(C, i) { dplain = dplain + 1; }
        i = i + 1;
    }
    assert_eq("plain cms merge equals direct build", dplain, 0);

    # CU：merge 与直接构造**不等**（CU 依赖当前状态 ⟹ 不再线性）
    B1 = cms_new(w, d);
    B2 = cms_new(w, d);
    D = cms_new(w, d);
    SSEED = 999;
    i = 0;
    while i < 250 {
        x = nxr(keys);
        cms_cu_add(B1, x, 1);
        cms_cu_add(D, x, 1);
        i = i + 1;
    }
    i = 0;
    while i < 250 {
        x = nxr(keys);
        cms_cu_add(B2, x, 1);
        cms_cu_add(D, x, 1);
        i = i + 1;
    }
    cms_merge(B1, B2);
    dcu = 0;
    i = 0;
    while i < keys {
        if cms_query(B1, i) != cms_query(D, i) { dcu = dcu + 1; }
        i = i + 1;
    }
    c1 = 0;
    if dcu > 0 { c1 = 1; }
    assert_eq("cu merge differs from direct build", c1, 1);

    # ── 实测数字（全部可见，便于复核）────────────────────────
    print("  cbf fp=");
    print_i64(fp);
    print(" bloom fp=");
    print_i64(fpb);
    print(" theory=");
    print_i64(th_i);
    print_nl();
    print("  cbf sat=");
    print_i64(CBFSAT);
    print(" neg=");
    print_i64(CBFSAT);
    print(" fn_after_absent_remove=");
    print_i64(fn2);
    print_nl();
    print("  cms err_sum=");
    print_i64(sumA);
    print(" max=");
    print_i64(maxA);
    print(" | cu err_sum=");
    print_i64(sumB);
    print(" max=");
    print_i64(maxB);
    print_nl();
    print("  merge diff plain=");
    print_i64(dplain);
    print(" cu=");
    print_i64(dcu);
    print_nl();

    return test_done();
}

# f64 → i64（只用于打印与区间换算，不参与确定性断言）
fn f64_to_i(v: f64) -> i64 {
    let x: i64 = 0;
    while f64(x + 1) <= v { x = x + 1; }
    return x;
}
