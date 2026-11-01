# 测试：spark 字段 hist N 历史走势模式（环形 push + 竖列块渲染）
import "uic.mo";
import "str.mo";

component Gr {
    tag: text width 6;
    load: spark width 10 hist 8;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Gr_set_tag("cpu");
    Gr_set_load(20);
    Gr_set_load(50);
    Gr_set_load(35);
    Gr_set_load(90);
    Gr_row(4, 6, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
