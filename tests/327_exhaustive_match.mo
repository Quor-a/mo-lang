# expect: 42
# v1.1144: match 穷尽性静态检查（缺臂编译报错 / _ 通配豁免）
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
    let q = Shape.Rect(5, 8);
    let a = area(q);
    print_i64(a);
    return (a + 2) % 256;
}
