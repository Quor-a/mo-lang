# 117 —— 反编译 → 结构化快速推理：拟合最好的基未必跑得最快（1.91）
# expect: 0
#
# 把 1.87（代码生成权重）、1.88（权重反编译成代码）、1.90（结构化快速乘）
# 串成一条完整的**部署管线**，并测量一个此前没人量过的权衡。
#
#   Phase A  稠密训练，得到一张训好的 W1
#   Phase B  用**两种**约束反编译 W1：
#             - 无约束（谁拟合得好选谁）
#             - 只允许可分离基（部署 / 快速推理）
#   Phase C  功能一致性：反编译后的网络与原网络的预测翻转数
#   Phase D  推理耗时：稠密（已物化 n²）vs 无约束 vs 可分离
#   Phase E  规模表 + 存储比
#
# 🔴 与 1.90 的区别：1.90 比的是「先展开 n² 再乘」（O(K·n²)），拿到 307x。
#    部署场景的真实对手是**已经物化好的稠密矩阵**（O(n²)），数字会小得多。
#    这里如实报告两种口径，不混用。
import "w2c.mo";

var NI: i64 = 32;
var NH: i64 = 32;
var NS: i64 = 256;

var TNH: i64 = 12;
var TW: [384]  i64 = 0;
var TB: [12]   i64 = 0;
var TV: [12]   i64 = 0;

var XD: [8192] i64 = 0;     # 256 x 32
var YD: [256]  i64 = 0;
var TS: [256]  i64 = 0;

var DW1: [1024] i64 = 0;    # 32 x 32
var DW2: [32]   i64 = 0;
var DB1: [32]   i64 = 0;
var DB2: [2]    i64 = 0;

# 反编译产物
var LU: i64 = 0;            # 无约束
var LS: i64 = 0;            # 只允许可分离
var RU: i64 = 0;
var RS: i64 = 0;

var G_W1: i64 = 0;
var G_W2: i64 = 0;
var G_B1: i64 = 0;
var G_B2: i64 = 0;
var G_OUT: i64 = 0;

var P0: [256] i64 = 0;      # 原网络预测

var WR: [16384] i64 = 0;    # Phase E 物化用（最大 128x128）
var HB: [256]   i64 = 0;
var HA: [256]   i64 = 0;
var HX: [256]   i64 = 0;

var TS2: [4] i64 = 0;
fn now() -> i64 {
    syscall(228, 1, &TS2, 0, 0, 0, 0);
    return load64(&TS2) * 1000000000 + load64(&TS2 + 8);
}

# ================================================================ 数据

fn teacher_init() -> i64 {
    let i: i64 = 0;
    nn_srand(987654321);
    i = 0;
    while i < 384 { TW[i] = nn_rand_fp(65536); i = i + 1; }
    i = 0;
    while i < 12 {
        TB[i] = nn_rand_fp(32768);
        TV[i] = nn_rand_fp(131072);
        i = i + 1;
    }
    return 0;
}

fn teacher_pre(s: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let acc: i64 = 0;
    let o: i64 = 0;
    while i < 12 {
        acc = TB[i];
        j = 0;
        while j < NI {
            acc = acc + nn_fmul(TW[i * NI + j], XD[s * NI + j]);
            j = j + 1;
        }
        o = o + nn_fmul(TV[i], nn_sigmoid(acc));
        i = i + 1;
    }
    return o;
}

fn gen_data() -> i64 {
    let s: i64 = 0;
    let j: i64 = 0;
    let h: i64 = 0;
    let x: i64 = 0;
    let c: i64 = 0;
    s = 0;
    while s < 256 {
        # 🔴 不能取 h&1：乘数是奇数、增量也是奇数，于是 mod 2 上
        #    h ← h+1，**必然逐位交替**。结果 256 个样本里只有 2 种不同输入，
        #    且完全由下标奇偶决定 —— 训练集(偶数下标)标签清一色为 0，
        #    网络学会常数预测器就拿到 128/128。取高位避开这个共振。
        h = s * 1103515245 + 12345;
        j = 0;
        while j < NI {
            h = h * 1103515245 + 12345;
            XD[s * NI + j] = ((h / 1024) & 1) * 65536;
            j = j + 1;
        }
        s = s + 1;
    }
    s = 0;
    while s < 256 { TS[s] = teacher_pre(s); s = s + 1; }
    # 按中位数切 —— 不能用固定阈值，否则标签倾斜，
    # 网络学会「永远输出一类」就能拿到好看却毫无意义的精度。
    s = 0;
    while s < 256 {
        c = 0;
        x = 0;
        while x < 256 { if TS[x] < TS[s] { c = c + 1; } x = x + 1; }
        if c >= 128 { YD[s] = 1; } else { YD[s] = 0; }
        s = s + 1;
    }
    return 0;
}

fn student_init() -> i64 {
    let i: i64 = 0;
    nn_srand(13579);
    i = 0;
    while i < NH * NI { DW1[i] = nn_rand_fp(32768); i = i + 1; }
    i = 0;
    while i < NH {
        DW2[i] = nn_rand_fp(32768);
        DB1[i] = 0;
        i = i + 1;
    }
    DB2[0] = 0;
    return 0;
}

# 1.73：逐行符号平衡，避免整行死亡单元
fn balance_rows() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let c: i64 = 0;
    i = 0;
    while i < NH {
        c = 0;
        j = 0;
        while j < NI { if DW1[i * NI + j] < 0 { c = c + 1; } j = j + 1; }
        if c == 0 {
            j = 0;
            while j < NI { if j % 2 == 0 { DW1[i * NI + j] = 0 - DW1[i * NI + j]; } j = j + 1; }
        }
        if c == NI {
            j = 0;
            while j < NI { if j % 2 == 1 { DW1[i * NI + j] = 0 - DW1[i * NI + j]; } j = j + 1; }
        }
        i = i + 1;
    }
    return 0;
}

# ================================================================ 训练

fn build(s: i64, tg: i64) -> i64 {
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
    while i < NI { ad_set(x + i, XD[s * NI + i]); i = i + 1; }

    w1 = ad_wblock(NH * NI);
    i = 0;
    while i < NH * NI { ad_set(w1 + i, DW1[i]); i = i + 1; }
    h = ad_matmul(w1, x, NH, NI);

    b1 = ad_wblock(NH);
    i = 0;
    while i < NH { ad_set(b1 + i, DB1[i]); i = i + 1; }
    hb = ad_vadd(h, b1, NH);
    a = ad_vsig(hb, NH);

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

    G_W1 = w1; G_W2 = w2; G_B1 = b1; G_B2 = b2; G_OUT = o;
    return l;
}

fn train_dense(lr: i64, nep: i64) -> i64 {
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
            ad_step(lr);
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
    return 0;
}

# ================================================================ 推理（不建 tape）

fn infer_dense(s: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let acc: i64 = 0;
    let y: i64 = 0;
    while i < NH {
        acc = 0;
        j = 0;
        while j < NI {
            acc = acc + nn_fmul(DW1[i * NI + j], XD[s * NI + j]);
            j = j + 1;
        }
        HB[i] = acc + DB1[i];
        HA[i] = nn_sigmoid(HB[i]);
        i = i + 1;
    }
    y = DB2[0];
    i = 0;
    while i < NH { y = y + nn_fmul(DW2[i], HA[i]); i = i + 1; }
    return nn_sigmoid(y);
}

fn infer_fast(s: i64, L: i64) -> i64 {
    let i: i64 = 0;
    let y: i64 = 0;
    i = 0;
    while i < NI { HX[i] = XD[s * NI + i]; i = i + 1; }
    caw_mv(L, &HX, &HB);
    i = 0;
    while i < NH {
        HB[i] = HB[i] + DB1[i];
        HA[i] = nn_sigmoid(HB[i]);
        i = i + 1;
    }
    y = DB2[0];
    i = 0;
    while i < NH { y = y + nn_fmul(DW2[i], HA[i]); i = i + 1; }
    return nn_sigmoid(y);
}

# 与原网络预测的**翻转数** —— 这才是"压缩这个模型"的代价，
# 与模型本身泛化得好不好无关（泛化是训练的问题，不是压缩的问题）。
fn flips(L: i64) -> i64 {
    let s: i64 = 0;
    let p: i64 = 0;
    let c: i64 = 0;
    while s < 256 {
        p = infer_fast(s, L);
        if p > 32768 { p = 1; } else { p = 0; }
        if p != P0[s] { c = c + 1; }
        s = s + 1;
    }
    return c;
}

# 平均输出偏差（Q16.16）—— 比类别翻转敏感得多，
# 翻转数常常是 0（阈值把小扰动吃掉了），看不出两条路径的差别。
fn dev(L: i64) -> i64 {
    let s: i64 = 0;
    let d: i64 = 0;
    let tot: i64 = 0;
    while s < 256 {
        d = infer_fast(s, L) - infer_dense(s);
        if d < 0 { d = 0 - d; }
        tot = tot + d;
        s = s + 1;
    }
    return tot / 256;
}

# 用 caw_gen 逐元素展开再乘（慢但直白）—— 快路径必须与它给出同一个结果。
# 这一步把「快路径对不对」与「反编译掉了多少精度」分开：
# 前者必须完全一致，后者可以不好。
fn infer_rec(s: i64, L: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let acc: i64 = 0;
    let y: i64 = 0;
    while i < NH {
        acc = 0;
        j = 0;
        while j < NI {
            acc = acc + nn_fmul(caw_gen(L, i, j), XD[s * NI + j]);
            j = j + 1;
        }
        HB[i] = acc + DB1[i];
        HA[i] = nn_sigmoid(HB[i]);
        i = i + 1;
    }
    y = DB2[0];
    i = 0;
    while i < NH { y = y + nn_fmul(DW2[i], HA[i]); i = i + 1; }
    return nn_sigmoid(y);
}

fn main() -> i64 {
    let fail: i64 = 0;
    let i: i64 = 0;
    let s: i64 = 0;
    let p: i64 = 0;
    let np: i64 = 0;
    let K: i64 = 0;
    let fu: i64 = 0;
    let fs: i64 = 0;
    let t0: i64 = 0;
    let t1: i64 = 0;
    let td: i64 = 0;
    let tu: i64 = 0;
    let tsv: i64 = 0;
    let r: i64 = 0;
    let n: i64 = 0;
    let LL: i64 = 0;
    let acc: i64 = 0;
    let cu: i64 = 0;
    let cs: i64 = 0;

    print("=== 反编译 → 结构化快速推理（1.91） ===\n");

    teacher_init();
    gen_data();
    student_init();
    balance_rows();

    s = 0;
    while s < 256 { if YD[s] == 1 { np = np + 1; } s = s + 1; }
    print("正例数="); print_i64(np); print(" / 256（中位数切分，应恰为 128）\n");
    if np != 128 { fail = fail + 1; print("  ✗ 标签倾斜，精度数字将不可信\n"); }

    # ---------------------------------------------------------- A. 训练
    print("\n-- A. 稠密训练（128 样本 × 8 epoch） --\n");
    train_dense(20000, 8);
    s = 0;
    while s < 256 {
        p = infer_dense(s);
        if p > 32768 { p = 1; } else { p = 0; }
        P0[s] = p;
        s = s + 1;
    }
    np = 0;
    s = 0;
    while s < 128 { if P0[s * 2] == YD[s * 2] { np = np + 1; } s = s + 1; }
    print("  原网络 训练集(128) 精度="); print_i64(np); print(" / 128\n");
    # 🔴 这里**不要求泛化**。1024 个权重配 128 个训练样本必然记住训练集，
    #    本用例测的是「压缩这个已训模型」的代价，泛化好不好是训练配置的事。
    #    但必须确认它不是常数预测器 —— 否则后面全是在比两个常数。
    if np < 100 { fail = fail + 1; print("  ✗ 训练集都没拟合，后续比较无意义\n"); }
    np = 0;
    s = 0;
    while s < 256 { np = np + P0[s]; s = s + 1; }
    print("  预测为正的样本数="); print_i64(np); print(" / 256（不能是 0 或 256）\n");
    if np < 5 { fail = fail + 1; print("  ✗ 常数预测器\n"); }
    if np > 251 { fail = fail + 1; print("  ✗ 常数预测器\n"); }

    # ---------------------------------------------------------- B. 两种约束反编译
    K = 8;
    print("\n-- B. 反编译 W1（32×32，K=8） --\n");

    w2c_from_block(0, NH, NI);
    i = 0;
    while i < NH * NI { w2c_w(i / NI, i % NI, DW1[i]); i = i + 1; }
    RU = w2c_fit(K);
    LU = w2c_emit();
    cu = caw_mv_ndense(LU);
    print("  无约束    残差="); print_i64(w2c_relsq());
    print("  其中 O(n²) 基="); print_i64(cu); print("\n");

    w2c_from_block(0, NH, NI);
    i = 0;
    while i < NH * NI { w2c_w(i / NI, i % NI, DW1[i]); i = i + 1; }
    RS = w2c_fit_sep(K);
    LS = w2c_emit();
    cs = caw_mv_ndense(LS);
    print("  仅可分离  残差="); print_i64(w2c_relsq());
    print("  其中 O(n²) 基="); print_i64(cs); print("\n");

    if cs != 0 { fail = fail + 1; print("  ✗ 可分离约束没生效\n"); }
    print("  🔴 拟合最好的基未必跑得最快：无约束选了 "); print_i64(cu);
    print(" 个 O(n²) 基（HASH/CHIRP）\n");

    # ---------------------------------------------------------- C. 功能一致性
    print("\n-- C. 与原网络的功能差异（256 输入上的预测翻转数） --\n");
    fu = flips(LU);
    fs = flips(LS);
    print("  无约束   翻转="); print_i64(fu); print(" / 256\n");
    print("  仅可分离 翻转="); print_i64(fs); print(" / 256\n");
    print("  无约束   平均输出偏差="); print_i64(dev(LU)); print("\n");
    print("  仅可分离 平均输出偏差="); print_i64(dev(LS)); print("\n");
    print("  （翻转数大 = 反编译损失，不是快路径的错。K=8 描述一个自由训练\n");
    print("    出来的权重本来就只有约 38% 能量 —— 1.89 已量过。）\n");

    # ---- C2. 隔离：快路径 vs 逐元素展开，必须完全一致 ----
    print("\n-- C2. 快路径正确性隔离（与逐元素展开比） --\n");
    fu = 0;
    s = 0;
    while s < 256 {
        p = infer_fast(s, LS);
        if p > 32768 { p = 1; } else { p = 0; }
        np = infer_rec(s, LS);
        if np > 32768 { np = 1; } else { np = 0; }
        if p != np { fu = fu + 1; }
        s = s + 1;
    }
    print("  快路径 vs 逐元素展开：预测翻转="); print_i64(fu); print(" / 256（应为 0）\n");
    if fu != 0 { fail = fail + 1; print("  ✗ 快路径与展开结果不一致\n"); }

    # ---------------------------------------------------------- D. 推理耗时
    print("\n-- D. 推理耗时（256 样本整轮 × 20 次取均值） --\n");
    r = 0;
    t0 = now();
    while r < 20 { s = 0; while s < 256 { p = infer_dense(s); s = s + 1; } r = r + 1; }
    t1 = now();
    td = (t1 - t0) / 20;
    print("  稠密（已物化 n²）  一轮="); print_i64(td); print(" ns\n");

    r = 0;
    t0 = now();
    while r < 20 { s = 0; while s < 256 { p = infer_fast(s, LU); s = s + 1; } r = r + 1; }
    t1 = now();
    tu = (t1 - t0) / 20;
    print("  无约束              一轮="); print_i64(tu); print(" ns\n");

    r = 0;
    t0 = now();
    while r < 20 { s = 0; while s < 256 { p = infer_fast(s, LS); s = s + 1; } r = r + 1; }
    t1 = now();
    tsv = (t1 - t0) / 20;
    print("  仅可分离            一轮="); print_i64(tsv); print(" ns\n");

    # 无约束反而更慢 —— 这就是本轮要量出来的现象
    if cu > 0 {
        if tu < td { print("  [!] 无约束本应更慢，实测却更快\n"); }
    }

    # ---------------------------------------------------------- E. 规模表
    print("\n-- E. 规模表：稠密 matvec（已物化）vs 结构化（8 个可分离基） --\n");
    n = 32;
    while n <= 128 {
        LL = caw_layer(n, n, 8);
        caw_basis(LL, 0, CB_CIRC, 0, 0);
        caw_basis(LL, 1, CB_CIRC, 3, 0);
        caw_basis(LL, 2, CB_SYM, 2, 0);
        caw_basis(LL, 3, CB_BAND, 4, 0);
        caw_basis(LL, 4, CB_LOW, 2, 3);
        caw_basis(LL, 5, CB_SIN, 3, 2);
        caw_basis(LL, 6, CB_POLY, 1, 2);
        caw_basis(LL, 7, CB_ONE, 0, 0);
        i = 0;
        while i < 8 { caw_amp(LL, i, 12000 + i * 3000); i = i + 1; }

        i = 0;
        while i < n * n { WR[i] = caw_gen(LL, i / n, i % n); i = i + 1; }
        i = 0;
        while i < n { HX[i] = i * 131 - 65536; i = i + 1; }

        r = 0;
        t0 = now();
        while r < 200 {
            i = 0;
            while i < n {
                acc = 0;
                s = 0;
                while s < n { acc = acc + nn_fmul(WR[i * n + s], HX[s]); s = s + 1; }
                HB[i] = acc;
                i = i + 1;
            }
            r = r + 1;
        }
        t1 = now();
        td = (t1 - t0) / 200;

        r = 0;
        t0 = now();
        while r < 200 { caw_mv(LL, &HX, &HB); r = r + 1; }
        t1 = now();
        tsv = (t1 - t0) / 200;

        print("  n="); print_i64(n);
        print("  权重="); print_i64(n * n);
        print("  稠密="); print_i64(td);
        print(" ns  结构化="); print_i64(tsv);
        print(" ns  存储比="); print_i64((n * n) / 32); print("x\n");

        if n >= 64 {
            if tsv >= td { fail = fail + 1; print("  ✗ n≥64 时结构化应当更快\n"); }
        }
        n = n * 2;
    }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("w2cfast: ALL PASS\n"); return 0; }
    return 1;
}
