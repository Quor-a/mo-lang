# examples/uic_dashboard.mo —— 完整 TUI 仪表盘示例
# 用墨语言画布标准库（lib/uic.mo）组合出完整的文本应用界面：
# 菜单栏 + 数据窗口（表格）+ 图表窗口（条形图）+ 进度 + 状态栏。
#
# 这展示了"任何 UI、组件、图标、样式都能自己写出来"——
# 开发者用基本原语自由组合，想象力决定界面。
#
# 编译：./bin/moc examples/uic_dashboard.mo uic_dashboard.elf && ./uic_dashboard.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(72, 26);
    uc_clear(UC_WHITE, UC_BLUE);

    # 顶部菜单栏（白色背景，黑字）
    uc_fill(0, 0, 72, 1, 32, UC_BLACK, UC_WHITE);
    uc_text(1, 0, "文件", UC_BLACK, UC_WHITE);
    uc_text(7, 0, "编辑", UC_BLACK, UC_WHITE);
    uc_text(13, 0, "视图", UC_BLACK, UC_WHITE);
    uc_text(19, 0, "帮助", UC_BLACK, UC_WHITE);
    uc_text(60, 0, "Mo 仪表盘 v1.343", UC_MAGENTA, UC_WHITE);

    # 主标题
    uc_text(2, 2, "系统监控", UC_YELLOW, UC_BLUE);

    # 数据窗口（左侧）：表格
    uc_window(1, 3, 38, 12, " 进程 ", UC_CYAN, UC_WHITE);
    uc_text(3, 5, "PID", UC_BLACK, UC_BLUE);
    uc_text(10, 5, "名称", UC_BLACK, UC_BLUE);
    uc_text(22, 5, "CPU%", UC_BLACK, UC_BLUE);
    uc_text(3, 6, "1", UC_WHITE, UC_BLUE);
    uc_text(10, 6, "init", UC_WHITE, UC_BLUE);
    uc_text(22, 6, "0.1", UC_GREEN, UC_BLUE);
    uc_text(3, 7, "2", UC_WHITE, UC_BLUE);
    uc_text(10, 7, "kworker", UC_WHITE, UC_BLUE);
    uc_text(22, 7, "1.2", UC_GREEN, UC_BLUE);
    uc_text(3, 8, "3", UC_WHITE, UC_BLUE);
    uc_text(10, 8, "moapp", UC_WHITE, UC_BLUE);
    uc_text(22, 8, "45.3", UC_YELLOW, UC_BLUE);
    uc_text(3, 9, "4", UC_WHITE, UC_BLUE);
    uc_text(10, 9, "web", UC_WHITE, UC_BLUE);
    uc_text(22, 9, "8.7", UC_GREEN, UC_BLUE);

    # 图表窗口（右侧）：条形图
    uc_window(42, 3, 28, 12, " CPU 使用率 ", UC_GREEN, UC_WHITE);
    uc_chart(45, 12, "20,60,35,80,50,90,40,70", 7, UC_CYAN, UC_BLUE);

    # 底部状态栏（黄色背景）
    uc_fill(0, 24, 72, 2, 32, UC_BLACK, UC_YELLOW);
    uc_label(1, 25, "运行中", UC_GREEN, UC_YELLOW, 1);
    uc_text(14, 25, "CPU 45%", UC_BLACK, UC_YELLOW);
    uc_text(30, 25, "内存 2.1GB", UC_BLACK, UC_YELLOW);
    uc_text(48, 25, "F1 帮助", UC_BLACK, UC_YELLOW);

    uc_render();
    return 0;
}