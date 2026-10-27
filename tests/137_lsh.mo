# 137 —— 局部敏感哈希（MinHash / SimHash / banding）        # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   MinHash : Broder 1997；Broder–Charikar–Frieze–Mitzenmacher 2000
#             "Min-wise independent permutations"
#   SimHash : Charikar 2002 "Similarity estimation techniques from
#             rounding algorithms"
#   banding : Indyk & Motwani 1998 "Approximate nearest neighbors"
#   无主流框架内建：Python 靠 datasketch、Java 靠 stream-lib，都是第三方。
#
# ── 本测试覆盖的**定量**结论 ────────────────────────────────
#   ① MinHash 无偏：E[估计] = 真实 Jaccard；J=1 与 J=0 是**精确**的
#   ② 方差 ∝ 1/k：MAD 随 k 增大按 √k 缩小
#   ③ SimHash 的 Charikar 定理：Pr[位不同] = θ/π，
#      用四个**解析精确点**验证（cos=1/√0.707/0.5/0 → θ/π=0/¼/⅓/½）
#      —— 刻意不查表、不近似 arccos：本轮第一版手写了一张 cos 表，
#         实测与真值差到 0.5（把"角度均分的 cos"当成"线性递减"），
#         已删除。解析点不需要任何近似源。
#   ④ banding 的 S 曲线 P = 1−(1−s^r)^b 与理论逐点吻合
#   ⑤ **LSH 会漏**：s 略高于阈值 t=(1/b)^(1/r) 时召回率仍明显 < 1
#      —— 这是 LSH 与前两轮 HDC/SDM 的本质差异，必须钉成数字
#
# ── 定点口径 ────────────────────────────────────────────────
#   Q16.16：1.0 = 65536。

import "assert.mo";
import "lsh.mo";

var TSA: i64 = 0;
var TSB: i64 = 0;
var TAA: i64 = 0;
var TAB: i64 = 0;
var TSG: i64 = 0;
var TSH: i64 = 0;

# ⚠️ TI / TJ 专供 build 与 sham_off 内部使用（它们会被下面各函数嵌套调用）。
#    mmean / mad / shmean / prate 各自用**独立的**循环变量 TQ0..TQ3 ——
#    本轮第一版全都共用 TI，于是 build 一返回 TI 就被改成 (n-c)+n，
#    外层循环当场退出，每个"重复 20/30 次"的实测其实**只跑了 1 次**：
#    J=1/3 的均值打印出 768（应为 21845）。不报错，只是数字不对。
var TI: i64 = 0;
var TJ: i64 = 0;
var TQ0: i64 = 0;
var TQ1: i64 = 0;
var TQ2: i64 = 0;
var TQ3: i64 = 0;
var TV: i64 = 0;
var TD: i64 = 0;
var TSUM: i64 = 0;
var TMAD: i64 = 0;
var TREP: i64 = 0;
var THIT: i64 = 0;

var MAD32: i64 = 0;
var MAD128: i64 = 0;
var P20: i64 = 0;
var P40: i64 = 0;
var P45: i64 = 0;
var P60: i64 = 0;

# ── MinHash 侧 ─────────────────────────────────────────────
# A = {0..n-1}，B = {(n-c) .. (n-c+n-1)}
#   |A|=|B|=n，|A∩B|=c，|A∪B|=2n-c，Jaccard = c/(2n-c)
fn build(n: i64, c: i64) -> i64 {
    lsh_mzero(TSA);
    lsh_mzero(TSB);
    TI = 0;
    while TI < n { lsh_madd(TSA, TI); TI = TI + 1; }
    TI = n - c;
    TJ = 0;
    while TJ < n { lsh_madd(TSB, TI); TI = TI + 1; TJ = TJ + 1; }
    return 0;
}

# 指定 k 与种子，返回 Jaccard 估计（Q16.16）
fn mest(k: i64, seed: i64, n: i64, c: i64) -> i64 {
    lsh_seed(seed);
    lsh_minit(k);
    build(n, c);
    return lsh_mest(TSA, TSB);
}

# 重复 reps 次的平均绝对偏差（相对真值 true_q）
fn mad(k: i64, n: i64, c: i64, true_q: i64, reps: i64) -> i64 {
    TMAD = 0;
    TQ1 = 0;
    while TQ1 < reps {
        TV = mest(k, 7000 + TQ1 * 131 + k, n, c);
        TD = TV - true_q;
        if TD < 0 { TD = 0 - TD; }
        TMAD = TMAD + TD;
        TQ1 = TQ1 + 1;
    }
    return TMAD / reps;
}

fn mmean(k: i64, n: i64, c: i64, reps: i64) -> i64 {
    TSUM = 0;
    TQ0 = 0;
    while TQ0 < reps {
        TSUM = TSUM + mest(k, 7000 + TQ0 * 131 + k, n, c);
        TQ0 = TQ0 + 1;
    }
    return TSUM / reps;
}

# ── SimHash 侧 ─────────────────────────────────────────────
# A = {0..na-1}，B = {(na-inter) .. (na-inter+nb-1)}
#   余弦 = inter / sqrt(na*nb)
fn sham_off(off: i64, na: i64, nb: i64, inter: i64) -> i64 {
    lsh_soff(off);
    lsh_sacczero(TAA);
    lsh_sacczero(TAB);
    TI = 0;
    while TI < na { lsh_sadd(TAA, TI); TI = TI + 1; }
    TI = na - inter;
    TJ = 0;
    while TJ < nb { lsh_sadd(TAB, TI); TI = TI + 1; TJ = TJ + 1; }
    lsh_sfin(TSG, TAA);
    lsh_sfin(TSH, TAB);
    return lsh_sdist(TSG, TSH);
}

fn shmean(na: i64, nb: i64, inter: i64, reps: i64) -> i64 {
    TSUM = 0;
    TQ2 = 0;
    while TQ2 < reps {
        TSUM = TSUM + sham_off(TQ2 * 977 + 3, na, nb, inter);
        TQ2 = TQ2 + 1;
    }
    return TSUM / reps;
}

# ── banding 侧 ─────────────────────────────────────────────
fn bcand(seed: i64, n: i64, c: i64) -> i64 {
    lsh_seed(seed);
    lsh_minit(128);
    lsh_binit(32, 4);          # b=32, r=4 → k=128，阈值 t=(1/32)^(1/4)≈0.4204
    build(n, c);
    return lsh_bcand(TSA, TSB);
}

fn prate(n: i64, c: i64, reps: i64) -> i64 {
    THIT = 0;
    TQ3 = 0;
    while TQ3 < reps {
        THIT = THIT + bcand(31000 + TQ3 * 577, n, c);
        TQ3 = TQ3 + 1;
    }
    return THIT * 65536 / reps;
}

fn main() -> i64 {
    lsh_reset();
    lsh_minit(256);            # 先按最大 k 分配，之后改 k 只影响前 k 个槽
    TSA = lsh_mnew();
    TSB = lsh_mnew();
    TAA = lsh_saccnew();
    TAB = lsh_saccnew();
    TSG = lsh_snew();
    TSH = lsh_snew();

    # ── ① MinHash 的两端是精确的 ──────────────────────────
    # 相同集合：min 必然相等，不是估计
    assert_eq("mh J=1 exact", mest(128, 11, 100, 100), 65536);
    # 不相交：Pr[min 相等] = J = 0
    assert_eq("mh J=0", mest(128, 12, 100, 0), 0);

    # ── ② 无偏性（k=256，20 次平均）───────────────────────
    # J=1/3 → 21845；σ_mean = √(J(1−J)/k)/√reps ≈ 0.0066，3σ≈1300
    TV = mmean(256, 100, 50, 20);
    TD = TV - 21845;
    if TD < 0 { TD = 0 - TD; }
    assert_true("mh J=1/3 unbiased", TD < 1500);

    # J=2/3 → 43690
    TV = mmean(256, 100, 80, 20);
    TD = TV - 43690;
    if TD < 0 { TD = 0 - TD; }
    assert_true("mh J=2/3 unbiased", TD < 1500);

    # ── ③ 方差 ∝ 1/k ─────────────────────────────────────
    MAD32 = mad(32, 100, 50, 21845, 24);
    MAD128 = mad(128, 100, 50, 21845, 24);
    # σ(32)/σ(128) = √(128/32) = 2，判据留余量取 1.5 倍
    assert_true("mhad shrinks with k", MAD32 > MAD128 + MAD128 / 2);
    assert_true("mad128 nonzero", MAD128 > 0);

    # ── ④ SimHash 的 Charikar 定理（解析精确点）───────────
    # 相同向量：签名逐位相同，不是估计
    assert_eq("sh cos=1 exact", shmean(100, 100, 100, 1), 0);
    # cos=0 → θ/π=0.5
    TV = shmean(64, 64, 0, 30);
    TD = TV - 32768;
    if TD < 0 { TD = 0 - TD; }
    assert_true("sh cos=0 -> 1/2", TD < 2500);
    # cos=1/√2 → θ/π=1/4
    TV = shmean(32, 64, 32, 30);
    TD = TV - 16384;
    if TD < 0 { TD = 0 - TD; }
    assert_true("sh cos=.707 -> 1/4", TD < 2500);
    # cos=0.5 → θ/π=1/3
    TV = shmean(100, 100, 50, 30);
    TD = TV - 21845;
    if TD < 0 { TD = 0 - TD; }
    assert_true("sh cos=.5 -> 1/3", TD < 2500);

    # ── ⑤ banding 的 S 曲线 ──────────────────────────────
    # 理论：s=0.2→0.0500；0.4→0.5639；0.6→0.9882；0.4493→0.7358
    P20 = prate(150, 50, 30);
    TD = P20 - 3274;
    if TD < 0 { TD = 0 - TD; }
    assert_true("band s=0.2", TD < 7864);

    P40 = prate(140, 80, 30);
    TD = P40 - 36955;
    if TD < 0 { TD = 0 - TD; }
    assert_true("band s=0.4", TD < 9830);

    P60 = prate(160, 120, 30);
    TD = P60 - 64764;
    if TD < 0 { TD = 0 - TD; }
    assert_true("band s=0.6", TD < 7864);

    # 陡变：跨过阈值 t≈0.42 后碰撞率必须大幅跃升
    assert_true("band S-curve jump", P60 - P20 > 39321);

    # ── ⑥ LSH 会漏（本轮最该钉住的一条）───────────────────
    # s=0.4493 > t=0.4204，理论 P=0.7358 —— 高于阈值仍会漏掉约 1/4
    P45 = prate(200, 124, 30);
    assert_true("band leaks below 1", P45 < 58982);
    assert_true("band still recalls", P45 > 39321);
    # 且必须低于 s=0.6 的召回 —— 证明不是"一到阈值就饱和"
    assert_true("band 0.45 < 0.6", P45 < P60 - 6553);

    assert_eq("pool no overflow", LSOVF, 0);

    print("  mh J=1/3 mean=");
    print_i64(mmean(256, 100, 50, 20));
    print("  band P(0.2/0.4/0.45/0.6)=");
    print_i64(P20);
    print_i64(P40);
    print_i64(P45);
    print_i64(P60);
    print_nl();

    return test_done();
}
