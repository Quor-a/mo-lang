# 测试：component delta 字段类型（▲▼ 涨跌差值渲染）
import "uic.mo";
import "str.mo";

component Stk {
    sym: text width 6;
    chg: delta width 8;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Stk_set_sym("AAPL");
    Stk_set_chg(12);
    Stk_row(1, 2, UC_WHITE, UC_BLUE);
    Stk_set_chg(-7);
    Stk_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
