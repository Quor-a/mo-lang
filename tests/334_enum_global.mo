# expect: 21
import "io.mo";
enum Sh { Circle(i64); Square(i64); }
var g: Sh;
fn make() -> Sh {
    return Sh.Circle(9);
}
fn main() -> i64 {
    let s: Sh = Sh.Circle(5);
    g = Sh.Square(7);
    let r: i64 = 0;
    match s {
        Circle(x) => { r = r + x; }
        Square(x) => { r = r + x; }
    }
    match g {
        Circle(x) => { r = r + x; }
        Square(x) => { r = r + x; }
    }
    let t: Sh = make();
    match t {
        Circle(x) => { r = r + x; }
        Square(x) => { r = r + x; }
    }
    return r;
}