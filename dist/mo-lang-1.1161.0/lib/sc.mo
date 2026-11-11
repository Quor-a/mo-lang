# sc —— 随机计算（Stochastic Computing, SC）
#
# ── 概念来源 ────────────────────────────────────────────────
#   SC 是 1960 年代提出、近十年因 AI 硬件而复兴的计算范式：
#   **数值编码为比特流中 1 的概率**，于是算术退化为几个逻辑门。
#
#   参考：
#     · Alaghi & Hayes, "Survey of Stochastic Computing" (ACM TECS 2013)
#     · Alaghi, Qian & Hayes, "The Promise and Challenge of SC" (2017)
#     · Qian, "The Logic of Random Pulses" (UW PhD thesis) —— 门-函数对应定理
#   现状：论文体系完整（编码/门/相关性定理/SNG 优化），
#         **主流框架零实现**——PyTorch/JAX 都没有 SC 算子，
#         只有 FPGA/ASIC 的 RTL 与少量 Python 仿真。
#         属于典型的"有数学、躺在论文里"的能力。
#
# ── 三条核心公式 ────────────────────────────────────────────
#   单极 UP（x ∈ [0,1]）：  乘法 = AND
#   双极 BP（x ∈ [-1,1]）： 乘法 = XNOR   （XOR 是"反相双极"乘法）
#   加法（两种编码通用）：  MUX + 选择线 P(sel)=1/2 → (x+y)/2
#                          ↑ 这叫 scaled add，结果被缩放 1/2
#
# ── 最重要的陷阱：相关性 ────────────────────────────────────
#   门实现的函数**取决于两路流的统计相关度 C**：
#       AND :  C=0 → x·y          C=1 → min(x,y)
#       XNOR:  C=0 → x·y          C=1 → 1 − |x−y|
#   也就是说：两路流若共享同一个随机源，
#   **乘法器算出来的根本不是乘积**，而且——这是关键——
#   该误差是**系统性**的，加长比特流也消除不掉
#   （Alaghi & Hayes 原话："cannot be corrected simply by extending N"）。
#
#   本库把"源编号"做成显式参数，正是为了让这个陷阱**可复现**：
#       同一 src → 两路流逐位相同 → C=1
#       不同 src → 独立序列     → C≈0
#
# ── 位并行（bit-slicing）────────────────────────────────────
#   把 L 个时间步打包进 L/64 个 i64 字，于是
#       一次 AND  = 64 个时间步的乘法
#       popcount  = 求和
#   墨语言有 i64 位运算，这条正合适。
#   注意打包的是**时间**维度（一个数自己的 L 个周期），
#   不是把不同的数塞进一个字。

import "io.mo";

# ── 存储池 ─────────────────────────────────────────────────
# 以 i64 字为单位，每个字承载 64 个时间步。
var SCP: [8192] i64 = 0;
var SCN: i64 = 0;

# ── 随机源 ─────────────────────────────────────────────────
# 每个源有独立初始种子与当前状态。
# 生成流时**重置到初始种子**，这样同一 src 生成的流逐位相同。
var SCS0: [64] i64 = 0;
var SCS: [64] i64 = 0;

# ── popcount（SWAR，无硬件指令时的标准写法）─────────────────
# ⚠️ 墨语言的 >> 是**算术**右移。这里恰好安全：
#    每一步的掩码都把最高位组清掉了，符号扩展位不会混进结果。
#    但换个写法就不一定——所以下面有逐位对照的测试。
fn popcount(x: i64) -> i64 {
    let v: i64 = x;
    v = v - ((v >> 1) & 6148914691236517205);
    v = (v & 3689348814741910323) + ((v >> 2) & 3689348814741910323);
    v = (v + (v >> 4)) & 1085102592571150095;
    return (v * 72340172838076673) >> 56;
}

# ── 源管理 ─────────────────────────────────────────────────
fn sc_mix(a: i64, b: i64) -> i64 {
    let x: i64 = a + b * 2654435761;
    x = x ^ (x << 13);
    x = x ^ (x >> 7);
    x = x ^ (x << 17);
    if x == 0 { x = 8837412947; }
    if x < 0 { x = 0 - x; }
    return x;
}

fn sc_rng_init(base: i64) -> i64 {
    let i: i64 = 0;
    while i < 64 {
        SCS0[i] = sc_mix(base, i + 1);
        SCS[i] = SCS0[i];
        i = i + 1;
    }
    return 0;
}

# 把源的状态拨回初始种子 —— 同一 src 因此得到逐位相同的流
fn sc_rng_reset(src: i64) -> i64 {
    SCS[src] = SCS0[src];
    return 0;
}

# 伪随机（xorshift64），返回 [0, 65536)
# ⚠️ 必须取**高位**。1.91 踩过 LCG 低位奇偶共振的坑：
#    LCG 的乘数与增量都是奇数时 mod 2 上恒为 h←h+1，
#    低位逐周期交替，用低位当随机源会让比特流变成规律方波。
fn sc_rng_next(src: i64) -> i64 {
    let x: i64 = SCS[src];
    x = x ^ (x << 13);
    x = x ^ (x >> 7);
    x = x ^ (x << 17);
    SCS[src] = x;
    if x < 0 { x = 0 - x; }
    # ⚠️ 移 47 位而不是 48：x 非负且 < 2^63，所以 x>>47 ∈ [0, 2^16)，
    #    正好覆盖 Q16.16 的 [0,65536)。第一版写 >>48 只到 [0,32768)，
    #    于是任何 p>0.5 的流都恒为全 1 —— 不报错，只是结果永远是 1.0。
    return (x >> 47) & 65535;
}

# radical inverse（基 b）：把 t 的 b 进制数字镜像到小数点右边
#   第 s 维用第 s 个素数做基 —— 这就是 Halton 序列。
#
# 🔴 多维必须**换基**，不能靠同一条序列做 XOR 加扰。
#    第一版就是后者：两个维度都源自 base-2 的 van der Corput，
#    只是异或了不同掩码。表面上"两路流各不相同"，
#    实际两维仍高度相关，做乘法反而比伪随机差
#    （实测 L=1024：XOR 加扰误差 7877，伪随机 901）。
#    症状是"低差异没效果"，根因是维度构造错了。
fn radical_p(t: i64, base: i64) -> i64 {
    let r: i64 = 0;
    let f: i64 = 4294967296 / base;
    let tt: i64 = t;
    while tt > 0 {
        r = r + (tt % base) * f;
        f = f / base;
        tt = tt / base;
    }
    return r;
}

fn sc_prime(s: i64) -> i64 {
    if s == 0 { return 2; }
    if s == 1 { return 3; }
    if s == 2 { return 5; }
    if s == 3 { return 7; }
    if s == 4 { return 11; }
    if s == 5 { return 13; }
    if s == 6 { return 17; }
    if s == 7 { return 19; }
    if s == 8 { return 23; }
    if s == 9 { return 29; }
    if s == 10 { return 31; }
    if s == 11 { return 37; }
    if s == 12 { return 41; }
    if s == 13 { return 43; }
    if s == 14 { return 47; }
    return 53;
}

# 低差异源：确定性，铺得比伪随机均匀。
#   论文结论：同长度下精度更高，或同精度下长度更短。
fn sc_ld_next(src: i64, t: i64) -> i64 {
    return radical_p(t + 1, sc_prime(src)) >> 16;
}

# ── 流的分配与生成 ──────────────────────────────────────────
fn sc_reset() -> i64 {
    SCN = 0;
    return 0;
}

# 返回字偏移（不是字节地址）
fn sc_alloc(w: i64) -> i64 {
    let o: i64 = SCN;
    SCN = SCN + w;
    return o;
}

# 生成比特流。p 是 Q16.16 的 [0,1]（0..65536）。
#   mode 0 = 伪随机 xorshift；mode 1 = 低差异 van der Corput
#   src 决定随机序列；**同一 src 生成的两条流完全相关**
fn sc_gen(off: i64, w: i64, p: i64, src: i64, mode: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = 0;
    let v: i64 = 0;
    let r: i64 = 0;
    if p <= 0 { p = 0; }
    if p >= 65536 { p = 65536; }
    sc_rng_reset(src);
    while i < w {
        v = 0;
        b = 0;
        while b < 64 {
            r = 0;
            if mode == 1 { r = sc_ld_next(src, i * 64 + b); }
            if mode == 0 { r = sc_rng_next(src); }
            v = v << 1;
            if r < p { v = v | 1; }
            b = b + 1;
        }
        SCP[off + i] = v;
        i = i + 1;
    }
    return 0;
}

# ── 基本运算 ───────────────────────────────────────────────
# 单极乘法 = AND（要求两路流独立）
fn sc_mul_up(d: i64, a: i64, b: i64, w: i64) -> i64 {
    let i: i64 = 0;
    while i < w {
        SCP[d + i] = SCP[a + i] & SCP[b + i];
        i = i + 1;
    }
    return 0;
}

# 双极乘法 = XNOR
fn sc_mul_bp(d: i64, a: i64, b: i64, w: i64) -> i64 {
    let i: i64 = 0;
    while i < w {
        SCP[d + i] = (SCP[a + i] ^ SCP[b + i]) ^ -1;
        i = i + 1;
    }
    return 0;
}

# scaled add = MUX。sel 是 P=1/2 的流，结果 (a+b)/2
fn sc_add(d: i64, a: i64, b: i64, sel: i64, w: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < w {
        s = SCP[sel + i];
        # (a & s) | (b & ~s)：s=1 选 a，s=0 选 b。
        # P(s)=1/2 时输出概率 = (p_a + p_b)/2
        SCP[d + i] = (SCP[a + i] & s) | (SCP[b + i] & (s ^ -1));
        i = i + 1;
    }
    return 0;
}

# 解码：统计 1 的个数 / 总位数 → Q16.16 的 [0,1]
fn sc_decode(off: i64, w: i64) -> i64 {
    let ones: i64 = 0;
    let i: i64 = 0;
    while i < w {
        ones = ones + popcount(SCP[off + i]);
        i = i + 1;
    }
    return (ones * 65536) / (w * 64);
}

# ── 双极编码转换 ────────────────────────────────────────────
# x ∈ [-1,1] 的 Q16.16 ↔ 概率 p ∈ [0,1] 的 Q16.16
fn sc_bp_encode(x: i64) -> i64 {
    return (x + 65536) >> 1;
}

fn sc_bp_decode(p: i64) -> i64 {
    return p * 2 - 65536;
}

# ── 诊断：两路流的经验重合度 ────────────────────────────────
# 返回 P(a=1, b=1) 的 Q16.16 值。独立时应 ≈ p_a·p_b；
# 完全相关时 P(a=1,b=1) = min(p_a,p_b)，与 p_a·p_b 明显不同。
fn sc_joint11(a: i64, b: i64, w: i64) -> i64 {
    let ones: i64 = 0;
    let i: i64 = 0;
    while i < w {
        ones = ones + popcount(SCP[a + i] & SCP[b + i]);
        i = i + 1;
    }
    return (ones * 65536) / (w * 64);
}
