# cnn.mo —— 用卷积神经网络做 8×8 形状分类
#
# 架构（全 Q16.16 定点，无 FPU）：
#
#     8×8 → conv(1→4, 3×3) → ReLU → pool2 → conv(4→8, 3×3) → ReLU
#          → flatten(8) → [全连接 8-8-4] → sigmoid 输出
#
# 为什么用**合成**数据集而不是真实 MNIST：
#   1. 自包含 —— 没数据文件也能跑，测试可复现
#   2. 形状是确定的，Python 参考实现能生成完全一样的输入
#   3. 四类形状（横条/竖条/对角/边框）足以检验卷积与反传是否正确
#
# **conv 后面必须接 ReLU**：纯线性卷积堆叠起来仍然是线性的，
# 没有非线性 CNN 就退化成一个大线性模型。
import "cnn.mo";

var IMG: [512] i64 = 0;      # 8 个样本 × 64 像素
var TG:  [32]  i64 = 0;      # 8 个样本 × 4（one-hot）
var LBL: [8]   i64 = 0;      # 类别 0..3
var GRAD: [8]  i64 = 0;      # 展平向量的梯度（接回 CNN 用）
var FCSZ: [3]  i64 = 0;      # 全连接层大小

# 四类形状：横条 / 竖条 / 对角 / 边框
fn make(s: i64, kind: i64) -> i64 {
    let base: i64 = s * 64;
    let i: i64 = 0;
    while i < 64 { store64(&IMG + (base + i) * 8, 0); i = i + 1; }

    let y: i64 = 0;
    while y < 8 {
        let x: i64 = 0;
        while x < 8 {
            let v: i64 = 0;
            if kind == 0 {
                if y == 2 { v = 1; }
                if y == 3 { v = 1; }
            }
            if kind == 1 {
                if x == 2 { v = 1; }
                if x == 3 { v = 1; }
            }
            if kind == 2 {
                if y == x { v = 1; }
            }
            if kind == 3 {
                if y == 0 { v = 1; }
                if y == 7 { v = 1; }
                if x == 0 { v = 1; }
                if x == 7 { v = 1; }
            }
            store64(&IMG + (base + y * 8 + x) * 8, v * 65536);
            x = x + 1;
        }
        y = y + 1;
    }

    # 第二个同类样本加一点扰动，逼网络学"形状"而不是"背答案"
    if s % 2 == 1 {
        let k: i64 = 0;
        while k < 64 {
            let c: i64 = load64(&IMG + (base + k) * 8);
            store64(&IMG + (base + k) * 8, c - 16384);      # -0.25
            k = k + 1;
        }
    }

    store64(&LBL + s * 8, kind);
    let o: i64 = s * 4;
    let c: i64 = 0;
    while c < 4 {
        if c == kind { store64(&TG + (o + c) * 8, 65536); }
        else { store64(&TG + (o + c) * 8, 0); }
        c = c + 1;
    }
    return 0;
}

fn main() -> i64 {
    let s: i64 = 0;
    while s < 8 {
        make(s, s / 2);       # 每类 2 个样本
        s = s + 1;
    }

    print("CNN: 8x8 shape classification (Q16.16, no FPU)\n");
    print("  conv(1->4,3x3) -> relu -> pool2 -> conv(4->8,3x3) -> relu -> fc(8-8-4)\n\n");

    nn_srand(12345);

    let cnn: i64 = cnn_new(3);
    cnn_set_conv(cnn, 0, 3, 3, 1, 4, 8, 8);      # 1@8x8  -> 4@6x6
    cnn_set_pool(cnn, 1, 4, 6, 6);               # 4@6x6  -> 4@3x3
    cnn_set_conv(cnn, 2, 3, 3, 4, 8, 3, 3);      # 4@3x3  -> 8@1x1
    cnn_alloc_bufs(cnn);
    cnn_rand_init(cnn);

    store64(&FCSZ + 0, 8);
    store64(&FCSZ + 8, 8);
    store64(&FCSZ + 16, 4);
    let fc: i64 = nn_new(FCSZ, 3);
    nn_set_act(fc, 1, 3);        # 隐藏层 tanh
    nn_set_act(fc, 2, 2);        # 输出层 sigmoid
    nn_rand_init(fc);

    let lr: i64 = 32768;         # 0.5
    let epochs: i64 = 400;
    let ep: i64 = 0;
    let loss: i64 = 0;

    while ep < epochs {
        let k: i64 = 0;
        while k < 8 {
            let f: i64 = cnn_forward(cnn, &IMG + k * 64 * 8);
            nn_forward(fc, f);
            loss = nn_backward(fc, &TG + k * 4 * 8, lr);
            nn_input_grad(fc, GRAD);          # 展平段的梯度
            cnn_backward(cnn, GRAD, lr);      # 交回 CNN 继续反传
            k = k + 1;
        }
        if ep < 3 { print("epoch "); print_i64(ep); print("  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        if ep == 199 { print("epoch   200  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        if ep == 399 { print("epoch   400  loss "); print_i64(nn_to_milli(loss)); print("\n"); }
        ep = ep + 1;
    }

    print("\npredictions:\n");
    let k: i64 = 0;
    let ok: i64 = 0;
    while k < 8 {
        let f: i64 = cnn_forward(cnn, &IMG + k * 64 * 8);
        nn_forward(fc, f);
        let p: i64 = nn_argmax(fc);
        let want: i64 = load64(&LBL + k * 8);
        print("  sample ");
        print_i64(k);
        print("  pred ");
        print_i64(p);
        print("  want ");
        print_i64(want);
        if p == want { print("  ok\n"); ok = ok + 1; }
        else { print("  MISS\n"); }
        k = k + 1;
    }

    print("\ncorrect: ");
    print_i64(ok);
    print(" / 8\n");
    if ok == 8 { print("CNN solved\n"); return 0; }
    print("not converged\n");
    return 1;
}
