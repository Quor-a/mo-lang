# nnet.mo —— 用墨语言写的神经网络，解决 XOR
#
# XOR 是经典的**非线性可分**问题：单层网络（感知机）无论怎么训练都解不了，
# 必须有隐藏层。所以它是对"反向传播真的在工作"最有力的检验 ——
# 如果梯度算错、下标搞反，这里几乎必然收敛不了。
#
# 网络：2 → 4 → 1，隐藏层 tanh，输出层 sigmoid，MSE 损失 + SGD。
# 全程 Q16.16 定点，没有任何浮点。
import "nn.mo";

var X: [8] i64 = 0;   # 4 个样本 × 2 个输入
var Y: [4] i64 = 0;   # 4 个标签
var SZ: [3] i64 = 0;  # 层大小

fn setup() -> i64 {
    # 定点：0 → 0，1 → 65536
    store64(&X + 0,  0);      store64(&X + 8,  0);   # 0,0
    store64(&X + 16, 0);      store64(&X + 24, 65536); # 0,1
    store64(&X + 32, 65536);  store64(&X + 40, 0);   # 1,0
    store64(&X + 48, 65536);  store64(&X + 56, 65536); # 1,1

    store64(&Y + 0,  0);
    store64(&Y + 8,  65536);
    store64(&Y + 16, 65536);
    store64(&Y + 24, 0);

    store64(&SZ + 0, 2);
    store64(&SZ + 8, 4);
    store64(&SZ + 16, 1);
    return 0;
}

fn main() -> i64 {
    setup();
    print("XOR with a 2-4-1 network (Q16.16 fixed point, no FPU)\n\n");

    nn_srand(12345);
    let net: i64 = nn_new(SZ, 3);
    if net == 0 { print("nn_new failed\n"); return 1; }
    nn_set_act(net, 1, 3);      # 隐藏层 tanh
    nn_set_act(net, 2, 2);      # 输出层 sigmoid
    nn_rand_init(net);

    let lr: i64 = 32768;        # 0.5
    let epochs: i64 = 3000;
    let ep: i64 = 0;
    let loss: i64 = 0;

    while ep < epochs {
        let s: i64 = 0;
        while s < 4 {
            loss = nn_train(net, &X + s * 16, &Y + s * 8, lr);
            s = s + 1;
        }
        # 前三轮的 loss 逐字节与 Python 定点参考实现比对（tools/nnref.py）。
        # 这是唯一能验证反向传播是否真的正确的方式 —— 见 nn.mo 里的说明。
        if ep < 3 { print("epoch "); print_i64(ep); print("  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        if ep == 499 { print("epoch   500  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        if ep == 1499 { print("epoch  1500  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        if ep == 2999 { print("epoch  3000  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        ep = ep + 1;
    }

    print("\npredictions:\n");
    let s: i64 = 0;
    let ok: i64 = 0;
    while s < 4 {
        nn_forward(net, &X + s * 16);
        let p: i64 = nn_out(net, 0);
        let want: i64 = load64(&Y + s * 8);
        print("  ");
        print_i64(load64(&X + s * 16) / 65536);
        print(" xor ");
        print_i64(load64(&X + s * 16 + 8) / 65536);
        print(" -> ");
        print_i64(nn_to_milli(p));
        print("  (want ");
        print_i64(want / 65536);
        print(")\n");
        # 判定：以 0.5 为界
        let got: i64 = 0;
        if p > 32768 { got = 1; }
        if got == want / 65536 { ok = ok + 1; }
        s = s + 1;
    }

    print("\ncorrect: ");
    print_i64(ok);
    print(" / 4\n");
    if ok == 4 { print("XOR solved\n"); return 0; }
    print("not converged\n");
    return 1;
}
