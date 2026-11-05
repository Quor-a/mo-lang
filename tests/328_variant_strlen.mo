# expect: 10
import "str.mo";
enum Sh { Circle(i64); Unit; }
fn area(s: Sh) -> i64 {
    match s {
        Circle(r) => { return r * strlen("ab"); }
        Unit => { return 0; }
    }
}
fn main() -> i64 {
    return area(Sh.Circle(5));
}
