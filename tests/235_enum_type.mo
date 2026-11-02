# expect: 4
# enum 名作类型（v1.1057）：let/全局 var/形参/返回类型等价 i64。
# c=BLUE(2) g=GREEN(1) d=pick(RED)=0+1=1 → 2+1+1=4
enum Color { RED; GREEN; BLUE; }
var g: Color;
fn pick(c: Color) -> Color {
    return c + 1;
}
fn main() -> i64 {
    let c: Color = BLUE;
    g = GREEN;
    let d: Color = pick(RED);
    return c + g + d;
}
