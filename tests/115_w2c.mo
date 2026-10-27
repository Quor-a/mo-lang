# 115 —— W2C 反编译器（1.89）
# expect: 0
#
# 覆盖的是 1.88 引入的 w2c_* 接口，以及它接进训练管线后暴露的四个坑。
# 每条断言都对应一个**实际发生过**的错误，不是凑数。
import "w2c.mo";

var NR: i64 = 16;
var NC: i64 = 8;

var SRC: [128] i64 = 0;

var fail: i64 = 0;

# ---------------------------------------------------------------- 1. 从训练块直接载入
#
# w2c_from_block 是「训练产物 → 反编译器」的接口。
# 顺序不能反：先 ad_val 读、后 w2c_set 清零会把待读的值先清成 0，
# 反编译出一张全零权重，残差当然是 0 —— 假的通过。
fn t_from_block() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    let bad: i64 = 0;
    let r: i64 = 0;
    let c: i64 = 0;
    while i < 128 { SRC[i] = (i + 1) * 977; i = i + 1; }
    ad_reset();
    s = ad_wblock(128);
    i = 0;
    while i < 128 { ad_set(s + i, SRC[i]); i = i + 1; }
    w2c_from_block(s, NR, NC);
    i = 0;
    while i < 128 {
        r = i / NC;
        c = i - r * NC;
        if w2c_getw(r, c) != SRC[i] { bad = bad + 1; }
        i = i + 1;
    }
    if bad != 0 { fail = fail + 1; print("  ✗ from_block 搬运错 "); print_i64(bad); print(" 处\n"); }
    return 0;
}

# ---------------------------------------------------------------- 2. 正交基 ⇒ 精确恢复
#
# CIRC(a) = 1 if (i-j) mod nr == a，不同 a 的支撑集互不相交 ⇒ 正交
# ⇒ OMP 退化成匹配追踪，必须精确找回。
#
# 🔴 能量检查不能省：caw_amp_rand 的第二个参数是**定点尺度**不是整数，
#    写成 3 的话振幅只有 3/65536 ≈ 0.00005，矩阵近乎全零，
#    而 w2c_relsq 在 energy < 1 时直接返回 0 ——
#    「退化矩阵」会被伪装成「完美拟合」。
fn t_ortho() -> i64 {
    let L: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let rel: i64 = 0;
    let e: i64 = 0;
    L = caw_layer(NR, NC, 6);
    caw_basis(L, 0, CB_CIRC, 1, 0);
    caw_basis(L, 1, CB_CIRC, 4, 0);
    caw_basis(L, 2, CB_CIRC, 6, 0);
    caw_basis(L, 3, CB_CIRC, 9, 0);
    caw_basis(L, 4, CB_CIRC, 11, 0);
    caw_basis(L, 5, CB_CIRC, 14, 0);
    caw_amp_rand(L, 32768);

    w2c_set(NR, NC);
    while i < NR {
        j = 0;
        while j < NC { w2c_w(i, j, caw_gen(L, i, j)); j = j + 1; }
        i = i + 1;
    }
    e = w2c_energy();
    if e < 65536 { fail = fail + 1; print("  ✗ 权重能量退化 "); print_i64(e); print("\n"); }
    w2c_pool();
    w2c_fit(6);
    rel = w2c_relsq();
    if rel != 0 { fail = fail + 1; print("  ✗ 正交基应精确恢复，实得残差 "); print_i64(rel); print("\n"); }
    return 0;
}

# ---------------------------------------------------------------- 3. 非正交基 ⇒ 残差 > 0
#
# 对照：混合基集互不正交，贪心 OMP **不保证**找回原集合。
# 这条断言的作用是证明第 2 条不是空转 —— 如果这里也返回 0，
# 说明 relsq 恒为 0，第 2 条的"精确恢复"毫无意义。
fn t_nonortho() -> i64 {
    let L: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let rel: i64 = 0;
    L = caw_layer(NR, NC, 6);
    caw_basis(L, 0, CB_CIRC, 3, 0);
    caw_basis(L, 1, CB_SIN, 2, 1);
    caw_basis(L, 2, CB_SYM, 2, 0);
    caw_basis(L, 3, CB_BAND, 2, 0);
    caw_basis(L, 4, CB_LOW, 2, 3);
    caw_basis(L, 5, CB_ONE, 0, 0);
    caw_amp_rand(L, 32768);

    w2c_set(NR, NC);
    while i < NR {
        j = 0;
        while j < NC { w2c_w(i, j, caw_gen(L, i, j)); j = j + 1; }
        i = i + 1;
    }
    if w2c_energy() < 65536 { fail = fail + 1; print("  ✗ 非正交用例能量退化\n"); }
    w2c_pool();
    w2c_fit(6);
    rel = w2c_relsq();
    if rel <= 0 { fail = fail + 1; print("  ✗ 非正交基残差应 > 0，实得 "); print_i64(rel); print("\n"); }
    return 0;
}

# ---------------------------------------------------------------- 4. 闭环与压缩比
#
# w2c_emit 把反编译结果落成 caw 层，caw_gen（正向，1.87）
# 必须与 w2c 的重建（逆向，1.88）给出同一个矩阵。
# 两条**独立实现**逐元素相等，才能说明 K 与振幅是自洽的。
fn t_roundtrip() -> i64 {
    let L: i64 = 0;
    let E: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let r4: i64 = 0;
    let r8: i64 = 0;
    while i < 128 { SRC[i] = (i + 1) * 977; i = i + 1; }
    w2c_set(NR, NC);
    i = 0;
    while i < NR {
        j = 0;
        while j < NC { w2c_w(i, j, SRC[i * NC + j]); j = j + 1; }
        i = i + 1;
    }
    w2c_pool();
    w2c_fit(8);
    E = w2c_emit();
    if E < 0 { fail = fail + 1; print("  ✗ emit 失败（层表耗尽？）\n"); return 0; }
    if w2c_roundtrip(E) != 0 { fail = fail + 1; print("  ✗ 正/逆向闭环不一致\n"); }

    # 压缩比是 Q16.16：K 越大比值越小
    w2c_fit(4);
    r4 = w2c_ratio();
    w2c_fit(8);
    r8 = w2c_ratio();
    if r4 <= r8 { fail = fail + 1; print("  ✗ 压缩比应随 K 下降\n"); }
    return 0;
}

fn main() -> i64 {
    print("=== W2C 反编译器测试 ===\n");
    t_from_block();
    t_ortho();
    t_nonortho();
    t_roundtrip();
    print("fail: ");
    print_i64(fail);
    print("\n");
    if fail == 0 { print("w2c: ALL PASS\n"); return 0; }
    return 1;
}
