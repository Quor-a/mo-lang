import "io.mo";
fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}
fn main() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        print_i64(fib(i));
        print(" ");
        i = i + 1;
    }
    print("\n");
    return 0;
}
