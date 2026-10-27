# Leaky ReLU：梯度正确性 + 死权重复活
import "autodiff.mo";
import "assert.mo";

var W: [4] i64 = 0;
var T: [4] i64 = 0;
var SW: i64 = 0;
var SOUT: i64 = 0;

fn build(x: i64, t: i64) -> i64 {
    ad_reset();
    SW = ad_wblock(1);
    ad_set(SW, load64(&W + 0));
    let a: i64 = ad_block(1);
    ad_set(a, x);
    let z: i64 = ad_mul(SW, a);
    # 关键：z 恒为负（x<0 且 w>0），relu 下梯度被完全阻断
    let h: i64 = ad_lrelu(z);
    SOUT = h;
    let tg: i64 = ad_block(1);
    ad_set(tg, t);
    # 🔴 数值梯度自检**必须**用 ad_mse 而不是 ad_mse_half。
    # ad_mse_half 的 loss 报告为 Σe²/n，反向却用 (y-t)/n（对应 ½Σe²），
    # 差一个系数 2 —— 那是 1.36 为对齐 nn.mo 手写反向约定而有意为之的。
    # 拿它做数值自检必然差 2 倍，看起来像梯度错了。
    return ad_mse(h, tg, 1);
}

fn grad_close(a: i64, b: i64) -> i64 {
    let d: i64 = a - b;
    if d < 0 { d = 0 - d; }
    # 绝对容差 3 + 5% 相对
    let lim: i64 = 3;
    let m: i64 = b;
    if m < 0 { m = 0 - m; }
    lim = lim + m / 20;
    if d <= lim { return 1; }
    return 0;
}

fn main() -> i64 {
    print("=== Leaky ReLU ===\n");
    let fail: i64 = 0;

    # ---- 1) 正半轴：应与 relu 完全一致 ----
    store64(&W + 0, 65536);              # w = 1.0
    let Lp: i64 = build(65536, 0);       # z = 1.0 > 0
    ad_backward(Lp);
    let gp: i64 = ad_grad(SW);
    # dL/dw = 2·(h-t)·x = 2·1.0·1.0 = 2.0 → 定点 131072 → milli 2000
    print("正半轴 dL/dw = "); print_i64(nn_to_milli(gp)); print("  (期望 2000)\n");
    if grad_close(gp, 131072) == 0 { fail = fail + 1; print("  ✗ 应为 2.0\n"); }

    # ---- 2) 负半轴：应为 slope（1/16 = 0.0625） ----
    let Ln: i64 = build(0 - 65536, 0);   # z = -1.0
    ad_backward(Ln);
    let gn: i64 = ad_grad(SW);
    # 手推：z = w·x = -1.0；h = slope·z = -0.0625
    #   dL/dh = h - t = -0.0625
    #   dh/dz = slope = 1/16；dz/dw = x = -1.0
    #   dL/dw = (-0.0625)·(1/16)·(-1) = 0.00390625 → 定点 256 → milli 4
    # dL/dw = 2·(h-t)·slope·x = 2·(-0.0625)·(1/16)·(-1) = 0.0078125
    #       → 定点 512 → milli 8
    print("负半轴 dL/dw = "); print_i64(nn_to_milli(gn)); print("  (期望 8 = 0.0078)\n");
    if grad_close(gn, 512) == 0 { fail = fail + 1; print("  ✗ 负半轴梯度不对\n"); }
    else { print("  ✓ 负半轴有非零梯度（relu 下这里必然是 0）\n"); }

    # ---- 3) 与 relu 对照：relu 在负半轴梯度恒为 0 ----
    ad_slope(0);                          # slope=0 → 等价于 relu
    let Lr: i64 = build(0 - 65536, 0);
    ad_backward(Lr);
    let gr: i64 = ad_grad(SW);
    print("slope=0 时 dL/dw = "); print_i64(nn_to_milli(gr)); print("  (relu，期望 0)\n");
    if gr != 0 { fail = fail + 1; print("  ✗ slope=0 应完全阻断\n"); }
    else { print("  ✓ slope=0 退化为 relu，梯度为 0\n"); }
    ad_slope(4096);

    # ---- 4) 数值梯度交叉验证（负半轴） ----
    # 🔴 必须**先把自动梯度存下来**再做数值检查：数值检查要反复
    # build()，而 build() 里的 ad_reset() 会把梯度清零 —— 不报错，
    # 只是打印出 0。这个坑 1.34 踩过一次，这里又踩了。
    store64(&W + 0, 65536);
    let Lb: i64 = build(0 - 65536, 0);
    ad_backward(Lb);
    let an: i64 = ad_grad(SW);

    let h2: i64 = 512;
    let w0: i64 = load64(&W + 0);
    store64(&W + 0, w0 + h2); let lp: i64 = ad_val(build(0 - 65536, 0));
    store64(&W + 0, w0 - h2); let lm: i64 = ad_val(build(0 - 65536, 0));
    store64(&W + 0, w0);
    let num: i64 = nn_fdiv(lp - lm, h2 + h2);
    print("数值梯度 "); print_i64(nn_to_milli(num));
    print("  自动梯度 "); print_i64(nn_to_milli(an)); print("\n");
    if grad_close(num, an) == 0 { fail = fail + 1; print("  ✗ 数值/自动不一致\n"); }
    else { print("  ✓ 数值梯度与自动梯度一致\n"); }

    # ---- 5) 块级版本 ----
    let b: i64 = ad_block(3);
    ad_set(b + 0, 65536);
    ad_set(b + 1, 0 - 65536);
    ad_set(b + 2, 131072);
    let o: i64 = ad_vlrelu(b, 3);
    print("vlrelu([1,-1,2]) = ");
    print_i64(nn_to_milli(ad_val(o + 0))); print(" ");
    print_i64(nn_to_milli(ad_val(o + 1))); print(" ");
    print_i64(nn_to_milli(ad_val(o + 2))); print("\n");
    # [1.0, -0.0625, 2.0]
    if grad_close(ad_val(o + 0), 65536) == 0 { fail = fail + 1; }
    if grad_close(ad_val(o + 1), 0 - 4096) == 0 { fail = fail + 1; }
    if grad_close(ad_val(o + 2), 131072) == 0 { fail = fail + 1; }

    # ---- 6) 固化已知行为：ad_mse_half 的 loss 与梯度差系数 2 ----
    # 这是 1.36 为对齐 nn.mo 手写反向约定而有意为之的，不是 bug。
    # 但如果有人拿它做数值自检，会得到 2 倍偏差并误判"梯度错了"。
    # 这里把它固定下来：改了就会失败，提醒去看 docs/autodiff.md。
    let b2: i64 = ad_block(1);
    ad_set(b2, 65536);
    let t2: i64 = ad_block(1);
    ad_set(t2, 0);
    let Lh: i64 = ad_mse_half(b2, t2, 1);
    ad_backward(Lh);
    let gh: i64 = ad_grad(b2);
    # 自洽的 mse 会给 2.0（131072）；mse_half 只给 1.0（65536）
    if gh != 65536 { fail = fail + 1; print("  ✗ mse_half 的 1/2 梯度约定已改变\n"); }
    else { print("  ✓ mse_half 的 ½ 梯度约定已固化（数值自检请用 ad_mse）\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("lrelu: ALL PASS\n"); return 0; }
    return 1;
}
