# expect: 57
import "io.mo";
fn main() -> i64 {
    let x: i64 = 5;
    let a = match x { y if y > 3 => y * 10, _ => 0 };
    let b = match x { y if y > 9 => y * 10, _ => 7 };
    let c = match x { 5 => 100, z if z < 0 => z, _ => 1 };
    print_i64(a);
    print_i64(b);
    print_i64(c);
    return a + b + c - 100;
}
