# expect: 0
# 148_cbfmerge —— 三种草图结构、三种合并运算
#
# ── 判据设计（本测试最要紧的部分）──────────────────────────
#   ① **逐格精确**：与测试**自己**算出的 max(SNA, SNB) 逐格比对，
#      diff 必须恰好 0。这是唯一独立于 cbf_merge 实现的参照。
#   ② **无假阴**（确定性）：合并后对 S_A ∪ S_B 全量回查，fn 必须**恰好 0**。
#   ③ **假阳的确定性单调**（不是概率）：
#        Z(A) ⊆ Z(merge)   ⟹ fp(A) ≤ fp(merge)
#        Z(merge) ⊆ Z(direct)（max ≤ sum 逐格）⟹ fp(merge) ≤ fp(direct)
#      两条都由"逐格蕴含"推出，任何一次运行都必须成立。
#   ④ **幂等**：CBF 有、CMS 没有 ——
#        cbf_count(merge(A,A)) == cbf_count(A)      （格 join 的幂等律）
#        cms_total(merge(C,C)) == 2 × cms_total(C)  （加法不幂等）
#   ⑤ 交换 / 结合：逐格 diff 必须 0。
#
# 🔴 ⑤ 抓不到"整字 max"：整数 max **同样**满足交换、结合、幂等。
#    格的三条律对"错误的运算"一样成立 —— 只有 ①②能抓到它。
#    这是本测试最反直觉的一条结论，已写进 docs/cbf.md。

import "assert.mo";
import "cbf.mo";
import "cms.mo";

var M: i64 = 1024;
var K: i64 = 3;

var SNA: [1024] i64 = 0;
var SNB: [1024] i64 = 0;
var EXP: [1024] i64 = 0;

# ── 建一个装 [lo,hi] 的 filter ─────────────────────────────
fn mk(lo: i64, hi: i64) -> i64 {
    let h: i64 = 0;
    let x: i64 = 0;
    h = cbf_new(M, K);
    x = lo;
    while x <= hi {
        cbf_add(h, x);
        x = x + 1;
    }
    return h;
}

# ── 两个 filter 逐格不同的格数 ─────────────────────────────
fn cmpcnt(a: i64, b: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 0;
    i = 0;
    while i < M {
        if cbf_cell(a, i) != cbf_cell(b, i) { d = d + 1; }
        i = i + 1;
    }
    return d;
}

# ── 与 SNA 快照逐格比对 ────────────────────────────────────
fn cmpsnap(h: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 0;
    i = 0;
    while i < M {
        if cbf_cell(h, i) != SNA[i] { d = d + 1; }
        i = i + 1;
    }
    return d;
}

fn main() -> i64 {
    let fa: i64 = 0;
    let fb: i64 = 0;
    let fA: i64 = 0;
    let fB: i64 = 0;
    let fD: i64 = 0;
    let fM: i64 = 0;
    let fM2: i64 = 0;
    let fP: i64 = 0;
    let p1: i64 = 0;
    let p2: i64 = 0;
    let p3: i64 = 0;
    let q1: i64 = 0;
    let q2: i64 = 0;
    let q3: i64 = 0;
    let r1: i64 = 0;
    let r2: i64 = 0;
    let s1: i64 = 0;
    let s2: i64 = 0;
    let v1: i64 = 0;
    let v2: i64 = 0;
    let v3: i64 = 0;
    let v4: i64 = 0;
    let fEA: i64 = 0;
    let fEB: i64 = 0;
    let fEM: i64 = 0;
    let fEM2: i64 = 0;
    let i: i64 = 0;
    let x: i64 = 0;
    let diff: i64 = 0;
    let ne: i64 = 0;
    let raise: i64 = 0;
    let fn_: i64 = 0;
    let fpA: i64 = 0;
    let fpB: i64 = 0;
    let fpM: i64 = 0;
    let fpD: i64 = 0;
    let ca0: i64 = 0;
    let lt: i64 = 0;
    let strict: i64 = 0;
    let ea: i64 = 0;
    let eb: i64 = 0;
    let em: i64 = 0;
    let bad: i64 = 0;
    let better: i64 = 0;
    let cs1: i64 = 0;
    let cs2: i64 = 0;
    let t0: i64 = 0;

    # ══ ① 逐格精确 + ② 无假阴 ══════════════════════════════
    fa = mk(1, 150);        # S_A = [1,150]
    fb = mk(101, 250);      # S_B = [101,250]，重叠 50 个

    i = 0;
    while i < M {
        SNA[i] = cbf_cell(fa, i);
        SNB[i] = cbf_cell(fb, i);
        if SNA[i] > SNB[i] { EXP[i] = SNA[i]; } else { EXP[i] = SNB[i]; }
        if SNA[i] != SNB[i] { ne = ne + 1; }
        if SNA[i] == 0 {
            if SNB[i] > 0 { raise = raise + 1; }
        }
        i = i + 1;
    }

    cbf_merge(fa, fb);

    i = 0;
    while i < M {
        if cbf_cell(fa, i) != EXP[i] { diff = diff + 1; }
        i = i + 1;
    }
    assert_eq("merge == 独立算出的逐格 max", diff, 0);
    assert_eq("守卫: A/B 有不同格（否则合并恒等）", ne > 0, 1);
    assert_eq("守卫: 存在 A=0 且 B>0 的格（必须被抬起）", raise > 0, 1);

    x = 1;
    fn_ = 0;
    while x <= 250 {
        if cbf_query(fa, x) == 0 { fn_ = fn_ + 1; }
        x = x + 1;
    }
    assert_eq("合并后对 S_A∪S_B 无假阴", fn_, 0);

    # ══ ③ 假阳的确定性单调 ════════════════════════════════
    fA = mk(1, 150);
    fB = mk(101, 250);
    fD = mk(1, 150);
    x = 101;
    while x <= 250 {          # direct union：重叠区插两次 ⟹ 逐格为 sum
        cbf_add(fD, x);
        x = x + 1;
    }
    fM = mk(1, 150);
    fM2 = mk(101, 250);
    cbf_merge(fM, fM2);

    i = 0;
    while i < 4000 {
        x = 5000 + i;         # [5000,8999] 全部未插入
        if cbf_query(fA, x) == 1 { fpA = fpA + 1; }
        if cbf_query(fB, x) == 1 { fpB = fpB + 1; }
        if cbf_query(fM, x) == 1 { fpM = fpM + 1; }
        if cbf_query(fD, x) == 1 { fpD = fpD + 1; }
        i = i + 1;
    }
    assert_eq("fp(merge) >= fp(A)（Z(A)⊆Z(merge)）", fpM >= fpA, 1);
    assert_eq("fp(merge) >= fp(B)（Z(B)⊆Z(merge)）", fpM >= fpB, 1);
    # 🔴 实测发现可以比"≤"强得多：**恰好相等**。
    #    query 只问"计数器 > 0"，而 max(a,b) > 0 ⟺ a+b > 0 ⟺ a>0 或 b>0。
    #    所以 merge 与 direct 的**非零格集合完全相同** ⟹ 假阳率逐位相同。
    #    差异只在**计数**（max vs 和），所以只体现在 cbf_est 上。
    assert_eq("fp(merge) == fp(direct)（非零格集合相同）", fpM, fpD);
    assert_eq("守卫: fp(merge) 严格大于 fp(A)、fp(B)", (fpM > fpA) + (fpM > fpB), 2);

    # merge 逐格 ≤ direct
    i = 0;
    while i < M {
        if cbf_cell(fa, i) > cbf_cell(fD, i) { lt = lt + 1; }
        if cbf_cell(fa, i) < cbf_cell(fD, i) { strict = strict + 1; }
        i = i + 1;
    }
    assert_eq("merge 逐格 <= direct（max<=sum）", lt, 0);
    assert_eq("守卫: max 确实严格小于 sum 过", strict > 0, 1);

    # ══ ④ 幂等：CBF 有，CMS 没有 ══════════════════════════
    fP = mk(1, 150);
    ca0 = cbf_count(fP);
    i = 0;
    while i < M {
        SNA[i] = cbf_cell(fP, i);
        i = i + 1;
    }
    cbf_merge(fP, fP);
    assert_eq("幂等: merge(A,A) 逐格不变", cmpsnap(fP), 0);
    assert_eq("幂等: cbf_count 不变", cbf_count(fP), ca0);

    cs1 = cms_new(64, 4);
    cs2 = cms_new(64, 4);
    x = 1;
    while x <= 150 {
        cms_add(cs1, x, 1);
        cms_add(cs2, x, 1);
        x = x + 1;
    }
    t0 = cms_total(cs1);
    assert_eq("守卫: cms_total 初值", t0, 150);
    cms_merge(cs1, cs2);
    assert_eq("CMS 不幂等: total 翻倍", cms_total(cs1), t0 + t0);

    # ══ ⑤ 交换 / 结合 ═════════════════════════════════════
    p1 = mk(1, 80);
    p2 = mk(61, 140);
    p3 = mk(121, 200);
    cbf_merge(p1, p2);
    cbf_merge(p1, p3);        # (S1⊔S2)⊔S3
    q1 = mk(1, 80);
    q2 = mk(61, 140);
    q3 = mk(121, 200);
    cbf_merge(q2, q3);
    cbf_merge(q1, q2);        # S1⊔(S2⊔S3)
    assert_eq("结合律", cmpcnt(p1, q1), 0);

    r1 = mk(1, 80);
    r2 = mk(61, 140);
    s1 = mk(1, 80);
    s2 = mk(61, 140);
    cbf_merge(r1, r2);
    cbf_merge(s2, s1);
    assert_eq("交换律", cmpcnt(r1, s2), 0);

    # ══ 参数不一致必须报错，不静默半合并 ═══════════════════
    CBFBAD = 0;
    v1 = cbf_new(256, 3);
    v2 = cbf_new(512, 3);
    assert_eq("m 不同必须报错", cbf_merge(v1, v2), 0 - 1);
    v3 = cbf_new(256, 3);
    v4 = cbf_new(256, 4);
    assert_eq("k 不同必须报错", cbf_merge(v3, v4), 0 - 1);
    assert_eq("参数不符置 CBFBAD", CBFBAD, 1);

    # ══ cbf_est 的单调性 ══════════════════════════════════
    fEA = mk(1, 150);
    fEB = mk(101, 250);
    fEM = mk(1, 150);
    fEM2 = mk(101, 250);
    cbf_merge(fEM, fEM2);
    x = 1;
    while x <= 250 {
        ea = cbf_est(fEA, x);
        eb = cbf_est(fEB, x);
        em = cbf_est(fEM, x);
        if em < ea { bad = bad + 1; }
        if em < eb { bad = bad + 1; }
        if ea > eb {
            if em > ea { better = better + 1; }
        } else {
            if em > eb { better = better + 1; }
        }
        x = x + 1;
    }
    assert_eq("est(merge) >= max(estA, estB)", bad, 0);

    assert_eq("池未溢出", CBFOV, 0);

    print("  diff=");
    print_i64(diff);
    print(" ne=");
    print_i64(ne);
    print(" raise=");
    print_i64(raise);
    print(" fn=");
    print_i64(fn_);
    print_nl();
    print("  fpA=");
    print_i64(fpA);
    print(" fpB=");
    print_i64(fpB);
    print(" fpM=");
    print_i64(fpM);
    print(" fpD=");
    print_i64(fpD);
    print_nl();
    print("  cbf_selfmerge_diff=");
    print_i64(cmpsnap(fP));
    print(" cbf_count=");
    print_i64(ca0);
    print(" cms_total_after=");
    print_i64(cms_total(cs1));
    print_nl();
    print("  strict_lt_sum=");
    print_i64(strict);
    print(" est_better=");
    print_i64(better);
    print(" est_bad=");
    print_i64(bad);
    print_nl();

    return test_done();
}
