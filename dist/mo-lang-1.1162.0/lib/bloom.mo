# bloom —— Bloom filter（Bloom 1970）+ Kirsch–Mitzenmacher double hashing
#
# ── 概念来源 ────────────────────────────────────────────────
#   Burton H. Bloom 1970  《Space/Time Trade-offs in Hash Coding with
#                          Allowable Errors》：用 k 个哈希把元素映射到 m 位的
#                          位数组，查询"全 1 则判存在"。
#                          **只会假阳，永不假阴** —— 这是它唯一的保证，
#                          也是本库最重要的可测性质。
#   Kirsch & Mitzenmacher 2006
#                          double hashing：h_i = h1 + i·h2 与"k 个独立哈希"
#                          的假阳率**渐近相同**，于是 O(1) 次哈希就能造出
#                          k 个"看起来独立"的位置。这是所有工业实现的做法。
#   Bose et al. 2008       理论下界：m/n 固定时假阳率不可能优于
#                          (1/2)^(m/n·ln2) —— Bloom 已经在这个常数的
#                          常数倍之内。
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   它是最早的"用可控错误率换空间"的结构，但**没有进任何主流语言的标准库**：
#     Python → pybloom / bloomfilter（第三方）
#     Java   → Guava BloomFilter（第三方；JDK 无）
#     Go     → bits-and-blooms/bloom（第三方）
#     C++    → 各家自研；标准库无
#     Redis  → BF.ADD（Redis 是存储，不是语言标准库）
#
# ── 与项目里其它"随机性换空间"库的对照 ──────────────────────
#     HDC : 保 代数结构     SDM : 保 内容寻址
#     LSH : 保 相似度序     HLL : 只保 一个基数 |A|
#     LSH 的 banding、HLL 的调和平均、本库的 k 个哈希位 —— 三者都是
#     "丢掉信息换空间"，但**丢的东西不同，因此可验证的性质也不同**：
#       HLL  → 估计值有 1.04/√m 的标准误差
#       LSH  → 召回率是 s 的 S 曲线，会漏
#       Bloom→ **永不假阴**（确定性的），假阳率有闭式解
#     本库是这条线上**唯一有确定性断言**的一档 —— 假阴次数必须**恰好为 0**，
#     不是"接近 0"。
#
# ── 三条公式（本库全部可测）─────────────────────────────────
#   假阳率      p = (1 − e^(−kn/m))^k
#   最优 k      k* = (m/n)·ln2           （p 取最小值）
#   最优下的 p  p* = (1/2)^k* = 0.6185^(m/n)
#   合并        (A ∪ B) 的 filter = 逐位 OR（假阳率不劣于插入 A∪B 的 filter）
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   BI / BW / BB / BX / BV / BA / BB2 是本库内部的循环/临时变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 bloom_add 就会改掉它们，
#   外层循环当场退出，症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   m 必须是 **2 的幂**（否则 bloom_new 返回 −1 并置 BLBAD）。
#   这不是偷懒：取模用 & (m−1) 才能绕开墨语言负数取模的坑，
#   而"静默接受非 2 的幂然后取模出错"正是本项目最警惕的形状。
#   位数组每个字 64 位；k ≤ 16。

import "fmath.mo";

# ── 池 ─────────────────────────────────────────────────────
# 每个 filter 占 3 + words 个字：
#   字 0     = m（位数）
#   字 1     = k（哈希个数）
#   字 2     = words
#   字 3..   = 位数组
var BLMP: [8192] i64 = 0;
var BLFREE: i64 = 0;

# ── 诊断 / 状态 ────────────────────────────────────────────
var BLOV: i64 = 0;      # 池越界
var BLBAD: i64 = 0;     # 参数非法（m 非 2 的幂 / k ≤ 0）
var BLNB: i64 = 0;      # 最近一次 bloom_count 的置位数

# ── 专用循环/临时变量 ──────────────────────────────────────
var BI: i64 = 0;
var BW: i64 = 0;
var BB: i64 = 0;
var BX: i64 = 0;
var BV: i64 = 0;
var BA: i64 = 0;
var BB2: i64 = 0;

# ── 逻辑右移 ───────────────────────────────────────────────
# ⚠️ 墨语言的 >> 是**算术**右移（sar）。HLL(v1.138) 已在此栽过一次：
#    `a ^ sar(a,k)` 的 bit63 = a63^a63 = 0 ⇒ 输出 bit63 恒为 0。
fn bl_shr(x: i64, n: i64) -> i64 {
    if n <= 0 { return x; }
    if n >= 64 { return 0; }
    return (x >> n) & ((1 << (64 - n)) - 1);
}

# ── splitmix64 常数（真值超出 i64 正值域，只能写成 0 − k）────
fn bl_delta() -> i64 { return 0 - 7046029254386353131; }  # 0x9E3779B97F4A7C15
fn bl_c1() -> i64    { return 0 - 4658895280553007687; }  # 0xBF58476D1CE4E5B9
fn bl_c2() -> i64    { return 0 - 7723592293110705685; }  # 0x94D049BB133111EB

# ── 哈希（splitmix64，纯函数）──────────────────────────────
# 必须**纯函数、无状态**：bloom_merge 要求 A、B 用同一套哈希，
# 有状态 PRNG 会让"先加哪个"影响结果。
fn bl_mix(z: i64) -> i64 {
    let a: i64 = z + bl_delta();
    a = a ^ bl_shr(a, 30);
    a = a * bl_c1();
    a = a ^ bl_shr(a, 27);
    a = a * bl_c2();
    a = a ^ bl_shr(a, 31);
    if a == 0 { a = 1; }
    return a;
}

fn bl_h1(x: i64) -> i64 { return bl_mix(x); }

# ── h2 置为奇数 ────────────────────────────────────────────
# h_i = h1 + i·h2 (mod m)，m = 2^p。
#
# 🔴 这里原本的注释写错了，实测把它改回来（v1.144）：
#    旧注释说"h2 偶数 ⟹ k 个位置只落在 m/gcd 个位置 ⟹ 只用了一小
#    部分位数组 ⟹ 假阳率远高于公式"。
#    实测（m=1024, n=200, k=4，逐个样本检查）：
#        h2 为偶数的样本      101 / 200
#        k=4 个位置出现重复    0
#        h2 ≡ 0 (mod 1024)    0 / 200
#    即 **k << m/gcd 时，h2 偶不偶数根本不影响位置互异性** ——
#    M2 变异（去掉 |1）因此**未被捕获**，25 项断言仍全绿。
#    这不是"断言空转"，是"这条改动在本参数区间确实无可观测后果"。
#
#    |1 真正的、也是唯一的作用：排除 h2 ≡ 0 (mod m)。
#    m = 2^p 的每个非零倍数都是偶数，而 0 也是偶数 ⟹
#    h2 |= 1 后**不可能是 m 的倍数**，于是 k 个位置必然互异。
#    该事件的概率只有 1/m（m=1024 时 0.1%），200 个样本一次未遇。
#    所以它是**廉价的保险**，不是性能关键 —— 注释不能再写成前提。
#
#    对照：lib/cms.mo 的 `if h2v == 0 { h2v = 1; }` **不是**廉价保险：
#    CMS 的 w 常常只有几十，h2 ≡ 0 (mod w) 的概率是 1/w，
#    属"必然发生"量级，且退化后 d 行**全落在同一列**。
fn bl_h2(x: i64) -> i64 { return bl_mix(x ^ bl_c1()) | 1; }

# ── 新建 ───────────────────────────────────────────────────
# 返回 handle（池内偏移），失败返回 0 − 1。
fn bloom_new(mbits: i64, k: i64) -> i64 {
    if mbits <= 0 { BLBAD = 1; return 0 - 1; }
    if k <= 0 { BLBAD = 1; return 0 - 1; }
    if k > 16 { BLBAD = 1; return 0 - 1; }
    # m 必须是 2 的幂
    let t: i64 = 1;
    while t < mbits { t = t * 2; }
    if t != mbits { BLBAD = 1; return 0 - 1; }
    let words: i64 = mbits / 64;
    if words < 1 { words = 1; }
    let base: i64 = BLFREE;
    if base + 3 + words > 8192 { BLOV = 1; return 0 - 1; }
    BLFREE = base + 3 + words;
    BLMP[base] = mbits;
    BLMP[base + 1] = k;
    BLMP[base + 2] = words;
    return base;
}

# ── 插入 ───────────────────────────────────────────────────
fn bloom_add(h: i64, x: i64) -> i64 {
    let m: i64 = BLMP[h];
    let k: i64 = BLMP[h + 1];
    let base: i64 = h + 3;
    let h1v: i64 = bl_h1(x);
    let h2v: i64 = bl_h2(x);
    BI = 0;
    BX = 0;
    BW = 0;
    BB = 0;
    while BI < k {
        BX = (h1v + BI * h2v) & (m - 1);
        BW = BX / 64;
        BB = BX - BW * 64;
        BLMP[base + BW] = BLMP[base + BW] | (1 << BB);
        BI = BI + 1;
    }
    return 0;
}

# ── 查询 ───────────────────────────────────────────────────
# 返回 1 = "可能存在"，0 = "一定不存在"。
# 唯一保证：**插入过的元素必然返回 1**（永不假阴）。
fn bloom_has(h: i64, x: i64) -> i64 {
    let m: i64 = BLMP[h];
    let k: i64 = BLMP[h + 1];
    let base: i64 = h + 3;
    let h1v: i64 = bl_h1(x);
    let h2v: i64 = bl_h2(x);
    BI = 0;
    BX = 0;
    BW = 0;
    BB = 0;
    while BI < k {
        BX = (h1v + BI * h2v) & (m - 1);
        BW = BX / 64;
        BB = BX - BW * 64;
        if (BLMP[base + BW] & (1 << BB)) == 0 { return 0; }
        BI = BI + 1;
    }
    return 1;
}

# ── 清空 ───────────────────────────────────────────────────
fn bloom_clear(h: i64) -> i64 {
    let words: i64 = BLMP[h + 2];
    let base: i64 = h + 3;
    BI = 0;
    while BI < words {
        BLMP[base + BI] = 0;
        BI = BI + 1;
    }
    return 0;
}

# ── 合并（按位 OR）─────────────────────────────────────────
# 要求 m 与 k 相同，否则返回 0 − 1 并置 BLBAD（不静默给出半合并的结果）。
fn bloom_merge(dst: i64, src: i64) -> i64 {
    if BLMP[dst] != BLMP[src] { BLBAD = 1; return 0 - 1; }
    if BLMP[dst + 1] != BLMP[src + 1] { BLBAD = 1; return 0 - 1; }
    let words: i64 = BLMP[dst + 2];
    let bd: i64 = dst + 3;
    let bs: i64 = src + 3;
    BI = 0;
    while BI < words {
        BLMP[bd + BI] = BLMP[bd + BI] | BLMP[bs + BI];
        BI = BI + 1;
    }
    return 0;
}

# ── 置位数（诊断）──────────────────────────────────────────
# 期望值 m·(1 − e^(−kn/m))；实测偏离它就是哈希不均匀的证据。
fn bl_pc(v: i64) -> i64 {
    let x: i64 = v;
    x = x - (bl_shr(x, 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + (bl_shr(x, 2) & 0x3333333333333333);
    x = (x + bl_shr(x, 4)) & 0x0f0f0f0f0f0f0f0f;
    # 每字节 ≤ 0x0f，8 字节和 ≤ 120 < 128 ⇒ 结果 bit63 = 0，sar 安全
    return (x * 0x0101010101010101) >> 56;
}

fn bloom_count(h: i64) -> i64 {
    let words: i64 = BLMP[h + 2];
    let base: i64 = h + 3;
    BA = 0;
    BI = 0;
    while BI < words {
        BA = BA + bl_pc(BLMP[base + BI]);
        BI = BI + 1;
    }
    BLNB = BA;
    return BA;
}

# ── 理论假阳率（f64）───────────────────────────────────────
# p = (1 − e^(−kn/m))^k，用 fmath 的 fm_exp；k 次乘方用循环。
# 测试用它算期望假阳数，与实测对照 —— **期望现算，不落仓库**，
# 于是不会出现"期望值陈旧但仍全绿"。
fn bloom_fp_theory(n: i64, m: i64, k: i64) -> f64 {
    let knm: f64 = 0.0 - f64(k) * f64(n) / f64(m);
    let e: f64 = fm_exp(knm);
    let p: f64 = 1.0 - e;
    let r: f64 = 1.0;
    let i: i64 = 0;
    while i < k {
        r = r * p;
        i = i + 1;
    }
    return r;
}
