# expect: 1
# enum 限定名 Color.GREEN 表达式（回归确认）：1 + 0*10 = 1
enum Color { RED; GREEN; }
fn main() -> i64 {
    return Color.GREEN + Color.RED * 10;
}
