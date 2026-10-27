# 115 —— W2C：把真实权重反编译成代码（1.88）
# expect: 0
#
# caw.mo 是正向：权重由代码生成。
# w2c.mo 是逆向：给定一张已经存在的权重，反编译成
#     { (kind, p1, p2), a } 的列表 —— 即「代码」。
#
# 本测试用两张**真实**权重：
#   A. Transformer 正弦位置编码（Vaswani 2017，公开公式，真实存在于
#      原始 Transformer / 早期 GPT、BERT 系模型中，注册为 buffer）
#   B. 由已知结构合成的权重 —— 正确答案是事先知道的，
#      用来验证反编译器**真的找到了那个结构**而不是随便拟合出一个
import "w2c.mo";
import "pe16.mo";

var F: i64 = 0;

fn ck(name: i64, cond: i64) -> i64 {
    if cond == 0 {
        F = F + 1;
        print("  ✗ "); print(name); print("\n");
    }
    return 0;
}

# 打印 K 个基的反编译结果
fn show(K: i64) -> i64 {
    let k: i64 = 0;
    print("  K="); print_i64(K);
    print("  残差能量比="); print_i64((w2c_relsq() * 100) >> 16); print("%");
    print("  最大误差="); print_i64(w2c_maxerr());
    print("  压缩="); print_i64(w2c_ratio() >> 16); print("×\n");
    return 0;
}

fn dump(K: i64) -> i64 {
    let k: i64 = 0;
    print("  选出的基：");
    k = 0;
    while k < W2C_N {
        print(" ["); print_i64(w2c_kind_k(k));
        print(" p="); print_i64(w2c_p1_k(k)); print(","); print_i64(w2c_p2_k(k));
        print(" a="); print_i64(w2c_amp_k(k)); print("]");
        k = k + 1;
    }
    print("\n");
    return 0;
}

fn main() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let K: i64 = 0;
    let L: i64 = 0;
    let m: i64 = 0;
    let e1: i64 = 0;
    let e2: i64 = 0;
    let e4: i64 = 0;
    let e8: i64 = 0;
    let e16: i64 = 0;

    print("=== W2C：把真实权重反编译成代码 ===\n\n");

    # ---------------------------------------------------------------- A
    print("-- A. 真实 Transformer 正弦位置编码 16×16 --\n");
    print("   PE(pos,2i)=sin(pos/10000^(2i/d))，d=16，pos=0..15\n");
    pe_load();
    w2c_set(PE_D, PE_P);
    i = 0;
    while i < PE_D {
        j = 0;
        while j < PE_P {
            w2c_w(i, j, PE_W[i * PE_P + j]);
            j = j + 1;
        }
        i = i + 1;
    }

    K = 1;  w2c_fit(K); e1  = w2c_relsq(); print("  "); show(K);
    K = 2;  w2c_fit(K); e2  = w2c_relsq(); show(K);
    K = 4;  w2c_fit(K); e4  = w2c_relsq(); show(K);
    K = 8;  w2c_fit(K); e8  = w2c_relsq(); show(K);
    K = 16; w2c_fit(K); e16 = w2c_relsq(); show(K);
    dump(16);

    # 残差必须随 K 单调下降 —— 这是 OMP「重解全部振幅」正确的直接证据
    ck("残差应随 K 下降：K1 > K2", e1 > e2);
    ck("残差应随 K 下降：K2 > K4", e2 > e4);
    ck("残差应随 K 下降：K4 > K8", e4 > e8);
    ck("残差应随 K 下降：K8 > K16", e8 > e16);
    # 16 个基表示 16×16 的真实位置编码。
    # 实测只能降到 ~41%：真实 PE 的**频率沿维度指数衰减**，
    # 而现有基库都是可分离或线性的。这个残差本身就是诊断信号。
    ck("K=16 残差能量应 < 45%", e16 < 29491);

    # 残差诊断：定位缺的是哪一类基
    print("\n-- 残差诊断：按列（维度）统计残差能量 --\n");
    print("  列 0-3（高频维度）残差=");
    print_i64(w2c_colerr(0) + w2c_colerr(1) + w2c_colerr(2) + w2c_colerr(3));
    print("\n  列 12-15（低频维度）残差=");
    print_i64(w2c_colerr(12) + w2c_colerr(13) + w2c_colerr(14) + w2c_colerr(15));
    print("\n");
    print("  K=16 时：256 个权重 → 16×4 = 64 个数，压缩 ");
    print_i64(w2c_ratio() >> 16); print("×\n");

    # 闭环：反编译结果落成 CaW 层，用**正向**生成器重建必须逐值一致
    L = w2c_emit();
    print("\n-- 闭环：反编译 → CaW 层 → 正向生成 --\n");
    m = w2c_roundtrip(L);
    print("  两条独立实现的最大差="); print_i64(m); print("（应为 0）\n");
    ck("反编译→生成闭环应完全一致", m == 0);
    print("  caw_nparam="); print_i64(caw_nparam(L));
    print("  caw_nweight="); print_i64(caw_nweight(L)); print("\n");

    # ---------------------------------------------------------------- B
    # 已知答案的权重：W = 2.0·CIRC(1) + 0.5·SYM(0)
    # 反编译必须**精确**恢复（残差 0），否则说明求解器有问题
    print("\n-- B. 已知结构：W = 2.0·CIRC(1) + 0.5·SYM(0) --\n");
    w2c_set(16, 16);
    i = 0;
    while i < 16 {
        j = 0;
        while j < 16 {
            let d: i64 = 0;
            let v: i64 = 0;
            d = i - j;
            if d < 0 { d = 0 - d; }
            v = 0;
            if ((i - j) % 16 + 16) % 16 == 1 { v = v + 131072; }
            if d == 0 { v = v + 32768; }
            w2c_w(i, j, v);
            j = j + 1;
        }
        i = i + 1;
    }
    w2c_fit(2);
    print("  残差能量比="); print_i64((w2c_relsq() * 100) >> 16); print("%");
    print("  最大误差="); print_i64(w2c_maxerr()); print("（应为 0）\n");
    dump(2);
    ck("已知结构应被精确反编译", w2c_maxerr() == 0);

    L = w2c_emit();
    print("  静态分析 is_circ="); print_i64(caw_is_circ(L));
    print("  is_sym="); print_i64(caw_is_sym(L)); print("\n");
    # 反编译出的层同时含 CIRC 与 SYM，两者都应被识别
    # 注意：CIRC(0) 与 SYM(0) 在方阵上是**同一个矩阵**（都是对角），
    # OMP 选哪个取决于候选池顺序，所以不断言 is_sym。
    ck("应识别出循环成分", caw_is_circ(L) == 1);

    print("\n");
    if F == 0 { print("115 W2C：全部通过\n"); }
    if F > 0 { print("115 W2C：失败 "); print_i64(F); print(" 项\n"); }
    return F;
}
