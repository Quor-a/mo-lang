# 测试：align right 推广到 pct/delta 字段
import "uic.mo";
import "str.mo";

component Srv {
    node: text width 8;
    cpu: pct width 8 align right;
    load: delta width 8 align right;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Srv_set_node("a1");
    Srv_set_cpu(99);
    Srv_set_load(1200);
    Srv_row(1, 2, UC_WHITE, UC_BLUE);
    Srv_set_node("b2");
    Srv_set_cpu(5);
    Srv_set_load(-7);
    Srv_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
