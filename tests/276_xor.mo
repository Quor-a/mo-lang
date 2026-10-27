import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

# 2→4→1 网络。H=4。
var WX1: [8] i64 = 0;    # W1[4×2]
var BX1: [4] i64 = 0;
var WH1: [4] i64 = 0;    # W2[1×4]
var BH1: [1] i64 = 0;
var XI: [2] i64 = 0;
var Z1: [4] i64 = 0;     # 隐层线性
var H1: [4] i64 = 0;     # 隐层激活
var ZO: [1] i64 = 0;
var OO: [1] i64 = 0;     # 输出 sigmoid
var GW1: [8] i64 = 0;
var GB1: [4] i64 = 0;
var GWH: [4] i64 = 0;
var GBH: [1] i64 = 0;
var DH: [4] i64 = 0;     # 隐层梯度
var DO: [1] i64 = 0;
var S: [32] byte = 0;

var SEEDR: i64 = 12345;

fn rnd1000() -> i64 {
    # 简单 LCG，返回 ±0.05 量级的定点
    SEEDR = (SEEDR * 1103515245 + 12345) & 2147483647;
    let v: i64 = SEEDR % 6554;
    return v - 3277;
}

fn forward() -> i64 {
    q16_linear(&Z1, &XI, &WX1, &BX1, 2, 4);
    let i: i64 = 0;
    while i < 4 {
        H1[i] = q16_sigmoid(Z1[i]);
        i = i + 1;
    }
    q16_linear(&ZO, &H1, &WH1, &BH1, 4, 1);
    OO[0] = q16_sigmoid(ZO[0]);
    return 0;
}

fn train_sample(want: i64, lr: i64) -> i64 {
    forward();
    let dO: i64 = q16_mul(OO[0] - want, q16_mul(OO[0], 65536 - OO[0]));
    # 输出层
    q16_linear_bwd(&GWH, &GBH, &DH, &H1, &WH1, &DO, 4, 1);
    DO[0] = dO;
    # 修正:先置 DO 再 bwd——重算
    q16_linear_bwd(&GWH, &GBH, &DH, &H1, &WH1, &DO, 4, 1);
    let j: i64 = 0;
    while j < 4 {
        # DH[j] *= sigmoid'(Z1[j])
        DH[j] = q16_mul(DH[j], q16_mul(H1[j], 65536 - H1[j]));
        j = j + 1;
    }
    # 隐层梯度对 W1/B1:GW1[o][i]=DH[o]*XI[i]
    let o: i64 = 0;
    while o < 4 {
        GB1[o] = DH[o];
        let i2: i64 = 0;
        while i2 < 2 {
            GW1[o * 2 + i2] = q16_mul(DH[o], XI[i2]);
            i2 = i2 + 1;
        }
        o = o + 1;
    }
    q16_sgd_step(&WH1, &GWH, 4, lr);
    q16_sgd_step(&BH1, &GBH, 1, lr);
    q16_sgd_step(&WX1, &GW1, 8, lr);
    q16_sgd_step(&BX1, &GB1, 4, lr);
    return 0;
}

fn main() -> i64 {
    # 初始化（小随机）
    let i: i64 = 0;
    while i < 8 { WX1[i] = rnd1000(); i = i + 1; }
    i = 0;
    while i < 4 { WH1[i] = rnd1000(); i = i + 1; }
    let lr: i64 = 32768;   # 0.5
    let ep: i64 = 0;
    # XOR 四样本，1000 轮
    while ep < 3000 {
        XI[0] = 0; XI[1] = 0; train_sample(0, lr);
        XI[0] = 0; XI[1] = 65536; train_sample(65536, lr);
        XI[0] = 65536; XI[1] = 0; train_sample(65536, lr);
        XI[0] = 65536; XI[1] = 65536; train_sample(0, lr);
        ep = ep + 1;
    }
    # 验证
    XI[0] = 0; XI[1] = 0; forward();
    if OO[0] > 16384 { print("x00="); f2sq16(&S, OO[0]); print(&S); print("\n"); return 1; }
    XI[0] = 0; XI[1] = 65536; forward();
    if OO[0] < 49152 { print("x01="); f2sq16(&S, OO[0]); print(&S); print("\n"); return 1; }
    XI[0] = 65536; XI[1] = 0; forward();
    if OO[0] < 49152 { print("x10="); f2sq16(&S, OO[0]); print(&S); print("\n"); return 1; }
    XI[0] = 65536; XI[1] = 65536; forward();
    if OO[0] > 16384 { print("x11="); f2sq16(&S, OO[0]); print(&S); print("\n"); return 1; }
    print("XOR_OK\n");
    return 0;
}
