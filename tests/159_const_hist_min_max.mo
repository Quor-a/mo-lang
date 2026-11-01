# expect: 0
# 测试：const 作 hist/min/max 属性（v1.997）
import "uic.mo";
import "str.mo";

const HB: i64 = 6;
const LO: i64 = 10;
const HI: i64 = 90;
component H rows 1 sep {
    t: spark width 10 hist HB min LO max HI;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    H_set_t(50);
    H_grid(1, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
