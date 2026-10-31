# 测试：component gauge 字段类型（块字符仪表渲染）
import "uic.mo";
import "str.mo";

component Cpu {
    core: text width 8;
    load: gauge width 14;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Cpu_set_core("cpu0");
    Cpu_set_load(45);
    Cpu_row(1, 2, UC_WHITE, UC_BLUE);
    Cpu_set_load(90);
    Cpu_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
