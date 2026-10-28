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
    uc_line(1, 1, 10, 5, '*', UC_RED, UC_BLUE);
    uc_circle(20, 5, 3, 'O', UC_YELLOW, UC_BLUE);
    uc_tri(30, 1, 35, 5, 25, 5, '#', UC_GREEN, UC_BLUE);
    uc_sprite(2, 7, ".##.,#..#,####", UC_MAGENTA, UC_BLUE);
    uc_window(3, 12, 20, 6, " 窗口 ", UC_CYAN, UC_WHITE);
    uc_panel(30, 12, 20, 6, " 面板 ", UC_GREEN, UC_BLUE);
    uc_gauge(3, 19, 16, 60, UC_GREEN, UC_BLUE);
    uc_scrollbar(55, 12, 8, 40, 2, UC_YELLOW, UC_BLUE);
    uc_dump_text();
    uc_dump_file("/tmp/uic_dump_test.txt");
    uc_render();
    return 0;
}