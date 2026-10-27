import "io.mo";
# expect: 0

fn zero() -> i64 { return 99; }
fn inc(a: i64) -> i64 { return a + 1; }
fn addf(a: i64, b: i64) -> i64 { return a + b; }
fn add3(a: i64, b: i64, c: i64) -> i64 { return a + b * 10 + c * 100; }

fn main() -> i64 {
    if call0(&zero) != 99 { print("f0\n"); return 1; }
    if call1(&inc, 41) != 42 { print("f1\n"); return 1; }
    if call2(&addf, 3, 4) != 7 { print("f2\n"); return 1; }
    if call3(&add3, 2, 3, 4) != 432 { print("f3\n"); return 1; }
    print("CALLFAM_OK\n");
    return 0;
}
