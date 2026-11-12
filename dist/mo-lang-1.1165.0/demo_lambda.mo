# demo: lambda expressions (v1.1165)
fn apply(f: ptr, x: i64) -> i64 {
    return f(x);
}

fn main() -> i64 {
    let dbl: ptr = fn(n: i64) -> i64 { return n * 2; };
    let a: i64 = apply(dbl, 21);
    let b: i64 = apply(fn(n: i64) -> i64 { return n + 1; }, 9);
    let c: i64 = apply(fn(n: i64) -> i64 { return n * 3; }, 4);
    return a + b + c;
}
