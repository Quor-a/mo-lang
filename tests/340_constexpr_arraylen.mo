import "io.mo";

# v1.1162: 数组长度接受任意常量表达式（数字算式 / const 名 / const fn 调用）
# expect: 145

const fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); }
const fn gcd2(a: i64, b: i64) -> i64 { if b == 0 { return a; } return gcd2(b, a % b); }
const N: i64 = 4;

var A: [2+3] i64 = 0;
var B: [10*2] i64 = 0;
var C: [1<<4] i64 = 0;
var D: [gcd2(48,18)] i64 = 0;
var E: [fact(5)] i64 = 0;
var F: [N] i64 = 0;
var G: [fact(N)+1] i64 = 0;
var H: [N*2][3] i64 = 0;
var I: [(2+3)*2] i64 = 0;

fn main() -> i64 {
    # s1..s9：各数组按权重 1..9 取值求和
    A[4] = 42; B[19] = 7; C[15] = 8; D[5] = 9; E[119] = 3;
    F[3] = 5; G[24] = 6; H[7][2] = 11; I[9] = 2;
    let s: i64 = 0;
    s = s + A[4] * 1;
    s = s + B[19] * 2;
    s = s + C[15] * 3;
    s = s + D[5] * 4;
    s = s + E[119] * 5;
    s = s + F[3] * 6;
    s = s + G[24] * 7;
    s = s + H[7][2] * 8;
    s = s + I[9] * 9;
    # s10：全部数组总槽数 mod 256（5+20+16+6+120+4+25+8+10=214），权重 10
    let t: i64 = 0;
    t = t + 5; t = t + 20; t = t + 16; t = t + 6; t = t + 120;
    t = t + 4; t = t + 25; t = t + 8; t = t + 10;
    s = s + (t % 256) * 10;
    print_i64(s); print("\n");
    return s % 256;
}
