import "str.mo";
import "io.mo";
# expect: 0

var S: [32] byte = 0;

fn rt(q: i64) -> i64 {
    f2sq16(&S, q);
    return q16f2s(&S);
}

fn main() -> i64 {
    if q16f2s("1.75") != 114688 { print("p1\n"); return 1; }
    if q16f2s("-0.5") != 0 - 32768 { print("p2\n"); return 1; }
    if q16f2s("3") != 196608 { print("p3\n"); return 1; }
    if q16f2s("2.99999") != 196601 { print("p4\n"); return 1; }  # 截断到 2.9999
    # round-trip：f2sq16 → q16f2s 幂等（4 位小数内）
    if rt(65536) != 65536 { print("rt1\n"); return 1; }
    if rt(32768) != 32768 { print("rt2\n"); return 1; }
    if rt(0 - 98304) != 0 - 98304 { print("rt3\n"); return 1; }
    if rt(114685) != 114688 { print("rt4\n"); return 1; }  # 1.74998→1.7500→114688
    print("Q2S_OK\n");
    return 0;
}
