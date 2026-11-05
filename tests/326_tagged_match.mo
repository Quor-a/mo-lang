# expect: 54
# v1.1144: tagged-union 变体模式 match（数据变体绑定）
import "io.mo";
enum Shape {
    Circle(i64);
    Rect(i64, i64);
    Nothing;
}
fn area(s: Shape) -> i64 {
    match s {
        Circle(r) => { return 3 * r; }
        Rect(w, h) => { return w * h; }
        Nothing => { return 0; }
    }
}
fn main() -> i64 {
    let c = Shape.Circle(4);
    let q = Shape.Rect(6, 7);
    let a = area(c);
    let b = area(q);
    print_i64(a);
    print_i64(b);
    return (a + b) % 256;
}
