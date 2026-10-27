# seg —— 线段树（Segment Tree）+ 懒标记（lazy propagation）
#
# ── 概念来源 ────────────────────────────────────────────────
#   线段树最早见于算法竞赛与计算几何教材（结构本身无单一发明人），
#   "懒标记 / lazy propagation" 是区间更新延迟下推的通行手法。
#   与 Fenwick(v1.148) 一样，**没有任何主流语言的标准库收录它**：
#   C++ 只有非标准的 __gnu_pbds / boost::icl 旁支，
#   Python / Java / Go / Rust 一律靠第三方或手写。
#
# ── 与 Fenwick 的分工（本库真正的定位）────────────────────
#   Fenwick 的前提是运算**可逆**（有逆元）——它靠差分 + 前缀和
#   把区间操作化成两次单点操作，所以只能做加法类的东西。
#   线段树的前提只是运算**可结合**（半群），因此能做：
#     · max / min / gcd —— **没有逆元**，Fenwick 结构上做不到
#     · 区间**赋值**（rset）—— 覆盖而非叠加，Fenwick 做不到
#   本库同时维护 sum 与 max 两个聚合量，就是为了把这条界线钉死：
#   同一棵树、同样的区间更新，sum 走加法、max 走半群。
#   ⇒ 判据一律 == （精确结构，不是草图）。
#
# ── 标记优先级：赋值 > 加法 ────────────────────────────────
#   一个节点上同时挂着"赋成 x"和"加上 y"时，两者**不能交换**：
#     set(x) 后 add(y)  ⟹ 结果是 x+y（赋值标记跟着 +y）
#     add(y) 后 set(x)  ⟹ 结果是 x  （加法标记被清掉）
#   所以 apply_add 必须先判 HS（有赋值标记）再决定往哪儿累加。
#   改错这里不报错、不崩溃，只在两种标记交替出现时给出偏大的值。
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   本库**所有**递归过程只用 let 局部变量（每帧独立），
#   但 SGNEG / SGPUSH / SGNODES 等诊断量是全局的：
#   调用方不得在自己的循环里读它们当循环变量。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   CMS(v1.144)、qdigest(v1.147)、fenw(v1.148) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   下标一律 **1-based** 闭区间 [l, r]。越界返回 -1 并置 SGBAD / SGOV，
#   **不静默夹紧**（悄悄夹紧会让调用方以为数据是对的）。
#   区间为空（l > r）同样报 SGBAD。

# ── 常量 ───────────────────────────────────────────────────
var SEG_MAXN: i64 = 256;
var SEG_CAPW: i64 = 106000;
# 注意：var 的初始值不接受表达式也不接受负号（墨语言限制），
# 所以 SEG_NEG 在 seg_new 里才赋值。直接写 `0 - 999999999` 是语法错误。
var SEG_NEG: i64 = 0;

# ── 池布局：每棵树占 1 + 5*stride 个字，stride = 4n+1 ──────
#   base + 0            = n
#   base + 1 + 0*st + p = SUM[p]   （p = 1..4n）
#   base + 1 + 1*st + p = MAX[p]
#   base + 1 + 2*st + p = ADD[p]   （懒加）
#   base + 1 + 3*st + p = SET[p]   （懒赋值）
#   base + 1 + 4*st + p = HS[p]    （1 = 有赋值标记）
var SEGP: [110000] i64 = 0;
var SEGFREE: i64 = 0;

# ── 诊断 / 状态（供测试做结构性断言，不是装饰）────────────
var SGOV: i64 = 0;        # 池越界 / n 超上限
var SGBAD: i64 = 0;       # 参数非法
var SGNODES: i64 = 0;     # 上一次操作访问的节点数（O(log n) 性质）
var SGPUSH: i64 = 0;      # 上一次操作实际下推标记的次数（>0 = 懒标记真的用上了）

# ── 内部：把一段整块设成 v ─────────────────────────────────
fn sg_apply_set(p: i64, l: i64, r: i64, v: i64, h: i64, st: i64) -> i64 {
    let cnt: i64 = r - l + 1;
    SEGP[h + 1 + p] = v * cnt;
    SEGP[h + 1 + st + p] = v;
    SEGP[h + 1 + 3 * st + p] = v;
    SEGP[h + 1 + 4 * st + p] = 1;
    SEGP[h + 1 + 2 * st + p] = 0;
    return 0;
}

# ── 内部：把一段整块加 v ───────────────────────────────────
#   有赋值标记时必须叠在 SET 上（set 后 add 的语义），否则入 ADD。
fn sg_apply_add(p: i64, l: i64, r: i64, v: i64, h: i64, st: i64) -> i64 {
    let cnt: i64 = r - l + 1;
    SEGP[h + 1 + p] = SEGP[h + 1 + p] + v * cnt;
    SEGP[h + 1 + st + p] = SEGP[h + 1 + st + p] + v;
    if SEGP[h + 1 + 4 * st + p] == 1 {
        SEGP[h + 1 + 3 * st + p] = SEGP[h + 1 + 3 * st + p] + v;
    } else {
        SEGP[h + 1 + 2 * st + p] = SEGP[h + 1 + 2 * st + p] + v;
    }
    return 0;
}

# ── 内部：下推标记到两个孩子 ───────────────────────────────
fn sg_push(p: i64, l: i64, r: i64, h: i64, st: i64) -> i64 {
    if l == r { return 0; }
    let mid: i64 = (l + r) / 2;
    let lc: i64 = 2 * p;
    let rc: i64 = 2 * p + 1;
    if SEGP[h + 1 + 4 * st + p] == 1 {
        let sv: i64 = SEGP[h + 1 + 3 * st + p];
        let d1: i64 = sg_apply_set(lc, l, mid, sv, h, st);
        let d2: i64 = sg_apply_set(rc, mid + 1, r, sv, h, st);
        SEGP[h + 1 + 4 * st + p] = 0;
        SGPUSH = SGPUSH + 1;
    }
    if SEGP[h + 1 + 2 * st + p] != 0 {
        let av: i64 = SEGP[h + 1 + 2 * st + p];
        let d3: i64 = sg_apply_add(lc, l, mid, av, h, st);
        let d4: i64 = sg_apply_add(rc, mid + 1, r, av, h, st);
        SEGP[h + 1 + 2 * st + p] = 0;
        SGPUSH = SGPUSH + 1;
    }
    return 0;
}

# ── 内部：区间加 ───────────────────────────────────────────
fn sg_radd(p: i64, l: i64, r: i64, ql: i64, qr: i64, v: i64, h: i64, st: i64) -> i64 {
    SGNODES = SGNODES + 1;
    if qr < l { return 0; }
    if r < ql { return 0; }
    if ql <= l {
        if r <= qr {
            let d0: i64 = sg_apply_add(p, l, r, v, h, st);
            return 0;
        }
    }
    let d1: i64 = sg_push(p, l, r, h, st);
    let mid: i64 = (l + r) / 2;
    let d2: i64 = sg_radd(2 * p, l, mid, ql, qr, v, h, st);
    let d3: i64 = sg_radd(2 * p + 1, mid + 1, r, ql, qr, v, h, st);
    SEGP[h + 1 + p] = SEGP[h + 1 + 2 * p] + SEGP[h + 1 + 2 * p + 1];
    let m1: i64 = SEGP[h + 1 + st + 2 * p];
    let m2: i64 = SEGP[h + 1 + st + 2 * p + 1];
    if m1 > m2 { SEGP[h + 1 + st + p] = m1; } else { SEGP[h + 1 + st + p] = m2; }
    return 0;
}

# ── 内部：区间赋值 ─────────────────────────────────────────
fn sg_rset(p: i64, l: i64, r: i64, ql: i64, qr: i64, v: i64, h: i64, st: i64) -> i64 {
    SGNODES = SGNODES + 1;
    if qr < l { return 0; }
    if r < ql { return 0; }
    if ql <= l {
        if r <= qr {
            let d0: i64 = sg_apply_set(p, l, r, v, h, st);
            return 0;
        }
    }
    let d1: i64 = sg_push(p, l, r, h, st);
    let mid: i64 = (l + r) / 2;
    let d2: i64 = sg_rset(2 * p, l, mid, ql, qr, v, h, st);
    let d3: i64 = sg_rset(2 * p + 1, mid + 1, r, ql, qr, v, h, st);
    SEGP[h + 1 + p] = SEGP[h + 1 + 2 * p] + SEGP[h + 1 + 2 * p + 1];
    let m1: i64 = SEGP[h + 1 + st + 2 * p];
    let m2: i64 = SEGP[h + 1 + st + 2 * p + 1];
    if m1 > m2 { SEGP[h + 1 + st + p] = m1; } else { SEGP[h + 1 + st + p] = m2; }
    return 0;
}

# ── 内部：区间和 ───────────────────────────────────────────
fn sg_qsum(p: i64, l: i64, r: i64, ql: i64, qr: i64, h: i64, st: i64) -> i64 {
    SGNODES = SGNODES + 1;
    if qr < l { return 0; }
    if r < ql { return 0; }
    if ql <= l {
        if r <= qr { return SEGP[h + 1 + p]; }
    }
    let d1: i64 = sg_push(p, l, r, h, st);
    let mid: i64 = (l + r) / 2;
    let a: i64 = sg_qsum(2 * p, l, mid, ql, qr, h, st);
    let b: i64 = sg_qsum(2 * p + 1, mid + 1, r, ql, qr, h, st);
    return a + b;
}

# ── 内部：区间最大值 ───────────────────────────────────────
fn sg_qmax(p: i64, l: i64, r: i64, ql: i64, qr: i64, h: i64, st: i64) -> i64 {
    SGNODES = SGNODES + 1;
    if qr < l { return SEG_NEG; }
    if r < ql { return SEG_NEG; }
    if ql <= l {
        if r <= qr { return SEGP[h + 1 + st + p]; }
    }
    let d1: i64 = sg_push(p, l, r, h, st);
    let mid: i64 = (l + r) / 2;
    let a: i64 = sg_qmax(2 * p, l, mid, ql, qr, h, st);
    let b: i64 = sg_qmax(2 * p + 1, mid + 1, r, ql, qr, h, st);
    if a > b { return a; }
    return b;
}

# ── 公开：建树（全 0）──────────────────────────────────────
fn seg_new(n: i64) -> i64 {
    if n < 1 { SGBAD = 1; return 0 - 1; }
    if n > SEG_MAXN { SGOV = 1; return 0 - 1; }
    let h: i64 = SEGFREE;
    let st: i64 = 4 * n + 1;
    if (h + 1 + 5 * st) > SEG_CAPW { SGOV = 1; return 0 - 1; }
    SEG_NEG = 0 - 999999999;
    SEGP[h] = n;
    let i: i64 = 0;
    while i < 5 * st {
        SEGP[h + 1 + i] = 0;
        i = i + 1;
    }
    SEGFREE = h + 1 + 5 * st;
    return h;
}

fn seg_n(h: i64) -> i64 { return SEGP[h]; }

# ── 公开：单点赋值 / 单点加 ────────────────────────────────
fn seg_set(h: i64, i: i64, v: i64) -> i64 {
    let n: i64 = SEGP[h];
    if i < 1 { SGBAD = 1; return 0 - 1; }
    if i > n { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    let d: i64 = sg_rset(1, 1, n, i, i, v, h, st);
    return 0;
}

fn seg_add(h: i64, i: i64, v: i64) -> i64 {
    let n: i64 = SEGP[h];
    if i < 1 { SGBAD = 1; return 0 - 1; }
    if i > n { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    let d: i64 = sg_radd(1, 1, n, i, i, v, h, st);
    return 0;
}

# ── 公开：区间加 / 区间赋值 ────────────────────────────────
fn seg_radd(h: i64, l: i64, r: i64, v: i64) -> i64 {
    let n: i64 = SEGP[h];
    if l < 1 { SGBAD = 1; return 0 - 1; }
    if r > n { SGBAD = 1; return 0 - 1; }
    if l > r { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    let d: i64 = sg_radd(1, 1, n, l, r, v, h, st);
    return 0;
}

fn seg_rset(h: i64, l: i64, r: i64, v: i64) -> i64 {
    let n: i64 = SEGP[h];
    if l < 1 { SGBAD = 1; return 0 - 1; }
    if r > n { SGBAD = 1; return 0 - 1; }
    if l > r { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    let d: i64 = sg_rset(1, 1, n, l, r, v, h, st);
    return 0;
}

# ── 公开：区间和 / 区间最大值 ──────────────────────────────
fn seg_qsum(h: i64, l: i64, r: i64) -> i64 {
    let n: i64 = SEGP[h];
    if l < 1 { SGBAD = 1; return 0 - 1; }
    if r > n { SGBAD = 1; return 0 - 1; }
    if l > r { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    return sg_qsum(1, 1, n, l, r, h, st);
}

fn seg_qmax(h: i64, l: i64, r: i64) -> i64 {
    let n: i64 = SEGP[h];
    if l < 1 { SGBAD = 1; return 0 - 1; }
    if r > n { SGBAD = 1; return 0 - 1; }
    if l > r { SGBAD = 1; return 0 - 1; }
    let st: i64 = 4 * n + 1;
    SGNODES = 0;
    SGPUSH = 0;
    return sg_qmax(1, 1, n, l, r, h, st);
}

fn seg_total(h: i64) -> i64 { return seg_qsum(h, 1, SEGP[h]); }
