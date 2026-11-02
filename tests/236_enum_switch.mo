# expect: 22
# enum 类型变量进 switch 判别（v1.1057）
enum Color { RED; GREEN; BLUE; }
fn main() -> i64 {
    let c: Color = GREEN;
    switch (c) {
        case RED: return 1;
        case GREEN: return 22;
        case BLUE: return 3;
    }
    return 0;
}
