# 测试：component pct 字段类型（百分比文本渲染）
import "uic.mo";
import "str.mo";

component Bat {
    id: text width 8;
    level: pct width 8;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Bat_set_id("bat1");
    Bat_set_level(85);
    Bat_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
