# enum 名作类型（v1.1057）：let/全局 var/形参/返回类型等价 i64。
enum Color { RED; GREEN; BLUE; }
fn pick(c: Color) -> Color {
    if c == RED { return BLUE; }
    return GREEN;
}
fn main() -> i64 {
    let c: Color = GREEN;
    let d: Color = pick(c);
    return d;   # pick(GREEN): 非 RED → GREEN=1
}
