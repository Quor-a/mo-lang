# bit —— Fenwick 树 / Binary Indexed Tree（用墨语言自己写的）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Peter M. Fenwick 1994
#   《A New Data Structure for Cumulative Frequency Tables》
#
#   核心恒等式：把下标 i 的**最低置位**记作 lowbit(i) = i & (−i)。
#     · 前缀和   sum(1..i) = Σ t[j]，j 从 i 开始每次 **减** lowbit(j)
#     · 单点加   add(i, d) = 对每个 j，**加** lowbit(j) 上去
#   两条路径互为逆运算，于是"改一个数"和"问一段和"都是 O(log n)，
#   而**结构本身只是一个平铺的数组**——没有指针、没有节点、没有旋转。
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   它是"用 O(n) 空间把前缀累计压到 O(log n)"的经典解，但
#   **同样没有进任何主流语言的标准库**：
#     C++  → 无（只有 boost / atcoder 的第三方）
#     Java → 无（JDK 无，竞赛代码里人手一份）
#     Go   → 无     Rust → 无     Python → 无（sortedcontainers 也不提供）
#   和线段树比：BIT 只支持**可逆**运算（加法），区间查询必须是
#   "前缀差"的形式；换成 min/max 就失效（min 不可减）。
#
# ── 与项目里四个概率性草图的对照（本库最重要的定位）─────────
#     同一个问题"小于等于 x 的有多少个"，有两条路：
#       qdigest(v1.147) → O(k) 空间，秩误差常数约 2·ε·N，**有误差**
#       本库             → O(n) 空间，误差 **恰好为 0**，**无误差**
#     Bloom/CMS/HLL/qdigest 全是"丢信息换空间"；
#     BIT 是**不丢任何信息**，代价是要按值域开满数组。
#     所以本库的断言可以写成 **==**，而那四个只能写成"≤ 某个界"。
#     —— 这正是它作为**对照物**的价值：草图那一侧的任何"误差"，
#        都必须拿"精确答案是多少"才量得出来，而精确答案由本库给出。
#
# ── 三条可测性质 ────────────────────────────────────────────
#   ① 前缀和 == 暴力 O(n) 求和（**逐位相等**，不是"接近"）
#   ② lower_bound 与线性扫描给出的下标**逐位相等**
#   ③ 合并是**逐格相加** ⇒ 线性、可交换、可结合、可精确拆分
#      （与 CMS 的 Conservative Update 相反：CU 用掉了线性性）
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   BI / BJ / BS / BD / BK / BP / BQ / BL / BR / BH / BG / BM
#   是本库内部的循环/临时变量。调用方**绝不能拿它们当自己的循环变量**
#   —— 一次 bit_add 就改掉它们，外层循环当场退出，
#   症状是"只处理了第一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   qdigest(v1.147) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   下标一律 **1-based**（1..n）。传 0 或 n+1 一律返回 −1 并置 BITBAD，
#   **不静默截断**（截断正是本项目最警惕的形状）。
#   元素可为负（add 的 delta 可为负），但 **bit_lower 要求全为非负**——
#   前缀和必须单调才能二分，这一点写在文档里而不是悄悄返回一个下标。
#   n ≤ BITMAXN；池满返回 −1 并置 BITOV。

import "mem.mo";

# ── 常量与池 ────────────────────────────────────────────────
var BITMAXN: i64 = 4096;
var BITPOOL: [70000] i64 = 0;
var BITFREE: i64 = 0;

# 每个树占 1 + n 个字：
#   base + 0 = n
#   base + i = t[i]   （i = 1..n）

# ── 诊断 / 状态 ────────────────────────────────────────────
var BITBAD: i64 = 0;      # 参数非法（下标越界 / n 非法 / 长度不匹配）
var BITOV: i64 = 0;       # 池越界
var BITSTP: i64 = 0;      # 上一次 bit_lower 的二分步数（结构性断言用）
var BITMOV: i64 = 0;      # 上一次操作的访存次数（诊断用）

# ── 内部临时变量（调用方禁用，见文件头禁令）────────────────
var BI: i64 = 0;
var BJ: i64 = 0;
var BS: i64 = 0;
var BD: i64 = 0;
var BK: i64 = 0;
var BP: i64 = 0;
var BQ: i64 = 0;
var BL: i64 = 0;
var BR: i64 = 0;
var BH: i64 = 0;
var BG: i64 = 0;
var BM: i64 = 0;

fn lowbit(x: i64) -> i64 {
    # ⚠️ 这里必须是 x & (0 - x)（取最低置位）。
    # 曾写成 x & (x - 1)，那是"清除最低置位"，两者不是一回事：
    #   lowbit(2) = 2 & 1 = 0  → bit_prefix 里 BJ = BJ - 0 永不推进 → **死循环**
    #   lowbit(6) = 6 & 5 = 4  → 本该是 2，add/prefix 的下标序列全错
    # 症状不是"算错"，是"空树调 bit_total 直接挂住、零输出"，
    # 而 tests/150_bit.mo 因此从未跑完，长期被误记为"计算密集 / 超时"。
    # 与 fenw.mo 的写法（i & (0 - i)）保持一致。
    return x & (0 - x);
}

# ── 生命周期 ────────────────────────────────────────────────
fn bit_new(n: i64) -> i64 {
    if n < 1 { BITBAD = BITBAD + 1; return 0 - 1; }
    if n > BITMAXN { BITBAD = BITBAD + 1; return 0 - 1; }
    if BITFREE + 1 + n > 70000 { BITOV = BITOV + 1; return 0 - 1; }
    let h: i64 = BITFREE;
    BITPOOL[h] = n;
    BI = 1;
    while BI <= n {
        BITPOOL[h + BI] = 0;
        BI = BI + 1;
    }
    BITFREE = BITFREE + 1 + n;
    return h;
}

fn bit_n(h: i64) -> i64 {
    return BITPOOL[h];
}

fn bit_clear(h: i64) -> i64 {
    let n: i64 = BITPOOL[h];
    BI = 1;
    while BI <= n {
        BITPOOL[h + BI] = 0;
        BI = BI + 1;
    }
    return 0;
}

# ── 单点加：i 从自身出发，每次 += lowbit(i) ─────────────────
fn bit_add(h: i64, i: i64, d: i64) -> i64 {
    let n: i64 = BITPOOL[h];
    if i < 1 { BITBAD = BITBAD + 1; return 0 - 1; }
    if i > n { BITBAD = BITBAD + 1; return 0 - 1; }
    BJ = i;
    BITMOV = 0;
    while BJ <= n {
        BITPOOL[h + BJ] = BITPOOL[h + BJ] + d;
        BJ = BJ + lowbit(BJ);
        BITMOV = BITMOV + 1;
    }
    return 0;
}

# ── 前缀和：i 从自身出发，每次 −= lowbit(i) ────────────────
fn bit_prefix(h: i64, i: i64) -> i64 {
    let n: i64 = BITPOOL[h];
    if i < 0 { BITBAD = BITBAD + 1; return 0 - 1; }
    if i > n { BITBAD = BITBAD + 1; return 0 - 1; }
    BJ = i;
    BS = 0;
    BITMOV = 0;
    while BJ > 0 {
        BS = BS + BITPOOL[h + BJ];
        BJ = BJ - lowbit(BJ);
        BITMOV = BITMOV + 1;
    }
    return BS;
}

fn bit_range(h: i64, l: i64, r: i64) -> i64 {
    let n: i64 = BITPOOL[h];
    if l < 1 { BITBAD = BITBAD + 1; return 0 - 1; }
    if r > n { BITBAD = BITBAD + 1; return 0 - 1; }
    if l > r { BITBAD = BITBAD + 1; return 0 - 1; }
    # 前缀差；l−1 合法（l ≥ 1 ⇒ l−1 ≥ 0）
    return bit_prefix(h, r) - bit_prefix(h, l - 1);
}

fn bit_point(h: i64, i: i64) -> i64 {
    return bit_range(h, i, i);
}

fn bit_set(h: i64, i: i64, v: i64) -> i64 {
    let cur: i64 = bit_point(h, i);
    if cur < 0 { return 0 - 1; }
    return bit_add(h, i, v - cur);
}

fn bit_total(h: i64) -> i64 {
    return bit_prefix(h, BITPOOL[h]);
}

# ── O(n) 批量建树 ───────────────────────────────────────────
#   t[i] += a[i]；若 j = i + lowbit(i) ≤ n 则 t[j] += t[i]
#   比逐点 add 少一半以上的访存，且**天然要求树先清零**。
#   src 是 i64 数组首地址。**第 j 个元素（1-based）在 src + j*8** ——
#   与墨语言 `ARR[j]` 的下标一致（实测：`&ARR` + 3*8 读到的正是 ARR[3]）。
#   ⚠️ 写成 (j−1)*8 会整段错位一格：不报错、不崩溃，只是所有前缀和
#      都按"移位后的数组"算，total 恰好差 SRC[n] − SRC[0]，看着完全合理。
fn bit_build(h: i64, src: i64, n: i64) -> i64 {
    if n != BITPOOL[h] { BITBAD = BITBAD + 1; return 0 - 1; }
    bit_clear(h);
    BI = 1;
    while BI <= n {
        BITPOOL[h + BI] = BITPOOL[h + BI] + load64(src + BI * 8);
        BJ = BI + lowbit(BI);
        if BJ <= n {
            BITPOOL[h + BJ] = BITPOOL[h + BJ] + BITPOOL[h + BI];
        }
        BI = BI + 1;
    }
    return 0;
}

# ── 二分提升：最小下标 pos 使 prefix(pos) ≥ k ───────────────
#   要求所有元素非负（前缀和单调）。k ≤ 0 返回 1；k > total 返回 n+1。
#   BITSTP 记录二分步数，用于断言"确实是 log n 而不是线性扫描"。
fn bit_lower(h: i64, k: i64) -> i64 {
    let n: i64 = BITPOOL[h];
    if k <= 0 { return 1; }
    BP = 0;
    BG = 1;
    while BG * 2 <= n {
        BG = BG * 2;
    }
    BL = BG;
    BK = k;
    BITSTP = 0;
    while BL > 0 {
        BQ = BP + BL;
        if BQ <= n {
            if BITPOOL[h + BQ] < BK {
                BK = BK - BITPOOL[h + BQ];
                BP = BQ;
            }
        }
        BL = BL / 2;
        BITSTP = BITSTP + 1;
    }
    return BP + 1;
}

# ── 合并：逐格相加（线性、可交换、可结合）─────────────────
#   与草图那一侧的根本差别：**精确**。
#   merge(A,B) 与"直接把 A∪B 插进去"**逐格相等**，差异数必须是 0。
fn bit_merge(a: i64, b: i64) -> i64 {
    let na: i64 = BITPOOL[a];
    let nb: i64 = BITPOOL[b];
    if na != nb { BITBAD = BITBAD + 1; return 0 - 1; }
    BI = 1;
    while BI <= na {
        BITPOOL[a + BI] = BITPOOL[a + BI] + BITPOOL[b + BI];
        BI = BI + 1;
    }
    return 0;
}

# ── 拆分：逐格相减（相加的逆运算，草图那一侧做不到）────────
fn bit_sub(a: i64, b: i64) -> i64 {
    let na: i64 = BITPOOL[a];
    let nb: i64 = BITPOOL[b];
    if na != nb { BITBAD = BITBAD + 1; return 0 - 1; }
    BI = 1;
    while BI <= na {
        BITPOOL[a + BI] = BITPOOL[a + BI] - BITPOOL[b + BI];
        BI = BI + 1;
    }
    return 0;
}

# ── 逐格相等（供测试做独立比对）───────────────────────────
fn bit_diff(a: i64, b: i64) -> i64 {
    let na: i64 = BITPOOL[a];
    let nb: i64 = BITPOOL[b];
    if na != nb { BITBAD = BITBAD + 1; return 0 - 1; }
    BM = 0;
    BI = 1;
    while BI <= na {
        if BITPOOL[a + BI] != BITPOOL[b + BI] { BM = BM + 1; }
        BI = BI + 1;
    }
    return BM;
}
