# cms —— Count-Min Sketch（Cormode & Muthukrishnan 2005）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Graham Cormode & S. Muthukrishnan 2005
#   《An Improved Data Stream Summary: The Count-Min Sketch and Its
#    Applications》：d 行 × w 列的计数器矩阵，每个元素在每行各加一次，
#    查询取 **d 行的最小值**。
#
#   两条保证（本库都做成了断言）：
#     ①  â_i ≥ a_i                        **确定性**，永不低估
#     ②  â_i ≤ a_i + ε·N 以概率 1 − δ      w = ⌈e/ε⌉，d = ⌈ln(1/δ)⌉
#   ① 来自"同一位置只会加，不会减"；② 的证明是 Markov 不等式 ——
#   d 行各自超标的概率 ≤ (1/e)^d = δ。
#
# ── 与 Bloom filter 的分工（本库存在的理由）──────────────────
#   Bloom 只回答"在不在"（1 bit/槽），CMS 回答"出现了几次"。
#   两者**误差方向相反，恰好互补**：
#     Bloom → 只会假**阳**（把不在的说成在的）
#     CMS   → 只会**高估**（把次数说多），永不会漏
#   所以 Bloom 的"假阳"和 CMS 的"高估"是同一种碰撞的两种后果，
#   而它们的**确定性保证**（无假阴 / 无低估）都是可写成 == 0 断言的。
#
# ── 为什么算"概念" ──────────────────────────────────────────
#   它是流数据 frequency estimation 的标准解，但**没有进任何主流语言的标准库**：
#     Python → countminsketch / datasketch（第三方）
#     Java   → stream-lib / Algebird（Twitter，第三方）
#     Go     → 各家自研；标准库无
#     C++    → 各家自研；标准库无
#     Redis  → CMS.INCRBY（Redis 是存储，不是语言标准库）
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   CI / CJ / CC / CV / CM 是本库内部的循环/临时变量，
#   调用方**绝不能拿它们当自己的循环变量** —— 一次 cms_add 就会改掉它们，
#   外层循环当场退出，症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   w、d 均为正整数（w 不必是 2 的幂 —— CMS 理论里 w = ⌈e/ε⌉）。
#   取模一律走 cms_mod()：**墨语言的 % 对负数返回负数**，
#   直接取模会得到负列号，写成静默越界。
#   合并是**逐格相加**（CMS 是线性的，这是它能分布式聚合的原因）；
#   Bloom 的合并是逐位 OR —— 同是"合并"，运算完全不同。

# ── 池 ─────────────────────────────────────────────────────
# 每个 sketch 占 3 + d·w 个字：
#   字 0     = w（列数）
#   字 1     = d（行数）
#   字 2     = N（累计加数，用于 ε·N 上界）
#   字 3..   = d 行 × w 列计数器
var CMSP: [16384] i64 = 0;
var CMSFREE: i64 = 0;

# ── 诊断 / 状态 ────────────────────────────────────────────
var CMSOV: i64 = 0;     # 池越界
var CMSBAD: i64 = 0;    # 参数非法
var CMSDEG: i64 = 0;    # 出现过"h2 mod w == 0 被强制改成 1"的次数（退化保护）

# ── 专用循环/临时变量 ──────────────────────────────────────
var CI: i64 = 0;
var CJ: i64 = 0;
var CC: i64 = 0;
var CV: i64 = 0;
var CM: i64 = 0;

fn cm_delta() -> i64 { return 0 - 7046029254386353131; }  # 0x9E3779B97F4A7C15
fn cm_c1() -> i64    { return 0 - 4658895280553007687; }  # 0xBF58476D1CE4E5B9
fn cm_c2() -> i64    { return 0 - 7723592293110705685; }  # 0x94D049BB133111EB

fn cm_shr(x: i64, n: i64) -> i64 {
    if n <= 0 { return x; }
    if n >= 64 { return 0; }
    return (x >> n) & ((1 << (64 - n)) - 1);
}

fn cm_mix(z: i64) -> i64 {
    let a: i64 = z + cm_delta();
    a = a ^ cm_shr(a, 30);
    a = a * cm_c1();
    a = a ^ cm_shr(a, 27);
    a = a * cm_c2();
    a = a ^ cm_shr(a, 31);
    if a == 0 { a = 1; }
    return a;
}

fn cm_h1(x: i64) -> i64 { return cm_mix(x); }
fn cm_h2(x: i64) -> i64 { return cm_mix(x ^ cm_c1()) | 1; }

# ── 取模（负数安全）────────────────────────────────────────
# 🔴 墨语言的 % 对负数返回负数。直接用会得到负列号，
#    进而读写 CMSP[base + 负数] —— 越界但**不报错**，
#    只表现为某个无关 sketch 的计数被悄悄改动。
fn cms_mod(v: i64, w: i64) -> i64 {
    let r: i64 = v % w;
    if r < 0 { r = r + w; }
    return r;
}

# ── 新建 ───────────────────────────────────────────────────
fn cms_new(w: i64, d: i64) -> i64 {
    if w <= 0 { CMSBAD = 1; return 0 - 1; }
    if d <= 0 { CMSBAD = 1; return 0 - 1; }
    let base: i64 = CMSFREE;
    if base + 3 + d * w > 16384 { CMSOV = 1; return 0 - 1; }
    CMSFREE = base + 3 + d * w;
    CMSP[base] = w;
    CMSP[base + 1] = d;
    CMSP[base + 2] = 0;
    return base;
}

# ── 插入（c 可为任意正整数）────────────────────────────────
fn cms_add(h: i64, x: i64, c: i64) -> i64 {
    let w: i64 = CMSP[h];
    let d: i64 = CMSP[h + 1];
    let base: i64 = h + 3;
    let h1v: i64 = cms_mod(cm_h1(x), w);
    let h2v: i64 = cms_mod(cm_h2(x), w);
    # 🔴 退化保护：h2 ≡ 0 (mod w) 时，i·h2 恒为 0 ⇒ d 行**全落在同一列**，
    #    sketch 退化成单行，误差上界从 ε·N 变成"与单行同阶"。
    #    不报错、不崩溃，只是误差悄悄变大 —— 正是要挡住的形状。
    #
    #    ⚠️ 但**w 为偶数时这段不可达**：cm_h2 已 |1 ⟹ h2 恒为奇数，
    #    而 "h2 ≡ 0 (mod w)" 要求 h2 是 w 的倍数 —— 偶数 w 的倍数必为偶数。
    #    实测（key 0..49）：w=20/22/24 命中 0 次；w=15 命中 4 次、w=23 命中 4 次。
    #    所以 tests/145_sketch.mo 专门用 **w=15（奇数）** 跑一遍，
    #    并断言 CMSDEG > 0 —— 没有这条守卫，本保护是死代码，
    #    去掉它的变异（M6）会"全绿未被捕获"（v1.144 实测确实如此）。
    if h2v == 0 { h2v = 1; CMSDEG = CMSDEG + 1; }
    CI = 0;
    CJ = 0;
    while CI < d {
        CJ = h1v + cms_mod(CI * h2v, w);
        if CJ >= w { CJ = CJ - w; }
        CMSP[base + CI * w + CJ] = CMSP[base + CI * w + CJ] + c;
        CI = CI + 1;
    }
    CMSP[h + 2] = CMSP[h + 2] + c;
    return 0;
}

# ── 查询（取 d 行的最小值）─────────────────────────────────
fn cms_query(h: i64, x: i64) -> i64 {
    let w: i64 = CMSP[h];
    let d: i64 = CMSP[h + 1];
    let base: i64 = h + 3;
    let h1v: i64 = cms_mod(cm_h1(x), w);
    let h2v: i64 = cms_mod(cm_h2(x), w);
    if h2v == 0 { h2v = 1; }
    CM = 9223372036854775807;
    CI = 0;
    CJ = 0;
    CV = 0;
    while CI < d {
        CJ = h1v + cms_mod(CI * h2v, w);
        if CJ >= w { CJ = CJ - w; }
        CV = CMSP[base + CI * w + CJ];
        if CV < CM { CM = CV; }
        CI = CI + 1;
    }
    return CM;
}

# ── 清空 ───────────────────────────────────────────────────
fn cms_clear(h: i64) -> i64 {
    let w: i64 = CMSP[h];
    let d: i64 = CMSP[h + 1];
    let base: i64 = h + 3;
    CI = 0;
    while CI < d * w {
        CMSP[base + CI] = 0;
        CI = CI + 1;
    }
    CMSP[h + 2] = 0;
    return 0;
}

# ── 合并（逐格相加）────────────────────────────────────────
# 要求 w、d 相同，否则返回 0 − 1 并置 CMSBAD。
# CMS 是**线性**的：merge(A,B) 的误差保证与直接构造 A+B 同阶 ——
# 这正是它能分布式聚合、而 Bloom 只能做 OR 的原因。
fn cms_merge(dst: i64, src: i64) -> i64 {
    if CMSP[dst] != CMSP[src] { CMSBAD = 1; return 0 - 1; }
    if CMSP[dst + 1] != CMSP[src + 1] { CMSBAD = 1; return 0 - 1; }
    let w: i64 = CMSP[dst];
    let d: i64 = CMSP[dst + 1];
    let bd: i64 = dst + 3;
    let bs: i64 = src + 3;
    CI = 0;
    while CI < d * w {
        CMSP[bd + CI] = CMSP[bd + CI] + CMSP[bs + CI];
        CI = CI + 1;
    }
    CMSP[dst + 2] = CMSP[dst + 2] + CMSP[src + 2];
    return 0;
}

# ── 累计加数 N（ε·N 上界要用）──────────────────────────────
fn cms_total(h: i64) -> i64 { return CMSP[h + 2]; }

# ── 理论参数：给 ε、δ 反解 w、d ────────────────────────────
#   w = ⌈e/ε⌉ ，d = ⌈ln(1/δ)⌉
# 用整数近似 e ≈ 2.71828 → e·100000 = 271828；ln(1/δ) 用 fm_log。
fn cms_w_for(eps_num: i64, eps_den: i64) -> i64 {
    # w = ceil(e / eps) = ceil(e * eps_den / eps_num)
    let num: i64 = 271828 * eps_den;
    let q: i64 = num / (eps_num * 100000);
    if q * (eps_num * 100000) < num { q = q + 1; }
    if q < 1 { q = 1; }
    return q;
}

# ═══ Conservative Update（CU）══════════════════════════════
# Cormode & Muthukrishnan 2005 §3 的同名变体。
#
#   普通 add：d 行**各**加 c。
#   CU     ：先取 d 行的当前最小值 v，只把 **< v+c 的行拉到 v+c**。
#
# 为什么更准：查询取 min。某行已经因为碰撞涨到很大了，再往上加
# 只会让 min 更难降下来 —— 而它本来就不参与 min。CU 干脆不动它。
#
# 两条性质（本库都做成断言）：
#   ① 无低估**仍然成立**：不变式"每行 T[i][pos_i(x)] ≥ 真实值 a"
#      在 CU 下保持 —— 更新前 min v ≥ a，更新后每行 ≥ v+c ≥ a+c。
#      ⟹ CU 换来的只是"更小的 **高估**"，不是放宽保证。
#   ② 实测平均误差显著低于普通 CMS（见 tests/147_cbfcu.mo）。
#
# 🔴 CU 的代价：**破坏线性性**。
#    CMS 的 merge（逐格相加）之所以成立，是因为"各加 c"与顺序无关；
#    CU 的"拉到 v+c"依赖**当前状态**，于是
#      merge(CU(A), CU(B))  ≠  CU(A ∪ B)
#    实测列为已知限制（tests/147 逐格比对出差值 > 0）。
#    这是 CU 换误差付出的真金白银：不能再分布式聚合。
#
# ⚠️ 与 cms_add 用**同一批**哈希（cm_h1/cm_h2）与同一套取模，
#    所以两者的差异**只可能**来自更新策略，不是哈希质量差异 ——
#    这是"对照"能成立的前提。
fn cms_cu_add(h: i64, x: i64, c: i64) -> i64 {
    let w: i64 = CMSP[h];
    let d: i64 = CMSP[h + 1];
    let base: i64 = h + 3;
    let h1v: i64 = cms_mod(cm_h1(x), w);
    let h2v: i64 = cms_mod(cm_h2(x), w);
    let v: i64 = 0;
    let pos: i64 = 0;
    if h2v == 0 { h2v = 1; CMSDEG = CMSDEG + 1; }
    # ── 第一遍：求 d 行的当前最小值 ──
    CM = 9223372036854775807;
    CI = 0;
    while CI < d {
        CJ = h1v + cms_mod(CI * h2v, w);
        if CJ >= w { CJ = CJ - w; }
        CV = CMSP[base + CI * w + CJ];
        if CV < CM { CM = CV; }
        CI = CI + 1;
    }
    v = CM;
    # ── 第二遍：只把低于 v+c 的行拉到 v+c ──
    #    等价于论文里"只更新 == v 的行"在 c=1 时的写法，
    #    但用 max 形式对 c>1 也正确（不变式证明见上）。
    CI = 0;
    while CI < d {
        CJ = h1v + cms_mod(CI * h2v, w);
        if CJ >= w { CJ = CJ - w; }
        pos = base + CI * w + CJ;
        if CMSP[pos] < v + c { CMSP[pos] = v + c; }
        CI = CI + 1;
    }
    CMSP[h + 2] = CMSP[h + 2] + c;
    return 0;
}
