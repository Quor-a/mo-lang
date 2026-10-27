# hdcnet —— 超维计算做分类，以及"item memory 怎么初始化"的 A/B
#
# ── 要检验的论点（NeurIPS 2022, Understanding HDC for Parallel Single-Pass
#    Learning）─────────────────────────────────────────────
#   二值 HDC 的能力上界由**可表达的相似度矩阵**决定，与维度 D 无关。
#   能表达哪些相似度矩阵，取决于超向量怎么初始化：
#      i.i.d. 随机 → sim(L_i, L_j) ≈ 0 (i≠j)      只能表达"相等/不等"
#      CIM 保序    → sim(L_i, L_j) 随 |i−j| 下降   能表达"相近"
#   论文处方是随机傅里叶特征（RFF）；这里用 HDC 文献里的等价做法 CIM
#   （逐级翻转固定位数）达到同一目的：让 item memory 带上序结构。
#
# ── 实验设计：让两种编码彻底分道扬镳 ──────────────────────
#   3 类，类心 level = 1 / 7 / 13（间距 6）。
#     训练用 level = 类心 ± 1  → 0,2 / 6,8 / 12,14
#     测试用 level = 类心 ± t
#   t=1 时训练测试重叠（同分布对照，两者都该高）；
#   t=0 时测试 level 是 1 / 7 / 13，与训练**完全不重叠** ——
#     i.i.d. : 测试 level 与训练见过的所有 level 正交 → 只能随机猜（≈33%）
#     CIM    : level 1 与 level 0/2 相似度 ≈0.93     → 能泛过去
#   没有 t=1 的对照，就无法区分"泛化失败"和"压根没学会"。

import "io.mo";
import "hdc.mo";

var NF: i64 = 8;
var MM: i64 = 16;
var NC: i64 = 3;
var NS: i64 = 16;
var NT: i64 = 8;

var SVC: i64 = 0;
var SVI: i64 = 0;
var SVJ: i64 = 0;
var IDM: i64 = 0;

# off：相对类心的偏移
fn gen(c: i64, off: i64) -> i64 {
    let center: i64 = 1 + c * 6;
    SVJ = 0;
    while SVJ < NF {
        HDV[SVJ] = center + off;
        SVJ = SVJ + 1;
    }
    return 0;
}

fn acc_off(proto: i64, lvm: i64, off: i64) -> i64 {
    let ok: i64 = 0;
    SVC = 0;
    while SVC < NC {
        SVI = 0;
        while SVI < NT {
            gen(SVC, off);
            hdc_enc_rec(HDA0, IDM, lvm, NF);
            if hdc_am(proto, NC, HDA0) == SVC { ok = ok + 1; }
            SVI = SVI + 1;
        }
        SVC = SVC + 1;
    }
    return ok;
}

fn train(proto: i64, lvm: i64) -> i64 {
    let cnt: i64 = hdc_cnt_new();
    SVC = 0;
    while SVC < NC {
        hdc_cnt_zero(cnt);
        SVI = 0;
        while SVI < NS {
            let off: i64 = 1;
            if SVI - SVI / 2 * 2 == 0 { off = 0 - 1; }
            gen(SVC, off);
            hdc_enc_rec(HDA1, IDM, lvm, NF);
            hdc_acc(cnt, HDA1);
            SVI = SVI + 1;
        }
        hdc_maj(cnt, NS, proto + SVC * HDW);
        SVC = SVC + 1;
    }
    return 0;
}

fn main() -> i64 {
    hdc_dim(64);                      # D = 4096
    IDM = hdc_new_n(NF);
    hdc_im_iid(IDM, NF, 11);
    let lvi: i64 = hdc_new_n(MM);
    let lvc: i64 = hdc_new_n(MM);
    hdc_im_iid(lvi, MM, 22);
    hdc_im_cim(lvc, MM, 22);
    let pi: i64 = hdc_new_n(NC);
    let pc: i64 = hdc_new_n(NC);
    train(pi, lvi);
    train(pc, lvc);

    print("== A. 同分布对照（测试 off=±1，训练见过）==");
    print_nl();
    print("  iid = ");
    print_i64(acc_off(pi, lvi, 1));
    print(" / ");
    print_i64(NC * NT);
    print_nl();
    print("  cim = ");
    print_i64(acc_off(pc, lvc, 1));
    print(" / ");
    print_i64(NC * NT);
    print_nl();
    print_nl();

    print("== B. 泛化（测试 level=类心，训练完全没见过）==");
    print_nl();
    print("  iid = ");
    print_i64(acc_off(pi, lvi, 0));
    print(" / ");
    print_i64(NC * NT);
    print_nl();
    print("  cim = ");
    print_i64(acc_off(pc, lvc, 0));
    print(" / ");
    print_i64(NC * NT);
    print_nl();
    print_nl();

    print("== C. 抗噪：原型翻转 pct% 位后的泛化准确率 ==");
    print_nl();
    let q: i64 = hdc_new_n(NC);
    let pct: i64 = 10;
    while pct < 41 {
        hdc_copy_n(q, pc, NC);
        SVC = 0;
        while SVC < NC {
            hdc_flip_pct(q + SVC * HDW, pct);
            SVC = SVC + 1;
        }
        print("  翻转 ");
        print_i64(pct);
        print("%: ");
        print_i64(acc_off(q, lvc, 0));
        print(" / ");
        print_i64(NC * NT);
        print_nl();
        pct = pct + 10;
    }
    return 0;
}
