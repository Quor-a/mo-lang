# 138 —— HyperLogLog 基数估计                            # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   Flajolet & Martin 1985            PCSA（前导零估计基数）
#   Whang–Vander-Zanden–Taylor 1990   Linear Counting（小基数修正）
#   Durand & Flajolet 2003            LogLog
#   Flajolet–Fusy–Gandouet–Meunier 2007
#                                     HyperLogLog：调和平均 + α_m
#   Heule–Nunkesser–Hall 2013         HLL++：大基数修正
#   无主流语言标准库内建（Python/Java/Go/C++ 全靠第三方）。
#
# ── 本测试覆盖的**定量**结论 ────────────────────────────────
#   ① 标准误差 1.04/√m：m=2^10 实测 σ≈30‰（理论 32.5‰），
#      m=2^8 ≈ 50~83‰（65‰）、m=2^6 ≈ 113‰（130‰）—— 三个量级都落在
#      理论附近，且**随 m 增大按 √m 缩小**。
#   ② 小基数修正是**必需**的，不是美化：
#      m=1024、n=100 时 原始估计误差 ≈ 6860‰，修正后 ≈ 20‰（差 300 倍）。
#   ③ 桶必须**全部**被覆盖：n=100000 时空桶数 V 必须为 0。
#      这条是本轮最大的守卫 —— 见下面「bit63」。
#   ④ 合并 = 逐桶 max：|A ∪ B| 的估计误差与单次同阶。
#
# ── 🔴 本轮的核心守卫：哈希的 bit63 ────────────────────────
#   第一版 hll_mix 直接照抄 lib/lsh.mo 的 lsh_mix，而它用的是
#   `a ^ (a >> k)`；墨语言的 >> 是**算术**右移，于是
#       y = a ^ sar(a,k) 的 bit63 = a63 ^ a63 = 0
#   —— 输出的 bit63 恒为 0。LSH 里无所谓（SimHash 用 64 位投票，
#      少一位看不出来），但 HLL 用哈希的**最高 p 位**选桶，
#      bit63 正是桶号的最高位 ⇒ 只有低 m/2 个桶可能被选中。
#   实测症状（p=10）：
#       n=1      V=1023  估计 1.00     ← 完全正常
#       n=1000   V=570   估计 599      ← 只是"偏低"
#       n=10000  V=512   估计 709      ← V 停在 512 不动
#       n=100000 V=512   估计 709      ← 与上一行**逐位相同**
#   不报错、不崩溃，估计值始终是个像样的数。
#   能揪出它的只有两个数字：**bit63 的占比**和**V 恰为 m/2 且不再下降**。
#   所以下面第 5、6 条断言不是"锦上添花"，是本测试存在的理由。

import "assert.mo";
import "hll.mo";

var TI: i64 = 0;      # fill 用
var TK: i64 = 0;      # 重复试验用
var TB63: i64 = 0;    # mix 输出 bit63=1 的计数
var TOK: i64 = 0;     # 布尔中转（assert_true 只吃 i64）

# ── 插入区间 [lo, lo+n) ────────────────────────────────────
fn fill(s: i64, lo: i64, n: i64) -> i64 {
    TI = 0;
    while TI < n {
        hll_add(s, lo + TI);
        TI = TI + 1;
    }
    return 0;
}

# ── |rel| 的均值（跨 t 次独立试验）──────────────────────────
# 每次试验用不同的元素区间，保证**元素互不相同**。
fn meanrel(p: i64, n: i64, t: i64) -> f64 {
    hll_reset();
    let s: i64 = hll_new(p);
    let acc: f64 = 0.0;
    TK = 0;
    while TK < t {
        hll_zero(s);
        fill(s, TK * 1000000, n);
        let est: f64 = hll_count(s);
        let rel: f64 = (est - f64(n)) / f64(n);
        if rel < 0.0 { rel = 0.0 - rel; }
        acc = acc + rel;
        TK = TK + 1;
    }
    return acc / f64(t);
}

# 半正态分布下 E|X| = σ·√(2/π)，所以 σ = E|rel| / 0.7979
fn sigma(p: i64, n: i64, t: i64) -> f64 {
    return meanrel(p, n, t) / 0.7979;
}

fn in_range(v: f64, lo: f64, hi: f64) -> i64 {
    TOK = 0;
    if v >= lo {
        if v <= hi { TOK = 1; }
    }
    return TOK;
}

fn main() -> i64 {
    hll_reset();

    # ── ① 空 sketch ────────────────────────────────────────
    let s0: i64 = hll_new(10);
    TOK = 0;
    if hll_count(s0) == 0.0 { TOK = 1; }
    assert_true("empty -> 0", TOK);
    assert_eq("empty V == m", hll_v(s0), 1024);

    # ── ② 小基数是**精确**的（Linear Counting）──────────────
    let s1: i64 = hll_new(10);
    fill(s1, 0, 1);
    assert_true("n=1 -> 1.00", in_range(hll_count(s1), 0.95, 1.05));
    hll_zero(s1);
    fill(s1, 0, 10);
    assert_true("n=10 -> 10", in_range(hll_count(s1), 9.0, 11.0));
    hll_zero(s1);
    fill(s1, 0, 100);
    assert_true("n=100 -> 100", in_range(hll_count(s1), 90.0, 110.0));

    # ── ③ 小基数修正 vs 原始估计（A/B，差两个数量级）────────
    #    这条是"修正是否真的生效"的唯一硬证据：
    #    只看修正后的数字，分不清"修正有效"和"本来就这么准"。
    hll_zero(s1);
    fill(s1, 0, 100);
    let e100: f64 = hll_count(s1);
    let r100: f64 = hll_diag_raw();
    let relc: f64 = (e100 - 100.0) / 100.0;
    let relr: f64 = (r100 - 100.0) / 100.0;
    if relc < 0.0 { relc = 0.0 - relc; }
    if relr < 0.0 { relr = 0.0 - relr; }
    assert_true("n=100 修正后 |rel| < 10%", in_range(relc, 0.0, 0.10));
    assert_true("n=100 原始估计 |rel| > 100%", in_range(relr, 1.0, 100.0));

    # ── ④ mix 的 bit63 必须均匀（核心守卫之一）─────────────
    TB63 = 0;
    TI = 0;
    while TI < 10000 {
        if hll_mix(TI) < 0 { TB63 = TB63 + 1; }
        TI = TI + 1;
    }
    assert_true("mix bit63 占比 >45%", TB63 > 4500);
    assert_true("mix bit63 占比 <55%", TB63 < 5500);

    # ── ⑤ 桶必须全部被覆盖（核心守卫之二）──────────────────
    let s2: i64 = hll_new(10);
    fill(s2, 0, 100000);
    assert_eq("V == 0 (n=100000)", hll_v(s2), 0);

    # ── ⑥ V 必须严格小于 m/2（bit63 缺陷下 V 恰好 == m/2）───
    #    这条是唯一能在**不看 bit63** 的情况下抓到该缺陷的端到端判据。
    # ⚠️ n 不能选太大：V = m·e^(−n/m)，n=20000 时 V 已经是 0，
    #    那样 "V < m/2" 就变成恒真、抓不到任何东西。
    #    n=2000 → V ≈ 1024·e^(−1.95) ≈ 145，严格落在 (0, m/2) 内。
    hll_zero(s2);
    fill(s2, 0, 2000);
    let v2k: i64 = hll_v(s2);
    assert_true("V < m/2 (n=2000)", v2k < 512);
    # 非空转守卫：V 也不能是"全都空"或"全都满"的平凡值
    assert_true("V > 0 (n=2000 尚未填满)", v2k > 0);
    assert_true("V 落在 (0,m/2) 中段", v2k > 40);

    # ── ⑦ ρ 的取值范围 ─────────────────────────────────────
    hll_zero(s2);
    fill(s2, 0, 20000);
    let mr: i64 = hll_maxreg(s2);
    assert_true("maxreg <= 64-p", mr <= 54);
    assert_true("maxreg >= 5 (n=20000)", mr >= 5);

    # ── ⑧ 标准误差 1.04/√m（三个量级）──────────────────────
    let sg10: f64 = sigma(10, 10000, 24);
    assert_true("m=2^10 sigma in [12,60] permille",
                in_range(sg10 * 1000.0, 12.0, 60.0));

    let sg8: f64 = sigma(8, 10000, 24);
    assert_true("m=2^8 sigma in [30,130] permille",
                in_range(sg8 * 1000.0, 30.0, 130.0));

    let sg6: f64 = sigma(6, 10000, 24);
    assert_true("m=2^6 sigma in [55,250] permille",
                in_range(sg6 * 1000.0, 55.0, 250.0));

    # 误差必须随 m 增大而缩小（√m 律）；只测一个 m 证明不了这点
    assert_true("sigma(m=64) > sigma(m=256)", sg6 > sg8);
    assert_true("sigma(m=256) > sigma(m=1024)", sg8 > sg10);
    print("实测 sigma(permille): m=1024 "); print_f64(sg10 * 1000.0);
    print("  m=256 "); print_f64(sg8 * 1000.0);
    print("  m=64 "); print_f64(sg6 * 1000.0);
    print("   (理论 1.04/sqrt(m): 32.5 / 65 / 130)\n");
    print("n=100: 修正后 "); print_f64(e100);
    print("  原始 "); print_f64(r100); print("\n");

    # ── ⑨ 合并（逐桶 max）──────────────────────────────────
    hll_reset();
    let a: i64 = hll_new(10);
    let b: i64 = hll_new(10);
    let c: i64 = hll_new(10);
    fill(a, 0, 5000);
    fill(b, 5000000, 5000);          # 与 A 完全不相交
    let ea: f64 = hll_count(a);
    let eb: f64 = hll_count(b);
    fill(c, 0, 5000);
    fill(c, 5000000, 5000);          # C = 真实并集
    let ec: f64 = hll_count(c);
    hll_zero(c);
    fill(c, 0, 5000);
    hll_merge(c, b);                 # C = A ⊎ B（sketch 合并）
    let em: f64 = hll_count(c);
    # 三种算法（sketch 合并 / 直接插并集 / A+B 相加）应给出同一个量级
    assert_true("union: merge ~ 10000", in_range(em, 8000.0, 12500.0));
    assert_true("union: direct ~ 10000", in_range(ec, 8000.0, 12500.0));
    let esum: f64 = ea + eb;
    assert_true("union: |A|+|B| ~ 10000", in_range(esum, 8000.0, 12500.0));
    # 合并幂等：把 A 合进已有 A 的 sketch，估计不变
    hll_zero(c);
    fill(c, 0, 5000);
    let e0: f64 = hll_count(c);
    hll_merge(c, a);
    let e1: f64 = hll_count(c);
    TOK = 0;
    if e0 == e1 { TOK = 1; }
    assert_true("merge 幂等", TOK);

    # ── ⑩ 大基数修正：单元级验证 ────────────────────────────
    #    ⚠️ 64 位哈希下阈值是 2^64/30 ≈ 6.1e17，端到端**不可能**达到。
    #       所以这里只验公式本身，不假装端到端测过。
    let two32: f64 = fm_ldexp(1.0, 32);
    let small: f64 = 1000.0;
    TOK = 0;
    if hll_bigfix(small, 32) == small { TOK = 1; }
    assert_true("bigfix 小值不变", TOK);
    # e = 2^32/2 时，修正后应为 −2^32·ln(1−1/2) = 2^32·ln2
    let big: f64 = two32 / 2.0;
    let want: f64 = two32 * 0.693147180559945;
    let got: f64 = hll_bigfix(big, 32);
    let d: f64 = got - want;
    if d < 0.0 { d = 0.0 - d; }
    assert_true("bigfix 公式正确 (2^32/2)", d < want / 1000.0);
    # 修正后的值必须**大于**原值（饱和方向）
    assert_true("bigfix 单调放大", got > big);

    # ── ⑪ 池与参数边界（不静默）────────────────────────────
    hll_reset();
    HLLBAD = 0;
    let bad: i64 = hll_new(3);
    assert_eq("p=3 被拒", bad, 0 - 1);
    assert_eq("HLLBAD 置位", HLLBAD, 1);

    return test_done();
}
