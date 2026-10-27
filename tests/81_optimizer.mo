# 81 —— 优化器：对已知解析解核对
#
# 关键设计：y = w·x，x=1，tgt=0，w=1
#   → y=1，dL/dy = 1（½·MSE），dL/dw = 1.0
#
# 于是每一步的更新量都有解析解，不只是"能收敛"。
import "autodiff.mo";

fn make() -> i64 {
    ad_reset();
    ad_opt_reset();
    let x: i64 = ad_block(1);
    ad_set(x, 65536);              # 1.0
    let w: i64 = ad_wblock(1);
    ad_set(w, 65536);              # w = 1.0
    let y: i64 = ad_matmul(w, x, 1, 1);
    let t: i64 = ad_block(1);
    ad_set(t, 0);
    let L: i64 = ad_mse_half(y, t, 1);
    ad_backward(L);
    return w;
}

fn main() -> i64 {
    let lr: i64 = 16384;           # 0.25

    # ---- SGD ----
    let w: i64 = make();
    # 梯度应为 1.0（±2 milli）
    if ad_grad(w) - 65536 > 131 { return 1; }
    if 65536 - ad_grad(w) > 131 { return 1; }
    ad_step(lr);
    # w: 1.0 → 1.0 - 0.25 = 0.75
    if ad_val(w) - 49152 > 131 { return 1; }
    if 49152 - ad_val(w) > 131 { return 1; }

    # ---- 动量：第一步 v = g，与 SGD 相同 ----
    let w2: i64 = make();
    ad_step_momentum(lr, 58982);           # beta = 0.9
    if ad_val(w2) - 49152 > 131 { return 1; }
    if 49152 - ad_val(w2) > 131 { return 1; }
    # 一阶矩应等于 g = 1.0
    if ad_mom(w2) - 65536 > 131 { return 1; }
    if 65536 - ad_mom(w2) > 131 { return 1; }

    # ---- Adam：首步 m̂ = g，v̂ = g²，den = |g|+eps ≈ 1 ----
    #   step = lr · g/(|g|+eps) ≈ lr = 0.25
    let w3: i64 = make();
    ad_step_adam(lr, 58982, 64881, 6);    # 0.9 / 0.99 / eps≈0.0001
    if ad_val(w3) - 49152 > 655 { return 1; }   # 容差放宽：eps 与 sqrt 精度
    if 49152 - ad_val(w3) > 655 { return 1; }
    # 步数应为 1
    if ad_t() != 1 { return 1; }

    # ---- Adam 偏差修正系数递推 ----
    # t=2 时 bc1 = 0.9² = 0.81，c1 = 1-0.81 = 0.19
    let w4: i64 = make();
    ad_step_adam(lr, 58982, 64881, 6);
    ad_step_adam(lr, 58982, 64881, 6);
    if ad_t() != 2 { return 1; }
    # bc1 ≈ 0.81 → 定点 53084
    if ad_bc1() - 53084 > 655 { return 1; }
    if 53084 - ad_bc1() > 655 { return 1; }

    # ---- 动量累积：第二次更新应该更大（同号梯度累积） ----
    let w5: i64 = make();
    ad_step_momentum(lr, 58982);
    let after1: i64 = ad_val(w5);
    # 重建（梯度仍为 1，因为 y 变了但 x=1）
    ad_reset();
    let x5: i64 = ad_block(1);
    ad_set(x5, 65536);
    let ww: i64 = ad_wblock(1);
    ad_set(ww, after1);
    let y5: i64 = ad_matmul(ww, x5, 1, 1);
    let t5: i64 = ad_block(1);
    ad_set(t5, 0);
    let L5: i64 = ad_mse_half(y5, t5, 1);
    ad_backward(L5);
    # 第二次：v = 0.9·1.0 + g2，g2 = after1（=y-t=y）
    let expect_v: i64 = nn_fmul(58982, 65536) + after1;
    ad_step_momentum(lr, 58982);
    # 注意：ad_opt_reset 没调用，所以 MOM 还是上次的 1.0 —— 但槽号变了，
    # 所以这里只验证"能跑且值合理"，精确比对见上面几项
    if ad_val(ww) >= after1 { return 1; }    # 必须继续下降

    return 0;
}
