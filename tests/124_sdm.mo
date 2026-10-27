# 124 —— Kanerva 稀疏分布式记忆（Sparse Distributed Memory）   # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   Kanerva, *Sparse Distributed Memory*, MIT Press 1988。
#   n 位地址空间（2^n），只显式存 M 个随机硬位置；
#   写/读都作用于"与地址汉明距离 ≤ r"的那批位置。
#   至今只有 sdmlib / numpy 演示级实现，无主流框架内建。
#
# ── 本测试覆盖的**定量**结论 ────────────────────────────────
#   ① 激活半径双向失败，且两端原因不同：
#        r 过小 → 0 个硬位置激活（读不出来）
#        r 过大 → 全部激活（所有模式叠加 → 无区分度）
#   ② 容量有限：恢复率随存储模式数 K 单调下降
#   ③ 内容寻址：地址带噪声仍能读出
#   ④ 内容计数器用**偏移表示**（0 = 字节 0x80），否则 SWAR 加减会跨字节
#
# ── 恢复率口径 ──────────────────────────────────────────────
#   recq = 1 − ham/D，Q16.16。65536 = 逐位一致，32768 = 随机猜。

import "assert.mo";
import "sdm.mo";

var KK: i64 = 40;
var MM: i64 = 512;

var ADR: i64 = 0;
var DAT: i64 = 0;
var QRY: i64 = 0;
var OUT: i64 = 0;
var OUT2: i64 = 0;

var CI: i64 = 0;
var SM: i64 = 0;
var PF: i64 = 0;
var AV: i64 = 0;
var V1: i64 = 0;
var V2: i64 = 0;
var V3: i64 = 0;
var NH0: i64 = 0;
var NH1: i64 = 0;
var OKF: i64 = 0;
# run_k 内部必须用**专用**变量：第一版复用了 V1/V2/V3，
# 于是 K=4 的结果被后两次 run_k 悄悄覆盖，断言比的是两个无意义的数。
var RQ1: i64 = 0;
var RQ2: i64 = 0;

fn mk(n: i64) -> i64 {
    CI = 0;
    while CI < n {
        SM = sdm_new();
        sdm_rand(SM);
        CI = CI + 1;
    }
    return 0;
}

# 写 K 个模式并统计：平均恢复率、完全恢复数、平均激活数
fn run_k(k: i64, r: i64) -> i64 {
    sdm_radius(r);
    sdm_init(7);
    ADR = sdm_new_n(k);
    DAT = sdm_new_n(k);
    CI = 0;
    while CI < k {
        sdm_rand(ADR + CI * SDW);
        CI = CI + 1;
    }
    CI = 0;
    while CI < k {
        sdm_rand(DAT + CI * SDW);
        CI = CI + 1;
    }
    QRY = sdm_new();
    OUT = sdm_new();

    CI = 0;
    while CI < k {
        SM = sdm_write(ADR + CI * SDW, DAT + CI * SDW);
        CI = CI + 1;
    }

    SM = 0;
    PF = 0;
    AV = 0;
    CI = 0;
    while CI < k {
        sdm_copy(QRY, ADR + CI * SDW);
        NH1 = sdm_read(QRY, OUT);
        AV = AV + NH1;
        RQ1 = sdm_recq(OUT, DAT + CI * SDW);
        SM = SM + RQ1;
        if RQ1 == 65536 { PF = PF + 1; }
        CI = CI + 1;
    }
    AV = AV / k;
    SM = SM / k;
    return SM;
}

fn main() -> i64 {
    SDW = 4;
    V1 = sdm_dim(4, MM);
    assert_eq("维数 = 256", V1, 256);
    assert_eq("每位置内容字数 = 32", SDCW, 32);
    assert_eq("默认半径 = 112", SDR, 112);

    sdm_init(7);
    assert_eq("硬位置数", SDN, MM);

    # ── ① 激活半径双向失败 ────────────────────────────────
    ADR = sdm_new();
    sdm_rand(ADR);

    SDNOHIT = 0;
    sdm_radius(64);
    NH0 = sdm_activate(ADR);
    print("r=64  激活数=");
    print_i64(NH0);
    print_nl();
    assert_eq("r=64 过小：0 个硬位置激活", NH0, 0);
    assert_eq("r=64 过小：SDNOHIT 被置位", SDNOHIT, 1);

    sdm_radius(112);
    NH0 = sdm_activate(ADR);
    print("r=112 激活数=");
    print_i64(NH0);
    print_nl();
    assert_true("r=112 有激活但远未全激活", (NH0 > 0) & (NH0 < MM / 4));

    sdm_radius(200);
    NH0 = sdm_activate(ADR);
    print("r=200 激活数=");
    print_i64(NH0);
    print_nl();
    assert_true("r=200 几乎全部激活", NH0 > MM - MM / 8);

    # ── ② 容量：恢复率随 K 下降 ───────────────────────────
    V1 = run_k(4, 112);
    print("K=4   平均恢复率=");
    print_i64(V1 / 655);
    print("%% 完全恢复=");
    print_i64(PF);
    print_nl();
    OKF = PF;
    assert_eq("K=4 全部完全恢复", PF, 4);
    assert_true("K=4 平均恢复率 ≈ 1", V1 > 63000);
    assert_eq("K=4 无溢出", SDOVF, 0);

    V2 = run_k(40, 112);
    print("K=40  平均恢复率=");
    print_i64(V2 / 655);
    print("%% 完全恢复=");
    print_i64(PF);
    print("/40 平均激活=");
    print_i64(AV);
    print_nl();

    V3 = run_k(200, 112);
    print("K=200 平均恢复率=");
    print_i64(V3 / 655);
    print("%% 完全恢复=");
    print_i64(PF);
    print_nl();

    assert_true("容量：K=4 的恢复率 > K=200", V1 > V3);
    assert_true("K=200 仍显著好于随机(32768)", V3 > 40000);
    assert_eq("全程无计数器溢出", SDOVF, 0);

    # ── ③ 半径过大 → 无区分度 ─────────────────────────────
    # 用两个不同模式查询，读出结果应几乎相同（都趋近全局和），
    # 而两个正确答案彼此正交 —— 这个对照直接证明"失去区分能力"。
    sdm_radius(200);
    sdm_init(7);
    ADR = sdm_new_n(4);
    DAT = sdm_new_n(4);
    OUT = sdm_new();
    OUT2 = sdm_new();
    QRY = sdm_new();
    CI = 0;
    while CI < 4 {
        sdm_rand(ADR + CI * SDW);
        CI = CI + 1;
    }
    CI = 0;
    while CI < 4 {
        sdm_rand(DAT + CI * SDW);
        CI = CI + 1;
    }
    CI = 0;
    while CI < 4 {
        SM = sdm_write(ADR + CI * SDW, DAT + CI * SDW);
        CI = CI + 1;
    }
    sdm_copy(QRY, ADR);
    SM = sdm_read(QRY, OUT);
    sdm_copy(QRY, ADR + 2 * SDW);
    SM = sdm_read(QRY, OUT2);
    V1 = sdm_ham(OUT, OUT2);          # 两个查询结果之间的距离
    V2 = sdm_ham(DAT, DAT + 2 * SDW); # 两个正确答案之间的距离
    print("r=200 两次查询结果距离=");
    print_i64(V1);
    print(" 正确答案间距离=");
    print_i64(V2);
    print_nl();
    assert_true("r 过大：不同查询返回几乎相同的结果", V1 < V2 / 4);
    RQ2 = sdm_recq(OUT, DAT);
    print("r=200 读出 vs 正确答案 恢复率=");
    print_i64(RQ2 / 655);
    print("%%");
    print_nl();
    # 原假设"r 过大 → 读出接近随机(50%)"**被实测推翻**：实测 73%。
    # 正确模型：r 过大时读出 = 全部模式的多数投票，与**单个**模式的匹配率是
    #   0.5·P(Bin(K−1) > K/2 − 1 | d=1) + 0.5·P(Bin(K−1) ≤ K/2 − 1 | d=0)
    #   K=4 → 0.5·0.5 + 0.5·0.875 = 0.6875（实测 73%，样本波动内）
    # 它随 K 增大才趋向 50%。所以"无区分度"的严格证据是**查询间距离为 0**，
    # 而不是"读出随机"。两条断言分开写，各管一件事。
    assert_true("r 过大：读出质量显著劣于 r 适中时(100%)", RQ2 < 55000);
    assert_true("r 过大：但仍高于随机(多数投票的偏向)", RQ2 > 40000);

    # ── ④ 内容寻址：地址带噪声仍能读出 ────────────────────
    sdm_radius(112);
    sdm_init(7);
    ADR = sdm_new_n(8);
    DAT = sdm_new_n(8);
    OUT = sdm_new();
    QRY = sdm_new();
    CI = 0;
    while CI < 8 {
        sdm_rand(ADR + CI * SDW);
        CI = CI + 1;
    }
    CI = 0;
    while CI < 8 {
        sdm_rand(DAT + CI * SDW);
        CI = CI + 1;
    }
    CI = 0;
    while CI < 8 {
        SM = sdm_write(ADR + CI * SDW, DAT + CI * SDW);
        CI = CI + 1;
    }
    sdm_noise_seed(12345);
    SM = 0;
    CI = 0;
    while CI < 8 {
        sdm_copy(QRY, ADR + CI * SDW);
        sdm_noise(QRY, 32);
        NH1 = sdm_read(QRY, OUT);
        SM = SM + sdm_recq(OUT, DAT + CI * SDW);
        CI = CI + 1;
    }
    SM = SM / 8;
    print("噪声 32/256 位 平均恢复率=");
    print_i64(SM / 655);
    print("%%");
    print_nl();
    assert_true("地址 12.5%% 位翻转后仍远好于随机", SM > 50000);

    return test_done();
}
