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
    uc_dump_html("/tmp/uic_dump_test.html");
    uc_layout_h(2, 21, 3, 8, 1, UC_GREEN, UC_BLUE);
    uc_layout_v(40, 20, 2, 3, 1, UC_YELLOW, UC_BLUE);
    uc_label(2, 23, "ON", UC_GREEN, UC_BLUE, 1);
    uc_chart(10, 24, "3,5,2", 4, UC_CYAN, UC_BLUE);
    uc_checkbox(20, 23, "记住", 1, UC_WHITE, UC_BLUE);
    uc_radio(30, 23, "A", 1, UC_WHITE, UC_BLUE);
    uc_input(2, 25, "admin", 8, UC_BLACK, UC_WHITE);
    uc_slider(20, 25, 14, 60, UC_YELLOW, UC_BLUE);
    uc_theme_dark();
    uc_apply_theme();
    uc_icon_check(2, 1, UC_GREEN, UC_BLUE);
    uc_icon_heart(8, 1, UC_RED, UC_BLUE);
    uc_icon_warn(14, 1, UC_YELLOW, UC_BLUE);
    uc_clear(196, 236);
    uc_text(2, 2, "256color", 196, 236);
    uc_text(2, 4, "Bold", UC_WHITE, UC_BLUE);
    uc_style_text(2, 4, "Bold", 1);
    uc_fill_circle(30, 3, 2, '#', UC_YELLOW, UC_BLUE);
    uc_polygon("5,8,7,4", "8,4,7,8", 4, '*', UC_GREEN, UC_BLUE);
    uc_progress_anim(20, 6, 16, 65, UC_GREEN, UC_BLUE);
    uc_digit2(20, 8, 12, UC_YELLOW, UC_BLUE);
    uc_text(5, 2, "MoveMe", UC_YELLOW, UC_BLUE);
    uc_scroll(1, 1, 32, UC_WHITE, UC_BLUE);
    uc_copy(5, 2, 4, 1);
    uc_paste(15, 2);
    uc_text(5, 3, "AB", UC_YELLOW, UC_BLUE);
    uc_flip_h();
    uc_render();
    return 0;
}