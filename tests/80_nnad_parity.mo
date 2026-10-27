# 80 —— 自动微分驱动 nn.mo：与手写反向**逐轮等价**
#
# 这个测试的意义不只是"nnad 能训练"，而是：
#
#   **语言自动求出的梯度，与手写的梯度逐轮一致。**
#
# 相同的初始权重、相同数据、相同学习率，每步比对 loss。
# 任何一点梯度算错，loss 立刻分岔。
import "nnad.mo";

var PX: [8] i64 = 0;
var PY: [4] i64 = 0;

fn init_data() -> i64 {
    store64(&PX + 0, 0);       store64(&PX + 8, 0);        store64(&PY + 0, 0);
    store64(&PX + 16, 0);      store64(&PX + 24, 65536);   store64(&PY + 8, 65536);
    store64(&PX + 32, 65536);  store64(&PX + 40, 0);       store64(&PY + 16, 65536);
    store64(&PX + 48, 65536);  store64(&PX + 56, 65536);   store64(&PY + 24, 0);
    return 0;
}

fn mknet() -> i64 {
    let sizes: [3] i64 = 0;
    store64(&sizes + 0, 2);
    store64(&sizes + 8, 4);
    store64(&sizes + 16, 1);
    let n: i64 = nn_new(&sizes, 3);
    nn_set_act(n, 1, 3);
    nn_set_act(n, 2, 2);
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
    copy_w(a, b);

    let lr: i64 = 32768;
    let ep: i64 = 0;
    while ep < 150 {
        let s: i64 = 0;
        while s < 4 {
            let la: i64 = nn_train(a, &PX + s * 16, &PY + s * 8, lr);
            let lb: i64 = nnad_train(b, &PX + s * 16, &PY + s * 8, lr);
            let d: i64 = la - lb;
            if d < 0 { d = 0 - d; }
            if d > 2 { return 1; }        # 分岔
            s = s + 1;
        }
        ep = ep + 1;
    }

    # 两边都应解出 XOR，且**预测值完全相同**
    let s2: i64 = 0;
    while s2 < 4 {
        nn_forward(a, &PX + s2 * 16);
        nnad_forward(b, &PX + s2 * 16);
        let va: i64 = load64(nn_aref(a, 2, 0));
        let vb: i64 = load64(nn_aref(b, 2, 0));
        let d2: i64 = va - vb;
        if d2 < 0 { d2 = 0 - d2; }
        if d2 > 2 { return 1; }
        let tv: i64 = load64(&PY + s2 * 8);
        let ma: i64 = nn_to_milli(va);
        if ma > 500 { if tv < 500 { return 1; } } else { if tv > 500 { return 1; } }
        s2 = s2 + 1;
    }
    return 0;
}
