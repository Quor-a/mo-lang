# expect: 0
# 随机计算（Stochastic Computing）核心性质验证
#
# 最要紧的一条是**相关性**：门实现的函数取决于两路流的统计相关度
#       AND:  C=0 → x·y        C=1 → min(x,y)
#   共享随机源时算出来的根本不是乘积，而且加长比特流也救不回来。
# 所以这里不只看"乘法对不对"，还专门验证"误差是否随 N 收敛"。
import "io.mo";
import "log.mo";
import "sc.mo";

var FAILS: i64 = 0;

fn ck(got: i64, want: i64, tol: i64, tag: i64) -> i64 {
    let d: i64 = got - want;
    if d < 0 { d = 0 - d; }
    if d > tol {
        print("FAIL "); print_i64(tag); print(": got ");
        print_i64(got); print(" want "); print_i64(want);
        print(" (tol "); print_i64(tol); print(")\n");
        FAILS = FAILS + 1;
    }
    return 0;
}

fn ckb(cond: i64, tag: i64, msg: i64) -> i64 {
    if cond == 0 {
        print("FAIL "); print_i64(tag); print(": "); print(msg); print("\n");
        FAILS = FAILS + 1;
    }
    return 0;
}

# ── 1. popcount 必须与逐位计数一致 ──────────────────────────
# >> 是算术右移，SWAR 写法在这点上很敏感，必须由对照钉死。
fn test_popcount() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let x: i64 = 0;
    let v: i64 = 0;
    let slow: i64 = 0;
    while i < 200 {
        x = sc_mix(12345, i);
        slow = 0;
        v = x;
        j = 0;
        while j < 64 {
            slow = slow + (v & 1);
            v = v >> 1;
            j = j + 1;
        }
        ck(popcount(x), slow, 0, 1);
        i = i + 1;
    }
    return 0;
}

# ── 2/3. 相关性：独立 vs 共享 ───────────────────────────────
# p_a=0.6, p_b=0.7 → 乘积 0.42，min = 0.6。两者差 0.18，很好区分。
fn corr_run(w: i64, shared: i64) -> i64 {
    let pa: i64 = 39321;   # 0.6
    let pb: i64 = 45875;   # 0.7
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    sc_reset();
    a = sc_alloc(w);
    b = sc_alloc(w);
    c = sc_alloc(w);
    sc_gen(a, w, pa, 0, 0);
    if shared == 1 { sc_gen(b, w, pb, 0, 0); }
    if shared == 0 { sc_gen(b, w, pb, 1, 0); }
    sc_mul_up(c, a, b, w);
    return sc_decode(c, w);
}

fn test_corr() -> i64 {
    let want_mul: i64 = 27525;   # 0.42
    let want_min: i64 = 39321;   # 0.6
    let ind: i64 = 0;
    let shr: i64 = 0;
    let e_ind_s: i64 = 0;
    let e_shr_s: i64 = 0;
    let e_ind_l: i64 = 0;
    let e_shr_l: i64 = 0;

    ind = corr_run(64, 0);
    shr = corr_run(64, 1);
    print("L=4096   独立 "); print_i64(ind); print("   共享 "); print_i64(shr); print("\n");
    ck(ind, want_mul, 1500, 2);        # 独立 → 乘积
    ck(shr, want_min, 1500, 3);        # 共享 → min，**不是**乘积
    e_ind_s = ind - want_mul;
    if e_ind_s < 0 { e_ind_s = 0 - e_ind_s; }
    e_shr_s = shr - want_mul;
    if e_shr_s < 0 { e_shr_s = 0 - e_shr_s; }

    # 共享流对"乘积"的偏离 ≈ |0.6 − 0.42| = 0.18 → Q16.16 ≈ 11796
    ck(e_shr_s, 11796, 2000, 4);

    # ── 关键：加长比特流 ──
    ind = corr_run(256, 0);
    shr = corr_run(256, 1);
    print("L=16384  独立 "); print_i64(ind); print("   共享 "); print_i64(shr); print("\n");
    e_ind_l = ind - want_mul;
    if e_ind_l < 0 { e_ind_l = 0 - e_ind_l; }
    e_shr_l = shr - want_mul;
    if e_shr_l < 0 { e_shr_l = 0 - e_shr_l; }

    # 独立：误差应显著下降（≈1/√N，长度 ×4 → 误差 ÷2）
    ckb(e_ind_l * 2 < e_ind_s + 400, 5, "独立流误差未随长度下降");
    # 共享：误差**不下降**——这就是论文说的"extends N 也救不回来"
    ckb(e_shr_l > e_shr_s / 2, 6, "共享流误差居然随长度下降了");
    ck(e_shr_l, 11796, 2000, 7);
    return 0;
}

# ── 4. 精度随长度收敛 ~1/√N ────────────────────────────────
fn test_converge() -> i64 {
    let pa: i64 = 39321;
    let pb: i64 = 45875;
    let want: i64 = 27525;
    let w: i64 = 8;
    let e: i64 = 0;
    let got: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let e_first: i64 = -1;
    let e_last: i64 = 0;
    while w <= 128 {
        sc_reset();
        a = sc_alloc(w);
        b = sc_alloc(w);
        c = sc_alloc(w);
        sc_gen(a, w, pa, 0, 0);
        sc_gen(b, w, pb, 1, 0);
        sc_mul_up(c, a, b, w);
        got = sc_decode(c, w);
        e = got - want;
        if e < 0 { e = 0 - e; }
        print("L="); print_i64(w * 64); print("  误差 "); print_i64(e); print("\n");
        if e_first < 0 { e_first = e; }
        e_last = e;
        w = w * 2;
    }
    # 采样误差本身有涨落，单步不保证单调 —— 只断言**整体**收敛：
    # 长度 ×16 后误差应至少减半（理论 ~1/√N，即 ÷4）
    ckb(e_last * 2 < e_first, 8, "误差未随长度收敛");
    return 0;
}

# ── 5. 低差异序列：同长度更准 ───────────────────────────────
# 伪随机误差 ~1/√N；van der Corput 是确定性的，误差 ~1/N。
fn test_lowdisc() -> i64 {
    let pa: i64 = 39321;
    let pb: i64 = 45875;
    let want: i64 = 27525;
    let w: i64 = 16;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let pr: i64 = 0;
    let ld: i64 = 0;
    let epr: i64 = 0;
    let eld: i64 = 0;

    sc_reset();
    a = sc_alloc(w); b = sc_alloc(w); c = sc_alloc(w);
    sc_gen(a, w, pa, 0, 0);
    sc_gen(b, w, pb, 1, 0);
    sc_mul_up(c, a, b, w);
    pr = sc_decode(c, w);

    sc_reset();
    a = sc_alloc(w); b = sc_alloc(w); c = sc_alloc(w);
    sc_gen(a, w, pa, 0, 1);
    sc_gen(b, w, pb, 1, 1);
    sc_mul_up(c, a, b, w);
    ld = sc_decode(c, w);

    epr = pr - want; if epr < 0 { epr = 0 - epr; }
    eld = ld - want; if eld < 0 { eld = 0 - eld; }
    print("L=1024   伪随机误差 "); print_i64(epr); print("   低差异误差 "); print_i64(eld); print("\n");
    ckb(eld <= epr, 9, "低差异序列并未更准");
    return 0;
}

# ── 6. 双极乘法 = XNOR ──────────────────────────────────────
fn test_bp() -> i64 {
    let w: i64 = 64;
    let xa: i64 = 19660;    # 0.3
    let xb: i64 = -32768;   # -0.5  → 期望 -0.15
    let want: i64 = -9830;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let got: i64 = 0;
    sc_reset();
    a = sc_alloc(w); b = sc_alloc(w); c = sc_alloc(w);
    sc_gen(a, w, sc_bp_encode(xa), 0, 0);
    sc_gen(b, w, sc_bp_encode(xb), 1, 0);
    sc_mul_bp(c, a, b, w);
    got = sc_bp_decode(sc_decode(c, w));
    print("BP 0.3 * (-0.5) = "); print_i64(got); print("  期望 "); print_i64(want); print("\n");
    ck(got, want, 2500, 10);
    return 0;
}

# ── 7. scaled add = MUX，结果被缩放 1/2 ────────────────────
fn test_add() -> i64 {
    let w: i64 = 64;
    let pa: i64 = 26214;    # 0.4
    let pb: i64 = 13107;    # 0.2  → (0.4+0.2)/2 = 0.3
    let want: i64 = 19660;
    let a: i64 = 0;
    let b: i64 = 0;
    let s: i64 = 0;
    let d: i64 = 0;
    let got: i64 = 0;
    sc_reset();
    a = sc_alloc(w); b = sc_alloc(w); s = sc_alloc(w); d = sc_alloc(w);
    sc_gen(a, w, pa, 0, 0);
    sc_gen(b, w, pb, 1, 0);
    sc_gen(s, w, 32768, 2, 0);
    sc_add(d, a, b, s, w);
    got = sc_decode(d, w);
    print("MUX (0.4+0.2)/2 = "); print_i64(got); print("  期望 "); print_i64(want); print("\n");
    ck(got, want, 2000, 11);
    return 0;
}

# ── 8. 位并行的加速：打包 vs 逐位 ───────────────────────────
# 逐位版把每个时间步单独存一个格；打包版一个 i64 装 64 个时间步。
var SERIAL: [8192] i64 = 0;

# now_ms 是毫秒级，打包版一次只要几十微秒，测出来恒为 0。
# 必须自己取纳秒，否则"加速比"实际上是 19ms 比 0ms —— 数字看着很漂亮，
# 但 0 只是"小于 1 毫秒"的意思，不是真的零耗时。
var NSB: [2] i64 = 0;

fn now_ns() -> i64 {
    let r: i64 = syscall(228, 1, &NSB, 0, 0, 0, 0);
    if r < 0 { return 0; }
    return load64(&NSB) * 1000000000 + load64(&NSB + 8);
}

fn bench_serial(l: i64, pa: i64, pb: i64) -> i64 {
    let i: i64 = 0;
    let acc: i64 = 0;
    let rb: i64 = 0;
    i = 0;
    while i < l {
        SERIAL[i] = 0;
        i = i + 1;
    }
    # 生成（用与打包版同一种子，保证数值可比）
    sc_rng_reset(0);
    i = 0;
    while i < l {
        if sc_rng_next(0) < pa { SERIAL[i] = 1; }
        i = i + 1;
    }
    sc_rng_reset(1);
    i = 0;
    while i < l {
        # 每个时间步都要消耗一个随机数，否则序列与打包版错位，
        # 比较"哪种实现更快"时比的是不同的东西。
        rb = sc_rng_next(1);
        if SERIAL[i] == 1 {
            if rb >= pb { SERIAL[i] = 0; }
        }
        acc = acc + SERIAL[i];
        i = i + 1;
    }
    return acc;
}

fn test_throughput() -> i64 {
    let l: i64 = 4096;
    let w: i64 = l / 64;
    let pa: i64 = 39321;
    let pb: i64 = 45875;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let ones_pack: i64 = 0;
    let ones_ser: i64 = 0;
    let t0: i64 = 0;
    let t1: i64 = 0;
    let rep: i64 = 0;
    let tp: i64 = 0;
    let ts: i64 = 0;

    sc_reset();
    a = sc_alloc(w); b = sc_alloc(w); c = sc_alloc(w);
    sc_gen(a, w, pa, 0, 0);
    sc_gen(b, w, pb, 1, 0);

    # 打包：w 次 AND + popcount
    t0 = now_ns();
    rep = 0;
    while rep < 2000 {
        sc_mul_up(c, a, b, w);
        ones_pack = sc_decode(c, w);
        rep = rep + 1;
    }
    t1 = now_ns();
    tp = (t1 - t0) / 2000;

    # 逐位：l 次循环
    t0 = now_ns();
    rep = 0;
    while rep < 200 {
        ones_ser = bench_serial(l, pa, pb);
        rep = rep + 1;
    }
    t1 = now_ns();
    ts = (t1 - t0) / 200;

    print("打包 "); print_i64(tp); print(" ns/次    逐位 "); print_i64(ts); print(" ns/次\n");
    print("ones: 打包 "); print_i64(ones_pack); print("  逐位(Q16.16 前) "); print_i64(ones_ser); print("\n");
    # 两条路径统计的 1 的个数应落在同一量级（都是 p_a*p_b*L ≈ 1720）
    ck(ones_ser, 1720, 120, 12);
    ck(ones_pack, 27525, 1500, 13);
    ckb(ts > tp, 14, "位并行反而更慢");
    return 0;
}

fn main() -> i64 {
    sc_rng_init(20240611);
    test_popcount();
    test_corr();
    test_converge();
    test_lowdisc();
    test_bp();
    test_add();
    test_throughput();
    if FAILS == 0 { print("sc: 全部通过\n"); }
    if FAILS != 0 {
        print("sc: 失败 "); print_i64(FAILS); print(" 项\n");
        return 1;
    }
    return 0;
}
