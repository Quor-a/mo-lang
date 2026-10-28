# examples/uic_all.mo —— 画布标准库全功能演示
# 展示墨语言 UI 标准库的全部能力：图形、图标、组件、主题、256色、样式。
#
# 编译：./bin/moc examples/uic_all.mo uic_all.elf && ./uic_all.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(72, 26);
    uc_theme_dark();
    uc_apply_theme();

    # 图形区
    uc_text(2, 1, "图形:", UC_YELLOW, 0);
    uc_rect(2, 2, 12, 6, '+', UC_CYAN, 0);
    uc_circle(22, 4, 2, 'O', UC_GREEN, 0);
    uc_line(28, 2, 38, 7, '*', UC_RED, 0);
    uc_tri(44, 2, 50, 7, 38, 7, '#', UC_MAGENTA, 0);
    uc_fill_circle(60, 4, 2, 'o', UC_YELLOW, 0);

    # 图标区
    uc_text(2, 10, "图标:", UC_YELLOW, 0);
    uc_icon_check(2, 11, UC_GREEN, 0);
    uc_icon_cross(8, 11, UC_RED, 0);
    uc_icon_warn(14, 11, UC_YELLOW, 0);
    uc_icon_search(20, 11, UC_CYAN, 0);
    uc_icon_lock(26, 11, UC_MAGENTA, 0);
    uc_icon_heart(32, 11, UC_RED, 0);

    # 组件区
    uc_text(2, 14, "组件:", UC_YELLOW, 0);
    uc_window(2, 15, 20, 5, " 窗口 ", UC_CYAN, UC_WHITE);
    uc_checkbox(26, 15, "记住", 1, UC_WHITE, 0);
    uc_radio(34, 15, "A", 1, UC_WHITE, 0);
    uc_input(26, 17, "admin", 10, UC_BLACK, UC_WHITE);
    uc_slider(40, 17, 14, 60, UC_YELLOW, 0);

    # 256色 + 样式
    uc_text(2, 21, "256色:", UC_YELLOW, 0);
    uc_text(8, 21, "RED", 196, 0);
    uc_style_text(8, 21, "RED", 1);
    uc_text(14, 21, "BLUE", 21, 0);
    uc_text(22, 21, "粗体", UC_WHITE, 0);
    uc_style_text(22, 21, "粗体", 1);
    uc_text(28, 21, "下划线", UC_WHITE, 0);
    uc_style_text(28, 21, "下划线", 2);

    # 条形图
    uc_text(2, 23, "图表:", UC_YELLOW, 0);
    uc_chart(8, 25, "20,60,35,80,50", 3, UC_CYAN, 0);

    uc_render();
    return 0;
}