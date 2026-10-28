# 101 —— lib/uic.mo 字符画布库
# 用画布原语绘制一个简单窗口，验证库可编译可运行。
# 期望退出码 0。
import "uic.mo";

fn main() -> i64 {
    uc_init(40, 10);
    uc_clear(UC_WHITE, UC_BLUE);
    uc_rect(0, 0, 40, 10, '+', UC_CYAN, UC_BLUE);
    uc_text(2, 1, "Hello Canvas", UC_YELLOW, UC_BLUE);
    uc_fill(1, 3, 20, 1, '=', UC_GREEN, UC_WHITE);
    uc_hline(1, 30, 5, '-', UC_RED, UC_WHITE);
    uc_vline(35, 1, 8, '|', UC_RED, UC_WHITE);
    uc_render();
    return 0;
}