# 测试：component suffix 属性（num 值后缀渲染 "75kg"）
import "uic.mo";
import "str.mo";

component Wx {
    item: text width 6;
    wt: num width 10 suffix "kg";
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Wx_set_item("iron");
    Wx_set_wt(75);
    Wx_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
