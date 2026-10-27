import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var IMG: [16] i64 = 0;   # 4x4
var K3: [9] i64 = 0;     # 3x3 恒等核
var CO: [4] i64 = 0;     # 2x2
var MP: [1] i64 = 0;
var S: [32] byte = 0;

fn main() -> i64 {
    # img[i][j] = i*4+j (0..15)
    let i: i64 = 0;
    while i < 16 { IMG[i] = i * 65536; i = i + 1; }
    # 恒等核：中心 1
    K3[0] = 0; K3[1] = 0; K3[2] = 0;
    K3[3] = 0; K3[4] = 65536; K3[5] = 0;
    K3[6] = 0; K3[7] = 0; K3[8] = 0;
    q16_conv2d(&CO, &IMG, &K3, 4, 4, 3, 3);
    # out[y][x] = img[y+1][x+1] = (y+1)*4+x+1 → 5,6,9,10
    f2sq16(&S, CO[0]);
    if streq(&S, "5.0000") != 1 { print("c0="); print(&S); print("\n"); return 1; }
    f2sq16(&S, CO[3]);
    if streq(&S, "10.0000") != 1 { print("c3="); print(&S); print("\n"); return 1; }
    # maxpool 2x2 on 2x2 out → max(5,6,9,10)=10
    q16_maxpool2(&MP, &CO, 2, 2);
    f2sq16(&S, MP[0]);
    if streq(&S, "10.0000") != 1 { print("mp="); print(&S); print("\n"); return 1; }
    print("Q16CV_OK\n");
    return 0;
}
