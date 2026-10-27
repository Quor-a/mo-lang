# hll —— HyperLogLog 基数估计（cardinality estimation）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Flajolet & Martin 1985    PCSA：用"哈希值前导零的最大长度"估计基数
#   Whang–Vander-Zanden–Taylor 1990
#                             Linear Counting：小基数区的无偏估计 m·ln(m/V)
#   Durand & Flajolet 2003    LogLog（去掉了 PCSA 的大量位图）
#   Flajolet, Fusy, Gandouet, Meunier 2007
#                             HyperLogLog：**调和平均** 代替算术平均 +
#                             α_m 偏差修正 → 标准误差 1.04/√m，只用 6 bit/桶
#   Heule, Nunkesser, Hall 2013
#                             HLL++：稀疏表示 + 大基数修正 + 经验偏差表
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   它是"用 O(m·loglog n) 位估计 n"的**理论极限附近**的算法：
#     m = 1024 个桶 × 6 bit ≈ 768 字节，就能估到百万级，误差 3.25%。
#   但它**没有进任何主流语言的标准库**：
#     Python → hyperloglog / datasketch（第三方）
#     Java   → stream-lib / Apache Druid（第三方）
#     Go     → axiomhq/hyperloglog（第三方）
#     C++    → 各家自研；标准库无
#     Redis  → PFADD/PFCOUNT（Redis 是存储，不是语言标准库）
#
# ── 与 HDC / SDM / LSH 的关系（项目内对照）──────────────────
#   本库是项目里第四个"随机性换空间"的库，但丢掉的东西最具体：
#     HDC : 保 **代数结构**   （⊕ ⊙ ⊗ 可逆，向量即符号）
#     SDM : 保 **内容寻址**   （噪声地址能找回原模式）
#     LSH : 保 **相似度序**   （是概率的，会漏）
#     HLL : 只保 **一个数**   （|A|；丢掉了集合本身，也丢掉了 A ∪ B 之外的
#                              一切信息——不能问"x 在不在里面"）
#   所以 HLL 是这条线上"压缩最狠、代价最明确"的一档。
#
# ── 三条公式（本库全部可测）─────────────────────────────────
#   原始估计      E = α_m · m² / Σ 2^(−M[j])          （调和平均）
#   小基数修正    E ≤ (5/2)m 且 V > 0 ⇒ E = m·ln(m/V)  （Linear Counting）
#   大基数修正    E > 2^64/30 ⇒ E = −2^64·ln(1 − E/2^64)
#   合并          (A ∪ B) 的 sketch = 逐桶 max        （损失与单次估计同阶）
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   HI / HJ / HT / HW / HR / HU / HV / HN 是本库内部的循环变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 hll_add 就会改掉它们，
#   外层循环当场退出，症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   估计值一律返回 f64。诊断量存 fbits()（i64 位模式），
#   因为墨语言的**全局变量不支持 f64**（var A: f64 → "expected a type"）。

import "io.mo";
import "fmath.mo";

# ── 池 ─────────────────────────────────────────────────────
# 每个 sketch 占 1 + m 个字：
#   字 0     = p（桶数的对数）
#   字 1..m  = M[j]，桶值 ∈ [0, 64]
# ⚠️ 桶值上限是 64 而不是 6 bit：6 bit 的截断只在 m 极大、
#    基数极大时才发生，本库不做截断（省掉一条静默丢失的路径）。
var HLLP: [20480] i64 = 0;
var HLLFREE: i64 = 0;

# ── 当前 sketch 的派生量（hll_bind 填充）────────────────────
var HLLPI: i64 = 0;        # p
var HLLMI: i64 = 0;        # m = 2^p
var HLLWI: i64 = 0;        # 64 − p：哈希里留给 ρ 的位宽

# ── 诊断 / 状态 ────────────────────────────────────────────
var HLLOVF: i64 = 0;       # 池越界
var HLLVI: i64 = 0;        # 最近一次计数的空桶数 V
var HLLERB: i64 = 0;       # 最近一次**原始**估计（fbits）
var HLLERLB: i64 = 0;      # 最近一次 Linear Counting 估计（fbits）
var HLLERHB: i64 = 0;      # 最近一次最终估计（fbits）
var HLLBIG: i64 = 0;       # 是否触发了大基数修正（0/1）
var HLLBAD: i64 = 0;       # p 非法

# ── 专用循环变量 ───────────────────────────────────────────
var HI: i64 = 0;
var HJ: i64 = 0;
var HT: i64 = 0;
var HW: i64 = 0;
var HR: i64 = 0;
var HU: i64 = 0;
var HV: i64 = 0;
var HN: i64 = 0;

# ── 逻辑右移 ───────────────────────────────────────────────
# ⚠️ 墨语言的 >> 是**算术**右移（sar），符号位会复制。
#    这是本库最大的坑的来源，见 hll_mix 的注释。
fn hll_shr(x: i64, n: i64) -> i64 {
    if n <= 0 { return x; }
    if n >= 64 { return 0; }
    return (x >> n) & ((1 << (64 - n)) - 1);
}

# ── splitmix64 常数（真值超出 i64 正值域，只能写成 0 − k）────
fn hll_delta() -> i64 { return 0 - 7046029254386353131; }  # 0x9E3779B97F4A7C15
fn hll_c1() -> i64    { return 0 - 4658895280553007687; }  # 0xBF58476D1CE4E5B9
fn hll_c2() -> i64    { return 0 - 7723592293110705685; }  # 0x94D049BB133111EB

# ── 哈希（splitmix64，纯函数）──────────────────────────────
# 必须**纯函数、无状态**：HLL 的合并要 A、B 用同一套哈希，
# 有状态 PRNG 会让"先加哪个"影响结果。
#
# 🔴 这里踩过本库最大的坑，值得整段写下来 ────────────────────
#   第一版直接照抄 lib/lsh.mo 的 lsh_mix：
#       a = a ^ (a >> 33); a = a * 2654435761; ... a = a ^ (a >> 31);
#   那个函数在 LSH 里**完全够用**（SimHash 用 64 位投票，少 1 bit
#   随机性看不出来）。但 `>>` 是**算术**右移，于是
#       y = a ^ sar(a, k) 的 bit63 = a63 ^ a63 = 0
#   ——**输出的 bit63 恒为 0**。LSH 无所谓，HLL 致命：
#   桶号取哈希的**最高 p 位**，bit63 正是桶号的最高位，
#   于是只有低 m/2 个桶可能被选中，另外一半**永远空着**。
#
#   症状（实测，p=10 / m=1024）：
#     n=1      V=1023   估计 1.00     ← 完全正常
#     n=1000   V=570    估计 599      ← 看起来只是"偏低"
#     n=10000  V=512    估计 709      ← V 停在 512 不动了
#     n=100000 V=512    估计 709      ← 与上一行**逐位相同**
#   不报错、不崩溃，估计值也始终是个"像样的数"。
#   只有"V 恰好等于 m/2 且不再下降"这一个数字能把它揪出来。
#
#   修法是换成真 splitmix64 + 逻辑右移（hll_shr）。
#   实测修复后 10000 个样本里 bit63=1 的比例回到 5000/10000。
#   教训：**从别处抄来的原语，要检查它在**新场景**下的前提是否还成立
#   —— 这和 LSH(v1.137) 里 "a·x+b 不是 min-wise" 是同一类错。
fn hll_mix(z: i64) -> i64 {
    let a: i64 = z + hll_delta();
    a = a ^ hll_shr(a, 30);
    a = a * hll_c1();
    a = a ^ hll_shr(a, 27);
    a = a * hll_c2();
    a = a ^ hll_shr(a, 31);
    if a == 0 { a = 1; }
    return a;
}

# ── 前导零（clz64）────────────────────────────────────────
# ⚠️ 墨语言的 >> 是**算术**右移，符号位会扩展，
#    所以不能用经典的二分 clz（(y>>32)==0 在 y<0 时恒假）。
#    这里改成"左移直到符号位为 1"：y<0 ⟺ bit63 == 1。
#    x==0 必须先判，否则 y<<1 仍是 0，死循环。
fn hll_clz64(x: i64) -> i64 {
    if x == 0 { return 64; }
    let n: i64 = 0;
    let y: i64 = x;
    while y >= 0 {
        n = n + 1;
        y = y << 1;
    }
    return n;
}

# ── 创建 ───────────────────────────────────────────────────
fn hll_new(p: i64) -> i64 {
    if p < 4 { HLLBAD = 1; return 0 - 1; }
    if p > 16 { HLLBAD = 1; return 0 - 1; }
    let m: i64 = 1 << p;
    let base: i64 = HLLFREE;
    if base + 1 + m > 20480 { HLLOVF = 1; return 0 - 1; }
    HLLFREE = base + 1 + m;
    HLLP[base] = p;
    HI = 1;
    while HI <= m {
        HLLP[base + HI] = 0;
        HI = HI + 1;
    }
    return base;
}

# ── 绑定派生量（所有桶操作前都要先调）──────────────────────
fn hll_bind(s: i64) -> i64 {
    HLLPI = HLLP[s];
    HLLMI = 1 << HLLPI;
    HLLWI = 64 - HLLPI;
    return 0;
}

fn hll_zero(s: i64) -> i64 {
    hll_bind(s);
    HI = 1;
    while HI <= HLLMI {
        HLLP[s + HI] = 0;
        HI = HI + 1;
    }
    return 0;
}

fn hll_p(s: i64) -> i64 { return HLLP[s]; }

fn hll_m(s: i64) -> i64 {
    hll_bind(s);
    return HLLMI;
}

# ── 加入一个元素 ───────────────────────────────────────────
# 分三步：h 的高 p 位选桶，低 (64−p) 位算 ρ = clz + 1，桶取 max。
fn hll_add(s: i64, x: i64) -> i64 {
    let h: i64 = hll_mix(x);
    return hll_add_h(s, h);
}

# 直接喂哈希值：测试用它绕开 mix，验证"哈希质量"这一维。
fn hll_add_h(s: i64, h: i64) -> i64 {
    hll_bind(s);
    let p: i64 = HLLPI;
    let m: i64 = HLLMI;
    # ⚠️ h >> (64−p) 是**算术**右移：h<0 时结果是 桶号 − m（符号扩展）。
    #    二补数下 (桶号 − m) & (m−1) == 桶号，所以 & (m−1) 不只是"顺手加的
    #    掩码"，它是**修正符号扩展的必要一步**。去掉它 → 一半元素落进负桶。
    let idx: i64 = (h >> (64 - p)) & (m - 1);
    # w 只占低 (64−p) 位 ⇒ 它的 clz64 必然 ≥ p，
    # 所以 ρ = clz64(w) − p + 1 ∈ [1, 64−p]。
    let w: i64 = h & ((1 << (64 - p)) - 1);
    let rho: i64 = 0;
    if w == 0 {
        rho = 65 - p;              # ρ(0) 的定义：字宽 + 1
    }
    if w != 0 {
        rho = hll_clz64(w) - p + 1;
    }
    if rho > HLLP[s + 1 + idx] {
        HLLP[s + 1 + idx] = rho;
    }
    return rho;
}

# ── 空桶数 V ───────────────────────────────────────────────
fn hll_v(s: i64) -> i64 {
    hll_bind(s);
    let v: i64 = 0;
    HJ = 1;
    while HJ <= HLLMI {
        if HLLP[s + HJ] == 0 { v = v + 1; }
        HJ = HJ + 1;
    }
    HLLVI = v;
    return v;
}

# ── α_m（Flajolet et al. 2007 Table 1）─────────────────────
# m<128 用论文给的表；m≥128 用拟合式 0.7213/(1+1.079/m)。
fn hll_alpha(m: i64) -> f64 {
    if m == 16 { return 0.673; }
    if m == 32 { return 0.697; }
    if m == 64 { return 0.709; }
    return 0.7213 / (1.0 + 1.079 / f64(m));
}

# ── 原始估计 E（调和平均，不带任何修正）────────────────────
fn hll_raw(s: i64) -> f64 {
    hll_bind(s);
    let m: i64 = HLLMI;
    let sum: f64 = 0.0;
    HN = 1;
    while HN <= m {
        let e: i64 = HLLP[s + HN];
        sum = sum + fm_ldexp(1.0, 0 - e);
        HN = HN + 1;
    }
    let a: f64 = hll_alpha(m);
    let est: f64 = a * f64(m) * f64(m) / sum;
    HLLERB = fbits(est);
    return est;
}

# ── Linear Counting（Whang et al. 1990）────────────────────
# 只在"空桶还多"时有效：V=0 时 ln(m/0) 无意义，本库返回 0.0 并置 HLLBAD。
fn hll_lc(s: i64) -> f64 {
    hll_bind(s);
    let m: i64 = HLLMI;
    let v: i64 = hll_v(s);
    if v <= 0 { HLLBAD = 1; return 0.0; }
    let r: f64 = f64(m) * fm_log(f64(m) / f64(v));
    HLLERLB = fbits(r);
    return r;
}

# ── 大基数修正（Heule et al. 2013）─────────────────────────
# 64 位哈希下阈值是 2^64/30 ≈ 6.1e17，**端到端不可能达到**
# （要插 6e17 个元素）。所以它在本库里是"正确但不可达"的代码 ——
# 测试用 hll_bigfix 单独喂值做**单元级**验证，不假装端到端测过。
fn hll_bigfix(e: f64, bits: i64) -> f64 {
    let two: f64 = fm_ldexp(1.0, bits);
    if e > two / 30.0 {
        return 0.0 - two * fm_log(1.0 - e / two);
    }
    return e;
}

# ── 最终估计（三段式）──────────────────────────────────────
fn hll_count(s: i64) -> f64 {
    hll_bind(s);
    let m: i64 = HLLMI;
    let v: i64 = hll_v(s);
    if v == m {
        HLLERB = fbits(0.0);
        HLLERLB = fbits(0.0);
        HLLERHB = fbits(0.0);
        return 0.0;                 # 全空：Σ 全是 1，调和平均会给出 α·m ≠ 0
    }
    let e: f64 = hll_raw(s);
    let lc: f64 = 0.0;
    if v > 0 { lc = hll_lc(s); }
    HLLERLB = fbits(lc);
    HLLBIG = 0;
    # 小基数区：调和平均在这里**系统性高估**，换成 Linear Counting
    if e <= 2.5 * f64(m) {
        if v > 0 {
            HLLERHB = fbits(lc);
            return lc;
        }
    }
    let r: f64 = hll_bigfix(e, 64);
    if r != e { HLLBIG = 1; }
    HLLERHB = fbits(r);
    return r;
}

# ── 合并（逐桶 max）────────────────────────────────────────
# 要求两个 sketch 的 p 相同；不同则置 HLLBAD 并返回 −1。
fn hll_merge(d: i64, a: i64) -> i64 {
    let pd: i64 = HLLP[d];
    let pa: i64 = HLLP[a];
    if pd != pa { HLLBAD = 1; return 0 - 1; }
    let m: i64 = 1 << pd;
    HU = 1;
    while HU <= m {
        let va: i64 = HLLP[a + HU];
        if va > HLLP[d + HU] { HLLP[d + HU] = va; }
        HU = HU + 1;
    }
    return 0;
}

# ── 取诊断位模式 → f64 ─────────────────────────────────────
fn hll_diag_raw() -> f64 { return ffrombits(HLLERB); }
fn hll_diag_lc() -> f64  { return ffrombits(HLLERLB); }
fn hll_diag_est() -> f64 { return ffrombits(HLLERHB); }

# ── 桶值统计（测试用：验证 ρ 的取值范围）───────────────────
fn hll_maxreg(s: i64) -> i64 {
    hll_bind(s);
    let r: i64 = 0;
    HV = 1;
    while HV <= HLLMI {
        if HLLP[s + HV] > r { r = HLLP[s + HV]; }
        HV = HV + 1;
    }
    return r;
}

fn hll_sumreg(s: i64) -> i64 {
    hll_bind(s);
    let r: i64 = 0;
    HV = 1;
    while HV <= HLLMI {
        r = r + HLLP[s + HV];
        HV = HV + 1;
    }
    return r;
}

fn hll_reset() -> i64 {
    HLLFREE = 0;
    HLLOVF = 0;
    HLLBAD = 0;
    HLLBIG = 0;
    return 0;
}
