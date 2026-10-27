# cbf —— Counting Bloom Filter（Fan, Cao, Almeida & Broder 2000）
#
# ── 概念来源 ────────────────────────────────────────────────
#   L. Fan, P. Cao, J. Almeida, A. Broder 2000
#   《Summary Cache: A Scalable Wide-Area Web Cache Sharing Protocol》
#   把 Bloom filter 的 **1 bit 换成 4-bit 计数器**，于是支持删除。
#
#   它补的正是 lib/bloom.mo 的已知限制（v1.144 明确记过）：
#     "Bloom 不支持删除"。
#   而"能删"这件事**不是免费的** —— 本库最重要的两个可测事实
#   都是它的代价：
#     ① 计数器必须**饱和**（停在 15）。不饱和则第 16 次插入让 4-bit
#        回绕成 0 ⟹ **假阴**。而 Bloom 的唯一硬保证就是"永不假阴"，
#        所以饱和度检查不是优化，是维护这条保证的必要条件。
#     ② 只能删**确实插入过的**元素。删一个没插入过的 x，会把 x 那 k 个
#        位置上的计数器减 1；若某个位置与已插入元素 y 共享且计数为 1，
#        y 就此变成**假阴**。这是 CBF 与 Bloom 最本质的分野。
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   主流语言标准库一个都没有（Bloom 本身也没有）：
#     Java   → Guava 只有 BloomFilter，**没有** counting 版
#     Redis  → BF.ADD 有，counting 版没有
#     C++    → 各家自研
#   4-bit 计数器的选择来自论文实测：4 位足够（溢出概率极低），
#   且一个 i64 正好装 16 个计数器 —— 本库按这个打包。
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   CFI / CFJ / CFW / CFS / CFV / CFB / CFM 是本库内部的循环/临时变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 cbf_add 就会改掉，
#   外层循环当场退出，症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   Bloom/CMS(v1.144) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   m 必须是 **2 的幂且 ≥ 16**（每个 i64 装 16 个 4-bit 计数器，
#   2 的幂才能用 & (m−1) 绕开墨语言负数取模的坑）。
#   非法参数返回 −1 并置 CBFBAD —— **不静默接受**。
#   计数器上限 15，达到后停在 15 并置 CBFSAT。
#   k ≤ 16。

import "cms.mo";       # 复用 cm_h1 / cm_h2 / cms_mod（纯函数，不碰 CMS 的全局临时）

# ── 池 ─────────────────────────────────────────────────────
# 每个 filter 占 3 + m/16 个字：
#   字 0     = m（计数器个数）
#   字 1     = k（哈希个数）
#   字 2     = words（= m/16）
#   字 3..   = 计数器数组，每个 i64 装 16 个 4-bit 计数器
var CBFP: [8192] i64 = 0;
var CBFFREE: i64 = 0;

# ── 诊断 / 状态 ────────────────────────────────────────────
var CBFBAD: i64 = 0;    # 参数非法
var CBFOV: i64 = 0;     # 池越界
var CBFSAT: i64 = 0;    # 饱和次数：计数器已 15 仍被 add（必须在测试里 > 0，否则饱和分支从未被执行）
var CBFNEG: i64 = 0;    # remove 时该计数器**已经是 0** 的次数
                        # ⟹ 强烈提示"删了没插入过的元素"，是假阴的先兆。不阻止，只记录。

# ── 专用循环/临时变量 ──────────────────────────────────────
var CFI: i64 = 0;
var CFJ: i64 = 0;
var CFW: i64 = 0;
var CFS: i64 = 0;
var CFV: i64 = 0;
var CFB: i64 = 0;
var CFM: i64 = 0;

fn cbf_cap() -> i64 { return 15; }

# ── 读一个 4-bit 计数器 ────────────────────────────────────
# ⚠️ `(w >> sh) & 15` 里的算术右移是**安全**的：墨语言的 >> 是 sar，
#    符号扩展的高位被 & 15 全部清掉，低 4 位即目标字段。
#    这比先做逻辑右移再取位更省一步，且对正负数都成立。
fn cbf_cell(h: i64, idx: i64) -> i64 {
    let sh: i64 = 0;
    sh = (idx - (idx / 16) * 16) * 4;
    return (CBFP[h + 3 + idx / 16] >> sh) & 15;
}

# ── 写一个 4-bit 计数器 ────────────────────────────────────
# 用 `w + (v − old)·2^sh` 而不是读改写掩码：墨语言里位取反/掩码构造
# 容易写错，而"加上差值"只需要一次减法，**不需要 ~ 运算**。
fn cbf_setc(h: i64, idx: i64, v: i64) -> i64 {
    let sh: i64 = 0;
    let old: i64 = 0;
    let w: i64 = 0;
    sh = (idx - (idx / 16) * 16) * 4;
    w = CBFP[h + 3 + idx / 16];
    old = (w >> sh) & 15;
    CBFP[h + 3 + idx / 16] = w + (v - old) * (1 << sh);
    return 0;
}

# ── 新建 ───────────────────────────────────────────────────
fn cbf_new(m: i64, k: i64) -> i64 {
    let words: i64 = 0;
    let base: i64 = 0;
    if m < 16 { CBFBAD = 1; return 0 - 1; }
    if k <= 0 { CBFBAD = 1; return 0 - 1; }
    if k > 16 { CBFBAD = 1; return 0 - 1; }
    # m 必须是 2 的幂：否则 & (m−1) 不成立，取模会走负数路径
    if (m & (m - 1)) != 0 { CBFBAD = 1; return 0 - 1; }
    words = m / 16;
    base = CBFFREE;
    if base + 3 + words > 8192 { CBFOV = 1; return 0 - 1; }
    CBFFREE = base + 3 + words;
    CBFP[base] = m;
    CBFP[base + 1] = k;
    CBFP[base + 2] = words;
    return base;
}

# ── 第 i 个哈希位置（double hashing）───────────────────────
fn cbf_pos(h: i64, x: i64, i: i64) -> i64 {
    let m: i64 = 0;
    let h1v: i64 = 0;
    let h2v: i64 = 0;
    let p: i64 = 0;
    m = CBFP[h];
    h1v = cms_mod(cm_h1(x), m);
    h2v = cms_mod(cm_h2(x), m);
    if h2v == 0 { h2v = 1; }
    p = h1v + cms_mod(i * h2v, m);
    if p >= m { p = p - m; }
    return p;
}

# ── 插入 ───────────────────────────────────────────────────
# 🔴 饱和是**必需的**，不是优化：
#    计数器到 15 后再 +1，4-bit 会回绕成 0（还会向相邻计数器进位），
#    于是 query 变假 ⟹ **假阴** —— 直接违反 Bloom 家族的唯一硬保证。
#    实测（tests/147）：同元素插入 20 次，做饱和 ⟹ query 仍真；
#    去掉饱和的变异 ⟹ 第 16 次起 query 变假。
fn cbf_add(h: i64, x: i64) -> i64 {
    let k: i64 = 0;
    let idx: i64 = 0;
    let v: i64 = 0;
    k = CBFP[h + 1];
    CFI = 0;
    while CFI < k {
        idx = cbf_pos(h, x, CFI);
        v = cbf_cell(h, idx);
        if v >= 15 {
            CBFSAT = CBFSAT + 1;
        } else {
            cbf_setc(h, idx, v + 1);
        }
        CFI = CFI + 1;
    }
    return 0;
}

# ── 删除 ───────────────────────────────────────────────────
# 🔴 无条件减。若某个计数器已经是 0，说明**删了一个没插入过的元素**
#    （或删的次数多于插入次数），置 CBFNEG 但不阻止 ——
#    这正是"静默"的形状，所以必须**显式响出来**而不是悄悄跳过。
#    为什么阻止不住：即使 x 确实插入过，它那些位置也可能与别的元素
#    共享；减 1 仍可能让共享方变假阴。安全删除请用 cbf_remove_safe，
#    但它也只能挡住"完全没插入过"这一种。
fn cbf_remove(h: i64, x: i64) -> i64 {
    let k: i64 = 0;
    let idx: i64 = 0;
    let v: i64 = 0;
    k = CBFP[h + 1];
    CFI = 0;
    while CFI < k {
        idx = cbf_pos(h, x, CFI);
        v = cbf_cell(h, idx);
        if v == 0 {
            CBFNEG = CBFNEG + 1;
        } else {
            cbf_setc(h, idx, v - 1);
        }
        CFI = CFI + 1;
    }
    return 0;
}

# ── 安全删除（只在 query 为真时减）─────────────────────────
# 挡住"完全没插入过"这一类误删，但**挡不住假阳导致的误删**：
# query 为真只说明 k 个位置都 >0，也可能是别的元素撞出来的。
fn cbf_remove_safe(h: i64, x: i64) -> i64 {
    if cbf_query(h, x) == 0 { return 0; }
    return cbf_remove(h, x);
}

# ── 查询：k 个计数器全部 > 0 ？ ────────────────────────────
fn cbf_query(h: i64, x: i64) -> i64 {
    let k: i64 = 0;
    let idx: i64 = 0;
    k = CBFP[h + 1];
    CFM = 1;
    CFI = 0;
    while CFI < k {
        idx = cbf_pos(h, x, CFI);
        if cbf_cell(h, idx) == 0 { CFM = 0; }
        CFI = CFI + 1;
    }
    return CFM;
}

# ── 计数估计（k 个计数器的最小值）──────────────────────────
# 与 CMS 取 min 同理：某计数器被别的元素撞过 → 偏大；
# 没被撞过的那个恰好等于真实次数。所以 min 是**最接近的下界之上**的估计。
# 注意它不是 a 的下界（可能仍偏大），这一点和 Bloom 的"只假阳"不同。
fn cbf_est(h: i64, x: i64) -> i64 {
    let k: i64 = 0;
    let idx: i64 = 0;
    let v: i64 = 0;
    k = CBFP[h + 1];
    CFM = 9223372036854775807;
    CFI = 0;
    while CFI < k {
        idx = cbf_pos(h, x, CFI);
        v = cbf_cell(h, idx);
        if v < CFM { CFM = v; }
        CFI = CFI + 1;
    }
    return CFM;
}

# ── 非零计数器个数 ─────────────────────────────────────────
# 与 bloom_count 同形，是"装填程度"的独立观测量。
fn cbf_count(h: i64) -> i64 {
    let m: i64 = 0;
    m = CBFP[h];
    CFM = 0;
    CFI = 0;
    while CFI < m {
        if cbf_cell(h, CFI) != 0 { CFM = CFM + 1; }
        CFI = CFI + 1;
    }
    return CFM;
}

# ── 清空 ───────────────────────────────────────────────────
fn cbf_clear(h: i64) -> i64 {
    let words: i64 = 0;
    words = CBFP[h + 2];
    CFI = 0;
    while CFI < words {
        CBFP[h + 3 + CFI] = 0;
        CFI = CFI + 1;
    }
    return 0;
}

# ── 合并（逐格取 max，in-place 进 dst）─────────────────────
#
# 三种草图结构各有自己的合并运算，这张表是本库与 bloom/cms 的分工：
#     Bloom  → 按位 **OR**      （幂等、交换、结合）
#     CBF    → 逐格 **max**     （幂等、交换、结合）  ← 本函数
#     CMS    → 逐格 **相加**    （交换、结合，**不幂等**）
#     CU-CMS → 无（依赖状态，连结合律都不成立，见 tests/147）
#
# 🔴 必须**逐格**取 max，绝不能对打包后的 i64 **整字**取 max：
#    max 在 4-bit 字段上**不满足分配律**。反例（两个字段）：
#      A 字 = 0x21（字段0=1, 字段1=2）    B 字 = 0x12（字段0=2, 字段1=1）
#      整字 max = 0x21 → 字段0=1（应为 2）
#    更狠的情形：A 的高位字段很大、B 的低位字段是唯一非零值，
#      整字 max 会选中 A 那个字，把 B 唯一的非零字段**抹成 0**
#      ⟹ 该元素查不到 ⟹ **假阴**，Bloom 家族唯一硬保证当场破。
#    所以这条不是风格问题，是正确性要求。
#
# 🔴 另一个易错点：整字 max 仍然满足交换律、结合律、幂等律 ——
#    **格的三条律对"错误的运算"同样成立**。也就是说只测这三条律
#    根本分不出对错（tests/148 里这三条在 M1 变异下依然全绿）。
#    能抓到它的只有：① 与"独立算出的逐格 max"逐格比对；
#    ② 合并后对 S_A ∪ S_B 做**无假阴**检查。
#
# 参数不一致（m 或 k 不同）返回 0 − 1 并置 CBFBAD，
# **不静默给出半合并的结果**。
fn cbf_merge(dst: i64, src: i64) -> i64 {
    let m: i64 = 0;
    let va: i64 = 0;
    let vb: i64 = 0;
    if CBFP[dst] != CBFP[src] { CBFBAD = 1; return 0 - 1; }
    if CBFP[dst + 1] != CBFP[src + 1] { CBFBAD = 1; return 0 - 1; }
    m = CBFP[dst];
    CFI = 0;
    while CFI < m {
        va = cbf_cell(dst, CFI);
        vb = cbf_cell(src, CFI);
        if vb > va { cbf_setc(dst, CFI, vb); }
        CFI = CFI + 1;
    }
    return 0;
}
