# 测试：component min/max 属性（setter 钳制 500→90, -50→10, 42 不变）
import "uic.mo";
import "str.mo";

component Vol {
    id: text width 5;
    lvl: num width 8 min 10 max 90;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Vol_set_id("a");
    Vol_set_lvl(500);
    Vol_row(1, 2, UC_WHITE, UC_BLUE);
    Vol_set_lvl(-50);
    Vol_row(1, 3, UC_WHITE, UC_BLUE);
    Vol_set_lvl(42);
    Vol_row(1, 4, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
