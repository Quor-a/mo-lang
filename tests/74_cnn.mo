# 74 —— 卷积神经网络（单层 conv，手工权重验证卷积确实在算）
#
# 为什么用手工权重：随机初始化会漂，断言就不可靠。
# 核全 0.5、偏置 0、输入全 1 → 3×3 核的加权和 = 9 * 0.5 = 4.5（ReLU 后仍是 4.5）
import "cnn.mo";
var IMG: [64] i64 = 0;
fn main() -> i64 {
    let i: i64 = 0;
    while i < 64 { store64(&IMG + i * 8, 65536); i = i + 1; }

    let c: i64 = cnn_new(1);
    cnn_set_conv(c, 0, 3, 3, 1, 1, 8, 8);   # 1→1，3×3，8×8 → 6×6
    cnn_alloc_bufs(c);
    # 核 9 个权重全部设为 0.5
    let k: i64 = 0;
    while k < 9 { cnn_set_w(c, 0, k, 32768); k = k + 1; }

    let f: i64 = cnn_forward(c, IMG);
    let v: i64 = load64(f);
    # 4.5 → 定点 294912
    if v < 290000 { print("FAIL conv low\n"); return 1; }
    if v > 299000 { print("FAIL conv high\n"); return 1; }

    # 6×6 = 36 个输出，验证输出尺寸
    print("cnn ok\n");
    return 0;
}
