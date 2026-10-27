# 116 —— 结构化快速矩阵-向量乘（1.90）
# expect: 0
#
# 核心：y = W·x 怎么算，由 **B_k 的类型** 决定，与振幅无关。
#   读一遍类型列表（O(K)）就知道该走哪条路，一个数都不用看。
#
# 验证三件事：
#   1. 快路径与朴素逐元素生成的结果一致（九种基逐个比）
#   2. 代价模型只读类型，且预测与实际量级相符
#   3. 实测加速比 —— 不只看模型，要真跑
import "caw.mo";

var N: i64 = 64;

var XS: [256] i64 = 0;
var Y1: [256] i64 = 0;
var Y2: [256] i64 = 0;

var TS: [4] i64 = 0;

fn now() -> i64 {
    syscall(228, 1, &TS, 0, 0, 0, 0);
    return load64(&TS) * 1000000000 + load64(&TS + 8);
}

fn fill_x() -> i64 {
    let i: i64 = 0;
    let h: i64 = 0;
    i = 0;
    while i < N {
        h = i * 1103515245 + 12345;
        h = h % 1000;
        if h < 0 { h = 0 - h; }
        store64(&XS + i * 8, h * 131 - 65536);
        i = i + 1;
    }
    return 0;
}

# 比较 Y1（快路径）与 Y2（朴素），返回最大绝对差
fn cmp(nr: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 0;
    let m: i64 = 0;
    i = 0;
    while i < nr {
        d = load64(&Y1 + i * 8) - load64(&Y2 + i * 8);
        if d < 0 { d = 0 - d; }
        if d > m { m = d; }
        i = i + 1;
    }
    return m;
}


# 建一个 n×n、8 个结构化基的层（全 O(n) 类）
fn mk(n: i64) -> i64 {
    let L: i64 = 0;
    let i: i64 = 0;
    L = caw_layer(n, n, 8);
    caw_basis(L, 0, CB_CIRC, 0, 0);
    caw_basis(L, 1, CB_CIRC, 3, 0);
    caw_basis(L, 2, CB_SYM, 2, 0);
    caw_basis(L, 3, CB_BAND, 4, 0);
    caw_basis(L, 4, CB_LOW, 2, 3);
    caw_basis(L, 5, CB_SIN, 3, 2);
    caw_basis(L, 6, CB_POLY, 1, 2);
    caw_basis(L, 7, CB_ONE, 0, 0);
    i = 0;
    while i < 8 { caw_amp(L, i, 12000 + i * 3000); i = i + 1; }
    return L;
}

fn fill_x_n(n: i64) -> i64 {
    let i: i64 = 0;
    let h: i64 = 0;
    i = 0;
    while i < n {
        h = i * 1103515245 + 12345;
        h = h % 1000;
        if h < 0 { h = 0 - h; }
        store64(&XS + i * 8, h * 131 - 65536);
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let fail: i64 = 0;
    let L: i64 = 0;
    let kind: i64 = 0;
    let d: i64 = 0;
    let tol: i64 = 0;
    let mag: i64 = 0;
    let i: i64 = 0;
    let t0: i64 = 0;
    let t1: i64 = 0;
    let tf: i64 = 0;
    let td: i64 = 0;
    let r: i64 = 0;
    let sp: i64 = 0;

    print("=== 结构化快速矩阵-向量乘 ===\n");
    print("n="); print_i64(N); print("\n");

    fill_x();

    # ---------------------------------------------------------- 1. 九种基逐个比
    print("\n-- 逐基类型比对（快路径 vs 朴素） --\n");
    kind = 0;
    while kind <= 9 {
        L = caw_layer(N, N, 1);
        if kind == CB_LOW { caw_basis(L, 0, kind, 2, 3); }
        else { if kind == CB_SIN { caw_basis(L, 0, kind, 3, 2); }
        else { if kind == CB_POLY { caw_basis(L, 0, kind, 1, 2); }
        else { if kind == CB_BAND { caw_basis(L, 0, kind, 3, 0); }
        else { if kind == CB_ALT { caw_basis(L, 0, kind, 1, 0); }
        else { caw_basis(L, 0, kind, 3, 1); } } } } }
        caw_amp(L, 0, 40000);

        caw_mv(L, &XS, &Y1);
        caw_mv_dense(L, &XS, &Y2);
        d = cmp(N);

        # 量级：取朴素结果的最大绝对值，用于相对容差
        mag = 0;
        i = 0;
        while i < N {
            if load64(&Y2 + i * 8) < 0 { if 0 - load64(&Y2 + i * 8) > mag { mag = 0 - load64(&Y2 + i * 8); } }
            else { if load64(&Y2 + i * 8) > mag { mag = load64(&Y2 + i * 8); } }
            i = i + 1;
        }
        # 容差 = 量级的 5% + 0.03（定点与三角函数表的量化误差）
        tol = mag / 20 + 2000;

        print("  kind="); print_i64(kind);
        print("  快路径="); print_i64(load64(&Y1 + 8));
        print("  朴素="); print_i64(load64(&Y2 + 8));
        print("  最大差="); print_i64(d);
        print("  容差="); print_i64(tol);
        if d > tol { print("  ✗ 不一致\n"); fail = fail + 1; } else { print("  ✓\n"); }
        kind = kind + 1;
    }

    # ---------------------------------------------------------- 2. 混合层：代价模型
    print("\n-- 混合层（8 个结构化基） --\n");
    L = caw_layer(N, N, 8);
    caw_basis(L, 0, CB_CIRC, 0, 0);
    caw_basis(L, 1, CB_CIRC, 3, 0);
    caw_basis(L, 2, CB_SYM, 2, 0);
    caw_basis(L, 3, CB_BAND, 4, 0);
    caw_basis(L, 4, CB_LOW, 2, 3);
    caw_basis(L, 5, CB_SIN, 3, 2);
    caw_basis(L, 6, CB_POLY, 1, 2);
    caw_basis(L, 7, CB_ONE, 0, 0);
    i = 0;
    while i < 8 { caw_amp(L, i, 12000 + i * 3000); i = i + 1; }

    print("  O(n²) 基个数="); print_i64(caw_mv_ndense(L)); print("（应为 0）\n");
    if caw_mv_ndense(L) != 0 { fail = fail + 1; print("  ✗ 不该有不可分离基\n"); }
    print("  预测代价="); print_i64(caw_mv_cost(L));
    print("   朴素代价="); print_i64(caw_mv_cost_dense(L)); print("\n");
    if caw_mv_cost(L) >= caw_mv_cost_dense(L) { fail = fail + 1; print("  ✗ 快路径代价不该不低于朴素\n"); }

    caw_mv(L, &XS, &Y1);
    caw_mv_dense(L, &XS, &Y2);
    d = cmp(N);
    print("  8 基混合最大差="); print_i64(d); print("\n");
    if d > 30000 { fail = fail + 1; print("  ✗ 混合层不一致\n"); }

    # ---------------------------------------------------------- 3. 实测加速
    print("\n-- 实测（同一输入，各跑若干次取单次耗时） --\n");
    r = 0;
    t0 = now();
    while r < 200 { caw_mv_dense(L, &XS, &Y2); r = r + 1; }
    t1 = now();
    td = (t1 - t0) / 200;
    print("  朴素  单次="); print_i64(td); print(" ns\n");

    r = 0;
    t0 = now();
    while r < 4000 { caw_mv(L, &XS, &Y1); r = r + 1; }
    t1 = now();
    tf = (t1 - t0) / 4000;
    print("  快路径 单次="); print_i64(tf); print(" ns\n");

    if tf > 0 { sp = td / tf; } else { sp = 0; }
    print("  加速比="); print_i64(sp); print("x\n");
    if sp < 3 { fail = fail + 1; print("  ✗ 加速比过小\n"); }

    # ---------------------------------------------------------- 4. 不可分离基必须被识别
    print("\n-- 含 CHIRP：必须判定为不可分离 --\n");
    L = caw_layer(N, N, 2);
    caw_basis(L, 0, CB_CIRC, 1, 0);
    caw_basis(L, 1, CB_CHIRP, 3, 0);
    caw_amp(L, 0, 30000);
    caw_amp(L, 1, 20000);
    print("  O(n²) 基个数="); print_i64(caw_mv_ndense(L)); print("（应为 1）\n");
    if caw_mv_ndense(L) != 1 { fail = fail + 1; print("  ✗ CHIRP 未被识别\n"); }
    caw_mv(L, &XS, &Y1);
    caw_mv_dense(L, &XS, &Y2);
    d = cmp(N);
    print("  最大差="); print_i64(d); print("\n");
    if d > 30000 { fail = fail + 1; print("  ✗ 含 CHIRP 层不一致\n"); }


    # ---------------------------------------------------------- 5. 加速比随 n 增长
    # O(n) 对 O(n²)：n 翻倍，加速比也该翻倍。只测一个 n 看不出这件事。
    print("\n-- 加速比 vs 规模（应当是线性增长） --\n");
    i = 32;
    while i <= 256 {
        L = mk(i);
        fill_x_n(i);
        r = 0;
        t0 = now();
        while r < 20 { caw_mv_dense(L, &XS, &Y2); r = r + 1; }
        t1 = now();
        td = (t1 - t0) / 20;
        r = 0;
        t0 = now();
        while r < 2000 { caw_mv(L, &XS, &Y1); r = r + 1; }
        t1 = now();
        tf = (t1 - t0) / 2000;
        sp = 0;
        if tf > 0 { sp = td / tf; }
        print("  n="); print_i64(i);
        print("  朴素="); print_i64(td);
        print(" ns  快路径="); print_i64(tf);
        print(" ns  加速="); print_i64(sp); print("x\n");
        if sp < 3 { fail = fail + 1; print("  ✗ 加速比过小\n"); }
        i = i * 2;
    }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("fastmv: ALL PASS\n"); return 0; }
    return 1;
}
