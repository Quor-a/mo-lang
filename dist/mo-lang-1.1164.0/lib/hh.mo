# hh —— Heavy Hitters（重击者）：Misra-Gries + Space-Saving
#
# ── 概念来源 ────────────────────────────────────────────────
#   Jayadev Misra, David Gries 1982
#   《Finding Repeated Elements》（引理 3 的"减一"算法）
#   → 现代称谓 Misra-Gries / "Frequent" (Cormode-Hadjieleftheriou 2008)
#
#   Ahmed Metwally, Divyakant Agrawal, Amr El Abbadi 2005
#   《Efficient Computation of Frequent and Top-k Elements in Data Streams》
#   → Space-Saving
#
# ── 与已有四个草图的分工 ────────────────────────────────────
#   Bloom(v1.144)  → 在不在       → 只假阳
#   CMS  (v1.144)  → 出现几次     → 只高估
#   HLL  (v1.138)  → 几个不同的   → 相对误差 1.04/√m
#   qdigest(v1.147)→ 排第 q 是几  → 秩误差与 k 同阶
#   **hh**         → **谁最频繁** → 见下
#
#   五个都没进任何主流语言的标准库（Python 靠 datasketch、
#   Java 靠 stream-lib、Go 靠第三方，全是外部包）。
#
# ── 本库最要紧的一条：**确定性，不用哈希** ──────────────────
#   Bloom / CMS / HLL 的误差都依赖哈希质量（本项目在 HLL v1.138
#   就栽在 `a ^ sar(a,k)` 的 bit63 恒为 0 上）。
#   **Misra-Gries 与 Space-Saving 完全不用哈希** —— 它们的误差
#   只来自计数器数量 k，是**确定性算法**。
#   所以它们的误差界是**硬保证**而非概率：
#     MG：est(x) ≤ true(x) ≤ est(x) + D，且 D ≤ N/(k+1)
#     SS：est(x) − err(x) ≤ true(x) ≤ est(x)，且 err 由替换过程记录
#
# ── 两个算法的方向恰好相反，因此可以**夹逼真值** ──────────────
#     mg_est(x) ≤ true(x) ≤ ss_est(x)
#   这条是本测试最硬的判据：任何一个实现写错方向，它立刻挂。
#   （CMS 也是高估，与 SS 同侧；MG 是这一组里**唯一给下界**的。）
#
# ── ⚠️ 调用方禁令 ──────────────────────────────────────────
#   HH1..HH4 / HHF1 / HHA1..HHA2 / HHQ1 / HHM1 是本库内部的
#   循环与临时变量，调用方**绝不能拿它们当自己的循环变量** ——
#   一次 hh_add 就改掉它们，外层循环当场退出，
#   症状是"只加了一个元素"，**不报错**。
#   本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
#   CMS(v1.144)、qdigest(v1.147)、seg(v1.149) 栽过同一类跟头。
#
# ── 口径 ────────────────────────────────────────────────────
#   两个算法共用一条输入流（hh_add 同时喂给两边），N 是总权重。
#   mg_est(x) 不在表中返回 0（下界仍成立）。
#   ss_est(x) 不在表中返回 -1 —— SS 对被逐出的元素**没有估计**，
#   返回 0 会让人误以为"它出现了 0 次"，那是假阴，必须区分。

# ── 容量 ───────────────────────────────────────────────────
# MG 用 k−1 个计数器时 D ≤ N/k；这里两者都按 HH_K 计，
# 于是 MG 的保证是 D ≤ N/(HH_K+1)，断言时用更松的 N/HH_K。
var HH_K: i64 = 64;

# ── Misra-Gries ────────────────────────────────────────────
var MG_KEY: [64] i64 = 0;
var MG_CNT: [64] i64 = 0;
var MG_N: i64 = 0;      # 已占用槽数
var MG_TOT: i64 = 0;    # 总权重 N
var MG_DEC: i64 = 0;    # 累计减量 D（误差上界）

# ── Space-Saving ───────────────────────────────────────────
var SS_KEY: [64] i64 = 0;
var SS_CNT: [64] i64 = 0;
var SS_ERR: [64] i64 = 0;   # over-estimate 上界：est − err ≤ true ≤ est
var SS_N: i64 = 0;
var SS_TOT: i64 = 0;
var SS_MIN: i64 = 0;        # 表中最小 count（查询时的误差上界）
var SS_REPL: i64 = 0;       # 替换次数（诊断 / 非空转守卫）

# ── 专用循环与临时变量 ──────────────────────────────────────
var HH1: i64 = 0;
var HH2: i64 = 0;
var HH3: i64 = 0;
var HH4: i64 = 0;
var HHF1: i64 = 0;
var HHA1: i64 = 0;
var HHA2: i64 = 0;
var HHQ1: i64 = 0;
var HHM1: i64 = 0;

# ── 诊断 ───────────────────────────────────────────────────
var HHBAD: i64 = 0;     # 参数非法（c ≤ 0）

# ── 内部：MG 查找 ──────────────────────────────────────────
fn mg_find(x: i64) -> i64 {
    HHF1 = 0;
    while HHF1 < MG_N {
        if MG_KEY[HHF1] == x {
            return HHF1;
        }
        HHF1 = HHF1 + 1;
    }
    return 0 - 1;
}

# ── 内部：SS 查找 ──────────────────────────────────────────
fn ss_find(x: i64) -> i64 {
    HHF1 = 0;
    while HHF1 < SS_N {
        if SS_KEY[HHF1] == x {
            return HHF1;
        }
        HHF1 = HHF1 + 1;
    }
    return 0 - 1;
}

# ── 内部：SS 找最小 count 的槽 ──────────────────────────────
fn ss_argmin() -> i64 {
    HHA1 = 0;
    HHA2 = 0;
    HHM1 = SS_CNT[0];
    while HHA1 < SS_N {
        if SS_CNT[HHA1] < HHM1 {
            HHM1 = SS_CNT[HHA1];
            HHA2 = HHA1;
        }
        HHA1 = HHA1 + 1;
    }
    return HHA2;
}

# ── 清空 ───────────────────────────────────────────────────
fn hh_clear() -> i64 {
    HH1 = 0;
    while HH1 < HH_K {
        MG_KEY[HH1] = 0;
        MG_CNT[HH1] = 0;
        SS_KEY[HH1] = 0;
        SS_CNT[HH1] = 0;
        SS_ERR[HH1] = 0;
        HH1 = HH1 + 1;
    }
    MG_N = 0;
    MG_TOT = 0;
    MG_DEC = 0;
    SS_N = 0;
    SS_TOT = 0;
    SS_MIN = 0;
    SS_REPL = 0;
    HHBAD = 0;
    return 0;
}

# ── 喂入一个元素（权重 c），同时更新两个草图 ─────────────────
fn hh_add(x: i64, c: i64) -> i64 {
    if c <= 0 {
        HHBAD = 1;
        return 0 - 1;
    }
    hh_mg_add(x, c);
    hh_ss_add(x, c);
    return 0;
}

fn hh_mg_add(x: i64, c: i64) -> i64 {
    MG_TOT = MG_TOT + c;

    HH1 = mg_find(x);
    if HH1 >= 0 {
        MG_CNT[HH1] = MG_CNT[HH1] + c;
        return 0;
    }

    # 还有空槽 → 直接放进去
    if MG_N < HH_K {
        MG_KEY[MG_N] = x;
        MG_CNT[MG_N] = c;
        MG_N = MG_N + 1;
        return 0;
    }

    # 满 → 所有计数减 c，归零的槽丢弃。
    # 这一步是 MG 的全部精髓：D 就是累计减量，
    # 真实频率与估计的差不可能超过 D。
    MG_DEC = MG_DEC + c;
    HH2 = 0;      # 写指针
    HH3 = 0;      # 读指针
    while HH3 < MG_N {
        MG_CNT[HH3] = MG_CNT[HH3] - c;
        if MG_CNT[HH3] > 0 {
            if HH2 != HH3 {
                MG_KEY[HH2] = MG_KEY[HH3];
                MG_CNT[HH2] = MG_CNT[HH3];
            }
            HH2 = HH2 + 1;
        }
        HH3 = HH3 + 1;
    }
    MG_N = HH2;
    return 0;
}

fn hh_ss_add(x: i64, c: i64) -> i64 {
    SS_TOT = SS_TOT + c;

    HH1 = ss_find(x);
    if HH1 >= 0 {
        SS_CNT[HH1] = SS_CNT[HH1] + c;
        return 0;
    }

    # 还有空槽 → 直接放进去，误差 0
    if SS_N < HH_K {
        SS_KEY[SS_N] = x;
        SS_CNT[SS_N] = c;
        SS_ERR[SS_N] = 0;
        SS_N = SS_N + 1;
        return 0;
    }

    # 满 → 替换 count 最小的那个：
    #   新槽 count = 旧 count + c
    #   新槽 err   = 旧 count      ← 被吸收掉的那部分，就是高估上界
    HH4 = ss_argmin();
    SS_ERR[HH4] = SS_CNT[HH4];
    SS_KEY[HH4] = x;
    SS_CNT[HH4] = SS_CNT[HH4] + c;
    SS_REPL = SS_REPL + 1;
    return 0;
}

# ── 查询 ───────────────────────────────────────────────────

# MG 估计：**下界**。不在表中返回 0（下界性质仍成立）。
fn mg_est(x: i64) -> i64 {
    HHQ1 = mg_find(x);
    if HHQ1 < 0 {
        return 0;
    }
    return MG_CNT[HHQ1];
}

# MG 是否在候选集中
fn mg_has(x: i64) -> i64 {
    if mg_find(x) >= 0 {
        return 1;
    }
    return 0;
}

# SS 估计：**上界**。不在表中返回 -1 —— 不能返回 0，那是假阴。
fn ss_est(x: i64) -> i64 {
    HHQ1 = ss_find(x);
    if HHQ1 < 0 {
        return 0 - 1;
    }
    return SS_CNT[HHQ1];
}

# SS 的 over-estimate 上界 err（不在表中返回 -1）
fn ss_err(x: i64) -> i64 {
    HHQ1 = ss_find(x);
    if HHQ1 < 0 {
        return 0 - 1;
    }
    return SS_ERR[HHQ1];
}

fn ss_has(x: i64) -> i64 {
    if ss_find(x) >= 0 {
        return 1;
    }
    return 0;
}

# SS 表中最小 count —— est(x) − true(x) ≤ 这个值
fn ss_min() -> i64 {
    if SS_N <= 0 {
        return 0;
    }
    HHQ1 = ss_argmin();
    SS_MIN = SS_CNT[HHQ1];
    return SS_MIN;
}

# ── 状态 ───────────────────────────────────────────────────
fn hh_total() -> i64 { return MG_TOT; }
fn mg_used() -> i64 { return MG_N; }
fn ss_used() -> i64 { return SS_N; }
fn mg_dec() -> i64 { return MG_DEC; }
fn ss_repl() -> i64 { return SS_REPL; }

# 导出候选集（按槽号），n 是槽数
fn mg_key(i: i64) -> i64 { return MG_KEY[i]; }
fn mg_cnt(i: i64) -> i64 { return MG_CNT[i]; }
fn ss_key(i: i64) -> i64 { return SS_KEY[i]; }
fn ss_cnt(i: i64) -> i64 { return SS_CNT[i]; }
fn ss_errat(i: i64) -> i64 { return SS_ERR[i]; }
