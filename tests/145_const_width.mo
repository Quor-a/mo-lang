# 测试：const 作 component 字段 width（v1.983）
# expect: 0
import "uic.mo";
import "str.mo";

const W: i64 = 8;
component Host rows 2 sep {
    node: text width W;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Host_set_node("a1");
    Host_grid(2, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
