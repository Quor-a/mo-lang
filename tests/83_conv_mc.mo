# 83 —— 广播与多通道卷积
#
# 全 1 输入（1 通道 3×3）、全 1 核（1 个输出通道）→ 输出 1×1 = 9
#   dK 每个元素 = 对应输入 = 1
#   dIn 每个元素 = 1（一个核覆盖每个位置恰好一次）
#
# 广播：A(2×3) 全 0，b=[1,2]，loss = Σ out
#   db[0] = 3（三个样本各贡献 1）
#   db[1] = 3
import "autodiff.mo";

fn main() -> i64 {
    let one: i64 = nn_from_i(1);
    let two: i64 = nn_from_i(2);

    # ---- 多通道卷积：ci=1, co=1 ----
    ad_reset();
    let inp: i64 = ad_block(9);
    let i: i64 = 0;
    while i < 9 { ad_set(inp + i, one); i = i + 1; }
    let k: i64 = ad_wblock(9);
    i = 0;
    while i < 9 { ad_set(k + i, one); i = i + 1; }
    let o: i64 = ad_conv_mc(inp, k, 3, 3, 1, 1);
    if ad_val(o) - nn_from_i(9) > 4 { return 1; }
    if nn_from_i(9) - ad_val(o) > 4 { return 1; }
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

    # ---- 多通道：ci=2, co=1 ----
    # 两个通道全 1，核全 1 → 输出 = 9 + 9 = 18
    ad_reset();
    let i2: i64 = ad_block(18);
    i = 0;
    while i < 18 { ad_set(i2 + i, one); i = i + 1; }
    let k2: i64 = ad_wblock(18);
    i = 0;
    while i < 18 { ad_set(k2 + i, one); i = i + 1; }
    let o2: i64 = ad_conv_mc(i2, k2, 3, 3, 2, 1);
    if ad_val(o2) - nn_from_i(18) > 8 { return 1; }
    if nn_from_i(18) - ad_val(o2) > 8 { return 1; }
    ad_backward(o2);
    # dK 全 1（18 个）
    i = 0;
    while i < 18 {
        if ad_grad(k2 + i) - one > 2 { return 1; }
        if one - ad_grad(k2 + i) > 2 { return 1; }
        i = i + 1;
    }

    # ---- 多输出通道：ci=1, co=2，第二个核全 0 ----
    # 输出通道 0 = 9，通道 1 = 0
    ad_reset();
    let i3: i64 = ad_block(9);
    i = 0;
    while i < 9 { ad_set(i3 + i, one); i = i + 1; }
    let k3: i64 = ad_wblock(18);
    i = 0;
    while i < 9 { ad_set(k3 + i, one); i = i + 1; }
    i = 9;
    while i < 18 { ad_set(k3 + i, 0); i = i + 1; }
    let o3: i64 = ad_conv_mc(i3, k3, 3, 3, 1, 2);
    if ad_val(o3 + 0) - nn_from_i(9) > 4 { return 1; }
    if ad_val(o3 + 1) != 0 { return 1; }
    # 只从输出通道 0 反传
    ad_backward(o3 + 0);
    # 核后半（通道 1）梯度应为 0
    i = 9;
    while i < 18 { if ad_grad(k3 + i) != 0 { return 1; } i = i + 1; }
    # 核前半梯度为 1
    if ad_grad(k3) - one > 2 { return 1; }

    # ---- 广播 ----
    # A(2×3) 全 0，b=[1,2]
    ad_reset();
    let a: i64 = ad_block(6);
    i = 0;
    while i < 6 { ad_set(a + i, 0); i = i + 1; }
    let b: i64 = ad_wblock(2);
    ad_set(b + 0, one);
    ad_set(b + 1, two);
    let y: i64 = ad_vadd_bcast(a, b, 2, 3);
    # 前向：[1,1,1, 2,2,2]
    i = 0;
    while i < 3 {
        if ad_val(y + i) - one > 2 { return 1; }
        i = i + 1;
    }
    i = 3;
    while i < 6 {
        if ad_val(y + i) - two > 2 { return 1; }
        i = i + 1;
    }
    # loss = Σ 全部 6 个 = 1+1+1+2+2+2 = 9
    let acc: i64 = y + 0;
    i = 1;
    while i < 6 { acc = ad_add(acc, y + i); i = i + 1; }
    ad_backward(acc);
    # db[0] = 3（三个样本），db[1] = 3
    if ad_grad(b + 0) - nn_from_i(3) > 4 { return 1; }
    if nn_from_i(3) - ad_grad(b + 0) > 4 { return 1; }
    if ad_grad(b + 1) - nn_from_i(3) > 4 { return 1; }
    if nn_from_i(3) - ad_grad(b + 1) > 4 { return 1; }
    # dA 全 1
    i = 0;
    while i < 6 {
        if ad_grad(a + i) - one > 2 { return 1; }
        i = i + 1;
    }

    return 0;
}
