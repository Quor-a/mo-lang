# 122 —— 超维计算 / 向量符号架构（HDC / VSA，BSC 族）      # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   Kanerva 2009（HDC）、Plate 1995（HRR）、Gayler 2003（VSA）。
#   三条代数要求（Kleyko et al. 2022 综述的通行表述）：
#     bundling : sim(a⊕b, a) ≫ 0 ；交换 ；sim(a⊕b, c) ≈ 0
#     binding  : sim(a⊗b, a) ≈ 0 ；可逆 ；⊗ 对 ⊕ 分配
#   之所以算"概念"：PeerJ Comput. Sci. 综述（Cumbo & Chicco 2025）原话
#     "the lack of dedicated general-purpose frameworks for vector-symbolic
#      computing ..."，且该领域普遍不公开代码。现有只有研究库，无主流框架内建。
#
# ── 本测试覆盖的**定量**结论 ────────────────────────────────
#   ① BSC 的 binding 是**精确**自逆（其它族 HRR/FHRR/MAP 都只是近似）
#   ② 近正交性：随机向量 sim ≈ 0，σ = 1/√D
#   ③ 计数器宽度存在饱和点：CW ≤ 4 时容量严格 = 2^CW − 1
#      （arXiv:1807.08583 图 18a 的两段式；论文 D=10000 报 5 bit 饱和，
#        本测试 D=4096 实测 6 bit 饱和 —— 判据与维度不同，趋势一致）
#   ④ item memory 的初始化决定可表达的相似度矩阵（NeurIPS 2022）：
#      i.i.d. 无法泛化到未见过的 level，CIM 可以
#
# ── 相似度口径 ──────────────────────────────────────────────
#   sim = 1 − 2·ham/D，Q16.16。随机向量 ≈ 0，相同 = 65536。
#   若误用余弦（1 − ham/D），随机向量会是 0.5 —— 正交判据全部失效。

import "assert.mo";
import "hdc.mo";

var NF: i64 = 8;
var MM: i64 = 16;
var NC: i64 = 3;
var NS: i64 = 16;
var NT: i64 = 8;

var SVC: i64 = 0;
var SVI: i64 = 0;
var SVJ: i64 = 0;
var IDM2: i64 = 0;

fn gen2(c: i64, off: i64) -> i64 {
    let center: i64 = 1 + c * 6;
    SVJ = 0;
    while SVJ < NF {
        HDV[SVJ] = center + off;
        SVJ = SVJ + 1;
    }
    return 0;
}

fn acc2(proto: i64, lvm: i64, off: i64) -> i64 {
    let ok: i64 = 0;
    SVC = 0;
    while SVC < NC {
        SVI = 0;
        while SVI < NT {
            gen2(SVC, off);
            hdc_enc_rec(HDA0, IDM2, lvm, NF);
            if hdc_am(proto, NC, HDA0) == SVC { ok = ok + 1; }
            SVI = SVI + 1;
        }
        SVC = SVC + 1;
    }
    return ok;
}

fn train2(proto: i64, lvm: i64) -> i64 {
    let cnt: i64 = hdc_cnt_new();
    SVC = 0;
    while SVC < NC {
        hdc_cnt_zero(cnt);
        SVI = 0;
        while SVI < NS {
            let off: i64 = 1;
            if SVI - SVI / 2 * 2 == 0 { off = 0 - 1; }
            gen2(SVC, off);
            hdc_enc_rec(HDA1, IDM2, lvm, NF);
            hdc_acc(cnt, HDA1);
            SVI = SVI + 1;
        }
        hdc_maj(cnt, NS, proto + SVC * HDW);
        SVC = SVC + 1;
    }
    return 0;
}

# 容量：bundle n 个正交向量，全部成员仍高于阈值才算 n 可行
fn cap(cw: i64) -> i64 {
    HDCW = cw;
    let k: i64 = hdc_cnt_new();
    let base: i64 = hdc_new_n(40);
    let i: i64 = 0;
    while i < 40 {
        hdc_rand(base + i * HDW, i * 104729 + 7);
        i = i + 1;
    }
    let p: i64 = hdc_new();
    let thr: i64 = 3072;               # 3/√4096
    let best: i64 = 0;
    let n: i64 = 3;
    while n < 40 {
        HDOVF = 0;
        hdc_cnt_zero(k);
        i = 0;
        while i < n { hdc_acc(k, base + i * HDW); i = i + 1; }
        if HDOVF == 0 {
            hdc_maj(k, n, p);
            let mn: i64 = 65536;
            i = 0;
            while i < n {
                let s: i64 = hdc_simq(p, base + i * HDW);
                if s < mn { mn = s; }
                i = i + 1;
            }
            if mn > thr { best = n; }
        }
        n = n + 1;
    }
    return best;
}

fn main() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let w: i64 = 0;

    # ── ① 位平衡与近正交（D = 1024，σ_sim = 1/√D ≈ 0.031）──
    hdc_dim(16);
    let a: i64 = hdc_new();
    let b: i64 = hdc_new();
    let c: i64 = hdc_new();
    hdc_rand(a, 12345);
    hdc_rand(b, 67890);

    # D/2 = 512，σ = 16；取 5σ = 80
    w = hdc_wt(a);
    assert_true("位平衡 |wt-D/2| < 5σ", (w > 432) & (w < 592));

    # 100 对随机向量，全部 |sim| < 5σ_sim = 0.156 → 10240
    let mx: i64 = 0;
    i = 0;
    while i < 20 {
        hdc_rand(a, i * 7919 + 1);
        j = i + 1;
        while j < 20 {
            hdc_rand(b, j * 104729 + 3);
            let s: i64 = hdc_simq(a, b);
            if s < 0 { s = 0 - s; }
            if s > mx { mx = s; }
            j = j + 1;
        }
        i = i + 1;
    }
    assert_true("近正交: 190 对全部 |sim| < 5σ", mx < 10240);

    # sim(a,a) 必须精确 = 1
    assert_eq("sim(a,a) == 1", hdc_simq(a, a), 65536);

    # ── ② binding：交换、产生新向量、**精确**自逆 ────────────
    hdc_rand(a, 111);
    hdc_rand(b, 222);
    hdc_bind(a, b, c);
    hdc_bind(b, a, HDA0);
    assert_eq("binding 交换律（逐位）", hdc_ham(c, HDA0), 0);

    let s1: i64 = hdc_simq(c, a);
    if s1 < 0 { s1 = 0 - s1; }
    assert_true("binding 产生新向量: |sim| < 5σ", s1 < 10240);

    # BSC 的独门性质：bind(bind(a,b), b) == a 逐位相等，零误差
    hdc_bind(c, b, HDA1);
    assert_eq("BSC binding 精确自逆（ham == 0）", hdc_ham(HDA1, a), 0);

    # ── ③ bundling：成员 vs 非成员 ──────────────────────────
    let base: i64 = hdc_new_n(40);
    i = 0;
    while i < 40 {
        hdc_rand(base + i * HDW, i * 31337 + 5);
        i = i + 1;
    }
    let cnt: i64 = hdc_cnt_new();
    let p: i64 = hdc_new();
    HDOVF = 0;
    hdc_cnt_zero(cnt);
    i = 0;
    while i < 8 { hdc_acc(cnt, base + i * HDW); i = i + 1; }
    assert_eq("8 个分量不溢出（CW=8）", HDOVF, 0);
    hdc_maj(cnt, 8, p);
    let mi: i64 = 65536;
    i = 0;
    while i < 8 {
        let s2: i64 = hdc_simq(p, base + i * HDW);
        if s2 < mi { mi = s2; }
        i = i + 1;
    }
    let nm: i64 = hdc_simq(p, base + 30 * HDW);
    assert_true("bundle: 最差成员 >> 非成员", mi > nm + 8192);

    # ── ④ 置换：可逆且改变向量 ──────────────────────────────
    hdc_perm(base, 1, HDA0);
    assert_true("perm 改变了向量", hdc_ham(HDA0, base) > 0);
    hdc_perm(HDA0, HDD - 1, HDA1);
    assert_eq("perm(1) 与 perm(D-1) 互逆", hdc_ham(HDA1, base), 0);
    hdc_perm(base, 64, HDA0);
    hdc_perm(HDA0, HDD - 64, HDA1);
    assert_eq("perm(64) 互逆（纯字移）", hdc_ham(HDA1, base), 0);
    hdc_perm(base, 63, HDA0);
    hdc_perm(HDA0, HDD - 63, HDA1);
    assert_eq("perm(63) 互逆（跨字+位移）", hdc_ham(HDA1, base), 0);

    # ── ⑤ item memory：i.i.d. 正交 vs CIM 保序 ───────────────
    # ⚠️ 这一条正是 1.108 修掉的坑：nflip 曾被 hdc_copy 抹掉，
    #    症状是"只有 level 1 与 level 0 相关"，而**没有任何报错**。
    let li: i64 = hdc_new_n(MM);
    let lc: i64 = hdc_new_n(MM);
    hdc_im_iid(li, MM, 22);
    hdc_im_cim(lc, MM, 22);

    # i.i.d.：j>0 全部 ≈ 0
    let mxi: i64 = 0;
    j = 1;
    while j < MM {
        let s3: i64 = hdc_simq(li, li + j * HDW);
        if s3 < 0 { s3 = 0 - s3; }
        if s3 > mxi { mxi = s3; }
        j = j + 1;
    }
    assert_true("iid: 各 level 互相正交", mxi < 10240);

    # CIM：sim(L0,Lj) 严格单调递减，且相邻 ≈ 1 − 2/(m−1) ≈ 0.87
    let mono: i64 = 1;
    j = 1;
    let prev: i64 = 65536;
    while j < MM {
        let s4: i64 = hdc_simq(lc, lc + j * HDW);
        if s4 > prev - 1 { mono = 0; }
        prev = s4;
        j = j + 1;
    }
    assert_eq("cim: sim(L0,Lj) 严格单调递减", mono, 1);
    let adj: i64 = hdc_simq(lc, lc + HDW);
    assert_true("cim: 相邻 level 相似 ≈0.87", (adj > 49152) & (adj < 65536));
    let far: i64 = hdc_simq(lc, lc + (MM - 1) * HDW);
    assert_true("cim: 最远 level 显著不相似", far < adj - 16384);

    # ── ⑥ 计数器宽度的两段式（D = 4096）──────────────────────
    hdc_dim(64);
    let c3: i64 = cap(3);
    let c4: i64 = cap(4);
    let c7: i64 = cap(7);
    assert_eq("CW=3 容量 = 2^3−1（受计数器上限）", c3, 7);
    assert_eq("CW=4 容量 = 2^4−1（受计数器上限）", c4, 15);
    assert_true("CW=7 容量远超 2^4−1（已转为受维度限制）", c7 > 30);

    # ── ⑦ 溢出必须显式暴露，不能静默 ─────────────────────────
    hdc_dim(64);
    HDCW = 2;                        # 上限 3
    let k2: i64 = hdc_cnt_new();
    let v0: i64 = hdc_new();
    let v1: i64 = hdc_new();
    let v2: i64 = hdc_new();
    let v3: i64 = hdc_new();
    hdc_rand(v0, 1);
    hdc_rand(v1, 2);
    hdc_rand(v2, 3);
    hdc_rand(v3, 4);
    HDOVF = 0;
    hdc_cnt_zero(k2);
    hdc_acc(k2, v0);
    hdc_acc(k2, v1);
    hdc_acc(k2, v2);
    assert_eq("CW=2 加 3 个不溢出", HDOVF, 0);
    hdc_acc(k2, v3);                 # 第 4 个 → 溢出
    assert_eq("CW=2 加第 4 个必须报溢出", HDOVF, 1);

    # ── ⑧ 分类 A/B：i.i.d. 泛不过去，CIM 可以 ────────────────
    HDCW = 8;
    hdc_dim(64);
    IDM2 = hdc_new_n(NF);
    hdc_im_iid(IDM2, NF, 11);
    let lvi: i64 = hdc_new_n(MM);
    let lvc: i64 = hdc_new_n(MM);
    hdc_im_iid(lvi, MM, 22);
    hdc_im_cim(lvc, MM, 22);
    let pi: i64 = hdc_new_n(NC);
    let pc: i64 = hdc_new_n(NC);
    train2(pi, lvi);
    train2(pc, lvc);

    let same_i: i64 = acc2(pi, lvi, 1);
    let same_c: i64 = acc2(pc, lvc, 1);
    let gen_i: i64 = acc2(pi, lvi, 0);
    let gen_c: i64 = acc2(pc, lvc, 0);

    # 对照组：同分布下两者都必须满分，否则"泛化失败"只是"没学会"
    assert_eq("同分布对照 iid 满分", same_i, NC * NT);
    assert_eq("同分布对照 cim 满分", same_c, NC * NT);
    # 泛化：CIM 满分，i.i.d. 明显掉下来
    assert_eq("泛化 cim 满分", gen_c, NC * NT);
    assert_true("泛化: cim 明显优于 iid", gen_c > gen_i + 3);

    # ── ⑨ 序列编码：置换承载顺序 ─────────────────────────────
    hdc_dim(16);
    let g: i64 = hdc_new_n(4);
    hdc_im_iid(g, 4, 7);
    let sq: i64 = hdc_new();
    HDV[0] = 1;
    HDV[1] = 2;
    HDV[2] = 3;
    HDV[3] = 0;
    hdc_enc_seq(sq, g, 4);
    assert_eq("序列自相似 = 1", hdc_simq(sq, sq), 65536);
    HDV[0] = 3;
    HDV[1] = 2;
    HDV[2] = 1;
    HDV[3] = 0;
    hdc_enc_seq(HDA0, g, 4);
    let sr: i64 = hdc_simq(sq, HDA0);
    assert_true("倒序后相似度显著下降", sr < 49152);

    return test_done();
}
