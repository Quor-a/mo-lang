# 100 —— lib/ui.mo 终端 UI 组件库
# 调用各组件函数，验证库可编译可运行（输出 ANSI 序列）。
# 期望退出码 0。
import "ui.mo";

fn main() -> i64 {
    ui_clear();
    ui_reset();
    ui_gotoxy(1, 1);
    ui_color(32, 40);
    ui_text(2, 1, "Hello UI");
    ui_num(3, 1, 42);
    ui_reset();
    ui_box(4, 1, 20, 5, "box");
    ui_button(6, 1, "OK");
    ui_progress(7, 1, 15, 50);
    ui_input(8, 1, 12, "user");
    ui_hline(10, 1, 20);
    ui_vline(1, 30, 5);
    ui_menu(12, 1, "new,open,save", 1);
    ui_reset();
    return 0;
}