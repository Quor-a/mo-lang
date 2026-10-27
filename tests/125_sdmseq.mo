# 125 —— SDM 序列存储（Kanerva 1988 Ch.8：转移记忆 + 迭代召回）   # expect: 0
#
# ── 概念 ────────────────────────────────────────────────────
#   address = a_i, content = a_{i+1} 存进 SDM；召回时把读出**直接**
#   当作下一个地址，形成链。至今只有 sdmlib / numpy 演示，无主流实现。
#
# ── 本测试覆盖的定量结论 ────────────────────────────────────
#   ① 读出误差沿链**放大**：单步读出几乎无损（平均 ham=1），
#      但连走 10 步就崩 —— 「单步准」不等于「链可用」。
#   ② SDM 自联想清洗**反而加速崩溃**（第 11 步 → 第 8 步）。
#      原因是它的吸引域只有约 5 位：输入误差 >8 时输出被放大。
#   ③ 最近邻清洗吸引域 ≥ 62 位，链全程正确（120/120）。
#      两种清洗相差一个数量级以上，不是调参问题。
#   ④ 分支歧义：共享前缀的分叉点，平局位从 0 跳到 108，
#      读出与两个后继距离几乎相等（55 / 53）—— 平局位数是检测器。
#   ⑤ 转移与自联想写进**同一组**计数器 → 叠加污染，链立刻废掉。
#
# ── 一条必须存在的断言 ──────────────────────────────────────
#   SQITER == steps：sq_recall 的循环变量 SQI 若被 sq_nearest 抹掉，
#   循环永远停在 11 而**不报错**（本轮第一版就是这样，3 步的测试
#   看起来通过、实际只走了 1 步）。只看「正确步数」抓不到它。

import "assert.mo";
import "sdm.mo";
import "sdmseq.mo";

var N: i64 = 40;
var STEPS: i64 = 120;
var R0: i64 = 0;
var R1: i64 = 0;
var R2: i64 = 0;
var F0: i64 = 0;
var F1: i64 = 0;
var EI: i64 = 0;
var EO: i64 = 0;
var T0: i64 = 0;
var TB: i64 = 0;
var H2: i64 = 0;
var H3: i64 = 0;
var RB: i64 = 0;

# 用 e 位噪声扰动第 0 项，返回经 SDM 自联想清洗后的误差
fn basin_sdm(e: i64) -> i64 {
    sdm_copy(SQX, sq_item(0));
    sdm_noise_seed(999);
    sdm_noise(SQX, e);
    EI = sdm_ham(SQX, sq_item(0));
    sdm_bank(1);
    sdm_read(SQX, SQY);
    sdm_bank(0);
    EO = sdm_ham(SQY, sq_item(0));
    return 0;
}

fn basin_nn(e: i64) -> i64 {
    sdm_copy(SQX, sq_item(0));
    sdm_noise_seed(999);
    sdm_noise(SQX, e);
    EI = sdm_ham(SQX, sq_item(0));
    return sq_nearest(SQX);
}

fn setup(n: i64) -> i64 {
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(n);
    sq_rand_all();
    sq_store_trans();
    sq_store_clean();
    return 0;
}

fn main() -> i64 {
    setup(N);

    # ① ③ 三种清洗模式
    R0 = sq_recall(0, STEPS, 0);
    F0 = SQFIRST;
    R1 = sq_recall(0, STEPS, 1);
    F1 = SQFIRST;
    R2 = sq_recall(0, STEPS, 2);

    assert_eq("最近邻清洗全程正确", R2, STEPS);
    assert_eq("SQITER == steps（循环变量未被抹掉）", SQITER, STEPS);
    assert_true("无清洗：链会崩", R0 < STEPS);
    assert_true("无清洗：不是一开始就崩", F0 > 1);
    assert_true("SDM 清洗反而更早崩", F1 < F0);
    assert_true("最近邻 > 无清洗", R2 > R0);

    # ② 吸引域
    basin_sdm(0);
    assert_true("SDM 清洗：输入无损时输出也近无损", EO <= 2);
    basin_sdm(18);
    assert_true("SDM 清洗：输入误差 18 时被放大", EO > EI);
    assert_eq("最近邻清洗：输入误差 >=60 仍吸附正确", basin_nn(120), 0);

    # ④ 分支歧义
    sdm_dim(4, 512);
    sdm_init(7);
    sq_init(4);
    sq_rand_all();
    sdm_bank(0);
    sdm_write(sq_item(0), sq_item(1));
    sdm_read(sq_item(0), SQY);
    T0 = SDTIE;
    sdm_write(sq_item(1), sq_item(2));
    sdm_write(sq_item(1), sq_item(3));
    sdm_read(sq_item(1), SQY);
    TB = SDTIE;
    H2 = sdm_ham(SQY, sq_item(2));
    H3 = sdm_ham(SQY, sq_item(3));
    assert_eq("非分支点无平局", T0, 0);
    assert_true("分支点平局位大增", TB >= 100);
    assert_true("分支点：两个后继等距", H2 - H3 <= 8);
    assert_true("分支点：两个后继等距（反向）", H3 - H2 <= 8);

    # ⑤ 单 bank 叠加污染
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(N);
    sq_rand_all();
    sq_store_both();
    RB = sq_recall(0, N, 0);
    assert_true("单 bank 混合转移+自联想 → 污染", RB < R0);

    # 低负载对照：负载低时误差不累积，三种模式都不分胜负。
    # 没有它，分不清「清洗有效」和「这个负载下本来就崩不了」。
    setup(10);
    assert_eq("n=10 mode0", sq_recall(0, 100, 0), 100);
    assert_eq("n=10 mode1", sq_recall(0, 100, 1), 100);
    assert_eq("n=10 mode2", sq_recall(0, 100, 2), 100);

    return test_done();
}
