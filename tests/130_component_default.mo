# 测试：component default 属性（init 函数填充默认值 "node-a"/8080）
import "uic.mo";
import "str.mo";

component Cfg {
    name: text width 8 default "node-a";
    port: num width 6 default 8080;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Cfg_init();
    Cfg_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
