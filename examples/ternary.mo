# 三元运算符 cond ? a : b（v1.1069）
import "io.mo";

fn main() {
    let a: i64 = 7;
    print_i64(a > 5 ? 100 : 200);        # 100
    print("\n");
    print_i64((a == 7 ? 1 : 2) * 10);    # 10
    print("\n");
    let s: i64 = a > 9 ? 1 : a > 8 ? 2 : 3;   # 嵌套 → 3
    print_i64(s);
    print("\n");
}
