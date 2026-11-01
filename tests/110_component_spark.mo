# 测试：component spark 字段类型（迷你走势/负载条渲染）
import "uic.mo";
import "str.mo";

component Net {
    dev: text width 8;
    util: spark width 16;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Net_set_dev("eth0");
    Net_set_util(30);
    Net_row(1, 2, UC_WHITE, UC_BLUE);
    Net_set_util(80);
    Net_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
