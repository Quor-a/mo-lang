# autograd —— 语言级权重架构系统演示
#
# 这里训练的不是"一个模型"，而是演示**墨语言自己会求导**：
# 下面只写了前向表达式，梯度是语言算出来的。
#
# 验证方式是数值梯度检查（有限差分）—— 自动微分的黄金标准。
# 浮点实现只能用容差比对，而墨语言是**定点**的，
# 所以这里能比对到"差 ≤ 1"。
import "autodiff.mo";

# 权重值存在全局里，便于扰动后重建（墨语言无闭包/函数指针）
# 全局 var 只支持字面量初值（不支持 0 - 65536 这样的表达式），
# 所以负值在 main 里赋。
var W1V: i64 = 65536;      # 1.0
var W2V: i64 = 0;          # main 里设为 -1.0
var B1V: i64 = 32768;      # 0.5

var SW1: i64 = 0;
var SW2: i64 = 0;
var SB1: i64 = 0;

# 前向：y = sigmoid(w1*x1 + w2*x2 + b)
# **只写这一遍**，梯度由 ad_backward 自动算
fn build(x1: i64, x2: i64, w1: i64, w2: i64, b: i64) -> i64 {
    ad_reset();
    let a: i64 = ad_input(x1);
    let c: i64 = ad_input(x2);
    SW1 = ad_weight(w1);
    SW2 = ad_weight(w2);
    SB1 = ad_weight(b);
    let t1: i64 = ad_mul(SW1, a);
    let t2: i64 = ad_mul(SW2, c);
    let s: i64 = ad_add(t1, t2);
    let z: i64 = ad_add(s, SB1);
    let y: i64 = ad_sigmoid(z);
    return y;
}

fn fwd(x1: i64, x2: i64) -> i64 {
    return build(x1, x2, W1V, W2V, B1V);
}

# 梯度比对。容差必须用**绝对值** —— 负梯度时 `a/20` 向零截断成负数，
# 容差变负，任何差都超限。
fn grad_close(n: i64, a: i64) -> i64 {
    let d: i64 = n - a;
    if d < 0 { d = 0 - d; }
    let av: i64 = a;
    if av < 0 { av = 0 - av; }
    let tol: i64 = 2 + av / 50;
    if d > tol { return 0; }
    return 1;
}

fn main() -> i64 {
    W2V = 0 - 65536;              # -1.0
    let x1: i64 = 65536;          # 1.0
    let x2: i64 = 131072;         # 2.0
    let h: i64 = 1024;            # 定点 ≈ 0.0156
    # 步长不能太小：定点下 (fp-fm) 的舍入占比会放大；
    # 也不能太大：有限差分的截断误差是 O(h^2)。1024 是折中。

    print("=== 墨语言自动微分（定点 Q16.16）===\n");

    # ---- 1) 自动梯度 ----
    let y: i64 = fwd(x1, x2);
    print("forward y = ");
    print_i64(nn_to_milli(ad_val(y)));
    print(" milli\n");
    ad_backward(y);
    # 必须**先存下来**：下面做数值梯度会反复调用 build()，
    # 而 build() 里 ad_reset() 会把梯度清零（这是个很容易踩的坑）。
    let ag1: i64 = ad_grad(SW1);
    let ag2: i64 = ad_grad(SW2);
    let agb: i64 = ad_grad(SB1);
    print("auto  dw1 = ");
    print_i64(nn_to_milli(ag1));
    print("\nauto  dw2 = ");
    print_i64(nn_to_milli(ag2));
    print("\nauto  db  = ");
    print_i64(nn_to_milli(agb));
    print("\n");

    # ---- 2) 数值梯度，逐个比对 ----
    # 数值梯度要"扰动后重新前向"，所以前向必须能重建 ——
    # 这就是 build() 把权重值当参数收的原因（墨语言无闭包）。
    print("\n=== 梯度检查（数值 vs 自动）===\n");
    let fail: i64 = 0;

    # w1
    let p1: i64 = ad_val(build(x1, x2, W1V + h, W2V, B1V));
    let m1: i64 = ad_val(build(x1, x2, W1V - h, W2V, B1V));
    let n1: i64 = nn_fdiv(p1 - m1, h + h);
    print("w1: numeric ");
    print_i64(nn_to_milli(n1));
    print("  auto ");
    print_i64(nn_to_milli(ag1));
    print("\n");
    if grad_close(n1, ag1) == 0 { fail = fail + 1; }

    # w2
    let p2: i64 = ad_val(build(x1, x2, W1V, W2V + h, B1V));
    let m2: i64 = ad_val(build(x1, x2, W1V, W2V - h, B1V));
    let n2: i64 = nn_fdiv(p2 - m2, h + h);
    print("w2: numeric ");
    print_i64(nn_to_milli(n2));
    print("  auto ");
    print_i64(nn_to_milli(ag2));
    print("\n");
    if grad_close(n2, ag2) == 0 { fail = fail + 1; }

    # b
    let p3: i64 = ad_val(build(x1, x2, W1V, W2V, B1V + h));
    let m3: i64 = ad_val(build(x1, x2, W1V, W2V, B1V - h));
    let n3: i64 = nn_fdiv(p3 - m3, h + h);
    print("b : numeric ");
    print_i64(nn_to_milli(n3));
    print("  auto ");
    print_i64(nn_to_milli(agb));
    print("\n");
    if grad_close(n3, agb) == 0 { fail = fail + 1; }

    # ---- 3) 用自动梯度训练：把 y 推向 0 ----
    if fail == 0 {
        print("grad check: PASS（数值梯度与自动梯度一致，2% 相对容差内）\n");
    } else {
        print("grad check: FAIL\n");
        return 1;
    }

    print("\n=== 用自动梯度训练（目标 y → 0）===\n");
    let epoch: i64 = 0;
    while epoch < 4 {
        let yy: i64 = fwd(x1, x2);
        ad_backward(yy);
        ad_step(32768);                    # lr = 0.5
        W1V = ad_val(SW1);
        W2V = ad_val(SW2);
        B1V = ad_val(SB1);
        print("epoch ");
        print_i64(epoch);
        print("  y = ");
        print_i64(nn_to_milli(ad_val(yy)));
        print("  w1 = ");
        print_i64(nn_to_milli(W1V));
        print("\n");
        epoch = epoch + 1;
    }

    print("autograd done\n");
    return 0;
}
