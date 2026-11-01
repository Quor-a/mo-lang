# 测试：component align right 属性（text 字段右对齐）
import "uic.mo";
import "str.mo";

component Tbl {
    city: text width 12 align right;
    pop: num width 8;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Tbl_set_city("Beijing");
    Tbl_set_pop(21540000);
    Tbl_row(1, 2, UC_WHITE, UC_BLUE);
    Tbl_set_city("Oslo");
    Tbl_set_pop(709000);
    Tbl_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
