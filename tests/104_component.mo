# 测试：编译器原生 component 展开（v1.941.0）
# 与 tests/103_comp_expand.mo 的手写模板对比，验证展开一致性
import "uic.mo";
import "str.mo";

component Task {
    name: text width 10;
    dur: num width 5;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Task_set_name("task-01");
    Task_set_dur(5);
    Task_row(1, 2, UC_WHITE, UC_BLUE);
    Task_set_name("task-02");
    Task_set_dur(12);
    Task_row(1, 3, UC_WHITE, UC_BLUE);
    Task_head(1, 1, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}