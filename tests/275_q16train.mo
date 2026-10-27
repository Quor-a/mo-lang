import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var X1: [1] i64 = 0;
var Y1: [1] i64 = 0;
var W1: [1] i64 = 0;      # 初始 0.1
var B1: [1] i64 = 0;
var P1: [1] i64 = 0;      # pred
var GW1: [1] i64 = 0;
var GB1: [1] i64 = 0;
var GX1: [1] i64 = 0;
var S: [32] byte = 0;

fn main() -> i64 {
    W1[0] = 6553;            # 0.1
    B1[0] = 0;
    let lr: i64 = 3277;      # 0.05
    let step: i64 = 0;
    while step < 200 {
        X1[0] = 65536;       # x=1
        Y1[0] = 131072;      # want 2
        q16_linear(&P1, &X1, &W1, &B1, 1, 1);
        P1[0] = P1[0] - Y1[0];   # dL/dY = pred - want (MSE/n)
        q16_linear_bwd(&GW1, &GB1, &GX1, &X1, &W1, &P1, 1, 1);
        # dL/dy = 2(y-want)/n = (y-want)  （n=1, 2/n=2 → 简化 y-want 的 2 倍省略,用 1 倍也能收敛）
        q16_sgd_step(&W1, &GW1, 1, lr);
        q16_sgd_step(&B1, &GB1, 1, lr);
        step = step + 1;
    }
    X1[0] = 65536;
    q16_linear(&P1, &X1, &W1, &B1, 1, 1);
    f2sq16(&S, P1[0]);
    # 200 步 lr=0.05 单样本应收敛到 ~1.999 (一阶收敛)
    if P1[0] < 126000 || P1[0] > 136000 { print("fit="); print(&S); print("\n"); return 1; }
    print(&S);
    print("\nQ16TRAIN_OK\n");
    return 0;
}
