import "io.mo";
const N: i64 = 4;
var A: [2+3] i64 = 0;
var B: [10*2] i64 = 0;
var C: [1<<4] i64 = 0;
var E: [N*2][3] i64 = 0;
fn main() -> i64 {
    A[4] = 42; B[19] = 7; C[15] = 8; E[7][2] = 11;
    print_i64(A[4]); print(" ");
    print_i64(B[19]); print(" ");
    print_i64(C[15]); print(" ");
    print_i64(E[7][2]); print("\n");
    return 0;
}
