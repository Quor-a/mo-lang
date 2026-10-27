import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var A: [4] i64 = 0;    # 2x2
var B: [4] i64 = 0;
var C: [4] i64 = 0;
var X: [2] i64 = 0;
var W: [4] i64 = 0;
var Bv: [2] i64 = 0;
var Y: [2] i64 = 0;
var WANT: [2] i64 = 0;
var S: [32] byte = 0;

fn main() -> i64 {
    # [[1,2],[3,4]]·[[5,6],[7,8]] = [[19,22],[43,50]]
    A[0] = 65536; A[1] = 131072; A[2] = 196608; A[3] = 262144;
    B[0] = 327680; B[1] = 393216; B[2] = 458752; B[3] = 524288;
    q16_mmul(&C, &A, &B, 2, 2, 2);
    f2sq16(&S, C[0]);
    if streq(&S, "19.0000") != 1 { print("mm0="); print(&S); print("\n"); return 1; }
    f2sq16(&S, C[3]);
    if streq(&S, "50.0000") != 1 { print("mm3="); print(&S); print("\n"); return 1; }
    # linear：W=[[1,0],[0,1]] 单位阵，b=[0.5,0]，x=[2,3] → y=[2.5,3]
    W[0] = 65536; W[1] = 0; W[2] = 0; W[3] = 65536;
    Bv[0] = 32768; Bv[1] = 0;
    X[0] = 131072; X[1] = 196608;
    q16_linear(&Y, &X, &W, &Bv, 2, 2);
    f2sq16(&S, Y[0]);
    if streq(&S, "2.5000") != 1 { print("y0="); print(&S); print("\n"); return 1; }
    f2sq16(&S, Y[1]);
    if streq(&S, "3.0000") != 1 { print("y1="); print(&S); print("\n"); return 1; }
    # mse：pred=[2.5,3] want=[2.5,3] → 0；差 0.5,0 → (0.25+0)/2=0.125
    WANT[0] = 131072; WANT[1] = 196608;
    if q16_mse(&Y, &Y, 2) != 0 { print("mse0\n"); return 1; }
    Y[0] = 65536;
    let m: i64 = q16_mse(&Y, &WANT, 2);
    f2sq16(&S, m);
    if streq(&S, "0.5000") != 1 { print("mse="); print(&S); print("\n"); return 1; }
    print("Q16MM_OK\n");
    return 0;
}
