# 测试：component title 属性（grid 顶部标题行 + sep 表格）
import "uic.mo";
import "str.mo";

component Host rows 2 sep title "Server List" {
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
