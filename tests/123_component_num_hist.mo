# 测试：num 字段 hist N 模式（历史均值 100..500 → 300）
import "uic.mo";
import "str.mo";

component Nh {
    id: text width 5;
    val: num width 12 hist 5;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Nh_set_id("a");
    Nh_set_val(100);
    Nh_set_val(200);
    Nh_set_val(300);
    Nh_set_val(400);
    Nh_set_val(500);
    Nh_row(2, 5, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
