# expect: 3
# 裸 enum 成员作表达式（v1.1049）：let c = GREEN + 1; switch case 兜底 enum_value。
# c=GREEN+1=2 → case BLUE(=2) → 3
enum Color { RED; GREEN; BLUE; }
fn main() -> i64 {
    let c: i64 = GREEN + 1;
    switch (c) {
        case RED: { return 1; }
        case GREEN: { return 2; }
        case BLUE: { return 3; }
    }
    return 0;
}
