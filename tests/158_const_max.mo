# expect: 0
# 测试：const 作 component gauge max 属性（v1.996）
import "uic.mo";
import "str.mo";

const MAXV: i64 = 200;
component H rows 1 sep {
    cpu: gauge width 10 max MAXV;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    H_set_cpu(100);
    H_grid(1, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
