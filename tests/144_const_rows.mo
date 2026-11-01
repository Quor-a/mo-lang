# 测试：const 作 component rows（v1.982）
# expect: 0
import "uic.mo";
import "str.mo";

const ROWS: i64 = 3;
component Host rows ROWS sep {
    node: text width 8;
    load: pct width 5;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Host_set_node("a1");
    Host_set_load(50);
    Host_grid(2, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
