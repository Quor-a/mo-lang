import "io.mo";

fn addv(a: i64, b: i64) -> i64 {
    let s: i64 = a + b;
    return s;
}

fn main() -> i64 {
    let x: i64 = 3;
    let y: i64 = 4;
    let z: i64 = addv(x, y);
    print_i64(z);
    print_nl();
    return 0;
}
