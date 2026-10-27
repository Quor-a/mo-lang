# nnet_ad —— 同一个网络，两条训练路径对照
#
#   A) nn_train   ：nn.mo 的**手写反向传播**
#   B) nnad_train ：**自动微分**（梯度由墨语言求）
#
# 两者用相同的初始权重、相同的数据、相同的学习率，
# 逐轮比对 loss —— 这能验证"自动求的梯度"与"手写的梯度"等价。
import "nnad.mo";

var X: [8] i64 = 0;
var Y: [4] i64 = 0;

fn init_data() -> i64 {
    store64(&X + 0, 0);       store64(&X + 8, 0);        store64(&Y + 0, 0);
    store64(&X + 16, 0);      store64(&X + 24, 65536);   store64(&Y + 8, 65536);
    store64(&X + 32, 65536);  store64(&X + 40, 0);       store64(&Y + 16, 65536);
    store64(&X + 48, 65536);  store64(&X + 56, 65536);   store64(&Y + 24, 0);
    return 0;
}

fn mknet() -> i64 {
    let sizes: [3] i64 = 0;
    store64(&sizes + 0, 2);
    store64(&sizes + 8, 4);
    store64(&sizes + 16, 1);
    let n: i64 = nn_new(&sizes, 3);
    nn_set_act(n, 1, 3);       # 隐藏层 tanh
    nn_set_act(n, 2, 2);       # 输出层 sigmoid
    return n;
}

fn copy_w(src: i64, dst: i64) -> i64 {
    let m: i64 = 1;
    while m < 3 {
        let nc: i64 = nn_size(src, m);
        let np: i64 = nn_size(src, m - 1);
        let j: i64 = 0;
        while j < nc {
            let k: i64 = 0;
            while k < np {
                store64(nn_wref(dst, m, j, k), load64(nn_wref(src, m, j, k)));
                k = k + 1;
            }
            store64(nn_bref(dst, m, j), load64(nn_bref(src, m, j)));
            j = j + 1;
        }
        m = m + 1;
    }
    return 0;
}

fn main() -> i64 {
    nn_srand(12345);
    init_data();

    let a: i64 = mknet();
    nn_rand_init(a);
    let b: i64 = mknet();
    copy_w(a, b);              # 两边**完全相同的初始权重**

    let lr: i64 = 32768;
    print("=== 手写反向 vs 自动微分（逐轮 loss 对照）===\n");

    let fail: i64 = 0;
    let ep: i64 = 0;
    while ep < 400 {
        let s: i64 = 0;
        while s < 4 {
            let la: i64 = nn_train(a, &X + s * 16, &Y + s * 8, lr);
            let lb: i64 = nnad_train(b, &X + s * 16, &Y + s * 8, lr);
            # 两条路径的 loss 应该一致（定点，允许 2 milli 差）
            let d: i64 = la - lb;
            if d < 0 { d = 0 - d; }
            if d > 2 {
                if fail == 0 {
                    print("diverge at epoch ");
                    print_i64(ep);
                    print(" sample ");
                    print_i64(s);
                    print(": hand ");
                    print_i64(nn_to_milli(la));
                    print("  autodiff ");
                    print_i64(nn_to_milli(lb));
                    print("\n");
                }
                fail = fail + 1;
            }
            s = s + 1;
        }
        if ep == 0 {
            print("epoch   0  hand ");
            print_i64(nn_to_milli(la_shown(a, &X, &Y)));
            print("  autodiff ");
            print_i64(nn_to_milli(nnad_shown(b, &X, &Y)));
            print("\n");
        }
        ep = ep + 1;
    }

    if fail == 0 {
        print("loss 逐轮一致：手写梯度 == 自动梯度\n");
    } else {
        print("diverged: ");
        print_i64(fail);
        print(" 次\n");
        return 1;
    }

    # ---- 两边都应解出 XOR ----
    print("\n--- 手写反向 ---\n");
    let ca: i64 = check(a);
    print("--- 自动微分 ---\n");
    let cb: i64 = check(b);
    print("correct: hand ");
    print_i64(ca);
    print(" / 4   autodiff ");
    print_i64(cb);
    print(" / 4\n");
    if ca == 4 { if cb == 4 { print("both solved XOR\n"); return 0; } }
    return 1;
}

fn la_shown(n: i64, xs: i64, ys: i64) -> i64 {
    nn_forward(n, xs);
    let nl: i64 = nn_nl(n);
    let o: i64 = load64(nn_aref(n, nl - 1, 0));
    let t: i64 = load64(ys + 0);
    let e: i64 = o - t;
    return nn_fmul(e, e);
}

fn nnad_shown(n: i64, xs: i64, ys: i64) -> i64 {
    nnad_forward(n, xs);
    let nl: i64 = nn_nl(n);
    let o: i64 = load64(nn_aref(n, nl - 1, 0));
    let t: i64 = load64(ys + 0);
    let e: i64 = o - t;
    return nn_fmul(e, e);
}

fn check(n: i64) -> i64 {
    let s: i64 = 0;
    let corr: i64 = 0;
    while s < 4 {
        nnad_forward(n, &X + s * 16);
        let nl: i64 = nn_nl(n);
        let yv: i64 = nn_to_milli(load64(nn_aref(n, nl - 1, 0)));
        let tv: i64 = nn_to_milli(load64(&Y + s * 8));
        print_i64(nn_to_milli(load64(&X + s * 16)));
        print(" xor ");
        print_i64(nn_to_milli(load64(&X + s * 16 + 8)));
        print(" -> ");
        print_i64(yv);
        print("  (want ");
        print_i64(tv);
        print(")\n");
        if yv > 500 { if tv > 500 { corr = corr + 1; } } else { if tv < 500 { corr = corr + 1; } }
        s = s + 1;
    }
    return corr;
}
