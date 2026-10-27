import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var S: [32] byte = 0;
var XS: [3] i64 = 0;
var SM: [3] i64 = 0;

fn chk(q: i64, want: ptr, tag: ptr) -> i64 {
    f2sq16(&S, q);
    if streq(&S, want) != 1 { print("fail "); print(tag); print("="); print(&S); print("\n"); return 1; }
    return 0;
}

fn main() -> i64 {
    # sigmoid：σ(0)=0.5, σ(2)=0.8808, σ(-2)=0.1192
    if chk(q16_sigmoid(0), "0.5000", "sig0") != 0 { return 1; }
    if chk(q16_sigmoid(131072), "0.8808", "sig2") != 0 { return 1; }
    if chk(q16_sigmoid(0 - 131072), "0.1192", "sign2") != 0 { return 1; }
    # tanh：0→0, 1→0.7616
    if chk(q16_tanh(0), "0.0000", "t0") != 0 { return 1; }
    if chk(q16_tanh(65536), "0.7616", "t1") != 0 { return 1; }
    # relu / leaky
    if q16_relu(0 - 65536) != 0 { print("r1\n"); return 1; }
    if q16_relu(65536) != 65536 { print("r2\n"); return 1; }
    let lr: i64 = q16_leaky_relu(0 - 65536);
    if lr > 0 - 600 || lr < 0 - 700 { print("l1="); print_i64(lr); print("\n"); return 1; }  # ≈-655(舍入方向浮动±1)
    # softmax：[1,2,3] → [0.0900, 0.2447, 0.6652]
    XS[0] = 65536; XS[1] = 131072; XS[2] = 196608;
    q16_softmax1(&SM, 3, &XS);
    if chk(SM[0], "0.0900", "sm0") != 0 { return 1; }
    if chk(SM[1], "0.2447", "sm1") != 0 { return 1; }
    if chk(SM[2], "0.6652", "sm2") != 0 { return 1; }
    print("Q16ACT_OK\n");
    return 0;
}
