# fenw —— Fenwick 树（Binary Indexed Tree / 二叉索引树）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Peter M. Fenwick 1994
#   《A New Data Structure for Cumulative Frequency Tables》
#   Software: Practice and Experience 24(3)
#
#   核心恒等式：设 lowbit(i) = i & (-i)（i 的最低置位），则
#       T[i] = A[i - lowbit(i) + 1 .. i]        （半开区间树）
#   于是两次遍历都只走 O(log n) 步：
#       prefix(i) = Σ T[k]，k 从 i 起不断 k -= lowbit(k)
#       add(i,d)  = 所有 k 起不断 k += lowbit(k) 的 T[k] += d
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   **没有任何主流语言的标准库收录它**。C++ 标准库里没有，
#   Python / Java / Go / Rust 也全靠第三方或手写。它常被当作
#   "十行代码片段"而不是一个正式的数据结构 —— 但下面四种形态里
#   有两种（区间加 + 区间和）**不是**十行能写对的。
#
# ── 与四个概率性草图的关系（本库真正的定位）────────────────
#   Bloom(v1.144) / CMS(v1.144) / HLL(v1.138) / qdigest(v1.147)
#   都是用**可控误差**换亚线性空间；Fenwick 走另一条路：
#   空间 O(n)、**答案精确**。它们回答的是同一类问题
#   （频次 / 前缀 / 秩），只是精度-空间取舍相反 ——
#   草图答"大约是多少"，Fenwick 答"恰好是多少"。
#   ⇒ 因此本库的判据一律是 == ，不是"接近"。
#
# ── 四种形态（同一句柄只能用一种，混用会给出无意义的值）────
#   ① 单点加 + 前缀和      fw_add / fw_prefix
#   ② 单点加 + 区间和      fw_add / fw_range
#   ③ 区间加 + 单点查      fw_radd / fw_prefix（B1 前缀即点值）
#   ④ 区间加 + 区间和      fw_radd / fw_rsum
#
#   ④ 的公式（两只 BIT，B1 存差分、B2 存加权差分）：
#       radd(l,r,d):  B1[l] += d,   B1[r+1] -= d
#                     B2[l] += d*(l-1), B2[r+1] -= d*r
#       prefix(i)   = i * B1.pre(i) - B2.pre(i)
#   推导：对任意区间 [l,r]，它在 i 处贡献
#       i>r  → d*(r-l+1)（整段）；l<=i<=r → d*(i-l+1)（部分）；
#       l>i  → 0
#   代入上式三项（+d*i / -d*(l-1) / +d*r）恰好分别命中，逐项可验。
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   FWI / FWJ / FWV / FWW / FWPW / FWK 是本库内部的循环/临时变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 fw_add 就改掉它们，
#   外层循环当场退出，症状是"只处理了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   CMS(v1.144)、qdigest(v1.147) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   下标一律 **1-based**（1..n）。越界一律返回 -1 并置 FWBAD / FWOV，
#   **不静默按 0 或按边界处理**（悄悄夹紧会让调用方以为数据是对的）。
#
# ── 诊断量（供测试做结构性断言，不是装饰）──────────────────
#   FWSTEP = 上一次遍历走过的步数。
#     · fw_prefix(i) 走 **popcount(i)** 步（每次剥掉一个置位）
#     · fw_lower()   走 **floor(log2 n) + 1** 步（二进制提升）
#   这两个数是**结构**性质：即使答案碰巧对，步数不对就说明
#   lowbit 遍历被改坏了（见 tests/150_fenw.mo 的 M1 变异）。

# ── 常量 ───────────────────────────────────────────────────
var FW_MAXN: i64 = 4096;

# ── 池：每个 sketch 占 2n + 3 个字 ─────────────────────────
#   base + 0          = n
#   base + 1 + i      = B1[i]   （i = 1..n）
#   base + 2 + n + i  = B2[i]   （i = 1..n，仅形态 ③④ 用）
var FWP: [60000] i64 = 0;
var FWFREE: i64 = 0;

# ── 诊断 / 状态 ────────────────────────────────────────────
var FWOV: i64 = 0;          # 池越界 / n 超上限
var FWBAD: i64 = 0;         # 参数非法（下标越界、空区间加法）
var FWSTEP: i64 = 0;        # 上一次遍历的步数（结构性断言用）

# ── 专用循环/临时变量（调用方不得使用）────────────────────
var FWI: i64 = 0;
var FWJ: i64 = 0;
var FWK: i64 = 0;
var FWV: i64 = 0;
var FWW: i64 = 0;
var FWPW: i64 = 0;

# ── 生命周期 ───────────────────────────────────────────────
fn fw_new(n: i64) -> i64 {
    if n < 1 { FWBAD = 1; return 0 - 1; }
    if n > FW_MAXN { FWOV = 1; return 0 - 1; }
    let h: i64 = FWFREE;
    FWP[h] = n;
    FWFREE = FWFREE + 2 * n + 3;
    if FWFREE > 60000 { FWOV = 1; return 0 - 1; }
    return h;
}

fn fw_n(h: i64) -> i64 {
    return FWP[h];
}

# ── 形态 ①②：单点加 ───────────────────────────────────────
# T[k] += d，k 从 i 起不断 k += lowbit(k)
fn fw_add(h: i64, i: i64, d: i64) -> i64 {
    let n: i64 = FWP[h];
    if i < 1 { FWBAD = 1; return 0 - 1; }
    if i > n { FWBAD = 1; return 0 - 1; }
    FWI = i;
    while FWI <= n {
        FWP[h + 1 + FWI] = FWP[h + 1 + FWI] + d;
        FWI = FWI + (FWI & (0 - FWI));
    }
    return 0;
}

# ── 前缀和：Σ T[k]，k 从 i 起不断 k -= lowbit(k) ───────────
# 形态 ①② 下返回 A[1..i] 之和；形态 ③④ 下返回 **A[i] 本身**
# （因为 B1 存的是差分数组，其前缀就是点值）。
fn fw_prefix(h: i64, i: i64) -> i64 {
    let n: i64 = FWP[h];
    if i < 0 { FWBAD = 1; return 0 - 1; }
    if i > n { FWBAD = 1; return 0 - 1; }
    FWV = 0;
    FWSTEP = 0;
    FWI = i;
    while FWI > 0 {
        FWV = FWV + FWP[h + 1 + FWI];
        FWI = FWI - (FWI & (0 - FWI));
        FWSTEP = FWSTEP + 1;
    }
    return FWV;
}

# B2 的前缀（内部用；不置 FWSTEP，免得盖掉调用方要看的数）
fn fw_pb2(h: i64, i: i64) -> i64 {
    let n: i64 = FWP[h];
    FWV = 0;
    FWI = i;
    while FWI > 0 {
        FWV = FWV + FWP[h + 2 + n + FWI];
        FWI = FWI - (FWI & (0 - FWI));
    }
    return FWV;
}

# ── 区间和（形态 ②：单点加模式下）─────────────────────────
fn fw_range(h: i64, l: i64, r: i64) -> i64 {
    let n: i64 = FWP[h];
    if l < 1 { FWBAD = 1; return 0 - 1; }
    if r > n { FWBAD = 1; return 0 - 1; }
    if l > r { return 0; }
    let hi: i64 = fw_prefix(h, r);
    let lo: i64 = fw_prefix(h, l - 1);
    if hi < 0 { return 0 - 1; }
    if lo < 0 { return 0 - 1; }
    return hi - lo;
}

# ── 全体之和 ───────────────────────────────────────────────
fn fw_total(h: i64) -> i64 {
    return fw_prefix(h, FWP[h]);
}

# ── lower_bound：最小的 idx 使 prefix(idx) >= target ───────
# 二进制提升（binary lifting），不是二分搜索 ——
# 它直接在 BIT 的数组上走，不需要另开数组。
# FWSTEP 会被置为 floor(log2 n) + 1（结构性断言用）。
# target > 全体和时返回 n + 1（表示"越界"，不是静默给 n）。
fn fw_lower(h: i64, target: i64) -> i64 {
    let n: i64 = FWP[h];
    if target <= 0 { return 1; }
    FWK = 0;
    FWW = target;
    FWPW = 1;
    while FWPW * 2 <= n { FWPW = FWPW * 2; }
    FWSTEP = 0;
    while FWPW > 0 {
        FWI = FWK + FWPW;
        if FWI <= n {
            if FWP[h + 1 + FWI] < FWW {
                FWK = FWI;
                FWW = FWW - FWP[h + 1 + FWI];
            }
        }
        FWPW = FWPW / 2;
        FWSTEP = FWSTEP + 1;
    }
    return FWK + 1;
}

# ── 形态 ③④：区间加 ──────────────────────────────────────
fn fw_addb2(h: i64, i: i64, d: i64) -> i64 {
    let n: i64 = FWP[h];
    if i < 1 { FWBAD = 1; return 0 - 1; }
    if i > n { FWBAD = 1; return 0 - 1; }
    FWI = i;
    while FWI <= n {
        FWP[h + 2 + n + FWI] = FWP[h + 2 + n + FWI] + d;
        FWI = FWI + (FWI & (0 - FWI));
    }
    return 0;
}

fn fw_radd(h: i64, l: i64, r: i64, d: i64) -> i64 {
    let n: i64 = FWP[h];
    if l < 1 { FWBAD = 1; return 0 - 1; }
    if r > n { FWBAD = 1; return 0 - 1; }
    if l > r { FWBAD = 1; return 0 - 1; }
    fw_add(h, l, d);
    fw_addb2(h, l, d * (l - 1));
    if r + 1 <= n {
        fw_add(h, r + 1, 0 - d);
        fw_addb2(h, r + 1, 0 - d * r);
    }
    return 0;
}

# ── 形态 ④：区间和 ─────────────────────────────────────────
#   sum(l..r) = [r*B1.pre(r) - B2.pre(r)] - [(l-1)*B1.pre(l-1) - B2.pre(l-1)]
fn fw_rsum(h: i64, l: i64, r: i64) -> i64 {
    let n: i64 = FWP[h];
    if l < 1 { FWBAD = 1; return 0 - 1; }
    if r > n { FWBAD = 1; return 0 - 1; }
    if l > r { return 0; }
    let p1: i64 = fw_prefix(h, r);
    let q1: i64 = fw_pb2(h, r);
    let hi: i64 = r * p1 - q1;
    let lo: i64 = 0;
    if l > 1 {
        let p0: i64 = fw_prefix(h, l - 1);
        let q0: i64 = fw_pb2(h, l - 1);
        lo = (l - 1) * p0 - q0;
    }
    return hi - lo;
}
