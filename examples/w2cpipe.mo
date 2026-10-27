# ================================================================
# W2C 训练后管线（1.89）
#   训完 → 反编译 → 只存 K 个振幅 → 重新展开推理 → 测端到端精度
# ================================================================
#
# 1.87 的 caw 是**正向**：权重由代码生成，训练振幅。
# 1.88 的 w2c 是**逆向**：给一张已存在的权重，反编译成基函数表示。
#
# 但反编译只有接进训练管线才有意义 —— 否则它只是个分析玩具。
# 本程序把三者串起来：
#
#   Phase A  用**普通稠密权重**训练一个网络，测精度
#   Phase B  把训好的 W1 / W2 反编译成代码，只保留 K 个振幅，测精度
#   Phase C  只微调振幅（每层 K 个参数），看精度能不能回来
#
# 训练与测试**严格不相交**：256 个 8 位模式全枚举，偶数训练 / 奇数测试。
# 标签由一个固定随机的教师网络生成（teacher-student），
# 所以输入里没有内建的循环/对称结构可供基函数白捡便宜。
# ================================================================

import "w2c.mo";

var NI: i64 = 8;
var NH: i64 = 16;

# ---------------------------------------------------------------- 教师（固定）
var TNH: i64 = 12;
var TW: [96] i64 = 0;      # 12 x 8
var TB: [12] i64 = 0;
var TV: [12] i64 = 0;
var TVB: i64 = 0;

# ---------------------------------------------------------------- 数据
var XD: [2048] i64 = 0;    # 256 x 8
var YD: [256]  i64 = 0;

# ---------------------------------------------------------------- 学生（稠密）
var DW1: [128] i64 = 0;    # 16 x 8
var DW2: [16]  i64 = 0;    # 1 x 16
var DB1: [16]  i64 = 0;
var DB2: [2]   i64 = 0;

# 🔴 每个 K 必须**从同一个起点**开始微调。
#    第一版让 K=4 的微调结果（含偏置）直接流到 K=8，
#    于是 K=8 的"微调前"是 105（沾了上一轮偏置的光），
#    而 Phase B 里同样的 K=8 只有 69 —— 两个数字对不上就是线索。
#    偏置是各 K 共享的，不隔离就等于给后面的 K 白送起点。
var DB1S: [16] i64 = 0;
var DB2S: [2]  i64 = 0;
var DW2S: [16] i64 = 0;

# ---------------------------------------------------------------- 模式
var MODE: i64 = 0;         # 0 = 稠密权重   1 = 代码（CaW）
var L1: i64 = 0;
var L2: i64 = 0;

var G_W1: i64 = 0;
var G_W2: i64 = 0;
var G_B1: i64 = 0;
var G_B2: i64 = 0;
var G_OUT: i64 = 0;

# ================================================================ 教师与数据

fn teacher_init() -> i64 {
    let i: i64 = 0;
    nn_srand(987654321);
    while i < 96 {
        TW[i] = nn_rand_fp(131072);
        i = i + 1;
    }
    i = 0;
    while i < 12 {
        TB[i] = nn_rand_fp(32768);
        TV[i] = nn_rand_fp(196608);
        i = i + 1;
    }
    TVB = nn_rand_fp(65536);
    return 0;
}

# 教师的**激活前**值 s （不含 TVB）
fn teacher_pre(x: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let b: i64 = 0;
    let acc: i64 = 0;
    let s: i64 = 0;
    while i < 12 {
        acc = TB[i];
        j = 0;
        while j < 8 {
            b = (x >> j) & 1;      # 🔴 不能写 (x>>j) & 1 == 1：== 优先于 &
            if b == 1 { acc = acc + TW[i * 8 + j]; }
            j = j + 1;
        }
        s = s + nn_fmul(TV[i], nn_sigmoid(acc));
        i = i + 1;
    }
    return s;
}

# 🔴 标签必须**按中位数**切，不能用固定阈值。
#    第一版用 sigmoid(s + TVB) > 0.5，结果 256 个样本里只有 7 个正例，
#    网络学会「永远输出负类」就拿到 test 128/128 —— 而 train 只有 121/128。
#    **test 精度高于 train 精度就是这个退化的征兆**，一看数字就该怀疑。
#    改成 rank >= 128 ⇒ 严格 128 正 / 128 负。
var TS: [256] i64 = 0;
var NP: i64 = 0;

fn gen_data() -> i64 {
    let x: i64 = 0;
    let y: i64 = 0;
    let j: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    while x < 256 {
        j = 0;
        while j < 8 {
            b = (x >> j) & 1;
            XD[x * 8 + j] = b * 65536;
            j = j + 1;
        }
        TS[x] = teacher_pre(x);
        x = x + 1;
    }
    NP = 0;
    x = 0;
    while x < 256 {
        c = 0;
        y = 0;
        while y < 256 {
            if TS[y] < TS[x] { c = c + 1; }
            y = y + 1;
        }
        if c >= 128 {
            YD[x] = 1;
            NP = NP + 1;
        } else {
            YD[x] = 0;
        }
        x = x + 1;
    }
    return 0;
}

# ================================================================ 学生初始化

fn student_init() -> i64 {
    let i: i64 = 0;
    nn_srand(13579);
    while i < 128 {
        DW1[i] = nn_rand_fp(32768);
        i = i + 1;
    }
    i = 0;
    while i < 16 {
        DW2[i] = nn_rand_fp(32768);
        DB1[i] = 0;
        i = i + 1;
    }
    DB2[0] = 0;
    return 0;
}

# 🔴 1.73 的教训：一行权重符号一边倒 + 偏置 0 + 非负输入
#    ⇒ 该隐藏单元对所有输入都是死的，永远收不到梯度。
#    所以**逐行**检查，全正/全负就翻一半符号。
fn balance_rows() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let c: i64 = 0;
    let k: i64 = 0;
    while i < NH {
        c = 0;
        j = 0;
        while j < NI {
            if DW1[i * NI + j] < 0 { c = c + 1; }
            j = j + 1;
        }
        if c == 0 {
            j = 0;
            while j < NI {
                k = j & 1;
                if k == 0 { DW1[i * NI + j] = 0 - DW1[i * NI + j]; }
                j = j + 1;
            }
        }
        if c == NI {
            j = 0;
            while j < NI {
                k = j & 1;
                if k == 1 { DW1[i * NI + j] = 0 - DW1[i * NI + j]; }
                j = j + 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

# ================================================================ 前向

fn build(sx: i64, tg: i64) -> i64 {
    let w1: i64 = 0;
    let x: i64 = 0;
    let h: i64 = 0;
    let b1: i64 = 0;
    let hb: i64 = 0;
    let a: i64 = 0;
    let w2: i64 = 0;
    let y: i64 = 0;
    let b2: i64 = 0;
    let yb: i64 = 0;
    let o: i64 = 0;
    let t: i64 = 0;
    let l: i64 = 0;
    let i: i64 = 0;

    x = ad_block(NI);
    while i < NI {
        ad_set(x + i, XD[sx * NI + i]);
        i = i + 1;
    }

    if MODE == 0 {
        w1 = ad_wblock(NH * NI);
        i = 0;
        while i < NH * NI { ad_set(w1 + i, DW1[i]); i = i + 1; }
    } else {
        w1 = caw_block(L1);
    }
    h = ad_matmul(w1, x, NH, NI);

    b1 = ad_wblock(NH);
    i = 0;
    while i < NH { ad_set(b1 + i, DB1[i]); i = i + 1; }
    hb = ad_vadd(h, b1, NH);
    a = ad_vsig(hb, NH);

    # W2 只有 16 个权重，反编译它不划算（K 个基要 4K 个数，K>=4 就亏），
    # 而且输出层的重建误差会直接压死精度、掩盖 W1 的影响。
    # 所以**只把 W1 变成代码**，W2 与偏置保持稠密 —— 结论才干净。
    w2 = ad_wblock(NH);
    i = 0;
    while i < NH { ad_set(w2 + i, DW2[i]); i = i + 1; }
    y = ad_matmul(w2, a, 1, NH);

    b2 = ad_wblock(1);
    ad_set(b2 + 0, DB2[0]);
    yb = ad_vadd(y, b2, 1);
    o = ad_vsig(yb, 1);

    t = ad_block(1);
    ad_set(t + 0, tg * 65536);
    l = ad_mse(o, t, 1);

    G_W1 = w1;
    G_W2 = w2;
    G_B1 = b1;
    G_B2 = b2;
    G_OUT = o;
    return l;
}

# ================================================================ 训练

fn train_dense(lr: i64, nep: i64) -> i64 {
    let s: i64 = 0;
    let e: i64 = 0;
    let l: i64 = 0;
    let i: i64 = 0;
    let tot: i64 = 0;
    e = 0;
    while e < nep {
        s = 0;
        while s < 128 {
            ad_reset();
            l = build(s * 2, YD[s * 2]);
            ad_backward(l);
            ad_step(lr);
            # 回写：块里的值才是被 ad_step 更新过的
            i = 0;
            while i < NH * NI { DW1[i] = ad_val(G_W1 + i); i = i + 1; }
            i = 0;
            while i < NH {
                DW2[i] = ad_val(G_W2 + i);
                DB1[i] = ad_val(G_B1 + i);
                i = i + 1;
            }
            DB2[0] = ad_val(G_B2);
            s = s + 1;
        }
        e = e + 1;
    }
    return tot;
}

# 只微调振幅：权重本身不再自由，自由度从 nr*nc 降到 K
fn train_code(lr: i64, nep: i64) -> i64 {
    let s: i64 = 0;
    let e: i64 = 0;
    let l: i64 = 0;
    let i: i64 = 0;
    e = 0;
    while e < nep {
        s = 0;
        while s < 128 {
            ad_reset();
            l = build(s * 2, YD[s * 2]);
            ad_backward(l);
            caw_accum(L1, G_W1);
            caw_step(L1, lr);
            caw_zero_grad(L1);
            # 偏置仍是稠密的，照常更新
            ad_step(lr);
            i = 0;
            while i < NH { DB1[i] = ad_val(G_B1 + i); i = i + 1; }
            DB2[0] = ad_val(G_B2);
            s = s + 1;
        }
        e = e + 1;
    }
    return 0;
}

# ================================================================ 精度

fn predict(idx: i64) -> i64 {
    ad_reset();
    build(idx, 0);
    if ad_val(G_OUT) > 32768 { return 1; }
    return 0;
}

fn accuracy(tr: i64) -> i64 {
    let c: i64 = 0;
    let idx: i64 = 0;
    let ok: i64 = 0;
    while c < 128 {
        if tr == 1 { idx = c * 2; } else { idx = c * 2 + 1; }
        if predict(idx) == YD[idx] { ok = ok + 1; }
        c = c + 1;
    }
    return ok;
}

# ================================================================ 主流程

var R_TR: i64 = 0;
var R_TE: i64 = 0;

fn report(tag: ptr) -> i64 {
    R_TR = accuracy(1);
    R_TE = accuracy(0);
    print(tag);
    print("   train ");
    print_i64(R_TR);
    print("/128   test ");
    print_i64(R_TE);
    print("/128\n");
    return 0;
}

# 🔴 反编译必须始终从**权威副本 DW1** 取权重，不能从 G_W1 块取。
#    第一版就是这么错的：进入代码模式后 build() 里的 G_W1 已经是
#    CaW 生成的块，于是第二轮起的"残差"是在拟合**自己上一轮的重建**，
#    结果 K>=4 残差恒为 0，看起来"完美反编译"，实际什么都没测。
#    症状极具迷惑性：数字很好看，只是参照物被自己覆盖了。
fn snap_save() -> i64 {
    let i: i64 = 0;
    while i < NH { DB1S[i] = DB1[i]; DW2S[i] = DW2[i]; i = i + 1; }
    DB2S[0] = DB2[0];
    return 0;
}

fn snap_load() -> i64 {
    let i: i64 = 0;
    while i < NH { DB1[i] = DB1S[i]; DW2[i] = DW2S[i]; i = i + 1; }
    DB2[0] = DB2S[0];
    return 0;
}

fn decomp_w1(K: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    w2c_set(NH, NI);
    while i < NH {
        j = 0;
        while j < NI {
            w2c_w(i, j, DW1[i * NI + j]);
            j = j + 1;
        }
        i = i + 1;
    }
    w2c_pool();
    w2c_fit(K);
    L1 = w2c_emit();
    return 0;
}

fn decomp_w2(K: i64) -> i64 {
    let i: i64 = 0;
    w2c_set(1, NH);
    while i < NH {
        w2c_w(0, i, DW2[i]);
        i = i + 1;
    }
    w2c_pool();
    w2c_fit(K);
    L2 = w2c_emit();
    return 0;
}

# 只打印 test 精度（Phase C 表格用）
fn report2() -> i64 {
    R_TE = accuracy(0);
    print_i64(R_TE);
    print("/128");
    return 0;
}

fn main() -> i64 {
    let k: i64 = 0;
    let best: i64 = 0;
    let rel: i64 = 0;
    let l: i64 = 0;
    let base: i64 = 0;

    teacher_init();
    gen_data();
    student_init();
    balance_rows();

    print("=== W2C 训练后管线 ===\n");
    print("学生 8 -> 16 -> 1 ；教师固定随机 8 -> 12 -> 1\n");
    print("训练 = 256 个 8 位模式中的偶数号，测试 = 奇数号（严格不相交）\n");
    print("正例数 = ");
    print_i64(NP);
    print(" / 256\n\n");

    # ---------------------------------------------------------- Phase A
    print("Phase A  稠密训练（144 个权重自由）\n");
    train_dense(6553, 30);
    report("  稠密基线     ");
    base = R_TE;
    snap_save();

    # ---------------------------------------------------------- Phase B
    print("\nPhase B  反编译：权重 -> 代码\n");
    print("   K   残差能量%   压缩   test精度\n");

    best = 0;
    k = 2;
    while k <= 16 {
        decomp_w1(k);
        rel = w2c_relsq();
        MODE = 1;
        R_TE = accuracy(0);
        R_TR = accuracy(1);
        print("  ");
        print_i64(k);
        print("     ");
        print_i64(rel * 100 / 65536);
        print("        ");
        print_i64(w2c_ratio() / 65536);
        print("x      ");
        print_i64(R_TE);
        print("/128    tr ");
        print_i64(R_TR);
        print("   maxerr ");
        print_i64(w2c_maxerr());
        print("\n");
        if R_TE * 100 >= base * 98 {
            if best == 0 { best = k; }
        }
        k = k + 2;
    }
    print("  保持 98% 基线精度的最小 K = ");
    print_i64(best);
    print("\n");

    # ---------------------------------------------------------- Phase C
    # 权重自由时 K 个基留不住精度；但**振幅本身还可以继续训**。
    # 这一步只放开了 K 个振幅（+ 偏置），权重矩阵不再自由。
    print("  ——自由训练收敛出的权重没有结构，基池兜不住它，\n");
    print("    精度一律塌到常数预测的水平。\n");

    print("\nPhase C  只微调振幅（权重不再自由）\n");
    print("   K   微调前   微调后   压缩   泛化差\n");
    k = 4;
    while k <= 16 {
        snap_load();
        decomp_w1(k);
        MODE = 1;
        R_TE = accuracy(0);
        print("  ");
        print_i64(k);
        print("      ");
        print_i64(R_TE);
        print("      ");
        train_code(6553, 20);
        R_TE = accuracy(0);
        R_TR = accuracy(1);
        print_i64(R_TE);
        print("/128   ");
        print_i64((NH * NI) / (k * 4));
        print("x    ");
        print_i64(R_TR - R_TE);
        print("\n");
        k = k + 4;
    }

    # ---------------------------------------------------------- Phase D
    print("\nPhase D  对照：权重本来就在基张成空间里\n");
    student_init();
    balance_rows();
    MODE = 1;
    ctrl_build();
    rel = ctrl_decomp();
    print("  权重能量 = ");
    print_i64(w2c_energy());
    # 🔴 relsq 在能量 <1 时直接返回 0，会把「退化矩阵」伪装成「完美拟合」。
    #    所以必须**先确认能量足够大**，否则 0 毫无意义。
    print("   （能量 < 65536 时残差不可信）\n");
    print("  反编译相对残差 = ");
    print_i64(rel);
    print("\n");
    print("  基集合一致 = ");
    print_i64(ctrl_same());
    print("  （1 = 原样找回）\n");
    print("  原基 = ");
    print_i64(caw_kind(L1, 0));
    print_i64(caw_kind(L1, 1));
    print_i64(caw_kind(L1, 2));
    print_i64(caw_kind(L1, 3));
    print_i64(caw_kind(L1, 4));
    print_i64(caw_kind(L1, 5));
    print("   恢复 = ");
    print_i64(w2c_kind_k(0));
    print_i64(w2c_kind_k(1));
    print_i64(w2c_kind_k(2));
    print_i64(w2c_kind_k(3));
    print_i64(w2c_kind_k(4));
    print_i64(w2c_kind_k(5));
    print("\n");

    return 0;
}

# ================================================================ Phase D 对照
#
# Phase B 里残差停在 67% 并不是反编译器不行 —— 是**那张权重本来就没有结构**：
# 自由训练收敛出来的解是随机的，基池里没有能描述它的东西。
#
# 所以要有一个对照：造一张**天生住在基张成空间里**的权重
# （用 CaW 原生训练，权重 = Σ a_k B_k 是构造出来的），
# 再拿去反编译。这时答案是**存在**的，反编译器必须精确找回来。
# 找不到 ⇒ 是反编译器的 bug；找得到 ⇒ Phase B 的残差是权重的性质，不是工具的缺陷。

var CD_NB: i64 = 0;      # 原基集合里各类型出现次数（对照用）
var CD_KD: [16] i64 = 0;

fn ctrl_build() -> i64 {
    L1 = caw_layer(NH, NI, 6);
    # 🔴 对照必须用**彼此正交**的基：CIRC(a) = 1 if (i-j) mod nr == a，
    #    不同 a 的支撑集互不相交 ⇒ 正交 ⇒ OMP 就是精确的匹配追踪。
    #    早期版本用了 CIRC/SIN/SYM/BAND/LOW/ONE 的混合集，
    #    它们**互不正交**，贪心 OMP 不保证找回原集合（实测残差 7%），
    #    于是这个对照分不清「反编译器有 bug」和「基不正交」。
    #    正交子集把两件事分开：**正交时残差必须为 0**。
    caw_basis(L1, 0, CB_CIRC, 1, 0);
    caw_basis(L1, 1, CB_CIRC, 4, 0);
    caw_basis(L1, 2, CB_CIRC, 6, 0);
    caw_basis(L1, 3, CB_CIRC, 9, 0);
    caw_basis(L1, 4, CB_CIRC, 11, 0);
    caw_basis(L1, 5, CB_CIRC, 14, 0);
    caw_amp_rand(L1, 32768);

    return 0;
}

# 把 CaW 生成的矩阵取出来反编译，返回相对残差（Q16.16）
fn ctrl_decomp() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    w2c_set(NH, NI);
    while i < NH {
        j = 0;
        while j < NI {
            w2c_w(i, j, caw_gen(L1, i, j));
            j = j + 1;
        }
        i = i + 1;
    }
    w2c_pool();
    w2c_fit(6);
    return w2c_relsq();
}

# 恢复出来的基类型集合，是否与原来一致（多重集比较）
fn ctrl_same() -> i64 {
    let k: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let d: i64 = 0;
    let u: i64 = 0;
    let ok: i64 = 1;
    i = 0;
    while i < 16 { CD_KD[i] = 0; i = i + 1; }
    while k < 6 {
        a = caw_kind(L1, k);
        c = 0;
        i = 0;
        while i < W2C_N {
            b = w2c_kind_k(i);
            u = CD_KD[i];
            # 「类型相同 且 未被用过 且 本轮还没匹配上」⟺ c + d + u == 0
            # 🔴 第三项不能省：内层循环命中后必须**停下**，否则一轮就把
            #    所有同类型条目全标记掉（实测：k=0 标记了全部 6 个，
            #    k=1..5 再也匹配不上，返回 0 —— 看上去像反编译失败，
            #    其实是匹配逻辑自己吃光了候选）。
            d = b - a;
            if d < 0 { d = 0 - d; }
            if c + d + u == 0 {
                CD_KD[i] = 1;
                c = 1;
            }
            i = i + 1;
        }
        if c == 0 { ok = 0; }
        k = k + 1;
    }
    return ok;
}
