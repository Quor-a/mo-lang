# 测试：text 字段超宽截断（width 6 里放 7 字符 Beijing，截为 Beijin 不串列）
import "uic.mo";
import "str.mo";

component Tr {
    short: text width 6;
    after: text width 6;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Tr_set_short("Beijing");
    Tr_set_after("ok");
    Tr_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
