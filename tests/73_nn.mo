# 70 —— 神经网络库（定点基础 + 手工权重前向）
#
# 为什么用**手工权重**而不是训练结果做断言：训练结果依赖随机初始化，
# 会漂；手工权重能精确验证"加权求和 → 激活"这条链路确实按定点规则在跑。
import "nn.mo";

var SZ: [2] i64 = 0;
var IN: [2] i64 = 0;

fn main() -> i64 {
    # 定点乘法：0.5 * 0.5 = 0.25
    if nn_fmul(32768, 32768) != 16384 { print("FAIL fmul\n"); return 1; }
    # 定点除法：1 / 4 = 0.25
    if nn_fdiv(65536, 262144) != 16384 { print("FAIL fdiv\n"); return 1; }

    # sigmoid(0) = 0.5
    let s: i64 = nn_sigmoid(0);
    if s < 32700 { print("FAIL sigmoid low\n"); return 1; }
    if s > 32800 { print("FAIL sigmoid high\n"); return 1; }

    # tanh(0) = 0；tanh 大正数应饱和到 1
    if nn_tanh(0) != 0 { print("FAIL tanh0\n"); return 1; }
    if nn_tanh(655360) < 65000 { print("FAIL tanh sat\n"); return 1; }

    # ReLU：负数归零
    if nn_relu(65536) != 65536 { print("FAIL relu pos\n"); return 1; }
    if nn_relu(-65536) != 0 { print("FAIL relu neg\n"); return 1; }

    # 定点开方：sqrt(4) = 2
    if nn_fsqrt(262144) != 131072 { print("FAIL fsqrt\n"); return 1; }

    # 2→1 线性网络： w = [0.5, 0.5], b = 0，输入 (1,1) → 1.0
    store64(&SZ + 0, 2);
    store64(&SZ + 8, 1);
    let net: i64 = nn_new(SZ, 2);
    if net == 0 { print("FAIL nn_new\n"); return 1; }
    nn_set_act(net, 1, 0);
    nn_set_w(net, 1, 0, 0, 32768);
    nn_set_w(net, 1, 0, 1, 32768);
    nn_set_b(net, 1, 0, 0);
    store64(&IN + 0, 65536);
    store64(&IN + 8, 65536);
    nn_forward(net, IN);
    let o: i64 = nn_out(net, 0);
    if o < 65000 { print("FAIL fwd low: "); print_i64(o); print("\n"); return 1; }
    if o > 66100 { print("FAIL fwd high: "); print_i64(o); print("\n"); return 1; }

    print("nn ok\n");
    return 0;
}
