# 78 —— 矩阵自动微分：梯度对已知解析解
#
# y = W·x，W = [[1,2],[3,4]]，x = [1,1]
#   → y = [3, 7]
# L = y[0] 时：dW[0][*] = x = [1,1]，dx = W[0][*] = [1,2]
# L = y[1] 时：dW[1][*] = x = [1,1]，dx = W[1][*] = [3,4]
import "autodiff.mo";

fn main() -> i64 {
    let one: i64 = nn_from_i(1);
    let two: i64 = nn_from_i(2);
    let three: i64 = nn_from_i(3);
    let four: i64 = nn_from_i(4);

    # ---- y[0] ----
    ad_reset();
    let w: i64 = ad_wblock(4);
    ad_set(w + 0, one);
    ad_set(w + 1, two);
    ad_set(w + 2, three);
    ad_set(w + 3, four);
    let x: i64 = ad_block(2);
    ad_set(x + 0, one);
    ad_set(x + 1, one);
    let y: i64 = ad_matmul(w, x, 2, 2);

    # 前向值：y[0]=3, y[1]=7
    if ad_val(y + 0) - three > 2 { return 1; }
    if three - ad_val(y + 0) > 2 { return 1; }
    if ad_val(y + 1) - nn_from_i(7) > 4 { return 1; }
    if nn_from_i(7) - ad_val(y + 1) > 4 { return 1; }

    # 从 y[0] 反传
    ad_backward(y + 0);
    # dW[0][0] = x[0] = 1
    if ad_grad(w + 0) - one > 2 { return 1; }
    if one - ad_grad(w + 0) > 2 { return 1; }
    # dW[0][1] = x[1] = 1
    if ad_grad(w + 1) - one > 2 { return 1; }
    if one - ad_grad(w + 1) > 2 { return 1; }
    # dW[1][*] 应该是 0（y[0] 不依赖第二行）
    if ad_grad(w + 2) != 0 { return 1; }
    # dx[0] = W[0][0] = 1
    if ad_grad(x + 0) - one > 2 { return 1; }
    if one - ad_grad(x + 0) > 2 { return 1; }
    # dx[1] = W[0][1] = 2
    if ad_grad(x + 1) - two > 2 { return 1; }
    if two - ad_grad(x + 1) > 2 { return 1; }

    # ---- y[1] ----
    ad_reset();
    let w2: i64 = ad_wblock(4);
    ad_set(w2 + 0, one);
    ad_set(w2 + 1, two);
    ad_set(w2 + 2, three);
    ad_set(w2 + 3, four);
    let x2: i64 = ad_block(2);
    ad_set(x2 + 0, one);
    ad_set(x2 + 1, one);
    let y2: i64 = ad_matmul(w2, x2, 2, 2);
    ad_backward(y2 + 1);
    # dx[0] = W[1][0] = 3
    if ad_grad(x2 + 0) - three > 4 { return 1; }
    if three - ad_grad(x2 + 0) > 4 { return 1; }
    # dx[1] = W[1][1] = 4
    if ad_grad(x2 + 1) - four > 4 { return 1; }
    if four - ad_grad(x2 + 1) > 4 { return 1; }

    # ---- 权重块应全部可训练 ----
    if ad_nweight() != 4 { return 1; }

    return 0;
}
