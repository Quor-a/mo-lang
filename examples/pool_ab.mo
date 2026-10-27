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
var GOUT: i64 = 0;

fn ad_gmax_out() -> i64 { return GOUT; }

var INIT_MODE: i64 = 0;   # 0 = 原始（±1 均匀）；1 = 符号平衡

fn init_w() -> i64 {
    let i: i64 = 0;
    if INIT_MODE == 1 {
        # He 缩放 + 按通道符号平衡
        nn_conv_init_ch(&KW, 4, 9, 46341);        # sqrt(2/9)≈0.471 → 30840
    } else {
    if INIT_MODE == 2 {
        # 1.75：改用 **autodiff 原生** 初始化接口（直接操作 AD_VAL 槽）。
        # 这里先借一个临时 wblock 生成，再拷回全局 KW ——
        # 目的是验证"原生接口产生的分布"与 nn.mo 版等效。
        ad_reset();
        let tk: i64 = ad_wblock(36);
        ad_wconv_init(tk, 4, 9);
        let j5: i64 = 0;
        while j5 < 36 { store64(&KW + j5 * 8, load64(&AD_VAL + (tk + j5) * 8)); j5 = j5 + 1; }
    } else {
        while i < 36 { store64(&KW + i * 8, nn_rand_fp(65536)); i = i + 1; }
    }
    }
    i = 0;
    while i < 5 { store64(&KB + i * 8, 0); i = i + 1; }
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
    let c3: i64 = act(c2, 144);
    # 池化方式由 POOL 决定：0 = gmax（只把梯度传给最大值位置）
    #                      1 = gavg（平均传给全部位置）
    #
    # 全局最大池化而不是 pool → flatten：
    #   flatten 出来接全连接是**位置相关**的，平移不变性会在那里丢掉。
    #   实测 conv+pool+FC(36→2) 在未见位置上只有 15/24，
    #   跟纯全连接的 13/24 几乎没差别 —— 差距 2 个样本，说明根本没学到。
    #   全局池化把每通道压成一个数，无论特征在哪，最大值都一样。
    let flat: i64 = pool(c3, 4, 36);
    GOUT = flat;

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


# ==========================================================================
#  A/B 对照：池化的**梯度稀疏性**是不是卷积核死权重的成因
# ==========================================================================
var POOL: i64 = 0;
var G_RISK: [5] i64 = 0;
var RUN_IDX: i64 = 0;

var USE_LEAKY: i64 = 0;

fn act(a: i64, n: i64) -> i64 {
    if USE_LEAKY == 1 { return ad_vlrelu(a, n); }
    return ad_vrelu(a, n);
}

fn pool(inp: i64, co: i64, n: i64) -> i64 {
    if POOL == 1 { return ad_gavg_mc(inp, co, n); }
    return ad_gmax_mc(inp, co, n);
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


fn run_pool(mode: i64, act: i64, initm: i64) -> i64 {
    POOL = mode;
    USE_LEAKY = act;
    INIT_MODE = initm;
    nn_srand(31337);
    gen(0, 0);
    gen(1, 1);
    init_w();

    let lr: i64 = 32768;
    ad_audit_reset();

    # 1.76：**训练前**记账。
    # ⚠️ 必须在训练前 —— 训练后 SKW 已被更新 120 epoch，符号分布早已漂移，
    # 那时记的是"训练后的分布"，不是初始化状态（1.76 第一版就犯了这个错，
    # 导致"符号平衡"那组反而报 3 个风险）。
    let L0: i64 = build_cnn(0, 0);
    let ir0: i64 = ad_init_risk_count();
    # 1.77：改用**自动推断**（不再手写 nin=9）。
    # 注意 conv 的核在 **b** 位、matmul 的权重在 **a** 位，两者相反。
    ad_init_note_auto(SKW, 36);
    let irv: i64 = ad_init_risk_count() - ir0;
    store64(&G_RISK + RUN_IDX * 8, irv);
    RUN_IDX = RUN_IDX + 1;

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
    # 1.76：初始化风险**记账**。注意必须在训练后由 AD_AUD_INITN 读出，
    # 而权重此刻已被更新 —— 所以这里记的是"最后一次 build 时的分布"，
    # 只在 INIT_MODE==0（未做符号平衡）时才可能非 0。
    let ndead: i64 = ad_audit();
    # ad_audit 把初始化风险也算进总数了；这里减掉，
    # 让"死权重"一列与 1.74 的数字保持可比（初始化风险单独一列显示）
    ndead = ndead - irv;
    # 诊断：打印死卷积核元素在 3×3 核内的位置分布
    if INIT_MODE == 1 {
        # 决定性验证：gmax 只把梯度传给每通道**最大激活位置**的那 3×3 窗口。
        # 收集训练集 24 样本 × 4 通道的全部 gmax 位置，统计每个核元素
        # (kr,kc) 在这些窗口内**见到非零像素的次数**。
        # 次数为 0 ⇒ dK = gy·input = 0 ⇒ 合理死亡。
        print("  [诊断] gmax 位置窗口内，各核元素见到非零像素的次数：\n");
        let ci4: i64 = 0;
        while ci4 < 4 {
            print("    ch"); print_i64(ci4); print(":");
            let ki4: i64 = 0;
            while ki4 < 9 {
                let kr4: i64 = ki4 / 3;
                let kc4: i64 = ki4 - (ki4 / 3) * 3;
                let cnt: i64 = 0;
                let si4: i64 = 0;
                while si4 < 24 {
                    let Lq: i64 = build_cnn(si4, 0);
                    let pp: i64 = load64(&AD_POOLPOS + (GOUT + ci4) * 8);
                    let pr: i64 = pp / 6;
                    let pc: i64 = pp - (pp / 6) * 6;
                    let px4: i64 = load64(&TIMG + si4 * 512
                        + (pr + kr4) * 64 + (pc + kc4) * 8);
                    if px4 > 0 { cnt = cnt + 1; }
                    si4 = si4 + 1;
                }
                print(" "); print_i64(kr4); print(","); print_i64(kc4);
                print("="); print_i64(cnt);
                if ad_ever_nz(SKW + ci4 * 9 + ki4) == 0 { print("[死]"); }
                ki4 = ki4 + 1;
            }
            print("\n");
            ci4 = ci4 + 1;
        }
    }
    if INIT_MODE == 1 {
        print("  [诊断] 各通道死卷积核数：");
        let ci: i64 = 0;
        while ci < 4 {
            print(" ch"); print_i64(ci); print("=");
            print_i64(ad_dead_in(SKW + ci * 9, 9));
            ci = ci + 1;
        }
        print("\n");
    }
    let tr: i64 = score(0, 0);
    let te: i64 = score(0, 1);
    return tr * 100000000 + te * 100000 + ndead;
}

fn main() -> i64 {
    print("=== A/B：池化梯度稀疏性 vs 卷积核死权重 ===\n");
    print("任务：平移泛化（训练位置 vs 未见位置）\n");
    print("假说：死权重的成因是 **gmax 只把梯度传给每通道 1 个位置**，\n");
    print("      而不是 relu（1.71 换 leaky 只把 16 减到 13）\n\n");

    let r_max:   i64 = run_pool(0, 0, 0);
    let r_max_l: i64 = run_pool(0, 1, 0);
    let r_avg:   i64 = run_pool(1, 0, 0);
    let r_bal:   i64 = run_pool(0, 0, 1);
    let r_nat:   i64 = run_pool(0, 0, 2);

    let i: i64 = 0;
    let rs: [5] i64 = 0;
    store64(&rs + 0, r_max);
    store64(&rs + 8, r_max_l);
    store64(&rs + 16, r_avg);
    store64(&rs + 24, r_bal);
    store64(&rs + 32, r_nat);
    let names: [3] i64 = 0;

    print("\n--- 结果 ---\n");
    while i < 5 {
        let r: i64 = load64(&rs + i * 8);
        let tr: i64 = r / 100000000;
        let rest: i64 = r - tr * 100000000;
        let te: i64 = rest / 100000;
        let nd: i64 = rest - te * 100000;
        if i == 0 { print("gmax  + relu   : "); }
        if i == 1 { print("gmax  + leaky  : "); }
        if i == 2 { print("gavg  + relu   : "); }
        if i == 3 { print("gmax+符号平衡(nn.mo) : "); }
        if i == 4 { print("gmax+原生ad_wconv_init: "); }
        print("训练 "); print_i64(tr); print("/24   测试(未见) ");
        print_i64(te); print("/24   死权重 "); print_i64(nd);
        print("   初始化风险 "); print_i64(load64(&G_RISK + i * 8)); print("\n");
        i = i + 1;
    }

    print("\n--- 结论 ---\n");
    let nd_max: i64 = r_max - (r_max / 100000) * 100000;
    let nd_bal: i64 = r_bal - (r_bal / 100000) * 100000;
    print("死权重：原始初始化 "); print_i64(nd_max);
    print(" → 符号平衡初始化 "); print_i64(nd_bal); print("\n");
    if nd_bal >= nd_max {
        print("✗ 符号平衡初始化没有减少死权重\n");
        return 1;
    }
    print("✓ 符号平衡初始化减少死权重 "); print_i64(nd_max - nd_bal); print(" 个\n");
    print("  → 根因确认：死通道是**初始化符号一边倒**造成的\n");
    return 0;
}
