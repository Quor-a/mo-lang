# 77 —— 语言级自动微分（用户只写前向，语言自动求导）
#
# 验证方式不是"能跑就行"，而是对**已知解析解**逐个核对：
#   y = w*x      →  dy/dw = x
#   y = a+b      →  dy/da = 1
#   y = w*w      →  dy/dw = 2w
#   y = relu(w)  →  w>0 时 1，w<0 时 0
import "autodiff.mo";

fn main() -> i64 {
    let one: i64 = nn_from_i(1);
    let two: i64 = nn_from_i(2);
    let three: i64 = nn_from_i(3);

    # y = w * x，dy/dw 应等于 x
    ad_reset();
    let x: i64 = ad_input(three);
    let w: i64 = ad_weight(two);
    let y: i64 = ad_mul(w, x);
    ad_backward(y);
    # dy/dw = 3.0 → 定点 196608
    let g: i64 = ad_grad(w);
    if g - 196608 > 2 { return 1; }
    if 196608 - g > 2 { return 1; }
    # dy/dx = w = 2.0 → 131072
    let gx: i64 = ad_grad(x);
    if gx - 131072 > 2 { return 1; }
    if 131072 - gx > 2 { return 1; }

    # y = w * w，dy/dw = 2w = 4.0 → 262144
    ad_reset();
    let w2: i64 = ad_weight(two);
    let y2: i64 = ad_mul(w2, w2);
    ad_backward(y2);
    let g2: i64 = ad_grad(w2);
    if g2 - 262144 > 4 { return 1; }
    if 262144 - g2 > 4 { return 1; }

    # y = a + a（同一槽被用两次），梯度应累加：dy/da = 2.0
    ad_reset();
    let a: i64 = ad_input(three);
    let y3: i64 = ad_add(a, a);
    ad_backward(y3);
    let g3: i64 = ad_grad(a);
    if g3 - 131072 > 2 { return 1; }
    if 131072 - g3 > 2 { return 1; }

    # relu：正值时梯度 1，负值时梯度 0
    ad_reset();
    let rp: i64 = ad_weight(one);
    let yp: i64 = ad_relu(rp);
    ad_backward(yp);
    if ad_grad(rp) - 65536 > 1 { return 1; }
    if 65536 - ad_grad(rp) > 1 { return 1; }

    ad_reset();
    let rn: i64 = ad_weight(0 - 65536);
    let yn: i64 = ad_relu(rn);
    ad_backward(yn);
    # relu 对负值输出 0，梯度必须也是 0
    if ad_grad(rn) != 0 { return 1; }

    # 权重数量：ad_weight 声明的才算
    ad_reset();
    let i1: i64 = ad_input(one);
    let q1: i64 = ad_weight(two);
    let q2: i64 = ad_weight(three);
    if ad_nweight() != 2 { return 1; }

    # ad_step 只更新权重，不动输入
    ad_reset();
    let iv: i64 = ad_input(one);
    let wv: i64 = ad_weight(two);
    let yv: i64 = ad_mul(wv, iv);
    ad_backward(yv);
    let before: i64 = ad_val(iv);
    ad_step(65536);                      # lr = 1.0
    if ad_val(iv) != before { return 1; }   # 输入不该被更新
    # w 从 2.0 减去 lr*grad = 1.0*1.0 = 1.0 → 应变成 1.0
    if ad_val(wv) - 65536 > 4 { return 1; }
    if 65536 - ad_val(wv) > 4 { return 1; }

    return 0;
}
