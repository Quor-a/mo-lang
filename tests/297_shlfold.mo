# expect: 32
import "io.mo";
fn main() -> i64 {
    # v1.1114: shl/sar 常量右值折叠 (imm8) + >63 回退
    let x: i64 = 3;
    let a: i64 = x << 4;        # 48
    let b: i64 = (0 - 64) >> 2; # -16
    let c: i64 = x << 70;       # 192 (cl mask 63)
    print_i64(a);
    print_i64(b);
    print_i64(c);
    # 48*80+32 = 3872; rc = 3872 & 255 = 32
    return a * 80 + 32;
}
