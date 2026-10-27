# hdcrt —— HDC retrain：整数累加原型 + 自适应步长
#
# ── 概念 ───────────────────────────────────────────────────
#   OnlineHD（arXiv:2110.03662）：单遍在线学习 + retrain 回路
#       错分样本上  A_true += x̃ ， A_pred −= x̃
#   AdaptHD（DAC 2019）：步长逐样本自适应，越错的样本步子越大。
#   两者至今只在 torchhd / hdlib 这类研究库里，没有主流框架内建。
#
# ── 关键区别（不是实现细节）────────────────────────────────
#   bundling 的原型是**二值**的（多数投票），±1 的修正会被多数投票吞掉；
#   retrain 的原型必须是**整数累加器** Σ ±x̃。所以 retrain 不能复用
#   hdc_maj，必须另起一套表示 —— 这是它能不能work的前提。
#
# ── 本例最重要的发现 ───────────────────────────────────────
#   **批式 retrain 在 HDC 上是空转的。** 单遍原型对每个训练样本都含一个
#   自项 x̃ᵢ·x̃ᵢ = D，必然压过交叉项，于是训练集**恒被拟合到 100%**，
#   没有错分样本可供更新 → 一个更新都不会发生（HDRU 等于样本数）。
#   retrain 真正有作用的是**在线/流式**场景：先预测、再更新。
#   所以本例的 A/B 全部跑在线模式，批式只用来做"零更新"的证伪对照。
#
# ── 任务故意做得不线性可分 ─────────────────────────────────
#   3 类，level 中心 1 / 3 / 5，样本在 ±1 抖动 → 相邻类边界重叠；
#   再对编码后的超向量翻 35% 的位。单遍在线必然错一部分，才有得改。

import "io.mo";
import "hdc.mo";

var NF: i64 = 4;
var MM: i64 = 8;
var NC: i64 = 3;
var NSP: i64 = 16;
var NTP: i64 = 8;

var IDM: i64 = 0;
var LVM: i64 = 0;
var XS: i64 = 0;
var YS: i64 = 0;
var XT: i64 = 0;
var YT: i64 = 0;
var NTR: i64 = 0;
var NTE: i64 = 0;
var GI: i64 = 0;
var GJ: i64 = 0;
var GR: i64 = 0;
var GLV: i64 = 0;
var GCT: i64 = 0;
# ⚠️ 特性循环必须用专属全局：gen 若复用 GI，会把调用方的类下标抹成 NF，
#    于是从第 2 个样本起全部写到越界槽、类号也变成 4 —— 不报错，只是全错。
var GF: i64 = 0;
var NOISE: i64 = 0;
var GA: i64 = 0;
var GT: i64 = 0;
# margin 必须用专属全局：它若复用 GI/GJ/GR/GLV/GCT，会把调用方的
# 循环变量抹掉 —— 症状是表格只打印一列，不报错。
var GM0: i64 = 0;
var GM1: i64 = 0;
var GM2: i64 = 0;
var GM3: i64 = 0;

fn gen(dst: i64, c: i64, sd: i64) -> i64 {
    hdc_seed(sd);
    GCT = 1 + c * 2;
    GF = 0;
    while GF < NF {
        GR = hdc_next();
        if GR < 0 { GR = 0 - GR; }
        GLV = GCT + (GR - (GR / 3) * 3) - 1;
        if GLV < 0 { GLV = 0; }
        if GLV > MM - 1 { GLV = MM - 1; }
        HDV[GF] = GLV;
        GF = GF + 1;
    }
    hdc_enc_rec(dst, IDM, LVM, NF);
    if NOISE > 0 { hdc_flip_pct(dst, NOISE); }
    return 0;
}

fn build() -> i64 {
    GI = 0;
    while GI < NC {
        GJ = 0;
        while GJ < NSP {
            gen(XS + (GI * NSP + GJ) * HDW, GI, 1000 + (GI * NSP + GJ) * 7919);
            HDP[YS + GI * NSP + GJ] = GI;
            GJ = GJ + 1;
        }
        GI = GI + 1;
    }
    GI = 0;
    while GI < NC {
        GJ = 0;
        while GJ < NTP {
            gen(XT + (GI * NTP + GJ) * HDW, GI, 50000 + (GI * NTP + GJ) * 104729);
            HDP[YT + GI * NTP + GJ] = GI;
            GJ = GJ + 1;
        }
        GI = GI + 1;
    }
    return 0;
}

# 测试集上的最小间隔：min_i ( s_true − max_{c≠true} s_c )
# 用来解释"为什么在线错误变少、留出准确率反而变差"——纠正会缩小间隔。
fn margin(m: i64) -> i64 {
    GM0 = 0;
    GM1 = 4611686018427387904;
    while GM0 < NTE {
        GM2 = hdc_rt_score(m + HDP[YT + GM0] * HDRCW * HDW, XT + GM0 * HDW);
        GM3 = 0 - 4611686018427387904;
        GCT = 0;
        while GCT < NC {
            if GCT != HDP[YT + GM0] {
                GT = hdc_rt_score(m + GCT * HDRCW * HDW, XT + GM0 * HDW);
                if GT > GM3 { GM3 = GT; }
            }
            GCT = GCT + 1;
        }
        if GM2 - GM3 < GM1 { GM1 = GM2 - GM3; }
        GM0 = GM0 + 1;
    }
    return GM1;
}

fn main() -> i64 {
    hdc_dim(16);
    NTR = NC * NSP;
    NTE = NC * NTP;
    IDM = hdc_new_n(NF);
    hdc_im_iid(IDM, NF, 11);
    LVM = hdc_new_n(MM);
    hdc_im_cim(LVM, MM, 22);
    XS = hdc_new_n(NTR);
    YS = hdc_new_n((NTR + HDW - 1) / HDW);
    XT = hdc_new_n(NTE);
    YT = hdc_new_n((NTE + HDW - 1) / HDW);
    let acc: i64 = hdc_rt_new(NC);

    NOISE = 35;
    build();

    print("== A. score 闭式 vs 逐 lane 参照（必须逐位相等）==");
    print_nl();
    hdc_rt_zero_n(acc, NC);
    hdc_rt_addsub(acc, XS, 1);
    hdc_rt_addsub(acc + HDRCW * HDW, XS, 1);
    hdc_rt_addsub(acc + HDRCW * HDW, XS, 0 - 1);
    GI = 0;
    GJ = 0;
    while GI < NC {
        GR = hdc_rt_score(acc + GI * HDRCW * HDW, XT + 3 * HDW);
        GLV = hdc_rt_score_ref(acc + GI * HDRCW * HDW, XT + 3 * HDW);
        print("  类 ");
        print_i64(GI);
        print(": 闭式 ");
        print_i64(GR);
        print("  参照 ");
        print_i64(GLV);
        print_nl();
        if GR != GLV { GJ = GJ + 1; }
        GI = GI + 1;
    }
    print("  不一致数 = ");
    print_i64(GJ);
    print_nl();
    print_nl();

    print("== B. 批式 retrain 是空转的（证伪对照）==");
    print_nl();
    hdc_rt_fit(acc, NC, XS, YS, NTR, 0, 0, 1);
    GI = hdc_rt_acc(acc, NC, XS, YS, NTR);
    hdc_rt_fit(acc, NC, XS, YS, NTR, 5, 0, 1);
    GJ = hdc_rt_acc(acc, NC, XS, YS, NTR);
    print("  单遍训练准确率 = ");
    print_i64(GI);
    print(" / ");
    print_i64(NTR);
    print("    （训练集恒 100% → 没有错分样本可更新）");
    print_nl();
    print("  批式 5 轮后 = ");
    print_i64(GJ);
    print("   更新次数 HDRU = ");
    print_i64(HDRU);
    print(" （= 样本数，说明一个纠正都没发生）");
    print_nl();
    print_nl();

    print("== C. 在线（先预测再更新）× 噪声扫描 ==");
    print_nl();
    print("  每格：在线错 / 测试准确率 / 测试最小间隔 / 更新次数");
    print_nl();
    print("  噪声   固定a=1    自适应    固定a=4    不纠正(对照)");
    print_nl();
    NOISE = 0;
    while NOISE < 41 {
        build();
        print("  ");
        print_i64(NOISE);
        print("%   ");
        GI = 0;
        while GI < 4 {
            GA = 1;
            if GI == 2 { GA = 4; }
            GJ = hdc_rt_online(acc, NC, XS, YS, NTR, GI, GA);
            print_i64(GJ);
            print(" / ");
            print_i64(hdc_rt_acc(acc, NC, XT, YT, NTE));
            print(" / ");
            print_i64(margin(acc));
            print(" / ");
            print_i64(HDRU);
            print("   ");
            GI = GI + 1;
        }
        print_nl();
        NOISE = NOISE + 10;
    }
    print_nl();
    print("  溢出标志 = ");
    print_i64(hdc_rt_ovf());
    print_nl();
    return 0;
}
