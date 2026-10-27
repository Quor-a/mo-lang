import "io.mo";
import "sort.mo";
# expect: 0

fn addf(a: i64, b: i64) -> i64 { return a + b; }
fn mulf(a: i64, b: i64) -> i64 { return a * b; }

var B: [4] i64 = 0;

fn main() -> i64 {
    let r1: i64 = call2(&addf, 3, 4);
    if r1 != 7 { print("fail1="); print_i64(r1); print("\n"); return 1; }
    let r2: i64 = call2(&mulf, 6, 7);
    if r2 != 42 { print("fail2="); print_i64(r2); print("\n"); return 1; }
    B[0] = 3; B[1] = 1; B[2] = 2;
    qsort_cmp(&B, 3, &cmp_desc);
    if B[0] != 3 || B[1] != 2 || B[2] != 1 { print("fail sort\n"); return 1; }
    print("CALL2_OK\n");
    return 0;
}
