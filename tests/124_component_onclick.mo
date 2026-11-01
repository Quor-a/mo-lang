# 测试：component on_click 回调（字段触发器调用用户函数）
import "uic.mo";
import "str.mo";

component Btn {
    label: text width 8;
    hits: num width 6 on_click bump;
}

var bumps: i64 = 0;

fn bump(h: i64) -> i64 {
    bumps = bumps + 1;
    return 0;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Btn_set_label("go");
    Btn_set_hits(0);
    Btn_click_hits();
    Btn_click_hits();
    Btn_click_hits();
    print_i64(bumps);
    print("\n");
    uc_render();
    return 0;
}
