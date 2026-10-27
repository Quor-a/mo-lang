# expect: 0
# SC 神经元：随机计算做推理
#
# 结构用的是论文里标准的 SC 神经元：
#   乘法 = XNOR 阵列（双极编码）
#   求和 = MUX 树
# 展示三件事：
#   1. SC 前向与定点解析解逐值一致（在统计误差内）
#   2. MUX 树的缩放必须显式补偿，否则阈值全错
#   3. 对比特翻转的容忍度 —— SC 相对定点的真正优势所在
import "io.mo";
import "sc.mo";
import "random.mo";

var FAILS: i64 = 0;

# L = 16384 比特。长度决定精度：误差 ~1/√L，
# 这里 σ_r ≈ 0.008（Q16.16 约 500），判据取 3σ 上下。
var W_: i64 = 256;

var A_X1: i64 = 0;
var A_X2: i64 = 0;
var A_W1: i64 = 0;
var A_W2: i64 = 0;
var A_B: i64 = 0;
var A_T1: i64 = 0;
var A_T2: i64 = 0;
var A_M: i64 = 0;
var A_R: i64 = 0;
var A_S1: i64 = 0;
var A_S2: i64 = 0;

fn setup() -> i64 {
    let w: i64 = W_;
    sc_reset();
    A_X1 = sc_alloc(w);
    A_X2 = sc_alloc(w);
    A_W1 = sc_alloc(w);
    A_W2 = sc_alloc(w);
    A_B = sc_alloc(w);
    A_T1 = sc_alloc(w);
    A_T2 = sc_alloc(w);
    A_M = sc_alloc(w);
    A_R = sc_alloc(w);
    A_S1 = sc_alloc(w);
    A_S2 = sc_alloc(w);
    # 选择线 P=1/2。两路必须各自独立，否则 MUX 退化成"选 a 或选 b"。
    sc_gen(A_S1, w, 32768, 10, 0);
    sc_gen(A_S2, w, 32768, 11, 0);
    return 0;
}

# 定点解析解：与 SC 走的完全是两条路，用来当参照。
#   树是 ((t1+t2)/2 + t3)/2 = (t1 + t2 + 2·t3)/4
#   要它等于 (w1x1 + w2x2 + bias)/4，t3 必须取 bias/2 —— 见下面的注释。
fn exact(x1: i64, x2: i64, w1: i64, w2: i64, bias: i64) -> i64 {
    let t1: i64 = (w1 * x1) >> 16;
    let t2: i64 = (w2 * x2) >> 16;
    return (t1 + t2 + bias) / 4;
}

# SC 神经元。bias 参数传**原始**偏置，函数内部负责 /2 补偿。
#
# 🔴 这个 /2 是本实现里最容易漏掉的一步。
#    MUX 树不是等权求和：t3 只经过一层 MUX，权重是 2；
#    t1/t2 经过两层，权重是 1。直接把 bias 塞进 t3 会得到
#    (w1x1 + w2x2 + 2·bias)/4 —— 偏置被放大一倍。
#    不报错、不崩溃，只是决策边界整体平移。
fn neuron(x1: i64, x2: i64, w1: i64, w2: i64, bias: i64) -> i64 {
    let w: i64 = W_;
    sc_gen(A_X1, w, sc_bp_encode(x1), 0, 0);
    sc_gen(A_X2, w, sc_bp_encode(x2), 1, 0);
    sc_gen(A_W1, w, sc_bp_encode(w1), 2, 0);
    sc_gen(A_W2, w, sc_bp_encode(w2), 3, 0);
    sc_gen(A_B, w, sc_bp_encode(bias / 2), 4, 0);
    sc_mul_bp(A_T1, A_X1, A_W1, w);
    sc_mul_bp(A_T2, A_X2, A_W2, w);
    sc_add(A_M, A_T1, A_T2, A_S1, w);
    sc_add(A_R, A_M, A_B, A_S2, w);
    return sc_bp_decode(sc_decode(A_R, w));
}

# 往一条流里注入 rate‰ 的比特翻转
fn flip(off: i64, w: i64, permille: i64) -> i64 {
    let total: i64 = w * 64;
    let n: i64 = total * permille / 1000;
    let i: i64 = 0;
    let p: i64 = 0;
    let b: i64 = 0;
    while i < n {
        p = rand_range(w);
        b = rand_range(64);
        SCP[off + p] = SCP[off + p] ^ (1 << b);
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let w: i64 = W_;
    let one: i64 = 65536;      # +1.0
    let neg: i64 = 0 - 65536;  # -1.0
    let wgt: i64 = 65536;      # w1 = w2 = +1
    let bias: i64 = 0 - 98304; # -1.5
    let got: i64 = 0;
    let want: i64 = 0;
    let d: i64 = 0;
    let x1: i64 = 0;
    let x2: i64 = 0;
    let i: i64 = 0;
    let correct: i64 = 0;
    let base: i64 = 0;

    srand(4242);
    sc_rng_init(20240611);
    setup();

    # ── 1. 四个输入组合：SC vs 定点 ─────────────────────────
    print("输入      SC 输出      定点解析     分类\n");
    i = 0;
    while i < 4 {
        if i == 0 { x1 = neg; x2 = neg; }
        if i == 1 { x1 = neg; x2 = one; }
        if i == 2 { x1 = one; x2 = neg; }
        if i == 3 { x1 = one; x2 = one; }
        got = neuron(x1, x2, wgt, wgt, bias);
        want = exact(x1, x2, wgt, wgt, bias);
        d = got - want;
        if d < 0 { d = 0 - d; }
        print_i64(x1 / 65536); print(","); print_i64(x2 / 65536);
        print("      "); print_i64(got);
        print("        "); print_i64(want);
        print("       ");
        if got > 0 { print("1"); } else { print("0"); }
        print("\n");
        if d > 3000 {
            print("FAIL 偏差过大 "); print_i64(d); print("\n");
            FAILS = FAILS + 1;
        }
        # AND 的真值：只有 (1,1) 为 1
        if i == 3 {
            if got > 0 { correct = correct + 1; }
        } else {
            if got < 0 { correct = correct + 1; }
        }
        i = i + 1;
    }
    print("AND 分类正确 "); print_i64(correct); print(" / 4\n");
    if correct != 4 {
        print("FAIL 分类不全对\n");
        FAILS = FAILS + 1;
    }

    # ── 2. 比特翻转容忍度 ───────────────────────────────────
    # 论文的卖点：SC 对比特错误天然宽容（一位错只影响一个时间步），
    # 而定点里高位翻转一次就是灾难。
    print("\n比特翻转率   输出(应≈8192)\n");
    neuron(one, one, wgt, wgt, bias);
    base = sc_bp_decode(sc_decode(A_R, w));
    print("0‰          "); print_i64(base); print("\n");

    i = 1;
    while i <= 50 {
        neuron(one, one, wgt, wgt, bias);
        if i == 1 { flip(A_R, w, 1); }
        if i == 10 { flip(A_R, w, 10); }
        if i == 50 { flip(A_R, w, 50); }
        got = sc_bp_decode(sc_decode(A_R, w));
        print_i64(i); print("‰         "); print_i64(got); print("\n");
        if i == 1 {
            # 1‰ 翻转：输出变化应在统计噪声量级内
            d = got - base;
            if d < 0 { d = 0 - d; }
            if d > 2500 {
                print("FAIL 1‰ 翻转影响过大\n");
                FAILS = FAILS + 1;
            }
        }
        if i == 1 { i = 10; } else { if i == 10 { i = 50; } else { i = 51; } }
    }

    if FAILS == 0 { print("\nscnet: 全部通过\n"); return 0; }
    print("\nscnet: 失败 "); print_i64(FAILS); print(" 项\n");
    return 1;
}
