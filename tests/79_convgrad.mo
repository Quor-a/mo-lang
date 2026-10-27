# 79 —— 卷积与池化的自动梯度（对已知解析解）
#
# 3×3 卷积核全 1，输入 3×3 全 1 → 输出 1×1 = 9
# dOut=1 时：dK 每个元素 = 对应输入 = 1（9 个）
#            dIn 每个元素 = 对应核 = 1（9 个）
import "autodiff.mo";

fn main() -> i64 {
    let one: i64 = nn_from_i(1);

    # ---- conv 前向 ----
    ad_reset();
    let inp: i64 = ad_block(9);
    let i: i64 = 0;
    while i < 9 { ad_set(inp + i, one); i = i + 1; }
    let k: i64 = ad_wblock(9);
    i = 0;
    while i < 9 { ad_set(k + i, one); i = i + 1; }
    let o: i64 = ad_conv(inp, k, 3, 3);
    # 输出 1×1 = 9.0
    if ad_val(o) - nn_from_i(9) > 4 { return 1; }
    if nn_from_i(9) - ad_val(o) > 4 { return 1; }

    # ---- conv 反向 ----
    ad_backward(o);
    # dK 全 1
    i = 0;
    while i < 9 {
        if ad_grad(k + i) - one > 2 { return 1; }
        if one - ad_grad(k + i) > 2 { return 1; }
        i = i + 1;
    }
    # dIn 全 1
    i = 0;
    while i < 9 {
        if ad_grad(inp + i) - one > 2 { return 1; }
        if one - ad_grad(inp + i) > 2 { return 1; }
        i = i + 1;
    }

    # ---- 非对称核：验证位置对应正确 ----
    # 核 = [[1,0,0],[0,0,0],[0,0,0]]，输入全 1 → 输出 = 1
    ad_reset();
    let i2: i64 = ad_block(9);
    i = 0;
    while i < 9 { ad_set(i2 + i, one); i = i + 1; }
    let k2: i64 = ad_wblock(9);
    i = 0;
    while i < 9 { ad_set(k2 + i, 0); i = i + 1; }
    ad_set(k2, one);
    let o2: i64 = ad_conv(i2, k2, 3, 3);
    if ad_val(o2) - one > 2 { return 1; }
    if one - ad_val(o2) > 2 { return 1; }
    ad_backward(o2);
    # dK[i][j] = gy · input[i][j] —— **与核值无关**，输入全 1 所以 dK 全 1。
    # 我第一版断言写成"只有 (0,0) 为 1"，那是把 dK 和 dIn 搞混了：
    #   dK  取决于输入（全 1 → 全 1）
    #   dIn 取决于核（只有 (0,0)=1 → 只有 (0,0) 为 1）
    # 这个错误是隔离测试打印实际值才发现的。
    let j2: i64 = 0;
    while j2 < 9 {
        if ad_grad(k2 + j2) - one > 2 { return 1; }
        if one - ad_grad(k2 + j2) > 2 { return 1; }
        j2 = j2 + 1;
    }
    # dIn 只有 (0,0) 为 1
    if ad_grad(i2) - one > 2 { return 1; }
    if ad_grad(i2 + 1) != 0 { return 1; }
    if ad_grad(i2 + 8) != 0 { return 1; }

    # ---- pool 前向 + 反向 ----
    # 输入 2×2 = [1, 5, 3, 2] → max = 5，位置 1
    ad_reset();
    let p: i64 = ad_block(4);
    ad_set(p + 0, one);
    ad_set(p + 1, nn_from_i(5));
    ad_set(p + 2, nn_from_i(3));
    ad_set(p + 3, nn_from_i(2));
    let po: i64 = ad_pool(p, 2, 2);
    if ad_val(po) - nn_from_i(5) > 2 { return 1; }
    if nn_from_i(5) - ad_val(po) > 2 { return 1; }
    ad_backward(po);
    # 只有位置 1 拿到梯度
    if ad_grad(p + 0) != 0 { return 1; }
    if ad_grad(p + 1) - one > 2 { return 1; }
    if one - ad_grad(p + 1) > 2 { return 1; }
    if ad_grad(p + 2) != 0 { return 1; }
    if ad_grad(p + 3) != 0 { return 1; }

    return 0;
}
