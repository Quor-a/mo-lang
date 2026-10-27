# 114 —— Code-as-Weights：权重即代码（1.87）
# expect: 0
#
# 核心：W[i][j] = Σ_k a[k]·B_k(i,j)
#   B_k 是代码定义的基函数，a[k] 是可学习振幅。
#   存储 O(K) 而非 O(nr·nc)；结构先验写在基函数类型里。
import "caw.mo";

# ---------------------------------------------------------------- 网络
var G_W1: i64 = 0;
var G_B1: i64 = 0;
var G_W2: i64 = 0;
var G_B2: i64 = 0;
var G_OUT: i64 = 0;

# 🔴 偏置必须用 ad_vadd 接进 tape。
#    早期版本用 ad_set 把激活值手工复制到新块来"拼接"常数 1，
#    结果梯度流在复制处断开 —— a / h / W1 的梯度全为 0，
#    只有最后一层权重在更新。loss 不降反升就是这么来的。
fn build(x0: i64, x1: i64, tg: i64) -> i64 {
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
    w1 = caw_block(0);
    x = ad_block(2);
    ad_set(x + 0, x0);
    ad_set(x + 1, x1);
    h = ad_matmul(w1, x, 8, 2);
    b1 = caw_block(1);
    hb = ad_vadd(h, b1, 8);
    a = ad_vsig(hb, 8);
    w2 = caw_block(2);
    y = ad_matmul(w2, a, 1, 8);
    b2 = caw_block(3);
    yb = ad_vadd(y, b2, 1);
    o = ad_vsig(yb, 1);
    t = ad_block(1);
    ad_set(t + 0, tg);
    l = ad_mse(o, t, 1);
    G_W1 = w1;
    G_B1 = b1;
    G_W2 = w2;
    G_B2 = b2;
    G_OUT = o;
    return l;
}

fn sample(k: i64) -> i64 {
    let l: i64 = 0;
    ad_reset();
    if k == 0 { l = build(0, 0, 0); }
    if k == 1 { l = build(0, 65536, 65536); }
    if k == 2 { l = build(65536, 0, 65536); }
    if k == 3 { l = build(65536, 65536, 0); }
    return l;
}

fn totalloss() -> i64 {
    let s: i64 = 0;
    let k: i64 = 0;
    s = 0;
    k = 0;
    while k < 4 {
        s = s + ad_val(sample(k));
        k = k + 1;
    }
    return s;
}

var FD_K: i64 = 0;
var FD_SLOT: i64 = 0;

fn fd_grad(L: i64, k: i64, h: i64) -> i64 {
    let v: i64 = 0;
    let lp: i64 = 0;
    let lm: i64 = 0;
    v = caw_getamp(L, k);
    caw_amp(L, k, v + h);
    lp = ad_val(sample(1));
    caw_amp(L, k, v - h);
    lm = ad_val(sample(1));
    caw_amp(L, k, v);
    return nn_fdiv((lp - lm) / 2, h);
}

fn main() -> i64 {
    let fail: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let k: i64 = 0;
    let it: i64 = 0;
    let lr: i64 = 0;
    let l: i64 = 0;
    let ag: i64 = 0;
    let fd: i64 = 0;
    let d: i64 = 0;
    let L: i64 = 0;
    let np: i64 = 0;
    let nw: i64 = 0;
    let NW1: i64 = 0;
    let NB1: i64 = 0;
    let NW2: i64 = 0;
    let NB2: i64 = 0;

    print("=== Code-as-Weights：权重即代码 ===\n\n");

    # ---- 2. 训练网络（层 ID 必须存变量：前面已建过验证层，不能假定为 0..3）----
    print("\n-- 训练：XOR（8 隐层，偏置也由 CaW 生成）--\n");
    NW1 = caw_layer(8, 2, 8);
    caw_basis(NW1, 0, CB_SIN, 1, 0);
    caw_basis(NW1, 1, CB_SIN, 1, 1);
    caw_basis(NW1, 2, CB_SIN, 2, 1);
    caw_basis(NW1, 3, CB_SIN, 3, 1);
    caw_basis(NW1, 4, CB_HASH, 1, 0);
    caw_basis(NW1, 5, CB_HASH, 7, 0);
    caw_basis(NW1, 6, CB_POLY, 1, 0);
    caw_basis(NW1, 7, CB_ONE, 0, 0);
    NB1 = caw_layer(8, 1, 5);
    caw_basis(NB1, 0, CB_SIN, 1, 0);
    caw_basis(NB1, 1, CB_SIN, 2, 0);
    caw_basis(NB1, 2, CB_SIN, 3, 0);
    caw_basis(NB1, 3, CB_HASH, 3, 0);
    caw_basis(NB1, 4, CB_ONE, 0, 0);
    NW2 = caw_layer(1, 8, 6);
    caw_basis(NW2, 0, CB_SIN, 1, 0);
    caw_basis(NW2, 1, CB_SIN, 2, 0);
    caw_basis(NW2, 2, CB_SIN, 3, 0);
    caw_basis(NW2, 3, CB_SIN, 5, 0);
    caw_basis(NW2, 4, CB_HASH, 5, 0);
    caw_basis(NW2, 5, CB_ONE, 0, 0);
    NB2 = caw_layer(1, 1, 1);
    caw_basis(NB2, 0, CB_ONE, 0, 0);

    caw_amp(NW1, 0, 8000);   caw_amp(NW1, 1, 0 - 6000); caw_amp(NW1, 2, 5500);  caw_amp(NW1, 3, 0 - 4500);
    caw_amp(NW1, 4, 5000);   caw_amp(NW1, 5, 0 - 3500); caw_amp(NW1, 6, 4000);  caw_amp(NW1, 7, 2000);
    caw_amp(NB1, 0, 3000);   caw_amp(NB1, 1, 0 - 2500); caw_amp(NB1, 2, 2200);  caw_amp(NB1, 3, 2000);
    caw_amp(NB1, 4, 1000);
    caw_amp(NW2, 0, 6000);   caw_amp(NW2, 1, 0 - 4500); caw_amp(NW2, 2, 3800);  caw_amp(NW2, 3, 0 - 3000);
    caw_amp(NW2, 4, 3500);   caw_amp(NW2, 5, 1500);
    caw_amp(NB2, 0, 0 - 1000);

    np = caw_nparam(NW1) + caw_nparam(NB1) + caw_nparam(NW2) + caw_nparam(NB2);
    nw = caw_nweight(NW1) + caw_nweight(NB1) + caw_nweight(NW2) + caw_nweight(NB2);
    print("  参数="); print_i64(np); print("  展开权重="); print_i64(nw); print("\n");

    # ---- 1. 基函数与结构先验（手工验算）----
    print("-- 循环矩阵：CIRC(0)·1.0 + CIRC(1)·0.5 --\n");
    L = caw_layer(4, 4, 2);
    caw_basis(L, 0, CB_CIRC, 0, 0);
    caw_basis(L, 1, CB_CIRC, 1, 0);
    caw_amp(L, 0, 65536);
    caw_amp(L, 1, 32768);
    # 手算：W[i][j] = 1.0 当 (i-j)≡0 (mod 4)；0.5 当 ≡1
    if caw_gen(L, 0, 0) != 65536 { fail = fail + 1; print("  ✗ W[0][0] 应为 65536\n"); }
    if caw_gen(L, 0, 3) != 32768 { fail = fail + 1; print("  ✗ W[0][3] 应为 32768\n"); }
    if caw_gen(L, 1, 0) != 32768 { fail = fail + 1; print("  ✗ W[1][0] 应为 32768\n"); }
    if caw_gen(L, 0, 2) != 0     { fail = fail + 1; print("  ✗ W[0][2] 应为 0\n"); }
    # 每行必须是上一行的循环移位
    i = 1;
    while i < 4 {
        j = 0;
        while j < 4 {
            if caw_gen(L, i, j) != caw_gen(L, i - 1, (j + 3) % 4) {
                fail = fail + 1;
                print("  ✗ 行 "); print_i64(i); print(" 不是上一行的循环移位\n");
            }
            j = j + 1;
        }
        i = i + 1;
    }
    print("  is_circ="); print_i64(caw_is_circ(L)); print("（应为 1）\n");
    if caw_is_circ(L) != 1 { fail = fail + 1; print("  ✗ 应识别为循环矩阵\n"); }

    print("\n-- 对称与带宽（静态分析，O(K) 不看数值）--\n");
    L = caw_layer(4, 4, 2);
    caw_basis(L, 0, CB_SYM, 0, 0);
    caw_basis(L, 1, CB_BAND, 1, 0);
    print("  SYM+BAND 方阵 is_sym="); print_i64(caw_is_sym(L)); print("（应为 1）\n");
    if caw_is_sym(L) != 1 { fail = fail + 1; print("  ✗ 应识别为对称\n"); }
    L = caw_layer(4, 4, 1);
    caw_basis(L, 0, CB_BAND, 2, 0);
    print("  BAND(2) bandwidth="); print_i64(caw_bandwidth(L)); print("（应为 2）\n");
    if caw_bandwidth(L) != 2 { fail = fail + 1; print("  ✗ 带宽应为 2\n"); }
    print("  混入 CIRC 后 is_sym=");
    caw_basis(L, 0, CB_CIRC, 0, 0);
    print_i64(caw_is_sym(L)); print("（应为 0）\n");
    if caw_is_sym(L) != 0 { fail = fail + 1; print("  ✗ 混基不应判为对称\n"); }

    print("\n-- 存储：16×16 层用 8 个基 --\n");
    L = caw_layer(16, 16, 8);
    np = caw_nparam(L);
    nw = caw_nweight(L);
    print("  参数="); print_i64(np); print("  展开权重="); print_i64(nw);
    print("  压缩="); print_i64(nw / np); print("×\n");
    if nw / np != 32 { fail = fail + 1; print("  ✗ 应为 32×\n"); }

    # ---- 3. 训练前：有限差分验证 CaW 梯度 ----
    print("\n-- 有限差分验证（训练前）--\n");
    l = sample(1);
    ad_backward(l);
    caw_zero_grad(NW1);
    caw_accum(NW1, G_W1);
    k = 0;
    while k < 8 {
        ag = caw_grad(NW1, k);
        fd = fd_grad(NW1, k, 65536);
        d = ag - fd;
        if d < 0 { d = 0 - d; }
        print("  k="); print_i64(k); print(" ad="); print_i64(ag);
        print(" fd="); print_i64(fd); print(" |差|="); print_i64(d); print("\n");
        # 定点量化下允许 20% 相对误差；两者都极小时只要求同号量级
        if ag < 0 { if 0 - ag > 0 { if d > (0 - ag) / 5 + 50 { fail = fail + 1; print("  ✗ 梯度不符\n"); } } }
        else { if d > ag / 5 + 50 { fail = fail + 1; print("  ✗ 梯度不符\n"); } }
        k = k + 1;
    }

    # ---- 4. 训练 ----
    print("\n-- 训练 1200 步 --\n");
    lr = 20000;
    it = 0;
    while it < 1200 {
        k = 0;
        while k < 4 {
            l = sample(k);
            ad_backward(l);
            caw_accum(NW1, G_W1);
            caw_accum(NB1, G_B1);
            caw_accum(NW2, G_W2);
            caw_accum(NB2, G_B2);
            k = k + 1;
        }
        caw_step_mom(NW1, lr, 55000);
        caw_step_mom(NB1, lr, 55000);
        caw_step_mom(NW2, lr, 55000);
        caw_step_mom(NB2, lr, 55000);
        it = it + 1;
    }
    print("  总 loss="); print_i64(totalloss()); print("\n");
    if totalloss() > 2000 { fail = fail + 1; print("  ✗ 总 loss 过大，未收敛\n"); }

    print("  预测（期望 0,1,1,0）:\n");
    k = 0;
    while k < 4 {
        l = sample(k);
        print("    "); print_i64(k); print(" -> "); print_i64(ad_val(G_OUT)); print("\n");
        if k == 0 { if ad_val(G_OUT) > 32768 { fail = fail + 1; print("  ✗ 应为 0\n"); } }
        if k == 1 { if ad_val(G_OUT) < 32768 { fail = fail + 1; print("  ✗ 应为 1\n"); } }
        if k == 2 { if ad_val(G_OUT) < 32768 { fail = fail + 1; print("  ✗ 应为 1\n"); } }
        if k == 3 { if ad_val(G_OUT) > 32768 { fail = fail + 1; print("  ✗ 应为 0\n"); } }
        k = k + 1;
    }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("caw: ALL PASS\n"); return 0; }
    return 1;
}
