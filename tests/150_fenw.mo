# expect: 0
# 150_fenw —— Fenwick 树（BIT）
#
# 判据设计（本测试最要紧的部分）：
#   ① **精确性**：Fenwick 是确定性结构，答案必须 == 暴力，不是"接近"。
#      这与 Bloom/CMS/HLL/qdigest 那组概率性草图相反 —— 后者断言的是
#      误差上界，这里断言的是 0 处不一致。
#   ② **结构性**：FWSTEP 必须等于 popcount(i)（前缀）与
#      floor(log2 n)+1（二进制提升）。这是本测试独有的价值 ——
#      它能在"答案碰巧对"时**仍然**抓出 lowbit 遍历被改坏
#      （见 M1 变异：值全对、结构全错）。
#   ③ **非空转守卫**：全体和 > 0、绝大多数元素非零、区间加覆盖大多数位置。
#      否则"0 处不一致"可能只是"全是 0 对 0"。
#   ④ **越界一律报错**，不静默夹紧。
#
# 参照一律是**暴力算法**（直接累加），不是另一个数据结构。

import "assert.mo";
import "fenw.mo";

var SEED: i64 = 0;
fn nx() -> i64 {
    SEED = SEED ^ (SEED << 13);
    SEED = SEED ^ (SEED >> 7);
    SEED = SEED ^ (SEED << 17);
    if SEED < 0 { SEED = 0 - SEED; }
    return SEED;
}
fn nxr(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return nx() % n;
}

var N1: i64 = 512;            # 形态 ①② 的规模
var N2: i64 = 256;            # 形态 ③④ 的规模

var A: [520] i64 = 0;         # 参照：原始值
var PS: [520] i64 = 0;        # 参照：精确前缀和
var B: [300] i64 = 0;         # 参照：区间加之后的点值
var PB: [300] i64 = 0;        # 参照：区间加之后的精确前缀和

fn popcount(x: i64) -> i64 {
    let c: i64 = 0;
    let b: i64 = 0;
    while x > 0 {
        b = x & 1;
        if b == 1 { c = c + 1; }
        x = x / 2;
    }
    return c;
}

fn flog2(x: i64) -> i64 {
    let c: i64 = 0;
    while x > 1 { x = x / 2; c = c + 1; }
    return c;
}

# 暴力：最小的 j 使 PS[j] >= t
fn bf_lower(t: i64) -> i64 {
    let j: i64 = 1;
    while j <= N1 {
        if PS[j] >= t { return j; }
        j = j + 1;
    }
    return N1 + 1;
}

fn main() -> i64 {
    SEED = 20240917;

    let h: i64 = fw_new(N1);
    assert_true("new 返回合法句柄", h >= 0);
    assert_eq("fw_n 返回 n", fw_n(h), N1);

    # ── 构造：512 个 0..99 的随机值 ───────────────────────
    let i: i64 = 1;
    let v: i64 = 0;
    while i <= N1 {
        v = nxr(100);
        A[i] = v;
        fw_add(h, i, v);
        i = i + 1;
    }
    PS[0] = 0;
    i = 1;
    while i <= N1 {
        PS[i] = PS[i - 1] + A[i];
        i = i + 1;
    }

    # ── ① 512 个前缀和逐位相等 + ② 结构性步数 ──────────────
    let bad: i64 = 0;
    let badstep: i64 = 0;
    i = 1;
    while i <= N1 {
        v = fw_prefix(h, i);
        if v != PS[i] { bad = bad + 1; }
        if FWSTEP != popcount(i) { badstep = badstep + 1; }
        i = i + 1;
    }
    assert_eq("512 个前缀和全部逐位相等", bad, 0);
    assert_eq("FWSTEP == popcount(i)（lowbit 遍历结构正确）", badstep, 0);
    assert_eq("全体和", fw_total(h), PS[N1]);

    # ── 区间和（形态 ②）───────────────────────────────────
    let l: i64 = 0;
    let r: i64 = 0;
    let want: i64 = 0;
    let got: i64 = 0;
    let badr: i64 = 0;
    i = 0;
    while i < 200 {
        l = 1 + nxr(N1);
        r = l + nxr(N1 - l + 1);
        want = PS[r] - PS[l - 1];
        got = fw_range(h, l, r);
        if got != want { badr = badr + 1; }
        i = i + 1;
    }
    assert_eq("200 个随机区间和全部相等", badr, 0);

    # ── lower_bound（二进制提升）──────────────────────────
    let t: i64 = 0;
    let badlb: i64 = 0;
    i = 0;
    while i < 300 {
        t = 1 + nxr(PS[N1] + 60);
        got = fw_lower(h, t);
        want = bf_lower(t);
        if got != want { badlb = badlb + 1; }
        i = i + 1;
    }
    assert_eq("300 个 lower_bound 与暴力一致", badlb, 0);
    assert_eq("lower_bound 步数 == floor(log2 n)+1", FWSTEP, flog2(N1) + 1);
    assert_eq("target=1 命中首个达到它的下标", fw_lower(h, 1), bf_lower(1));
    assert_eq("target 超过全体和 → n+1（不静默给 n）", fw_lower(h, PS[N1] + 1), N1 + 1);

    # ── 形态 ④：区间加 + 区间和 ───────────────────────────
    let h2: i64 = fw_new(N2);
    assert_true("h2 返回合法句柄", h2 >= 0);
    let j: i64 = 0;
    i = 0;
    while i < 400 {
        l = 1 + nxr(N2);
        r = l + nxr(N2 - l + 1);
        v = nxr(101) - 50;                  # d ∈ [-50, 50]
        fw_radd(h2, l, r, v);
        j = l;
        while j <= r {
            B[j] = B[j] + v;
            j = j + 1;
        }
        i = i + 1;
    }
    PB[0] = 0;
    j = 1;
    while j <= N2 {
        PB[j] = PB[j - 1] + B[j];
        j = j + 1;
    }

    # 点值：形态 ③④ 下 B1 的前缀就是 A[i]
    let badp: i64 = 0;
    j = 1;
    while j <= N2 {
        if fw_prefix(h2, j) != B[j] { badp = badp + 1; }
        j = j + 1;
    }
    assert_eq("256 个点值与暴力一致（区间加模式）", badp, 0);

    let badrs: i64 = 0;
    i = 0;
    while i < 200 {
        l = 1 + nxr(N2);
        r = l + nxr(N2 - l + 1);
        want = PB[r] - PB[l - 1];
        got = fw_rsum(h2, l, r);
        if got != want { badrs = badrs + 1; }
        i = i + 1;
    }
    assert_eq("200 个区间和（区间加模式）全部相等", badrs, 0);

    # ── ④ 越界一律报错，不静默夹紧 ────────────────────────
    assert_eq("add(0) 报错", fw_add(h, 0, 1), 0 - 1);
    assert_eq("add(n+1) 报错", fw_add(h, N1 + 1, 1), 0 - 1);
    assert_true("越界置 FWBAD", FWBAD == 1);
    assert_eq("prefix(n+1) 报错", fw_prefix(h, N1 + 1), 0 - 1);
    assert_eq("空区间和为 0", fw_range(h, 5, 3), 0);
    assert_eq("new(0) 报错", fw_new(0), 0 - 1);
    assert_eq("new(超上限) 报错", fw_new(FW_MAXN + 1), 0 - 1);
    assert_true("超上限置 FWOV", FWOV == 1);

    # ── ③ 非空转守卫 ──────────────────────────────────────
    assert_true("非空转：全体和 > 0", PS[N1] > 0);
    let nz: i64 = 0;
    i = 1;
    while i <= N1 {
        if A[i] != 0 { nz = nz + 1; }
        i = i + 1;
    }
    assert_true("非空转：绝大多数元素非零", nz > 400);
    let nzb: i64 = 0;
    j = 1;
    while j <= N2 {
        if B[j] != 0 { nzb = nzb + 1; }
        j = j + 1;
    }
    assert_true("非空转：区间加覆盖了大多数位置", nzb > 200);

    print("n1=");
    print_i64(N1);
    print(" total=");
    print_i64(PS[N1]);
    print(" n2=");
    print_i64(N2);
    print(" nz=");
    print_i64(nz);
    print(" nzb=");
    print_i64(nzb);
    print_nl();

    return test_done();
}
