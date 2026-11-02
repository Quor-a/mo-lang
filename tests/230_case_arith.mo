# expect: 3
# case 算术（v1.1051）：enum case 的 +/- 后缀折叠；const 名后缀（旧有）；括号乘除（v1.998）。
# c=RED=0 → (BLUE*2)-4 = 0 → 命中 → 3
enum Color { RED; GREEN; BLUE; }
const OFF: i64 = 10;
fn main() -> i64 {
    let c: i64 = RED;
    switch (c) {
        case RED + OFF: { return 1; }
        case (BLUE * 2) - 4: { return 3; }
    }
    return 9;
}
