# expect: 0
# hdcrt —— HDC retrain（整数累加原型）回归测试
#
# 判据全部来自实测（D=1024 / NF=4 / MM=8 / NC=3 / 噪声 0%），不是凑出来的：
#   批式 retrain 空转      HDRU == NTR（一个纠正都没发生）
#   在线错误数             不纠正 29 > 固定a=1 16 > 固定a=4 6
#   留出准确率             不纠正 24 > 固定a=1 9 ≥ 固定a=4 8
#   测试最小间隔           不纠正 +276 > 0 > 固定a=1 −3422 > 固定a=4 −7682
# 最后两行是解释性的：**在线错越少 → 间隔越小 → 泛化越差**。
#
# 反向验证见 tools/hdcrtmut.sh：把"减掉错分那一类"去掉，这些断言必须变红。

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
var GF: i64 = 0;
var GM0: i64 = 0;
var GM1: i64 = 0;
var GM2: i64 = 0;
var GM3: i64 = 0;
var GK: i64 = 0;
var GT: i64 = 0;
var PASS: i64 = 0;
var FAIL: i64 = 0;

fn cke(a: i64, b: i64) -> i64 {
    if a == b { PASS = PASS + 1; print("PASS"); }
    if a != b { FAIL = FAIL + 1; print("FAIL got "); print_i64(a); print(" want "); print_i64(b); }
    print_nl();
    return 0;
}

fn ckg(a: i64, b: i64) -> i64 {
    if a > b { PASS = PASS + 1; print("PASS"); }
    if a <= b { FAIL = FAIL + 1; print("FAIL got "); print_i64(a); print(" > "); print_i64(b); }
    print_nl();
    return 0;
}

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

# 测试集最小间隔：min_i ( s_true − max_{c≠true} s_c )
# ⚠️ 必须用专属全局 GM*/GK/GT：若复用 GI/GJ，会把调用方循环变量抹掉。
fn marg(m: i64) -> i64 {
    GM0 = 0;
    GM1 = 4611686018427387904;
    while GM0 < NTE {
        GM2 = hdc_rt_score(m + HDP[YT + GM0] * HDRCW * HDW, XT + GM0 * HDW);
        GM3 = 0 - 4611686018427387904;
        GK = 0;
        while GK < NC {
            if GK != HDP[YT + GM0] {
                GT = hdc_rt_score(m + GK * HDRCW * HDW, XT + GM0 * HDW);
                if GT > GM3 { GM3 = GT; }
            }
            GK = GK + 1;
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
    build();
    let acc: i64 = hdc_rt_new(NC);

    hdc_rt_zero_n(acc, NC);
    hdc_rt_addsub(acc, XS, 1);
    hdc_rt_addsub(acc + HDRCW * HDW, XS, 1);
    hdc_rt_addsub(acc + HDRCW * HDW, XS, 0 - 1);
    GI = 0;
    GJ = 0;
    while GI < NC {
        if hdc_rt_score(acc + GI * HDRCW * HDW, XT + 3 * HDW) != hdc_rt_score_ref(acc + GI * HDRCW * HDW, XT + 3 * HDW) { GJ = GJ + 1; }
        GI = GI + 1;
    }
    print("  1. score 闭式 == 逐lane参照: ");
    cke(GJ, 0);

    hdc_rt_zero_n(acc, 1);
    hdc_rt_addsub(acc, XS, 1);
    GR = hdc_rt_score(acc, XS);
    hdc_rt_addsub(acc, XS, 0 - 1);
    GJ = hdc_rt_score(acc, XS);
    hdc_rt_addsub(acc, XS, 0 - 1);
    GLV = hdc_rt_score(acc, XS);
    print("  2a. +=x 后 score == D: ");
    cke(GR, HDD);
    print("  2b. 再 -=x 后 score == 0: ");
    cke(GJ, 0);
    print("  2c. 再 -=x 后 score == -D（补码负数）: ");
    cke(GLV, 0 - HDD);

    hdc_rt_fit(acc, NC, XS, YS, NTR, 5, 0, 1);
    print("  3. 批式5轮 HDRU == 样本数（零更新）: ");
    cke(HDRU, NTR);

    let e0: i64 = hdc_rt_online(acc, NC, XS, YS, NTR, 3, 1);
    let t0: i64 = hdc_rt_acc(acc, NC, XT, YT, NTE);
    let m0: i64 = marg(acc);
    let e1: i64 = hdc_rt_online(acc, NC, XS, YS, NTR, 0, 1);
    let t1: i64 = hdc_rt_acc(acc, NC, XT, YT, NTE);
    let m1: i64 = marg(acc);
    let e4: i64 = hdc_rt_online(acc, NC, XS, YS, NTR, 2, 4);
    let t4: i64 = hdc_rt_acc(acc, NC, XT, YT, NTE);
    let m4: i64 = marg(acc);

    print("  4. 在线错 不纠正 > a=1: ");
    ckg(e0, e1);
    print("  5. 在线错 a=1 > a=4: ");
    ckg(e1, e4);
    print("  6. 留出准确率 不纠正 > a=1: ");
    ckg(t0, t1);
    print("  7. 留出准确率 a=1 >= a=4: ");
    ckg(t1 + 1, t4);
    print("  8. 间隔 不纠正 > 0: ");
    ckg(m0, 0);
    print("  9. 间隔 a=1 < 0: ");
    ckg(0, m1);
    print("  10. 间隔 a=1 > a=4: ");
    ckg(m1, m4);
    print("  11. 溢出标志 == 0: ");
    cke(hdc_rt_ovf(), 0);

    print("通过 ");
    print_i64(PASS);
    print(" / 失败 ");
    print_i64(FAIL);
    print_nl();
    if FAIL > 0 { return 1; }
    return 0;
}
