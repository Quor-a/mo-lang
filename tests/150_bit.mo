# expect: 0
# 150_bit —— Fenwick 树 / Binary Indexed Tree
#
# 判据设计（本测试最要紧的部分）：
#   ① **精确**断言：bit_prefix / bit_range 与暴力 O(n) 求和**逐位相等**
#      （差异数必须为 0）。本库是**精确结构**，不像草图只能写"≤ 界"。
#   ② **独立算法**参照：暴力求和是完全不同的算法（平铺累加 vs 树跳），
#      不是把同一个公式再写一遍。近似对近似没有意义，同理
#      "用同一套 lowbit 逻辑验自己"也没有意义。
#   ③ **结构**断言：前缀/加法的访存次数 ≤ log2(n)+1（证明是 O(log n) 跳转，
#      不是退化成线性扫描）；BITSTP == ⌊log2 n⌋+1（二分提升的步数是确定的）。
#   ④ **非空转守卫**：
#        - lower_bound 的答案必须有相当一部分 ≠ 1（否则说明 k 全落在第一段，
#          "与线性扫描相等"可能只是"都返回 1"）
#        - 合并后的树必须与合并前**确实不同**（否则 bit_diff==0 平凡成立）
#        - bit_lower 的 k 必须真的覆盖到后段
#   ⑤ **负 delta**：BIT 的加法可逆，负 delta 必须同样精确
#      （而 bit_lower 要求单调，这一点在库文档里写明，不在测试里含糊过去）

import "assert.mo";
import "bit.mo";

var NN: i64 = 512;

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

# ── 暴力参照（平铺数组，1-based）────────────────────────────
var A: [600] i64 = 0;
var SRC: [600] i64 = 0;
var SRC2: [600] i64 = 0;
var SRC3: [600] i64 = 0;

fn brute_prefix(i: i64) -> i64 {
    let s: i64 = 0;
    let j: i64 = 1;
    while j <= i {
        s = s + A[j];
        j = j + 1;
    }
    return s;
}

fn brute_range(l: i64, r: i64) -> i64 {
    let s: i64 = 0;
    let j: i64 = l;
    while j <= r {
        s = s + A[j];
        j = j + 1;
    }
    return s;
}

# 线性扫描版 lower_bound：第一个使前缀和 ≥ k 的下标
fn brute_lower(k: i64) -> i64 {
    let s: i64 = 0;
    let j: i64 = 1;
    while j <= NN {
        s = s + A[j];
        if s >= k { return j; }
        j = j + 1;
    }
    return NN + 1;
}

fn main() -> i64 {
    SSEED = 88172645463325252;

    let h: i64 = bit_new(NN);
    assert_true("bit_new 返回合法句柄", h >= 0);
    assert_eq("bit_n 返回 n", bit_n(h), NN);
    assert_eq("空树 total 为 0", bit_total(h), 0);

    let i: i64 = 0;
    let d: i64 = 0;
    let l: i64 = 0;
    let r: i64 = 0;
    let got: i64 = 0;
    let want: i64 = 0;
    let bad: i64 = 0;
    let k: i64 = 0;
    let maxmov: i64 = 0;

    # ── ① 随机正 delta 插入 ────────────────────────────────
    i = 0;
    while i < 3000 {
        let idx: i64 = 1 + nxr(NN);
        d = 1 + nxr(9);
        A[idx] = A[idx] + d;
        bit_add(h, idx, d);
        i = i + 1;
    }

    # ── ② 前缀和：与暴力逐位相等 ───────────────────────────
    bad = 0;
    maxmov = 0;
    i = 0;
    while i < 200 {
        let q: i64 = 1 + nxr(NN);
        got = bit_prefix(h, q);
        want = brute_prefix(q);
        if got != want { bad = bad + 1; }
        if BITMOV > maxmov { maxmov = BITMOV; }
        i = i + 1;
    }
    assert_eq("200 个前缀和与暴力逐位相等", bad, 0);

    # ── ③ 区间和 ───────────────────────────────────────────
    bad = 0;
    i = 0;
    while i < 200 {
        l = 1 + nxr(NN);
        r = l + nxr(NN - l + 1);
        got = bit_range(h, l, r);
        want = brute_range(l, r);
        if got != want { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("200 个区间和与暴力逐位相等", bad, 0);

    # ── ④ total ────────────────────────────────────────────
    want = brute_prefix(NN);
    assert_eq("total 等于暴力总和", bit_total(h), want);

    # ── ⑤ 结构断言：前缀访存次数 ≤ log2(n)+1 ───────────────
    assert_true("前缀访存次数 ≤ 10（O(log n) 而非线性）", maxmov <= 10);
    assert_true("前缀访存次数 ≥ 2（确实走了树）", maxmov >= 2);

    # ── ⑥ lower_bound 与线性扫描逐位相等 ───────────────────
    bad = 0;
    let ntriv: i64 = 0;
    let nlate: i64 = 0;
    i = 0;
    while i < 300 {
        k = 1 + nxr(brute_prefix(NN));
        got = bit_lower(h, k);
        want = brute_lower(k);
        if got != want { bad = bad + 1; }
        if want > 1 { ntriv = ntriv + 1; }
        if want > NN / 2 { nlate = nlate + 1; }
        i = i + 1;
    }
    assert_eq("300 个 lower_bound 与线性扫描逐位相等", bad, 0);
    assert_true("lower_bound 非空转：多数答案 ≠ 1", ntriv > 150);
    assert_true("lower_bound 覆盖到后段（答案 > n/2）", nlate > 0);
    assert_eq("二分提升步数 == ⌊log2 n⌋+1", BITSTP, 10);

    # ── ⑦ bit_set ──────────────────────────────────────────
    bad = 0;
    i = 0;
    while i < 100 {
        let idx2: i64 = 1 + nxr(NN);
        d = nxr(50);
        bit_set(h, idx2, d);
        A[idx2] = d;
        if bit_point(h, idx2) != d { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("100 次 bit_set 后点值精确", bad, 0);
    assert_eq("set 之后 total 仍精确", bit_total(h), brute_prefix(NN));

    # ── ⑧ 负 delta：加法可逆，必须同样精确 ─────────────────
    bad = 0;
    i = 0;
    while i < 500 {
        let idx3: i64 = 1 + nxr(NN);
        d = 0 - (1 + nxr(5));
        A[idx3] = A[idx3] + d;
        bit_add(h, idx3, d);
        i = i + 1;
    }
    i = 0;
    while i < 200 {
        let q2: i64 = 1 + nxr(NN);
        if bit_prefix(h, q2) != brute_prefix(q2) { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("负 delta 后 200 个前缀和仍逐位相等", bad, 0);

    # ── ⑨ O(n) 批量建树 与 逐点插入 必须完全一致 ───────────
    let t1: i64 = bit_new(NN);
    let t2: i64 = bit_new(NN);
    i = 1;
    while i <= NN {
        SRC[i] = nxr(1000);
        i = i + 1;
    }
    bit_build(t1, &SRC, NN);
    i = 1;
    while i <= NN {
        bit_add(t2, i, SRC[i]);
        i = i + 1;
    }
    assert_eq("O(n) 建树与逐点插入逐格相等", bit_diff(t1, t2), 0);
    i = 1;
    while i <= NN {
        A[i] = SRC[i];
        i = i + 1;
    }
    assert_eq("建树后 total 精确", bit_total(t1), brute_prefix(NN));
    bad = 0;
    i = 1;
    while i <= NN {
        if bit_prefix(t1, i) != brute_prefix(i) { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("建树后全部 n 个前缀和逐位相等", bad, 0);

    # ── ⑩ 合并 / 拆分：精确，且不是"什么都没变"────────────
    let ta: i64 = bit_new(NN);
    let tb: i64 = bit_new(NN);
    let tc: i64 = bit_new(NN);
    i = 1;
    while i <= NN {
        SRC2[i] = nxr(700);
        SRC3[i] = SRC[i] + SRC2[i];
        i = i + 1;
    }
    bit_build(ta, &SRC, NN);
    bit_build(tb, &SRC2, NN);
    bit_build(tc, &SRC3, NN);

    let dbefore: i64 = bit_diff(ta, tc);
    assert_true("合并前 ta 与 tc 确实不同（非空转守卫）", dbefore > 0);

    bit_merge(ta, tb);
    assert_eq("merge 与直接构造逐格相等", bit_diff(ta, tc), 0);
    assert_eq("merge 后 total 精确", bit_total(ta), bit_total(tc));

    bit_sub(ta, tb);
    assert_eq("sub 是 merge 的逆运算（逐格还原）", bit_diff(ta, t2), 0);

    # ── ⑪ 参数非法必须响出来，不静默截断 ───────────────────
    let badbefore: i64 = BITBAD;
    assert_eq("add 下标 0 返回 -1", bit_add(h, 0, 1), 0 - 1);
    assert_eq("add 下标 n+1 返回 -1", bit_add(h, NN + 1, 1), 0 - 1);
    assert_eq("prefix 下标 n+1 返回 -1", bit_prefix(h, NN + 1), 0 - 1);
    assert_eq("range 左 > 右 返回 -1", bit_range(h, 10, 5), 0 - 1);
    assert_eq("长度不匹配的 merge 返回 -1", bit_merge(ta, bit_new(8)), 0 - 1);
    assert_true("非法参数确实置了 BITBAD", BITBAD > badbefore);

    # ── ⑫ 边界：k 超出总和返回 n+1 ─────────────────────────
    assert_eq("k 大于总和时返回 n+1", bit_lower(t1, bit_total(t1) + 1), NN + 1);
    assert_eq("k ≤ 0 时返回 1", bit_lower(t1, 0), 1);

    return test_done();
}
