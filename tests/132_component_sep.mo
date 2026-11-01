# 测试：component sep 属性（grid 行间 40 个 '-' 分隔线）
import "uic.mo";
import "str.mo";

component Host rows 3 sep {
    node: text width 8;
    ip: text width 10;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Host_set_node("a1");
    Host_set_ip("10.0.0.1");
    Host_grid(2, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
