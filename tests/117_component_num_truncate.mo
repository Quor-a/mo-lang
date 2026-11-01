# 测试：num/pct 字段超宽截断（123456789 在 width 5 里截为 12345 不串列）
import "uic.mo";
import "str.mo";

component Nt {
    id: text width 5;
    big: num width 5;
    pctv: pct width 5;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Nt_set_id("ab");
    Nt_set_big(123456789);
    Nt_set_pctv(123456789);
    Nt_row(1, 2, UC_WHITE, UC_BLUE);
    Nt_set_id("cd");
    Nt_set_big(42);
    Nt_set_pctv(7);
    Nt_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
