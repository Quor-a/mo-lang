# 测试：delta 字段超宽截断（1234567 在 width 6 里截为 123456 不串列）
import "uic.mo";
import "str.mo";

component Dt {
    id: text width 4;
    d: delta width 6;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Dt_set_id("a");
    Dt_set_d(1234567);
    Dt_row(1, 2, UC_WHITE, UC_BLUE);
    Dt_set_id("b");
    Dt_set_d(-5);
    Dt_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
