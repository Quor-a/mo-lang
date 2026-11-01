# 测试：component on_hover 回调（悬停触发器，text 字段传 &数组）
import "uic.mo";
import "str.mo";

component Cell {
    id: text width 6 on_hover show;
}

var shown: i64 = 0;

fn show(v: ptr) -> i64 {
    shown = shown + 1;
    return 0;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Cell_set_id("c1");
    Cell_hover_id();
    Cell_hover_id();
    print_i64(shown);
    print("\n");
    uc_render();
    return 0;
}
