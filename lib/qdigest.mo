# qdigest —— Q-digest 分位数草图（用墨语言自己写的）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Nisheeth Shrivastava, Chiranjeeb Buragohain, Divyakant Agrawal,
#   Subhash Suri 2004
#   《Medians and Beyond: New Aggregation Techniques for Sensor Networks》
#
#   结构：在值域 [1, σ] 上建一棵 **二分区间树**（dyadic tree），
#   每个节点代表一个形如 [j·L+1, (j+1)·L] 的区间，L 是 2 的幂。
#   插入一个值 = 给对应**叶子**的计数 +1。
#   压缩 = 自底向上：若某节点及两个孩子的计数之和 ≤ k，
#          就把孩子并进父节点（父 += 左 + 右，孩子清零）。
#   查询 = 把非空节点按 **右端点升序** 累加计数，
#          累到目标秩时返回该节点的右端点。
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   它与已有的三个草图构成"流数据摘要"的四件套，而**四个都没进任何
#   主流语言的标准库**：
#     Bloom(v1.144)   → 成员判定      → 只假阳
#     CMS  (v1.144)   → 频次估计      → 只高估
#     HLL  (v1.138)   → 基数估计      → 相对误差 1.04/√m
#     qdigest         → 分位数估计    → 秩误差 ≤ εN
#   Python/Java/Go/C++ 均只有第三方实现（datasketch / stream-lib / ...）。
#
# ── 与 HLL 的分工 ──────────────────────────────────────────
#   HLL 回答"有多少个**不同的**"，qdigest 回答"排第 q 的那个是几"。
#   两者对同一条流给出的是互补的两个数，互不替代。
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   QI / QJ / QK / QV / QW 是本库内部的循环/临时变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 qd_add 就改掉它们，
#   外层循环当场退出，症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   CMS(v1.144) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   值域固定 [1, QD_SIG]（QD_SIG = 4096）。超出范围的值返回 -1
#   并置 QDBAD，**不静默截断**（截断会让分位数悄悄偏走）。
#   φ 用**千分数**传入（0..1000），避免浮点。
#   合并是**逐节点相加** —— 线性、可交换、可结合，
#   因此 qdigest **可以分布式聚合**（这一点与 CMS 的
#   Conservative Update 相反，见 docs/sketch.md）。

# ── 常量 ───────────────────────────────────────────────────
# σ = 4096 ⇒ 叶子 4096..8191，内部节点 1..4095，根 = 1
#   节点 i 覆盖的区间长度 = σ / 2^depth(i)
var QD_SIG: i64 = 4096;

# ── 池：每个 sketch 占 2 + 8192 个字 ───────────────────────
#   base + 0        = N（累计插入数）
#   base + 1        = 保留
#   base + 2 + i    = 节点 i 的计数（i = 1..8191）
var QDP: [50000] i64 = 0;
var QDFREE: i64 = 0;

# ── 诊断 / 状态 ────────────────────────────────────────────
var QDOV: i64 = 0;      # 池越界
var QDBAD: i64 = 0;     # 参数非法（值越界 / φ 越界）
var QDNNZ: i64 = 0;     # 上一次 qd_size 统计到的非空节点数（诊断用）

# ── 专用循环/临时变量 ──────────────────────────────────────
var QI: i64 = 0;
var QJ: i64 = 0;
var QK: i64 = 0;
var QV: i64 = 0;
var QW: i64 = 0;

# 查询用的计数排序暂存：索引 = 右端点（1..σ）
var QHB: [4098] i64 = 0;

# ── 节点区间的左右端点 ─────────────────────────────────────
# depth(i) = floor(log2(i))，len = σ >> depth
# lo = (i - 2^depth) * len + 1，hi = lo + len - 1
fn qd_depth(i: i64) -> i64 {
    QK = 0;
    QW = 1;
    while QW * 2 <= i {
        QW = QW * 2;
        QK = QK + 1;
    }
    return QK;
}

fn qd_lo(i: i64) -> i64 {
    let d: i64 = qd_depth(i);
    let pw: i64 = 1 << d;
    let len: i64 = QD_SIG >> d;
    return (i - pw) * len + 1;
}

fn qd_hi(i: i64) -> i64 {
    let d: i64 = qd_depth(i);
    let pw: i64 = 1 << d;
    let len: i64 = QD_SIG >> d;
    return (i - pw) * len + len;
}

# ── 新建 ───────────────────────────────────────────────────
fn qd_new() -> i64 {
    let base: i64 = QDFREE;
    if base + 2 + 8192 > 50000 { QDOV = 1; return 0 - 1; }
    QDFREE = base + 2 + 8192;
    QI = 0;
    while QI < 8192 {
        QDP[base + 2 + QI] = 0;
        QI = QI + 1;
    }
    QDP[base] = 0;
    QDP[base + 1] = 0;
    return base;
}

# ── 插入 ───────────────────────────────────────────────────
fn qd_add(h: i64, v: i64) -> i64 {
    if v < 1 { QDBAD = 1; return 0 - 1; }
    if v > QD_SIG { QDBAD = 1; return 0 - 1; }
    let leaf: i64 = QD_SIG + v - 1;
    QDP[h + 2 + leaf] = QDP[h + 2 + leaf] + 1;
    QDP[h] = QDP[h] + 1;
    return 0;
}

# ── 计数总和（**永远等于 N**，压缩只是把计数上移，不丢）────
fn qd_total(h: i64) -> i64 {
    QV = 0;
    QI = 1;
    while QI <= 8191 {
        QV = QV + QDP[h + 2 + QI];
        QI = QI + 1;
    }
    return QV;
}

# ── 非空节点数（压缩的效果就看它）─────────────────────────
fn qd_size(h: i64) -> i64 {
    QV = 0;
    QI = 1;
    while QI <= 8191 {
        if QDP[h + 2 + QI] != 0 { QV = QV + 1; }
        QI = QI + 1;
    }
    QDNNZ = QV;
    return QV;
}

# ── 压缩 ───────────────────────────────────────────────────
# 🔴 必须**自底向上**（i 从 σ-1 递减到 1）。
#    若改成自顶向下，父节点先并完、孩子已清零 ⇒ 压缩只对最上面几层生效，
#    非空节点数几乎不下降 —— 不报错、不崩溃，只是"压缩看起来没用"。
#    tests/149 用 qd_size 的上界断言钉住它（M4 变异实测被捕获）。
fn qd_compress(h: i64, k: i64) -> i64 {
    if k < 0 { QDBAD = 1; return 0 - 1; }
    # ⚠️ 循环体内不声明 let（墨语言会累积栈帧），临时量一律用库级变量
    QI = QD_SIG - 1;
    while QI >= 1 {
        QV = QDP[h + 2 + QI * 2];
        QW = QDP[h + 2 + QI * 2 + 1];
        QK = QDP[h + 2 + QI];
        if QK + QV + QW <= k {
            QDP[h + 2 + QI] = QK + QV + QW;
            QDP[h + 2 + QI * 2] = 0;
            QDP[h + 2 + QI * 2 + 1] = 0;
        }
        QI = QI - 1;
    }
    return 0;
}

# ── 查询 ───────────────────────────────────────────────────
# phi_ppm：千分数（0..1000）。目标秩 r = ceil(phi_ppm * N / 1000)。
# 做法：把非空节点按**右端点**做计数排序（O(σ + 非空数)），
#       再从小到大累加，第一次达到 r 时返回该右端点。
fn qd_query(h: i64, phi_ppm: i64) -> i64 {
    if phi_ppm < 0 { QDBAD = 1; return 0 - 1; }
    if phi_ppm > 1000 { QDBAD = 1; return 0 - 1; }
    let n: i64 = QDP[h];
    if n == 0 { return 0; }
    let r: i64 = (phi_ppm * n + 999) / 1000;
    if r < 1 { r = 1; }
    if r > n { r = n; }

    QI = 1;
    while QI <= QD_SIG {
        QHB[QI] = 0;
        QI = QI + 1;
    }
    QI = 1;
    while QI <= 8191 {
        QV = QDP[h + 2 + QI];
        if QV != 0 {
            QW = qd_hi(QI);
            QHB[QW] = QHB[QW] + QV;
        }
        QI = QI + 1;
    }
    QV = 0;
    QI = 1;
    while QI <= QD_SIG {
        QV = QV + QHB[QI];
        if QV >= r { return QI; }
        QI = QI + 1;
    }
    return QD_SIG;
}

# ── 合并（**逐节点相加**）──────────────────────────────────
# 线性 ⇒ 可交换、可结合 ⇒ 可分布式聚合。
# 这与 CMS 的 Conservative Update 正好相反（CU 不线性，见 v1.145）。
# N 也相加，因此合并后的草图就是"把两条流当一条"的草图。
fn qd_merge(a: i64, b: i64) -> i64 {
    let c: i64 = qd_new();
    if c < 0 { return 0 - 1; }
    QI = 1;
    while QI <= 8191 {
        QDP[c + 2 + QI] = QDP[a + 2 + QI] + QDP[b + 2 + QI];
        QI = QI + 1;
    }
    QDP[c] = QDP[a] + QDP[b];
    return c;
}

# ── 取节点计数（供测试核对）────────────────────────────────
fn qd_cnt(h: i64, i: i64) -> i64 {
    return QDP[h + 2 + i];
}

# ── 取 N ───────────────────────────────────────────────────
fn qd_n(h: i64) -> i64 {
    return QDP[h];
}
