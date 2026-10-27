# lsh —— 局部敏感哈希（Locality-Sensitive Hashing）
#
# ── 概念来源 ────────────────────────────────────────────────
#   MinHash（min-wise independent permutations）
#     Broder 1997；Broder–Charikar–Frieze–Mitzenmacher 2000，
#     "Min-wise independent permutations"，JCSS 60(3)
#     → 估计 **Jaccard** 相似度
#   SimHash
#     Charikar 2002 "Similarity estimation techniques from rounding algorithms"
#     → 估计 **余弦 / 角度** 相似度；核心定理 Pr[第 i 位不同] = θ(x,y)/π
#   Banding（把签名切成 band 以放大差距）
#     Indyk & Motwani 1998 "Approximate nearest neighbors: towards removing
#     the curse of dimensionality"
#     → P(成为候选) = 1 − (1 − s^r)^b，一条 S 曲线
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   LSH 是**次线性相似检索**的经典理论基础。但主流框架里一个都没有：
#     Python → datasketch（第三方）、Java → stream-lib（第三方）、
#     C++ → 各家自研；Go / Rust / .NET 标准库无。
#   它也不是"数据结构练习"，核心是一句**概率恒等式**：
#       Pr[ min h(A) = min h(B) ] = |A ∩ B| / |A ∪ B|
#   签名不存集合，只存 k 个最小值 —— 压缩是**有理论保证的**，
#   而不是"够用就行"。
#
# ── 与 HDC / SDM 的关系（项目内对照）────────────────────────
#   三者都用随机性，但保的东西不同：
#     HDC : 随机高维向量 + **代数运算**  （⊕ 保相似、⊗ 保可逆）
#     SDM : 随机硬地址   + **邻接激活**  （保内容寻址）
#     LSH : 随机哈希     + **保序压缩**  （只保相似度序，且是概率的）
#   最关键的区别：**LSH 会漏**（banding 有假阴性，阈值附近尤其明显），
#   前两者在容量内是确定的。本库把这个差异做成可测的数字，
#   而不是一句"近似算法"。
#
# ── 定点口径 ────────────────────────────────────────────────
#   所有相似度 / 概率用 Q16.16：1.0 = 65536，0.5 = 32768。

import "io.mo";

# ── 存储池 ─────────────────────────────────────────────────
# 以 i64 字为单位。minhash 签名占 LSK 个字；simhash 签名占 1 个字，
# 累加器占 64 个字。
var LSP: [24576] i64 = 0;
var LSFREE: i64 = 0;

# ── MinHash 参数 ───────────────────────────────────────────
# P = 2^31 − 1（梅森素数）。a ∈ [1, P−1]，b ∈ [0, P−1]。
var LSK: i64 = 0;
var LSA: [512] i64 = 0;
var LSB: [512] i64 = 0;
var LSPM: i64 = 2147483647;   # P
var LSSENT: i64 = 2147483647; # 空签名哨兵：任何 h 值都 < P，故用 P 本身

# ── banding 参数 ───────────────────────────────────────────
var LSBAND: i64 = 0;          # band 数 b
var LSR: i64 = 0;             # 每 band 行数 r（要求 b*r == k）

# ── SimHash 参数 ───────────────────────────────────────────
var LSNB: i64 = 64;           # 签名位宽（一个 i64）

# ── 随机源 ─────────────────────────────────────────────────
var LSRS: i64 = 8837412947;

# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   LSI / LSJ / LST / LSC / LSV / LSW 是本库内部的循环变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 lsh_madd 就会把它们
#   改成 LSK，外层循环当场退出，症状是"只加了一个元素"，不报错。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、深层闭包(v1.130) 栽过同一类跟头，
#   这里提前写明；写文档时我自己就又踩了一次。

# ── 诊断 / 状态 ────────────────────────────────────────────
var LSOVF: i64 = 0;           # 分配越界

# ── 专用循环变量 ───────────────────────────────────────────
# ⚠️ 本项目已多次栽在"共享临时变量被嵌套调用抹掉"上（HDC v1.108、
#    SDM v1.110、深层闭包 v1.130…）。这里一律用带 LS 前缀的专用全局，
#    凡跨调用存活的值绝不放在可被别的函数改写的槽里。
var LSI: i64 = 0;
var LSJ: i64 = 0;
var LST: i64 = 0;
var LSC: i64 = 0;
var LSV: i64 = 0;
var LSW: i64 = 0;

# SimHash 的超平面偏移。lsh_mix 是纯函数（不消耗 PRNG 状态），
# 所以想换一组独立超平面只能靠改这个偏移 —— 测试靠它做多次重复。
var LSOFF: i64 = 0;

# ── 随机数 ─────────────────────────────────────────────────
fn lsh_next() -> i64 {
    let a: i64 = LSRS;
    a = a ^ (a << 13);
    a = a ^ (a >> 7);
    a = a ^ (a << 17);
    if a == 0 { a = 8837412947; }
    LSRS = a;
    let b: i64 = a * 2654435761;
    b = b ^ (b >> 15);
    if b == 0 { b = 1; }
    return b;
}

fn lsh_seed(s: i64) -> i64 {
    if s == 0 { LSRS = 8837412947; }
    if s != 0 { LSRS = s; }
    return 0;
}

# 纯函数混合（splitmix64 风格，常数压缩到 i64 范围内）——
# SimHash 的权重必须**可复现**：同一个 dim 每次要拿到同一组 ±1，
# 所以不能用有状态 PRNG，只能用 (i) 的纯函数。
fn lsh_mix(z: i64) -> i64 {
    let a: i64 = z;
    a = a ^ (a >> 33);
    a = a * 2654435761;
    a = a ^ (a >> 27);
    a = a * 830283109;
    a = a ^ (a >> 31);
    if a == 0 { a = 1; }
    return a;
}

# ── 分配 ───────────────────────────────────────────────────
fn lsh_alloc(n: i64) -> i64 {
    LSV = LSFREE;
    LSFREE = LSFREE + n;
    if LSFREE > 24576 { LSOVF = 1; }
    return LSV;
}

fn lsh_reset() -> i64 {
    LSFREE = 0;
    LSOVF = 0;
    return 0;
}

# =========================================================================
#  MinHash —— 估计 Jaccard
# =========================================================================

# 初始化 k 个 (a, b)。每个 a 必须非零，否则 h 恒为常数。
fn lsh_minit(k: i64) -> i64 {
    LSK = k;
    LSI = 0;
    while LSI < k {
        LSA[LSI] = (lsh_next() & 2147483647) % 2147483646 + 1;
        LSB[LSI] = lsh_next() & 2147483647;
        LSI = LSI + 1;
    }
    return k;
}

# 第 t 个哈希在元素 x 上的值
#
# 🔴 本轮最大的坑：**不能直接对原始元素号做 a·x+b**。
#   集合的元素号常常是连续整数（0,1,2,…），而 {a·x+b mod P} 在这种
#   输入上是**等差数列**——它的最小值位置分布严重不均（三条距离定理），
#   于是 Pr[min h(A) = min h(B)] 不再等于 J。
#   实测（A={0..99} B={50..149}，J=1/3 应为 21845）：
#       raw a*x+b        → 18634   ← 系统性偏低 15%
#       mix(x) 再线性     → 21757   ← 本库采用
#       mix(x)+salt      → 21692
#   不报错、不崩溃，只是估计值永远偏低一截。
#   教训：MinHash 的理论前提是"h 在集合上是均匀随机排列"，
#   pairwise independent（a·x+b 只满足这一条）**不够**，
#   必须先用一个混合函数把结构化 ID 打散。
fn lsh_mh(t: i64, x: i64) -> i64 {
    LSV = LSA[t] * (lsh_mix(x) & 2147483647) + LSB[t];
    LSV = LSV % 2147483647;
    if LSV < 0 { LSV = LSV + 2147483647; }
    return LSV;
}

fn lsh_mnew() -> i64 {
    return lsh_alloc(LSK);
}

fn lsh_mzero(sig: i64) -> i64 {
    LSI = 0;
    while LSI < LSK {
        LSP[sig + LSI] = 2147483647;
        LSI = LSI + 1;
    }
    return 0;
}

fn lsh_madd(sig: i64, x: i64) -> i64 {
    LSI = 0;
    while LSI < LSK {
        LSV = lsh_mh(LSI, x);
        if LSV < LSP[sig + LSI] { LSP[sig + LSI] = LSV; }
        LSI = LSI + 1;
    }
    return 0;
}

# 相等的分量数（Jaccard 估计的分子）
fn lsh_mcmp(a: i64, b: i64) -> i64 {
    LSC = 0;
    LSI = 0;
    while LSI < LSK {
        if LSP[a + LSI] == LSP[b + LSI] { LSC = LSC + 1; }
        LSI = LSI + 1;
    }
    return LSC;
}

# Jaccard 估计，Q16.16
fn lsh_mest(a: i64, b: i64) -> i64 {
    if LSK == 0 { return 0; }
    LSC = lsh_mcmp(a, b);
    return LSC * 65536 / LSK;
}

# =========================================================================
#  SimHash —— 估计余弦 / 角度
# =========================================================================
#  权重不是存表，而是由 dim 号**现算**：w(i) 是一个 64 位随机字，
#  第 j 位决定第 j 个超平面的 ±1。这样内存 O(1)，且可复现。

fn lsh_snew() -> i64 {
    return lsh_alloc(1);
}

fn lsh_saccnew() -> i64 {
    return lsh_alloc(64);
}

fn lsh_sacczero(acc: i64) -> i64 {
    LSI = 0;
    while LSI < 64 {
        LSP[acc + LSI] = 0;
        LSI = LSI + 1;
    }
    return 0;
}

# 换一组独立超平面（测试用它做多次重复以降低方差）
fn lsh_soff(o: i64) -> i64 {
    LSOFF = o;
    return o;
}

# 加入第 i 维（indicator：该维在集合内）
fn lsh_sadd(acc: i64, i: i64) -> i64 {
    LSW = lsh_mix(i + 1 + LSOFF);
    LSJ = 0;
    while LSJ < 64 {
        # ⚠️ 必须写成 ((x >> j) & 1) == 0 —— `==` 优先级高于 `&`，
        #    裸写 `(x >> j) & 1 == 0` 会被解析成 `(x >> j) & (1 == 0)`，
        #    即 `& 0`，**恒假**。本轮第一版就是这么写的：减分支从不执行，
        #    SimHash 退化成"只加不减"，acc 恒为正、签名恒定，
        #    所有汉明距离 = 0。不报错、不崩溃，而 "cos=1 时 ham=0"
        #    那条断言**照样通过** —— 测试全绿、什么都没验。
        #    lib/sdm.mo 第 335 行早有这条警告，本库是**第二次**栽上。
        if ((LSW >> LSJ) & 1) == 0 { LSP[acc + LSJ] = LSP[acc + LSJ] - 1; }
        if ((LSW >> LSJ) & 1) == 1 { LSP[acc + LSJ] = LSP[acc + LSJ] + 1; }
        LSJ = LSJ + 1;
    }
    return 0;
}

# 符号位 → 签名
fn lsh_sfin(sig: i64, acc: i64) -> i64 {
    LSV = 0;
    LSJ = 0;
    while LSJ < 64 {
        if LSP[acc + LSJ] > 0 { LSV = LSV + (1 << LSJ); }
        LSJ = LSJ + 1;
    }
    LSP[sig] = LSV;
    return LSV;
}

fn lsh_popcnt(x: i64) -> i64 {
    let v: i64 = x;
    v = v - ((v >> 1) & 6148914691236517205);
    v = (v & 3689348814741910323) + ((v >> 2) & 3689348814741910323);
    v = (v + (v >> 4)) & 1085102592571150095;
    return (v * 72340172838076673) >> 56;
}

# 两个签名的汉明距离（0..64）
fn lsh_sham(a: i64, b: i64) -> i64 {
    return lsh_popcnt(LSP[a] ^ LSP[b]);
}

# 汉明比例 ham/64，Q16.16。
# ∠ Charikar 定理说的是 Pr[位不同] = θ/π，**不是** 1−cos。
#   所以这个数的期望等于 θ/π，要拿回相似度还得过一次 arccos。
#   本库不提供 arccos（会引入又一个近似源），测试改用**解析精确点**：
#   cos=1→θ/π=0、cos=1/√2→1/4、cos=0.5→1/3、cos=0→1/2，全部可手算。
fn lsh_sdist(a: i64, b: i64) -> i64 {
    return lsh_sham(a, b) * 65536 / 64;
}

# =========================================================================
#  Banding —— S 曲线
# =========================================================================
#  P(候选) = 1 − (1 − s^r)^b
#  阈值 t ≈ (1/b)^(1/r)：s < t 时急速降到 0，s > t 时急速升到 1。

fn lsh_binit(b: i64, r: i64) -> i64 {
    LSBAND = b;
    LSR = r;
    return b * r;
}

# 第 band 个 band 的混合哈希
fn lsh_bhash(sig: i64, band: i64) -> i64 {
    let h: i64 = band * 7919 + 13;
    LSJ = 0;
    while LSJ < LSR {
        h = h * 1000003 + LSP[sig + band * LSR + LSJ];
        h = h ^ (h >> 17);
        LSJ = LSJ + 1;
    }
    return h;
}

# 任一 band 的哈希相等即候选
fn lsh_bcand(a: i64, b: i64) -> i64 {
    if LSBAND * LSR != LSK { return 0; }
    LSI = 0;
    while LSI < LSBAND {
        if lsh_bhash(a, LSI) == lsh_bhash(b, LSI) { return 1; }
        LSI = LSI + 1;
    }
    return 0;
}

