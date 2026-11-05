# expect: 234
import "io.mo";
# v1.1142: enum 带数据变体（tagged union 构造）
enum Shape {
    Circle(f64);
    Rect(f64, f64);
}
enum Val {
    Num(i64);
    Str(str);
    Nothing;
}
fn main() -> i64 {
    let c = Shape.Circle(2.5);
    let r = Shape.Rect(3.0, 4.0);
    let n = Val.Num(42);
    let s = Val.Str("hi");
    let acc: i64 = 0;
    acc = acc + c.tag;
    acc = acc + r.tag * 10;
    acc = acc + (r._1 as i64) * 100;
    acc = acc + n.tag * 1000;
    acc = acc + (n._0 / 6) * 10000;
    acc = acc + s.tag * 100000;
    if s._0 == "hi" { acc = acc + 1000000; }
    print_i64(acc);
    print("\n");
    return acc;
}
