# 测试：component bar 字段类型（进度条渲染）
import "uic.mo";
import "str.mo";

component Job {
    name: text width 10;
    pct: bar width 12;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Job_set_name("sync-01");
    Job_set_pct(70);
    Job_row(1, 2, UC_WHITE, UC_BLUE);
    Job_set_pct(100);
    Job_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
