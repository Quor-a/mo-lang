# expect: 42
# 组件 _init 自动调用（v1.1052）：首次 _row 前自动应用 default → T_n == 42。
import "uic.mo";
import "str.mo";
component T {
    n: num width 5 default 42;
}
fn main() -> i64 {
    uc_init(30, 5);
    T_row(0, 0, 7, 0);
    return T_n;
}
