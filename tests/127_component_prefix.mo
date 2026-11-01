# 测试：component prefix 属性（num 值前缀渲染 "¥38"）
import "uic.mo";
import "str.mo";

component Pay {
    item: text width 6;
    amt: num width 10 prefix "¥";
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Pay_set_item("latte");
    Pay_set_amt(38);
    Pay_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
