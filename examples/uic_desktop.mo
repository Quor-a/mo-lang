# examples/uic_desktop.mo —— 桌面 UI 示例
# 用画布组件组合一个迷你桌面：任务栏 + 窗口 + 图标 + 状态栏。
# 展示墨语言画布标准库的组合能力。
#
# 编译：./bin/moc examples/uic_desktop.mo uic_desktop.elf && ./uic_desktop.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(50, 18);
    uc_clear(UC_WHITE, UC_BLUE);
    # 桌面背景（渐变）
    uc_gradient(1, 1, 48, 13, UC_WHITE, UC_BLUE);
    # 桌面图标
    uc_icon_folder(3, 2, UC_YELLOW, UC_BLUE);
    uc_text(2, 4, "Docs", UC_WHITE, UC_BLUE);
    uc_icon_file(3, 6, UC_CYAN, UC_BLUE);
    uc_text(2, 8, "File", UC_WHITE, UC_BLUE);
    # 打开一个窗口
    uc_window(12, 2, 24, 8, " 我的窗口 ", UC_CYAN, UC_BLUE);
    uc_text(14, 4, "这是墨语言画的窗口", UC_WHITE, UC_BLUE);
    uc_button(14, 6, 8, "OK", UC_GREEN, UC_BLUE, 1);
    # 任务栏
    uc_status_bar(1, 15, 48, "Mo Desktop", 5, 5, 80, UC_WHITE, UC_BLUE);
    # 开始按钮
    uc_button(1, 15, 10, "开始", UC_YELLOW, UC_BLUE, 1);
    uc_render();
    return 0;
}