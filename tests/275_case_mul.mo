# expect: 3
# case 乘除折叠（v1.1092）：switch case 支持 * /（与 enum/const 原子组合）
enum Color { RED; GREEN; BLUE; }

fn main() -> i64 {
    let c: i64 = 2;
    let r: i64 = 0;
    switch (c) {
        case RED + 10: r = 1;
        case GREEN * 3: r = 2;
        case BLUE: r = 3;
    }
    return r;
}
