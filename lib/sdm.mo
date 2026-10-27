# sdm —— Kanerva 稀疏分布式记忆（Sparse Distributed Memory）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Pentti Kanerva, *Sparse Distributed Memory*, MIT Press 1988
#   （NASA Ames 技术报告 1984 起）。
#
#   结构：n 位地址空间（2^n 个地址，n=256 → 比宇宙原子数还多），
#   但**只显式存 M 个随机硬位置**（hard locations，M ≪ 2^n）。
#   写：激活所有与地址汉明距离 ≤ r 的硬位置，把内容 ±1 累加进它们的计数器。
#   读：激活同一批硬位置，把计数器按维求和，符号即读出位。
#
#   **为什么算"概念"**：Kanerva 1988 至今只有 sdmlib / 若干 numpy 演示，
#   没有主流框架内建；综述（2022 CS-SDM）指出"缺乏通用框架"，
#   且硬件实现集中在 FPGA/VLSI，软件侧没有可参考的规范实现。
#   它和 HDC（1.108 的 BSC）相邻但机制不同：
#     HDC  = 代数运算（⊕ bundling / ⊗ binding），向量本身就是表示
#     SDM  = 显式地址空间 + 邻接激活 + **内容计数器**，读写分离
#
# ── 三条可测的理论性质 ──────────────────────────────────────
#   ① 激活半径双向失败（本实现的重点）：
#        r 太小 → 0 个硬位置激活 → 读不出来
#        r 太大 → 全部激活     → 所有模式叠在一起 → 无区分度
#      两端失败**原因不同**，中间存在最优。
#   ② 容量有限且可量化：
#        信号 = |A_i|（本模式激活的位置数）
#        噪声 = Σ_{j≠i} |A_i ∩ A_j| ≈ (K−1)·M·P²
#      随存储模式数 K 增长，读出恢复率单调下降。
#   ③ 内容可噪：地址带噪声仍能读出（内容寻址 / 联想记忆的本质）。
#
# ── 内容计数器的表示（本实现的关键设计）────────────────────
#   每维一个计数器，用 **SWAR** 把 8 个 int8 打包进一个 i64。
#   但直接存补码 int8 会**跨字节借位**：
#       字节 0x00 减 1 → 0xFF 并向相邻字节借位
#       字节 0xFF 加 1 → 0x00 并向相邻字节进位
#   而 SDM 的计数器恰恰**常年在 0 附近摆动**——这个 bug 会静默发生。
#   所以本实现用**偏移表示**：存 count + 128，0 表现为字节值 0x80。
#   于是内容区初始化必须是 0x8080...80，**不是 0**。
#   溢出（字节触及 0x00 / 0xFF）显式置 SDOVF，绝不静默。

import "io.mo";

# ── 配置 ───────────────────────────────────────────────────
var SDW: i64 = 0;      # 地址/数据的字数（i64）
var SDD: i64 = 0;      # 维数 = SDW * 64
var SDN: i64 = 0;      # 硬位置数
var SDR: i64 = 0;      # 激活半径（汉明距离 ≤ r）
var SDCW: i64 = 0;     # 每个硬位置的内容字数 = SDW * 8

# ── 存储 ───────────────────────────────────────────────────
var SDBANK: i64 = 0;     # 0 = 转移记忆，1 = 清洗记忆（独立计数器）
var SDLOC: [8192] i64 = 0;      # 硬位置地址：SDN × SDW
var SDCNT: [32768] i64 = 0;     # 内容计数器（SWAR）：SDN × SDCW
var SDCNT2: [32768] i64 = 0;    # 第二组计数器：清洗记忆
var SDGI: i64 = 0;      # bank 访问器专用临时（不得与其它函数共用：
var SDGJ: i64 = 0;      # 本项目已多次因共享临时被嵌套调用抹掉而静默出错）
var SDHIT: [2048] i64 = 0;      # 本次激活的硬位置下标
var SDACC: [1024] i64 = 0;      # 读出累加器：SDD 个
var SDVP: [4096] i64 = 0;       # 向量池（地址 / 数据 / 临时）
var SDVF: i64 = 0;              # 池分配指针

# ── 状态 ───────────────────────────────────────────────────
var SDNH: i64 = 0;      # 本次激活数
var SDOVF: i64 = 0;     # 计数器溢出标志
var SDNOHIT: i64 = 0;   # 无硬位置被激活（半径过小）
var SDTIE: i64 = 0;     # 读出时求和恰为 0 的维数
var SDWARN: i64 = 0;    # 容量不足等显式告警

# ── SWAR 常量（构造而非字面量，避免超大十进制与有符号歧义）──
var SDONE: i64 = 0;     # 0x0101010101010101
var SDMSB: i64 = 0;     # 0x8080808080808080

# ── 循环/临时：全部专用，绝不复用共享名 ────────────────────
# HDC 那轮踩过：库内共享临时被嵌套调用抹掉，症状是"不报错只结果错"。
# 这里每个函数用自己的一组，跨调用存活的值用专用全局。
var SDI: i64 = 0;
var SDJ: i64 = 0;
var SDK: i64 = 0;
var SDPI: i64 = 0;
var SDPJ: i64 = 0;
var SDDST: i64 = 0;
var SDBASE: i64 = 0;
var SDDB: i64 = 0;
var SDDEL: i64 = 0;
var SDT: i64 = 0;
var SDU: i64 = 0;
var SDV: i64 = 0;
var SDSUM: i64 = 0;
var SDBIT: i64 = 0;
var SDADM: i64 = 0;     # SWAR 加掩码（数据位 1 的字节 = 0x01）
var SDSBM: i64 = 0;     # SWAR 减掩码（数据位 0 的字节 = 0x01）

var SDRS: i64 = 0;

fn sdm_popcnt(x: i64) -> i64 {
    let v: i64 = x;
    v = v - ((v >> 1) & 6148914691236517205);
    v = (v & 3689348814741910323) + ((v >> 2) & 3689348814741910323);
    v = (v + (v >> 4)) & 1085102592571150095;
    return (v * 72340172838076673) >> 56;
}

fn sdm_next() -> i64 {
    let a: i64 = SDRS;
    a = a ^ (a << 13);
    a = a ^ (a >> 7);
    a = a ^ (a << 17);
    if a == 0 { a = 8837412947; }
    SDRS = a;
    let b: i64 = a * 2654435761;
    b = b ^ (b >> 29);
    if b == 0 { b = 1; }
    return b;
}

fn sdm_seed(s: i64) -> i64 {
    if s == 0 { SDRS = 8837412947; }
    if s != 0 { SDRS = s; }
    return 0;
}

# ── 初始化 ─────────────────────────────────────────────────
fn sdm_dim(nw: i64, nloc: i64) -> i64 {
    SDW = nw;
    SDD = nw * 64;
    SDN = nloc;
    SDCW = nw * 8;
    SDR = SDD / 2 - SDD / 16;      # n=256 → 112（约 −2σ）
    SDOVF = 0;
    SDNOHIT = 0;
    SDTIE = 0;
    SDWARN = 0;
    SDVF = 0;

    SDONE = 1;
    SDONE = SDONE | (SDONE << 8);
    SDONE = SDONE | (SDONE << 16);
    SDONE = SDONE | (SDONE << 32);
    SDMSB = 1 << 7;
    SDMSB = SDMSB | (SDMSB << 8);
    SDMSB = SDMSB | (SDMSB << 16);
    SDMSB = SDMSB | (SDMSB << 32);
    return SDD;
}

# 硬位置必须重新生成，否则换半径后仍是同一批 —— 但那不算错，
# 只在测试里要求"换配置后必须调本函数"才成立。
fn sdm_init(seed: i64) -> i64 {
    sdm_seed(seed);
    SDI = 0;
    while SDI < SDN * SDW {
        SDLOC[SDI] = sdm_next();
        SDI = SDI + 1;
    }
    # 内容区：偏移表示，0 计数 = 字节 0x80。
    # 填 0 是错的：第一次 −1 就会跨字节借位，且不报错。
    SDI = 0;
    while SDI < SDN * SDCW {
        SDCNT[SDI] = SDMSB;
        SDCNT2[SDI] = SDMSB;
        SDI = SDI + 1;
    }
    return 0;
}

# 计数器访问按当前 bank 分派。两个 bank **共享硬位置**，
# 只有内容计数器独立 —— 地址译码相同，不影响正确性。
fn sdm_cget(i: i64) -> i64 {
    if SDBANK == 0 { return SDCNT[i]; }
    return SDCNT2[i];
}

fn sdm_cset(i: i64, v: i64) -> i64 {
    if SDBANK == 0 { SDCNT[i] = v; }
    if SDBANK != 0 { SDCNT2[i] = v; }
    return 0;
}

fn sdm_bank(b: i64) -> i64 {
    SDBANK = b;
    return b;
}

fn sdm_radius(r: i64) -> i64 {
    SDR = r;
    return SDR;
}

# ── 向量池 ─────────────────────────────────────────────────
fn sdm_new() -> i64 {
    SDT = SDVF;
    SDVF = SDVF + SDW;
    return SDT;
}

fn sdm_new_n(n: i64) -> i64 {
    SDT = SDVF;
    SDVF = SDVF + SDW * n;
    return SDT;
}

fn sdm_zero(v: i64) -> i64 {
    SDI = 0;
    while SDI < SDW {
        SDVP[v + SDI] = 0;
        SDI = SDI + 1;
    }
    return 0;
}

fn sdm_rand(v: i64) -> i64 {
    SDI = 0;
    while SDI < SDW {
        SDVP[v + SDI] = sdm_next();
        SDI = SDI + 1;
    }
    return 0;
}

fn sdm_copy(dst: i64, src: i64) -> i64 {
    SDI = 0;
    while SDI < SDW {
        SDVP[dst + SDI] = SDVP[src + SDI];
        SDI = SDI + 1;
    }
    return 0;
}

# ── 距离 ───────────────────────────────────────────────────
fn sdm_ham(a: i64, b: i64) -> i64 {
    SDPI = 0;
    SDPJ = 0;
    while SDPI < SDW {
        SDPJ = SDPJ + sdm_popcnt(SDVP[a + SDPI] ^ SDVP[b + SDPI]);
        SDPI = SDPI + 1;
    }
    return SDPJ;
}

# 恢复率 = 1 − ham/D，Q16.16。1 = 完全一致。
fn sdm_recq(a: i64, b: i64) -> i64 {
    SDPI = sdm_ham(a, b);
    return ((SDD - SDPI) << 16) / SDD;
}

fn sdm_wt(v: i64) -> i64 {
    SDI = 0;
    SDT = 0;
    while SDI < SDW {
        SDT = SDT + sdm_popcnt(SDVP[v + SDI]);
        SDI = SDI + 1;
    }
    return SDT;
}

# 翻转 k 个随机位（查询噪声）。用固定 LCG 以便复现。
var SDFRS: i64 = 0;
var SDFI: i64 = 0;
var SDFP: i64 = 0;

fn sdm_noise(v: i64, k: i64) -> i64 {
    SDFI = 0;
    while SDFI < k {
        SDFRS = SDFRS * 6364136223846793005 + 1442695040888963407;
        SDT = SDFRS >> 33;
        if SDT < 0 { SDT = 0 - SDT; }
        SDFP = SDT / SDD;
        SDT = SDT - SDFP * SDD;
        SDBIT = SDT / 64;
        SDV = SDT - SDBIT * 64;
        SDVP[v + SDBIT] = SDVP[v + SDBIT] ^ (1 << SDV);
        SDFI = SDFI + 1;
    }
    return 0;
}

fn sdm_noise_seed(s: i64) -> i64 {
    SDFRS = s;
    return 0;
}

# 与**硬位置**的汉明距离。硬位置在 SDLOC 里，不在向量池 SDVP 里 ——
# 第一版直接调 sdm_ham(a, SDI * SDW)，比的是池里同下标的无关向量，
# 于是激活数对 r 完全不敏感（r=64 与 r=112 都得 1），且不报错。
fn sdm_ham_loc(a: i64, loc: i64) -> i64 {
    SDPI = 0;
    SDPJ = 0;
    while SDPI < SDW {
        SDPJ = SDPJ + sdm_popcnt(SDVP[a + SDPI] ^ SDLOC[loc * SDW + SDPI]);
        SDPI = SDPI + 1;
    }
    return SDPJ;
}

# ── 激活 ───────────────────────────────────────────────────
# 扫描全部硬位置。M 大时应换成哈希/采样寻址（Kanerva 原文也这么做），
# 但本实现要的就是**精确**的半径语义，扫描才不会引入近似。
fn sdm_activate(a: i64) -> i64 {
    SDNH = 0;
    SDI = 0;
    while SDI < SDN {
        SDDST = sdm_ham_loc(a, SDI);
        if SDDST <= SDR {
            if SDNH < 2048 {
                SDHIT[SDNH] = SDI;
            }
            SDNH = SDNH + 1;
        }
        SDI = SDI + 1;
    }
    if SDNH == 0 { SDNOHIT = 1; }
    return SDNH;
}

# ── 写：激活位置的计数器 ±1 ────────────────────────────────
fn sdm_write(a: i64, d: i64) -> i64 {
    SDNH = sdm_activate(a);
    if SDNH == 0 { return 0 - 1; }
    SDK = 0;
    while SDK < SDNH {
        SDBASE = SDHIT[SDK] * SDCW;
        SDI = 0;
        while SDI < SDW {
            SDJ = 0;
            while SDJ < 8 {
                SDDB = (SDVP[d + SDI] >> (SDJ * 8)) & 255;
                # 加/减**必须分开做**。
                # 第一版用一个 delta 字、用 0xFF 表示 −1，于是
                #     0x80 + 0xFF = 0x17F → 字节结果 0x7F 且**进位 1 到相邻字节**
                # 相邻维的计数器被凭空 +1。不报错、不崩溃，恢复率从 100% 掉到 87%。
                # 分开后：0x80 + 0x01 = 0x81、0x80 − 0x01 = 0x7F，都不跨字节。
                SDADM = 0;
                SDSBM = 0;
                SDPJ = 0;
                while SDPJ < 8 {
                    # 绝不写 `(x >> j) & 1 == 1`：`==` 优先级高于 `&`，
                    # 会静默变成判 x>>j。本项目已第五次栽在优先级上。
                    SDBIT = (SDDB >> SDPJ) & 1;
                    if SDBIT == 1 {
                        SDADM = SDADM | (1 << (SDPJ * 8));
                    }
                    if SDBIT == 0 {
                        SDSBM = SDSBM | (1 << (SDPJ * 8));
                    }
                    SDPJ = SDPJ + 1;
                }
                SDT = sdm_cget(SDBASE + SDI * 8 + SDJ);
                # 溢出预检：有字节已到 0x00 或 0xFF 边界，再动就跨字节。
                # 保守（不看具体是加还是减），但绝不放过真实的饱和。
                SDU = (SDT - SDONE) & ((0 - 1) ^ SDT) & SDMSB;
                if SDU != 0 { SDOVF = 1; }
                SDU = (((0 - 1) ^ SDT) - SDONE) & SDT & SDMSB;
                if SDU != 0 { SDOVF = 1; }
                SDT = SDT + SDADM;
                SDT = SDT - SDSBM;
                sdm_cset(SDBASE + SDI * 8 + SDJ, SDT);
                SDJ = SDJ + 1;
            }
            SDI = SDI + 1;
        }
        SDK = SDK + 1;
    }
    return SDNH;
}

# ── 读：激活位置的计数器按维求和，符号即读出位 ─────────────
fn sdm_read(a: i64, dst: i64) -> i64 {
    SDNH = sdm_activate(a);
    if SDNH == 0 { return 0 - 1; }
    SDI = 0;
    while SDI < SDD {
        SDACC[SDI] = 0;
        SDI = SDI + 1;
    }
    SDK = 0;
    while SDK < SDNH {
        SDBASE = SDHIT[SDK] * SDCW;
        SDI = 0;
        while SDI < SDCW {
            SDT = sdm_cget(SDBASE + SDI);
            SDJ = 0;
            while SDJ < 8 {
                # 偏移表示还原：字节值 − 128 才是真实计数
                SDV = (SDT >> (SDJ * 8)) & 255;
                SDACC[SDI * 8 + SDJ] = SDACC[SDI * 8 + SDJ] + SDV - 128;
                SDJ = SDJ + 1;
            }
            SDI = SDI + 1;
        }
        SDK = SDK + 1;
    }
    SDI = 0;
    while SDI < SDW {
        SDVP[dst + SDI] = 0;
        SDI = SDI + 1;
    }
    SDTIE = 0;
    SDPI = 0;
    while SDPI < SDD {
        SDSUM = SDACC[SDPI];
        SDBIT = SDPI / 64;
        SDV = SDPI - SDBIT * 64;
        if SDSUM > 0 {
            SDVP[dst + SDBIT] = SDVP[dst + SDBIT] | (1 << SDV);
        }
        if SDSUM == 0 { SDTIE = SDTIE + 1; }
        SDPI = SDPI + 1;
    }
    return SDNH;
}
