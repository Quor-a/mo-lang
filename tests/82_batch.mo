# 82 —— batch 矩阵自动微分
#
# W = [[1,2],[3,4]]（2×2），X = [[1,0],[1,1]]（2 特征 × 2 样本）
#
# Z = W·X：
#   样本0: [1,1] → [3, 7]
#   样本1: [0,1] → [2, 4]
#
# loss = Z[0][0] + Z[0][1] = 3 + 2 = 5
#   dZ[0][0] = 1, dZ[0][1] = 1，其余 0
#   dW[0][0] = Σ_b dz[0][b]·X[0][b] = 1·1 + 1·0 = 1
#   dW[0][1] = Σ_b dz[0][b]·X[1][b] = 1·1 + 1·1 = 2
#   dW[1][*] = 0
import "autodiff.mo";

fn main() -> i64 {
    let one: i64 = nn_from_i(1);
    let two: i64 = nn_from_i(2);
    let three: i64 = nn_from_i(3);
    let four: i64 = nn_from_i(4);

    ad_reset();
    let w: i64 = ad_wblock(4);
    ad_set(w + 0, one);   ad_set(w + 1, two);
    ad_set(w + 2, three); ad_set(w + 3, four);

    # X 是 2 特征 × 2 样本：[feature][sample]
    let x: i64 = ad_block(4);
    ad_set(x + 0, one);   ad_set(x + 1, 0);      # feature 0: [1, 0]
    ad_set(x + 2, one);   ad_set(x + 3, one);    # feature 1: [1, 1]

    let z: i64 = ad_matmul_batch(w, x, 2, 2, 2);

    # 布局是**行主序** Z[i][b] = z + i*bs + b：
    #   z+0 = Z[0][0]=3   z+1 = Z[0][1]=2
    #   z+2 = Z[1][0]=7   z+3 = Z[1][1]=4
    # 我第一版把 z+1/z+2 的期望写反了（当成列主序），
    # 是隔离打印实际值才发现的。
    if ad_val(z + 0) - three > 4 { return 1; }
    if three - ad_val(z + 0) > 4 { return 1; }
    if ad_val(z + 1) - two > 4 { return 1; }
    if two - ad_val(z + 1) > 4 { return 1; }
    if ad_val(z + 2) - nn_from_i(7) > 8 { return 1; }
    if nn_from_i(7) - ad_val(z + 2) > 8 { return 1; }
    if ad_val(z + 3) - four > 8 { return 1; }
    if four - ad_val(z + 3) > 8 { return 1; }

    # 反向：loss = Z[0][0] + Z[0][1]（输出维 0 在全部样本上的和）
    let s: i64 = ad_add(z + 0, z + 1);
    ad_backward(s);

    # dW[0][0] = 1
    if ad_grad(w + 0) - one > 4 { return 1; }
    if one - ad_grad(w + 0) > 4 { return 1; }
    # dW[0][1] = 2
    if ad_grad(w + 1) - two > 4 { return 1; }
    if two - ad_grad(w + 1) > 4 { return 1; }
    # dW[1][*] = 0
    if ad_grad(w + 2) != 0 { return 1; }
    if ad_grad(w + 3) != 0 { return 1; }

    # ---- ad_matmul_at：Y = A·Bᵀ ----
    # A(1×2)=[1,2]，B(2×2)=[[1,0],[0,1]] → Y(1×2) = [1, 2]
    ad_reset();
    let a: i64 = ad_block(2);
    ad_set(a + 0, one);
    ad_set(a + 1, two);
    let b: i64 = ad_block(4);
    ad_set(b + 0, one);  ad_set(b + 1, 0);
    ad_set(b + 2, 0);    ad_set(b + 3, one);
    let y: i64 = ad_matmul_at(a, b, 1, 2, 2);
    if ad_val(y + 0) - one > 4 { return 1; }
    if ad_val(y + 1) - two > 4 { return 1; }
    # 从 Y[0][1] 反传：dA[1] = B[1][1] = 1
    ad_backward(y + 1);
    if ad_grad(a + 1) - one > 4 { return 1; }
    if one - ad_grad(a + 1) > 4 { return 1; }

    return 0;
}
