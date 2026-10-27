import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var S: [32] byte = 0;

fn main() -> i64 {
    if q16_mul(65536, 98304) != 98304 { print("m1\n"); return 1; }        # 1.0*1.5=1.5
    if q16_mul(32768, 32768) != 16384 { print("m2\n"); return 1; }        # 0.5*0.5=0.25
    if q16_div(98304, 65536) != 98304 { print("d1\n"); return 1; }        # 1.5/1.0
    if q16_div(65536, 32768) != 131072 { print("d2\n"); return 1; }       # 1.0/0.5=2.0
    if q16_div(65536, 0) != 0 { print("d3\n"); return 1; }                # 除零护栏
    if q16_abs(0 - 65536) != 65536 { print("a1\n"); return 1; }
    if q16_min(3, 5) != 3 || q16_max(3, 5) != 5 { print("mm\n"); return 1; }
    let sq: i64 = q16_sqrt(196608);                                        # sqrt(3)=1.7320..
    f2sq16(&S, sq);
    if streq(&S, "1.7321") != 1 { print("sq:"); print(&S); print("\n"); return 1; }
    print("Q16_OK\n");
    return 0;
}
