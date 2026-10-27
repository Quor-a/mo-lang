import "str.mo";
import "io.mo";
# expect: 0

var S: [32] byte = 0;

fn main() -> i64 {
    f2sq16(&S, 65536);            # 1.0
    if streq(&S, "1.0000") != 1 { print("f1:"); print(&S); print("\n"); return 1; }
    f2sq16(&S, 32768);            # 0.5
    if streq(&S, "0.5000") != 1 { print("f2:"); print(&S); print("\n"); return 1; }
    f2sq16(&S, 0 - 98304);        # -1.5
    if streq(&S, "-1.5000") != 1 { print("f3:"); print(&S); print("\n"); return 1; }
    f2sq16(&S, 0);                # 0
    if streq(&S, "0.0000") != 1 { print("f4:"); print(&S); print("\n"); return 1; }
    f2sq16(&S, 114688);           # 1.75
    if streq(&S, "1.7500") != 1 { print("f5:"); print(&S); print("\n"); return 1; }
    f2sq16(&S, 65623);            # 1.0013(四舍五入 65623*10000/65536=10013)
    if streq(&S, "1.0013") != 1 { print("f6:"); print(&S); print("\n"); return 1; }
    print("F2S_OK\n");
    return 0;
}
