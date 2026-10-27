# hdc —— 超维计算 / 向量符号架构（Hyperdimensional Computing / VSA）
#
# ── 概念来源 ────────────────────────────────────────────────
#   HDC / VSA：把符号、记录、序列编码成**几千维的随机向量**，
#   用三个代数运算做组合，全部是位运算，不需要浮点、不需要训练。
#     Kanerva 2009（HDC 命名）、Plate 1995（HRR）、Gayler 2003（VSA）
#
#   三条代数要求（pyhdc 文档、Kleyko et al. 2022 综述的通行表述）：
#     bundling ⊕ :  sim(a⊕b, a) ≫ 0       交换        sim(a⊕b, c) ≈ 0
#     binding  ⊗ :  sim(a⊗b, a) ≈ 0       可逆        ⊗ 对 ⊕ 分配
#     n 个等权分量 bundle 后，对每个分量的相似度 ≈ 1/√n
#
#   **为什么算"概念"**：PeerJ Comput. Sci. 综述（Cumbo & Chicco 2025）原话——
#     "the lack of dedicated general-purpose frameworks for vector-symbolic
#      computing makes it difficult for researchers and developers to
#      experiment with and deploy HDC-based solutions efficiently"
#     且该领域**普遍不公开代码**，违反 FAIR 原则。
#   现有只有 torchhd / pyhdc / hdlib 这类研究库，**没有主流框架内建**。
#
# ── 本实现选 BSC（Binary Spatter Codes）────────────────────
#   向量空间 {0,1}^D，binding = XOR。
#   BSC 的独门性质：**binding 精确自逆**，
#       bind(bind(a, b), b) == a   逐位相等，零误差
#   其它族（HRR / FHRR / MAP）都只是**近似**可逆。
#   代价是二值化损失；好处是 XOR 一个指令 64 位，
#   Hamming 距离 = XOR + popcount —— 与墨语言的位并行天然契合。
#
# ── 相似度口径 ──────────────────────────────────────────────
#   {0,1} 向量的余弦相似度 = 1 − ham/D，随机向量 ≈ 0.5。
#   但 HDC 文献通行的"归一化汉明相似度"是
#       sim = 1 − 2·ham/D ∈ [−1, 1]
#   它等价于把 {0,1} 映到 {−1,+1} 后的余弦。本库用它：
#   相同 = 1，随机 ≈ 0，正交判据才好写。
#
# ── bundling 用位平面计数器 ─────────────────────────────────
#   每个维度一个 CW 位的计数器，按**位平面**打包：
#     cnt[b·HDW + j] = 第 b 位平面
#   加一个 {0,1} 向量就是行波进位加法器，64 lane 全并行：
#     plane ^= carry ; carry = old_plane & carry
#   arXiv:1807.08583（硬件优化）实测：宽度 5 bit 就够追平
#   golden method（多数投票）的容量 —— 本库可以实测这条曲线。

import "io.mo";

# ── 存储池 ─────────────────────────────────────────────────
# 以 i64 字为单位，一个向量占 HDW 个字 = HDD 位。
var HDP: [24576] i64 = 0;
var HDFREE: i64 = 0;

var HDW: i64 = 0;        # 字数
var HDD: i64 = 0;        # 维数（位数）
var HDCW: i64 = 8;       # bundling 计数器宽度（位平面数）
var HDOVF: i64 = 0;      # 计数器溢出标志

# hdc_dim 时一次性分配的复用区（避免每次调用都吃掉池）
var HDBM: i64 = 0;       # 位图：翻转去重
var HDC0: i64 = 0;       # 临时计数器
var HDA0: i64 = 0;       # 临时向量
var HDA1: i64 = 0;
var HDA2: i64 = 0;

# ── 全局临时（循环内声明 let 会累积栈帧，故一律提到外面）────
var _h0: i64 = 0;
var _h1: i64 = 0;
var _h2: i64 = 0;
var _h3: i64 = 0;
var _h4: i64 = 0;
var _h5: i64 = 0;
var _h6: i64 = 0;
var _h7: i64 = 0;
var _h8: i64 = 0;

# ── 跨调用存活的值必须用专用全局 ───────────────────────────
# ⚠️ 本轮最大的坑：_h0.._h8 是**共享**临时，被调函数会随手改。
#    凡是"循环变量 / 跨调用要保持的中间结果"都存在这里，
#    否则 hdc_im_cim 的翻转位数会被 hdc_copy 抹掉 —— 不报错，
#    只是 CIM 退化成"只有 level 1 与 level 0 相关"。
var HDI: i64 = 0;      # 循环变量 i
var HDJ: i64 = 0;      # 循环变量 j
var HDK: i64 = 0;      # 循环变量 k
var HDNF: i64 = 0;     # CIM 每级翻转位数
var HDBI: i64 = 0;     # 关联检索：最佳下标
var HDBS: i64 = 0;     # 关联检索：最佳相似度

# ── 用户填充的特征值（避免跨数组传址）───────────────────────
var HDV: [512] i64 = 0;

# ── 随机源 ─────────────────────────────────────────────────
var HDRS: i64 = 8837412947;

fn hdc_popcnt(x: i64) -> i64 {
    let v: i64 = x;
    v = v - ((v >> 1) & 6148914691236517205);
    v = (v & 3689348814741910323) + ((v >> 2) & 3689348814741910323);
    v = (v + (v >> 4)) & 1085102592571150095;
    return (v * 72340172838076673) >> 56;
}

# xorshift64 + 一次乘法混合。
# 低位质量直接影响超向量的平衡性 —— 正交性测试就是它的检验。
fn hdc_next() -> i64 {
    let a: i64 = HDRS;
    a = a ^ (a << 13);
    a = a ^ (a >> 7);
    a = a ^ (a << 17);
    if a == 0 { a = 8837412947; }
    HDRS = a;
    let b: i64 = a * 2654435761;
    b = b ^ (b >> 15);
    if b == 0 { b = 1; }
    return b;
}

fn hdc_seed(s: i64) -> i64 {
    if s == 0 { HDRS = 8837412947; }
    if s != 0 { HDRS = s; }
    return 0;
}

# ── 维度与分配 ─────────────────────────────────────────────
fn hdc_dim(nw: i64) -> i64 {
    HDW = nw;
    HDD = nw * 64;
    HDFREE = 0;
    HDOVF = 0;
    HDBM = hdc_new();
    HDC0 = hdc_cnt_new();
    HDA0 = hdc_new();
    HDA1 = hdc_new();
    HDA2 = hdc_new();
    return HDD;
}

fn hdc_new() -> i64 {
    _h0 = HDFREE;
    HDFREE = HDFREE + HDW;
    return _h0;
}

# 分配 n 个连续向量，返回首槽
fn hdc_new_n(n: i64) -> i64 {
    _h0 = HDFREE;
    HDFREE = HDFREE + HDW * n;
    return _h0;
}

fn hdc_zero(v: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        HDP[v + _h0] = 0;
        _h0 = _h0 + 1;
    }
    return 0;
}

fn hdc_copy(dst: i64, src: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        HDP[dst + _h0] = HDP[src + _h0];
        _h0 = _h0 + 1;
    }
    return 0;
}

# 复制 n 个连续向量
fn hdc_copy_n(dst: i64, src: i64, n: i64) -> i64 {
    HDI = 0;
    while HDI < n * HDW {
        HDP[dst + HDI] = HDP[src + HDI];
        HDI = HDI + 1;
    }
    return 0;
}

fn hdc_fill(v: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        HDP[v + _h0] = hdc_next();
        _h0 = _h0 + 1;
    }
    return 0;
}

fn hdc_rand(v: i64, seed: i64) -> i64 {
    hdc_seed(seed);
    return hdc_fill(v);
}

# ── binding：XOR（BSC）──────────────────────────────────────
fn hdc_bind(a: i64, b: i64, dst: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        HDP[dst + _h0] = HDP[a + _h0] ^ HDP[b + _h0];
        _h0 = _h0 + 1;
    }
    return 0;
}

# ── 相似度 ─────────────────────────────────────────────────
fn hdc_ham(a: i64, b: i64) -> i64 {
    _h0 = 0;
    _h1 = 0;
    while _h0 < HDW {
        _h1 = _h1 + hdc_popcnt(HDP[a + _h0] ^ HDP[b + _h0]);
        _h0 = _h0 + 1;
    }
    return _h1;
}

# sim = 1 − 2·ham/D，Q16.16
fn hdc_simq(a: i64, b: i64) -> i64 {
    _h0 = hdc_ham(a, b);
    return ((HDD - _h0 - _h0) << 16) / HDD;
}

# 位平衡性：1 的个数（应接近 D/2）
fn hdc_wt(v: i64) -> i64 {
    _h0 = 0;
    _h1 = 0;
    while _h0 < HDW {
        _h1 = _h1 + hdc_popcnt(HDP[v + _h0]);
        _h0 = _h0 + 1;
    }
    return _h1;
}

# ── bundling：位平面计数器 ──────────────────────────────────
fn hdc_cnt_new() -> i64 {
    _h0 = HDFREE;
    HDFREE = HDFREE + HDCW * HDW;
    return _h0;
}

fn hdc_cnt_zero(c: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDCW * HDW {
        HDP[c + _h0] = 0;
        _h0 = _h0 + 1;
    }
    return 0;
}

# 累加一个 {0,1} 向量：行波进位，64 lane 并行
fn hdc_acc(c: i64, v: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        _h1 = HDP[v + _h0];          # carry-in 就是待加的位
        _h2 = 0;
        while _h2 < HDCW {
            _h3 = c + _h2 * HDW + _h0;
            _h4 = HDP[_h3];
            HDP[_h3] = _h4 ^ _h1;
            _h1 = _h4 & _h1;         # 进位
            _h2 = _h2 + 1;
        }
        if _h1 != 0 { HDOVF = 1; }   # 溢出：结果已错，必须显式暴露
        _h0 = _h0 + 1;
    }
    return 0;
}

# 加权累加 k 次（k 为负表示"减去"，用于 HDC 的 retrain）
fn hdc_accn(c: i64, v: i64, k: i64) -> i64 {
    HDI = 0;
    while HDI < k {
        hdc_acc(c, v);
        HDI = HDI + 1;
    }
    return 0;
}

# 多数投票：value > n/2 的位取 1，平局位随机打破
# 逐位比较器（位串行、64 lane 并行）：从高位到低位维护 eq / gt
fn hdc_maj(c: i64, n: i64, dst: i64) -> i64 {
    _h0 = 0;
    _h8 = n / 2;
    while _h0 < HDW {
        _h1 = 0 - 1;                 # eq: 全 1（假设相等）
        _h2 = 0;                     # gt
        _h3 = HDCW - 1;              # 位平面下标
        while _h3 > -1 {
            _h4 = HDP[c + _h3 * HDW + _h0];        # 该位平面的 64 个 bit
            _h5 = (_h8 >> _h3) & 1;
            _h6 = 0;
            if _h5 == 1 { _h6 = 0 - 1; }           # 阈值的第 b 位广播成掩码
            _h2 = _h2 | (_h1 & _h4 & (_h6 ^ (0 - 1)));
            _h1 = _h1 & ((_h4 ^ _h6) ^ (0 - 1));
            _h3 = _h3 - 1;
        }
        # 平局位（eq）用随机位打破，否则偶数个分量时半数维度恒为 0
        _h7 = hdc_next();
        HDP[dst + _h0] = _h2 | (_h1 & _h7);
        _h0 = _h0 + 1;
    }
    return 0;
}

# 不从 dst 读：先算出再写，故支持 dst == c 所在向量的情形
fn hdc_bundle(c: i64, n: i64, dst: i64) -> i64 {
    hdc_maj(c, n, dst);
    return 0;
}

# ── 置换（循环移位 k 位）─────────────────────────────────────
# ⚠️ 墨语言的 >> 是**算术**右移。取高 bs 位时若直接 >>，
#    符号扩展会把高位全填成 1 —— 必须与低 bs 位掩码相与。
#    bs == 0 时没有"高 0 位"，必须单独分支（1 << 64 未定义）。
fn hdc_perm(v: i64, k: i64, dst: i64) -> i64 {
    _h0 = k / 64;                    # 字移
    _h1 = k - _h0 * 64;              # 位移
    _h2 = 0;
    while _h2 < HDW {
        HDP[dst + _h2] = 0;
        _h2 = _h2 + 1;
    }
    _h2 = 0;
    while _h2 < HDW {
        _h3 = HDP[v + _h2];
        _h4 = _h2 + _h0;
        while _h4 > HDW - 1 { _h4 = _h4 - HDW; }
        if _h1 == 0 {
            HDP[dst + _h4] = HDP[dst + _h4] | _h3;
        }
        if _h1 != 0 {
            HDP[dst + _h4] = HDP[dst + _h4] | (_h3 << _h1);
            # 高 bs 位：算术右移后用掩码清掉符号扩展
            _h5 = (_h3 >> (64 - _h1)) & ((1 << _h1) - 1);
            _h6 = _h4 + 1;
            if _h6 > HDW - 1 { _h6 = 0; }
            HDP[dst + _h6] = HDP[dst + _h6] | _h5;
        }
        _h2 = _h2 + 1;
    }
    return 0;
}

# ── 恰好翻转 k 个**不同**的位 ────────────────────────────────
# 位图去重：随机取模会重复，直接翻会导致实际翻转数 < k，
# 而"抗噪能力"的定量结论恰恰依赖"恰好 k 位"。
fn hdc_flip_n(v: i64, k: i64) -> i64 {
    _h0 = 0;
    while _h0 < HDW {
        HDP[HDBM + _h0] = 0;
        _h0 = _h0 + 1;
    }
    _h1 = 0;                         # 已翻
    _h2 = 0;                         # 尝试次数，防死循环
    while _h1 < k {
        _h3 = hdc_next();
        if _h3 < 0 { _h3 = 0 - _h3; }
        _h4 = _h3 - (_h3 / HDD) * HDD;
        _h5 = _h4 / 64;
        _h6 = _h4 - _h5 * 64;
        _h7 = (HDP[HDBM + _h5] >> _h6) & 1;
        if _h7 == 0 {
            HDP[HDBM + _h5] = HDP[HDBM + _h5] | (1 << _h6);
            HDP[v + _h5] = HDP[v + _h5] ^ (1 << _h6);
            _h1 = _h1 + 1;
        }
        _h2 = _h2 + 1;
        if _h2 > HDD * 8 { return 0 - 1; }
    }
    return _h1;
}

# 翻转 pct%（按 D 计算，向下取整）
fn hdc_flip_pct(v: i64, pct: i64) -> i64 {
    _h0 = HDD * pct / 100;
    return hdc_flip_n(v, _h0);
}

# ── item memory ────────────────────────────────────────────
# 两种初始化，直接决定"可表达的相似度矩阵"（NeurIPS 2022 的核心论点）：
#   iid : 各 level 独立随机 → sim(L_i, L_j) ≈ 0，对 i≠j
#   cim : 逐级翻转固定位数 → sim(L_i, L_j) = 1 − 2|i−j|/(m−1)（保留序结构）
fn hdc_im_iid(base: i64, m: i64, seed: i64) -> i64 {
    hdc_seed(seed);
    HDI = 0;
    while HDI < m {
        hdc_fill(base + HDI * HDW);
        HDI = HDI + 1;
    }
    return 0;
}

fn hdc_im_cim(base: i64, m: i64, seed: i64) -> i64 {
    hdc_seed(seed);
    hdc_fill(base);
    # 相邻 level 翻转 D/(2(m−1)) 位 → 相邻相似度 1/(m−1) 的间距
    HDNF = HDD / (2 * (m - 1));
    if HDNF < 1 { HDNF = 1; }
    HDI = 1;
    while HDI < m {
        hdc_copy(base + HDI * HDW, base + (HDI - 1) * HDW);
        hdc_flip_n(base + HDI * HDW, HDNF);
        HDI = HDI + 1;
    }
    return 0;
}

# ── 记录编码：H = ⊕_f ( ID_f ⊗ Level_{v_f} ) ────────────────
# 特征值放在 HDV[0..nf-1]，level 记忆在 lvm，ID 记忆在 idm（每特征一个向量）
fn hdc_enc_rec(dst: i64, idm: i64, lvm: i64, nf: i64) -> i64 {
    hdc_cnt_zero(HDC0);
    HDI = 0;
    while HDI < nf {
        hdc_bind(idm + HDI * HDW, lvm + HDV[HDI] * HDW, HDA0);
        hdc_acc(HDC0, HDA0);
        HDI = HDI + 1;
    }
    hdc_maj(HDC0, nf, dst);
    return 0;
}

# ── n-gram 序列编码：H = ⊕_t ( Π^t G_{s_t} ) ────────────────
# s 放在 HDV[0..n-1]，符号记忆在 gm
fn hdc_enc_seq(dst: i64, gm: i64, n: i64) -> i64 {
    hdc_cnt_zero(HDC0);
    HDI = 0;
    while HDI < n {
        hdc_perm(gm + HDV[HDI] * HDW, HDI, HDA0);
        hdc_acc(HDC0, HDA0);
        HDI = HDI + 1;
    }
    hdc_maj(HDC0, n, dst);
    return 0;
}

# ── 关联检索：在 base 起的 n 个向量里找与 q 最相似的 ─────────
fn hdc_am(base: i64, n: i64, q: i64) -> i64 {
    HDBI = 0;
    HDBS = 0 - 1073741824;           # -∞
    HDI = 1;
    while HDI < n {
        _h0 = hdc_simq(base + HDI * HDW, q);
        if _h0 > HDBS {
            HDBS = _h0;
            HDBI = HDI;
        }
        HDI = HDI + 1;
    }
    _h0 = hdc_simq(base, q);
    if _h0 > HDBS { HDBI = 0; }
    return HDBI;
}

# ════════════════════════════════════════════════════════════
# ── retrain：整数累加原型 ──────────────────────────────────
#
#   概念来源：
#     OnlineHD（Hernandez-Cane / Kim / Simic / Nowick / Imani,
#       arXiv:2110.03662）—— 首次把 HDC 做成**单遍在线学习**，
#       并给出 retrain 回路：错分样本上 A_true += x̃ ，A_pred −= x̃
#     AdaptHD（Imani / Kim / Rosing, DAC 2019）—— 学习率
#       **逐样本自适应**：越错的样本步子越大。
#   两者至今只在 torchhd / hdlib 这类研究库里，没有主流框架内建。
#
#   ── 与 bundling 的根本区别（不是实现细节）────────────────
#   bundling 的原型是**二值**的（多数投票），±1 的修正会被多数投票
#   直接吞掉；retrain 的原型必须是**整数累加器** Σ ±x̃。
#   所以 retrain 不能复用 hdc_maj，必须另起一套表示。
#
#   ── 累加器怎么存 ────────────────────────────────────────
#   位平面：plane[b] 的第 j 位 = 第 j 个 lane 计数器的第 b 位。
#   每个 lane 独立 ±1，行波进位/借位，64 lane 全并行：
#       加: new = old ^ ca ;  ca' = old & ca
#       减: new = old ^ cs ;  cs' = (~old) & cs
#   两个掩码初始互补（x 与 ~x），且 ca' 要求 old=1、cs' 要求 old=0，
#   故传播中始终不交 —— 可以**合并成一趟**：
#       new = old ^ (ca|cs) ;  ca = old & ca ;  cs = (~old) & cs
#   ⚠️ 计数按 mod 2^HDRCW 回绕（补码），负数靠最高位平面解释。
#      回绕**不报错**，只会让分数悄悄变错 —— 用 HDRU 守着。
#
#   ── score 的闭式（只用 popcount，不需要逐 lane 展开）──────
#   m_j = c_j − 2^RCW·t_j（t_j = 最高位平面），x̃_j = 2x_j − 1
#     Σ_j c_j·x̃_j = Σ_b 2^b·u_b ，u_b = 2·popc(P_b & x) − popc(P_b)
#   最高位平面取负权即为补码：
#     score = Σ_{b<RCW−1} 2^b·u_b − 2^(RCW−1)·u_{RCW−1}
#   逐 lane 展开的慢速参照见 hdc_rt_score_ref —— 两者必须逐位相等。

var HDRCW: i64 = 12;      # retrain 累加器位宽（位平面数）
var HDRI: i64 = 0;
var HDRJ: i64 = 0;
var HDRK: i64 = 0;
var HDRE: i64 = 0;
var HDRU: i64 = 0;        # 累计 ±1 更新次数（守回绕）
var HDRVO: i64 = 0;       # 有符号溢出标志（回绕时会悄悄算错）
var HDRT0: i64 = 0;
var HDRT1: i64 = 0;
var HDRT2: i64 = 0;
var HDRT3: i64 = 0;
var HDRT4: i64 = 0;
var HDRP0: i64 = 0;
var HDRP1: i64 = 0;
var HDRP2: i64 = 0;
var HDRP3: i64 = 0;
var HDRP4: i64 = 0;
var HDRQ0: i64 = 0;
var HDRQ1: i64 = 0;
var HDRQ2: i64 = 0;
var HDRQ3: i64 = 0;
var HDRB0: i64 = 0;
var HDRB1: i64 = 0;
var HDRB2: i64 = 0;
var HDRB3: i64 = 0;
var HDRHM: i64 = 1;   # 自适应步长的归一化尺度：历史最大 hinge（自校准）

fn hdc_rt_new(n: i64) -> i64 {
    HDRT0 = HDFREE;
    HDFREE = HDFREE + HDRCW * HDW * n;
    return HDRT0;
}

fn hdc_rt_zero_n(a: i64, n: i64) -> i64 {
    HDRI = 0;
    while HDRI < HDRCW * HDW * n {
        HDP[a + HDRI] = 0;
        HDRI = HDRI + 1;
    }
    return 0;
}

# a += s·x̃ ，s = ±1
fn hdc_rt_addsub(a: i64, v: i64, s: i64) -> i64 {
    HDRI = 0;
    while HDRI < HDW {
        HDRT0 = HDP[v + HDRI];
        if s == 1 { HDRT2 = HDRT0; HDRT3 = HDRT0 ^ (0 - 1); }
        if s != 1 { HDRT2 = HDRT0 ^ (0 - 1); HDRT3 = HDRT0; }
        HDRJ = 0;
        while HDRJ < HDRCW {
            HDRT1 = HDP[a + HDRJ * HDW + HDRI];
            if HDRJ == HDRCW - 1 { HDRT4 = HDRT2 | HDRT3; }
            HDP[a + HDRJ * HDW + HDRI] = HDRT1 ^ (HDRT2 | HDRT3);
            HDRT2 = HDRT1 & HDRT2;
            HDRT3 = (HDRT1 ^ (0 - 1)) & HDRT3;
            HDRJ = HDRJ + 1;
        }
        # 有符号溢出 = 进/借位"入最高位"与"出最高位"不同。
        # 回绕本身不报错，只会让分数悄悄变错，所以必须显式暴露。
        HDRVO = HDRVO | (HDRT4 ^ (HDRT2 | HDRT3));
        HDRI = HDRI + 1;
    }
    HDRU = HDRU + 1;
    return 0;
}

fn hdc_rt_ovf() -> i64 {
    return HDRVO;
}

fn hdc_rt_score(a: i64, x: i64) -> i64 {
    HDRT0 = 0;
    HDRJ = 0;
    while HDRJ < HDRCW {
        HDRT1 = 0;
        HDRI = 0;
        while HDRI < HDW {
            HDRT2 = HDP[a + HDRJ * HDW + HDRI];
            HDRT1 = HDRT1 + 2 * hdc_popcnt(HDRT2 & HDP[x + HDRI]) - hdc_popcnt(HDRT2);
            HDRI = HDRI + 1;
        }
        if HDRJ == HDRCW - 1 { HDRT0 = HDRT0 - (1 << (HDRCW - 1)) * HDRT1; }
        if HDRJ != HDRCW - 1 { HDRT0 = HDRT0 + (1 << HDRJ) * HDRT1; }
        HDRJ = HDRJ + 1;
    }
    return HDRT0;
}

# 慢速参照：逐 lane 展开计数器再点积。只用于交叉验证闭式。
fn hdc_rt_score_ref(a: i64, x: i64) -> i64 {
    HDRT0 = 0;
    HDRI = 0;
    while HDRI < HDW {
        HDRJ = 0;
        while HDRJ < 64 {
            HDRT1 = 0;
            HDRK = 0;
            while HDRK < HDRCW {
                HDRT2 = (HDP[a + HDRK * HDW + HDRI] >> HDRJ) & 1;
                HDRT1 = HDRT1 + HDRT2 * (1 << HDRK);
                HDRK = HDRK + 1;
            }
            HDRT3 = (HDP[a + (HDRCW - 1) * HDW + HDRI] >> HDRJ) & 1;
            if HDRT3 == 1 { HDRT1 = HDRT1 - (1 << HDRCW); }
            HDRT4 = (HDP[x + HDRI] >> HDRJ) & 1;
            if HDRT4 == 1 { HDRT0 = HDRT0 + HDRT1; }
            if HDRT4 != 1 { HDRT0 = HDRT0 - HDRT1; }
            HDRJ = HDRJ + 1;
        }
        HDRI = HDRI + 1;
    }
    return HDRT0;
}

# ⚠️ 必须用专属全局：hdc_rt_fit / hdc_rt_acc 的循环变量是 HDRP0，
#    若这里复用，pred 会把调用方的样本下标改成类别号 —— 死循环。
fn hdc_rt_pred(base: i64, k: i64, x: i64) -> i64 {
    HDRB0 = 0 - 1;
    HDRB1 = 0 - 4611686018427387904;
    HDRB2 = 0;
    while HDRB2 < k {
        HDRB3 = hdc_rt_score(base + HDRB2 * HDRCW * HDW, x);
        if HDRB3 > HDRB1 { HDRB1 = HDRB3; HDRB0 = HDRB2; }
        HDRB2 = HDRB2 + 1;
    }
    return HDRB0;
}

fn hdc_rt_acc(base: i64, k: i64, xs: i64, ys: i64, n: i64) -> i64 {
    HDRP0 = 0;
    HDRP4 = 0;
    while HDRP0 < n {
        HDRP1 = hdc_rt_pred(base, k, xs + HDRP0 * HDW);
        if HDRP1 == HDP[ys + HDRP0] { HDRP4 = HDRP4 + 1; }
        HDRP0 = HDRP0 + 1;
    }
    return HDRP4;
}

# mode 0: 固定 α=1，仅错分更新（OnlineHD 原式）
# mode 1: 自适应 α∈[1,amax]，仅错分更新（AdaptHD 思路）
#         α = 1 + (amax−1)·hinge/HSCALE，HSCALE 由 retrain 前的
#         最大 hinge 标定 —— 自校准，没有魔法常数
# mode 2: 固定 α=amax，仅错分更新（大步长对照，预期震荡）
# mode 3: 不纠正，每个样本继续往正确类累加（多遍 bundling 对照）
fn hdc_rt_abs(x: i64) -> i64 {
    if x < 0 { return 0 - x; }
    return x;
}

# ── 在线（流式）：逐样本"先预测、再更新"，返回在线错误数 ──────
#   这才是 OnlineHD 真正的场景。批式 retrain 在 HDC 上往往是空转的：
#   单遍原型对每个训练样本都含一个 x̃ᵢ·x̃ᵢ = D 的自项，必然压过交叉项，
#   于是训练集**恒被拟合到 100%**，没有错分样本可供更新。
#   mode 3 = 不纠正（纯累加），是在线场景下的对照组。
fn hdc_rt_online(base: i64, k: i64, xs: i64, ys: i64, n: i64, mode: i64, amax: i64) -> i64 {
    HDRU = 0;
    HDRVO = 0;
    hdc_rt_zero_n(base, k);
    HDRP0 = 0;
    HDRQ1 = 0;                       # 在线错误数
    HDRHM = 1;
    while HDRP0 < n {
        HDRP2 = HDP[ys + HDRP0];
        HDRP1 = 0 - 1;
        if HDRP0 > 0 { HDRP1 = hdc_rt_pred(base, k, xs + HDRP0 * HDW); }
        if HDRP1 != HDRP2 {
            HDRQ1 = HDRQ1 + 1;
            if mode != 3 {
                if HDRP1 > 0 - 1 {
                    HDRP3 = hdc_rt_score(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW);
                    HDRP4 = hdc_rt_score(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW);
                    HDRQ2 = 1;
                    if mode == 2 { HDRQ2 = amax; }
                    if mode == 1 { HDRQ2 = 1 + (amax - 1) * (HDRP3 - HDRP4) / HDRHM; }
                    if HDRQ2 > amax { HDRQ2 = amax; }
                    if HDRQ2 < 1 { HDRQ2 = 1; }
                    if HDRP3 - HDRP4 > HDRHM { HDRHM = HDRP3 - HDRP4; }
                    HDRQ3 = 0;
                    while HDRQ3 < HDRQ2 {
                        hdc_rt_addsub(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW, 0 - 1);
                        HDRQ3 = HDRQ3 + 1;
                    }
                    HDRQ3 = 1;
                    while HDRQ3 < HDRQ2 {
                        hdc_rt_addsub(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW, 1);
                        HDRQ3 = HDRQ3 + 1;
                    }
                }
            }
        }
        hdc_rt_addsub(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW, 1);
        HDRP0 = HDRP0 + 1;
    }
    return HDRQ1;
}

fn hdc_rt_fit(base: i64, k: i64, xs: i64, ys: i64, n: i64, epochs: i64, mode: i64, amax: i64) -> i64 {
    HDRU = 0;
    HDRVO = 0;
    hdc_rt_zero_n(base, k);
    HDRP0 = 0;
    while HDRP0 < n {
        hdc_rt_addsub(base + HDP[ys + HDRP0] * HDRCW * HDW, xs + HDRP0 * HDW, 1);
        HDRP0 = HDRP0 + 1;
    }
    HDRHM = 1;
    HDRE = 0;
    while HDRE < epochs {
        HDRP0 = 0;
        while HDRP0 < n {
            HDRP1 = hdc_rt_pred(base, k, xs + HDRP0 * HDW);
            HDRP2 = HDP[ys + HDRP0];
            if mode == 3 {
                hdc_rt_addsub(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW, 1);
            }
            if mode != 3 {
                if HDRP1 != HDRP2 {
                    HDRP3 = hdc_rt_score(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW);
                    HDRP4 = hdc_rt_score(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW);
                    HDRQ1 = HDRP3 - HDRP4;
                    HDRQ2 = 1;
                    if mode == 2 { HDRQ2 = amax; }
                    if mode == 1 { HDRQ2 = 1 + (amax - 1) * HDRQ1 / HDRHM; }
                    if HDRQ2 > amax { HDRQ2 = amax; }
                    if HDRQ2 < 1 { HDRQ2 = 1; }
                    if HDRQ1 > HDRHM { HDRHM = HDRQ1; }
                    HDRQ3 = 0;
                    while HDRQ3 < HDRQ2 {
                        hdc_rt_addsub(base + HDRP2 * HDRCW * HDW, xs + HDRP0 * HDW, 1);
                        hdc_rt_addsub(base + HDRP1 * HDRCW * HDW, xs + HDRP0 * HDW, 0 - 1);
                        HDRQ3 = HDRQ3 + 1;
                    }
                }
            }
            HDRP0 = HDRP0 + 1;
        }
        HDRE = HDRE + 1;
    }
    return HDRU;
}
