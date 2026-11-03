# expect: 53
import "io.mo";
fn main() -> i64 {
    # v1.1113: sub 常量折叠 + shl/sar xchg 路径
    let x: i64 = 20;
    let a: i64 = x - 7;         # sub rax,imm8 折叠
    let b: i64 = a - 100000;    # sub rax,imm32 折叠
    let c: i64 = (b + 100093) << 2;   # shl xchg 路径
    let d: i64 = c >> 3;        # sar xchg 路径
    print_i64(d);
    return d;
}
