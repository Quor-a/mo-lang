# cnn_shift —— 证明卷积+池化**真的有用**（平移泛化对照）
#
# 任务：8×8 二值图，区分"紧凑块"与"散点"
#   正样本：4 个像素组成 2×2 块       → 3×3 窗口里能看到 4 个 1
#   负样本：4 个像素两两距离 ≥ 3      → 3×3 窗口里最多看到 1 个 1
#
# **两类像素总数完全相同（都是 4）**，所以任何只看"有多少个 1"
# 的线性特征都分不开。
#
# 关键设计（平移泛化）：
#   训练集正样本的块位置： (r+c) 为偶数
#   测试集正样本的块位置： (r+c) 为奇数     ← **训练时从未见过这些位置**
#
#   卷积+池化具有平移不变性 → 应该能泛化
#   纯全连接靠记忆位置      → 应该泛化不了
#
# 两个网络都用 autodiff 训练（只写前向），参数量 CNN 还更少：
#   CNN : 36 + 4 + 8 + 2 = 50（全局池化后接 4→2）
#   FC  : 512 + 8 + 16 + 2 = 538
import "autodiff.mo";

var NTR: i64 = 24;
var NTE: i64 = 24;

var TIMG: [1536] i64 = 0;
var TLBL: [24] i64 = 0;
var EIMG: [1536] i64 = 0;
var ELBL: [24] i64 = 0;

# 负样本采样用的暂存（记录已选点）
var PR: [4] i64 = 0;
var PC: [4] i64 = 0;

# ---------------------------------------------------------------- 随机数
fn rnd(n: i64) -> i64 {
    let v: i64 = nn_rand();
    if v < 0 { v = 0 - v; }
    return v - (v / n) * n;
}

fn is_even(v: i64) -> i64 {
    return v - (v / 2) * 2;
}

# ---------------------------------------------------------------- 数据生成
# which: 0=训练集 1=测试集   parity: 正样本块位置的 (r+c) 奇偶
fn gen(which: i64, parity: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    let r: i64 = 0;
    let c: i64 = 0;
    let k: i64 = 0;
    let j: i64 = 0;
    let tr: i64 = 0;
    let tc: i64 = 0;
    let ok: i64 = 0;
    let att: i64 = 0;
    let dr: i64 = 0;
    let dc: i64 = 0;
    let half: i64 = 12;

    while s < 24 {
        # 清空
        i = 0;
        while i < 64 {
            if which == 0 { store64(&TIMG + s * 512 + i * 8, 0); }
            else { store64(&EIMG + s * 512 + i * 8, 0); }
            i = i + 1;
        }

        if s < half {
            # ---- 正样本：2×2 块，位置满足 (r+c) 奇偶 ----
            # 🔴 原来写成 r=0; c=0; 再进循环判断 ——
            #   parity=0 时 (0+0) 是偶数，**第一次判断就满足**，
            #   于是 12 个训练正样本**全部落在左上角 (0,0)**。
            #   网络只见过一个位置，当然泛化不了。
            #   必须先采样一次再判断。
            r = rnd(7);
            c = rnd(7);
            att = 0;
            while att < 400 {
                if is_even(r + c) != parity {
                    r = rnd(7);
                    c = rnd(7);
                } else { att = 400; }
                att = att + 1;
            }
            # 若没找到就强制调整一格
            if is_even(r + c) != parity { c = c + 1; if c > 6 { c = 6; r = r + 1; if r > 6 { r = 6; } } }
            if which == 0 {
                store64(&TIMG + s * 512 + r * 64 + c * 8, 65536);
                store64(&TIMG + s * 512 + r * 64 + (c + 1) * 8, 65536);
                store64(&TIMG + s * 512 + (r + 1) * 64 + c * 8, 65536);
                store64(&TIMG + s * 512 + (r + 1) * 64 + (c + 1) * 8, 65536);
                store64(&TLBL + s * 8, 65536);
            } else {
                store64(&EIMG + s * 512 + r * 64 + c * 8, 65536);
                store64(&EIMG + s * 512 + r * 64 + (c + 1) * 8, 65536);
                store64(&EIMG + s * 512 + (r + 1) * 64 + c * 8, 65536);
                store64(&EIMG + s * 512 + (r + 1) * 64 + (c + 1) * 8, 65536);
                store64(&ELBL + s * 8, 65536);
            }
        } else {
            # ---- 负样本：4 个两两切比雪夫距离 ≥ 3 的散点 ----
            # 这样 3×3 窗口里最多看到 1 个 1，与正样本的"4 个"区分度很大
            k = 0;
            while k < 4 {
                att = 0;
                ok = 0;
                while att < 400 {
                    if ok == 0 {
                        tr = rnd(8);
                        tc = rnd(8);
                        ok = 1;
                        j = 0;
                        while j < k {
                            dr = tr - load64(&PR + j * 8);
                            if dr < 0 { dr = 0 - dr; }
                            dc = tc - load64(&PC + j * 8);
                            if dc < 0 { dc = 0 - dc; }
                            # 切比雪夫距离 < 3 就拒绝
                            if dr < 3 { if dc < 3 { ok = 0; } }
                            j = j + 1;
                        }
                        if ok == 1 {
                            store64(&PR + k * 8, tr);
                            store64(&PC + k * 8, tc);
                        }
                    }
                    att = att + 1;
                }
                if ok == 0 { store64(&PR + k * 8, 0); store64(&PC + k * 8, 0); }
                if which == 0 {
                    store64(&TIMG + s * 512 + load64(&PR + k * 8) * 64 + load64(&PC + k * 8) * 8, 65536);
                } else {
                    store64(&EIMG + s * 512 + load64(&PR + k * 8) * 64 + load64(&PC + k * 8) * 8, 65536);
                }
                k = k + 1;
            }
            if which == 0 { store64(&TLBL + s * 8, 0); }
            else { store64(&ELBL + s * 8, 0); }
        }
        s = s + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 权重
# CNN
var KW: [36] i64 = 0;
var KB: [4] i64 = 0;
var FW: [8] i64 = 0;
var FB: [2] i64 = 0;
# FC
var GW1: [512] i64 = 0;
var GB1: [8] i64 = 0;
var GW2: [16] i64 = 0;
var GB2: [2] i64 = 0;

var SKW: i64 = 0;
var SKB: i64 = 0;
var SFW: i64 = 0;
var SFB: i64 = 0;
var SGW1: i64 = 0;
var SGB1: i64 = 0;
var SGW2: i64 = 0;
var SGB2: i64 = 0;
var SOUT: i64 = 0;

fn init_w() -> i64 {
    let i: i64 = 0;
    while i < 36 { store64(&KW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&KB + i * 8, 0); i = i + 1; }
    i = 0;
    while i < 8 { store64(&FW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&FB + i * 8, 0); i = i + 1; }
    i = 0;
    while i < 512 { store64(&GW1 + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 8 { store64(&GB1 + i * 8, 0); i = i + 1; }
    i = 0;
    while i < 16 { store64(&GW2 + i * 8, nn_rand_fp(65536)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&GB2 + i * 8, 0); i = i + 1; }
    return 0;
}

# ---------------------------------------------------------------- CNN（只写前向）
fn build_cnn(s: i64, iste: i64) -> i64 {
    ad_reset();
    let x: i64 = ad_block(64);
    let i: i64 = 0;
    while i < 64 {
        if iste == 0 { ad_set(x + i, load64(&TIMG + s * 512 + i * 8)); }
        else { ad_set(x + i, load64(&EIMG + s * 512 + i * 8)); }
        i = i + 1;
    }

    SKW = ad_wblock(36);
    i = 0;
    while i < 36 { ad_set(SKW + i, load64(&KW + i * 8)); i = i + 1; }
    SKB = ad_wblock(4);
    i = 0;
    while i < 4 { ad_set(SKB + i, load64(&KB + i * 8)); i = i + 1; }

    let c1: i64 = ad_conv_mc(x, SKW, 8, 8, 1, 4);
    let c2: i64 = ad_vadd_bcast(c1, SKB, 4, 36);
    let c3: i64 = ad_vrelu(c2, 144);
    #
    # 全局最大池化而不是 pool → flatten：
    #   flatten 出来接全连接是**位置相关**的，平移不变性会在那里丢掉。
    #   实测 conv+pool+FC(36→2) 在未见位置上只有 15/24，
    #   跟纯全连接的 13/24 几乎没差别 —— 差距 2 个样本，说明根本没学到。
    #   全局池化把每通道压成一个数，无论特征在哪，最大值都一样。
    let flat: i64 = ad_gmax_mc(c3, 4, 36);

    SFW = ad_wblock(8);
    i = 0;
    while i < 8 { ad_set(SFW + i, load64(&FW + i * 8)); i = i + 1; }
    SFB = ad_wblock(2);
    i = 0;
    while i < 2 { ad_set(SFB + i, load64(&FB + i * 8)); i = i + 1; }

    let z2: i64 = ad_matmul(SFW, flat, 2, 4);
    let y: i64 = ad_vsig(ad_vadd(z2, SFB, 2), 2);
    SOUT = y;

    let t: i64 = ad_block(2);
    let lb: i64 = 0;
    if iste == 0 { lb = load64(&TLBL + s * 8); } else { lb = load64(&ELBL + s * 8); }
    if lb == 0 { ad_set(t, 65536); ad_set(t + 1, 0); }
    else { ad_set(t, 0); ad_set(t + 1, 65536); }
    return ad_mse_half(y, t, 2);
}

fn save_cnn() -> i64 {
    let i: i64 = 0;
    while i < 36 { store64(&KW + i * 8, ad_val(SKW + i)); i = i + 1; }
    i = 0;
    while i < 4 { store64(&KB + i * 8, ad_val(SKB + i)); i = i + 1; }
    i = 0;
    while i < 8 { store64(&FW + i * 8, ad_val(SFW + i)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&FB + i * 8, ad_val(SFB + i)); i = i + 1; }
    return 0;
}

# ---------------------------------------------------------------- FC（只写前向）
fn build_fc(s: i64, iste: i64) -> i64 {
    ad_reset();
    let x: i64 = ad_block(64);
    let i: i64 = 0;
    while i < 64 {
        if iste == 0 { ad_set(x + i, load64(&TIMG + s * 512 + i * 8)); }
        else { ad_set(x + i, load64(&EIMG + s * 512 + i * 8)); }
        i = i + 1;
    }
    SGW1 = ad_wblock(512);
    i = 0;
    while i < 512 { ad_set(SGW1 + i, load64(&GW1 + i * 8)); i = i + 1; }
    SGB1 = ad_wblock(8);
    i = 0;
    while i < 8 { ad_set(SGB1 + i, load64(&GB1 + i * 8)); i = i + 1; }
    SGW2 = ad_wblock(16);
    i = 0;
    while i < 16 { ad_set(SGW2 + i, load64(&GW2 + i * 8)); i = i + 1; }
    SGB2 = ad_wblock(2);
    i = 0;
    while i < 2 { ad_set(SGB2 + i, load64(&GB2 + i * 8)); i = i + 1; }

    let z1: i64 = ad_matmul(SGW1, x, 8, 64);
    let h: i64 = ad_vsig(ad_vadd(z1, SGB1, 8), 8);
    let z2: i64 = ad_matmul(SGW2, h, 2, 8);
    let y: i64 = ad_vsig(ad_vadd(z2, SGB2, 2), 2);
    SOUT = y;

    let t: i64 = ad_block(2);
    let lb: i64 = 0;
    if iste == 0 { lb = load64(&TLBL + s * 8); } else { lb = load64(&ELBL + s * 8); }
    if lb == 0 { ad_set(t, 65536); ad_set(t + 1, 0); }
    else { ad_set(t, 0); ad_set(t + 1, 65536); }
    return ad_mse_half(y, t, 2);
}

fn save_fc() -> i64 {
    let i: i64 = 0;
    while i < 512 { store64(&GW1 + i * 8, ad_val(SGW1 + i)); i = i + 1; }
    i = 0;
    while i < 8 { store64(&GB1 + i * 8, ad_val(SGB1 + i)); i = i + 1; }
    i = 0;
    while i < 16 { store64(&GW2 + i * 8, ad_val(SGW2 + i)); i = i + 1; }
    i = 0;
    while i < 2 { store64(&GB2 + i * 8, ad_val(SGB2 + i)); i = i + 1; }
    return 0;
}

# ---------------------------------------------------------------- 评估
fn score(mode: i64, iste: i64) -> i64 {
    let corr: i64 = 0;
    let s: i64 = 0;
    while s < 24 {
        if mode == 0 { build_cnn(s, iste); } else { build_fc(s, iste); }
        let v0: i64 = ad_val(SOUT);
        let v1: i64 = ad_val(SOUT + 1);
        let pred: i64 = 0;
        if v1 > v0 { pred = 65536; }
        let lb: i64 = 0;
        if iste == 0 { lb = load64(&TLBL + s * 8); } else { lb = load64(&ELBL + s * 8); }
        if pred == lb { corr = corr + 1; }
        s = s + 1;
    }
    return corr;
}

# 统计两类的像素总数（证明"只看数量分不开"）
fn count_pixels(iste: i64, ispos: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    let acc: i64 = 0;
    let n: i64 = 0;
    while s < 12 {
        acc = 0;
        i = 0;
        while i < 64 {
            let v: i64 = 0;
            if iste == 0 { v = load64(&TIMG + (s + ispos * 12) * 512 + i * 8); }
            else { v = load64(&EIMG + (s + ispos * 12) * 512 + i * 8); }
            if v > 0 { acc = acc + 1; }
            i = i + 1;
        }
        n = n + acc;
        s = s + 1;
    }
    return n / 12;
}

fn main() -> i64 {
    nn_srand(31337);
    gen(0, 0);          # 训练集：正样本块位置 (r+c) 偶数
    gen(1, 1);          # 测试集：正样本块位置 (r+c) 奇数  ← 从未训练过
    init_w();

    print("=== 平移泛化对照：CNN vs 全连接 ===\n");
    print("任务：区分 2×2 紧凑块 与 4 个散点（两者像素数相同）\n\n");

    print("训练正样本块位置（前 6）: ");
    let d: i64 = 0;
    while d < 6 {
        # 找第一个 1 的坐标
        let rr: i64 = 0;
        let cc: i64 = 0;
        let found: i64 = 0;
        while rr < 8 {
            if found == 0 {
                cc = 0;
                while cc < 8 {
                    if found == 0 {
                        if load64(&TIMG + d * 512 + rr * 64 + cc * 8) > 0 {
                            found = 1;
                            print_i64(rr);
                            print(",");
                            print_i64(cc);
                            print("  ");
                        }
                    }
                    cc = cc + 1;
                }
            }
            rr = rr + 1;
        }
        d = d + 1;
    }
    print("\n");

    print("训练集正样本平均像素数 = ");
    print_i64(count_pixels(0, 0));
    print("   负样本 = ");
    print_i64(count_pixels(0, 1));
    print("\n");
    print("测试集正样本平均像素数 = ");
    print_i64(count_pixels(1, 0));
    print("   负样本 = ");
    print_i64(count_pixels(1, 1));
    print("\n");
    print("（两类像素数相同 → 任何只看数量的线性特征都分不开）\n\n");

    let lr: i64 = 32768;
    ad_audit_reset();          # EVER 按槽号记录，切换模型（CNN→FC）时要清
    let ep: i64 = 0;
    while ep < 120 {
        let s: i64 = 0;
        while s < 24 {
            let L: i64 = build_cnn(s, 0);
            ad_backward(L);
            ad_step(lr);
            save_cnn();
            s = s + 1;
        }
        ep = ep + 1;
    }
    print("--- CNN 训练后 ---\n");
    let nd1: i64 = ad_audit();
    # 诊断：按层统计死权重（槽号区间由 build_cnn 的分配顺序决定）
    print("  [诊断] SKW 槽 "); print_i64(SKW); print("-"); print_i64(SKW + 35); print("\n");
    print("  [诊断] SKB 槽 "); print_i64(SKB); print("-"); print_i64(SKB + 3); print("\n");
    print("  [诊断] SFW 槽 "); print_i64(SFW); print("-"); print_i64(SFW + 7); print("\n");
    print("  [诊断] SFB 槽 "); print_i64(SFB); print("-"); print_i64(SFB + 1); print("\n");

    # FC 模型换了槽布局，必须清 EVER，否则沿用 CNN 的记录（串味）
    ad_audit_reset();
    ep = 0;
    while ep < 120 {
        let s: i64 = 0;
        while s < 24 {
            let L2: i64 = build_fc(s, 0);
            ad_backward(L2);
            ad_step(lr);
            save_fc();
            s = s + 1;
        }
        ep = ep + 1;
    }
    print("--- FC 训练后 ---\n");
    let nd2: i64 = ad_audit();

    let ctr: i64 = score(0, 0);      # CNN 训练
    let ftr: i64 = score(1, 0);      # FC  训练
    let cte: i64 = score(0, 1);      # CNN 测试（未见位置）
    let fte: i64 = score(1, 1);      # FC  测试（未见位置）

    print("\n--- 结果 ---\n");
    print("           训练(已见位置)   测试(未见位置)\n");
    print("CNN        ");
    print_i64(ctr);
    print(" / 24            ");
    print_i64(cte);
    print(" / 24\n");
    print("全连接     ");
    print_i64(ftr);
    print(" / 24            ");
    print_i64(fte);
    print(" / 24\n");

    if cte > fte {
        print("\nCNN 泛化更好：卷积+池化具备平移不变性\n");
        return 0;
    }
    print("\nCNN 未体现出泛化优势\n");
    return 1;
}
