# examples/uic_cmd.mo —— 命令面板示例
# 用画布组件组合一个命令面板：
# 搜索框 + 命令列表 + 快捷键提示。
# 展示墨语言画布标准库的交互式 UI 能力。
#
# 编译：./bin/moc examples/uic_cmd.mo uic_cmd.elf && ./uic_cmd.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(40, 12);
    uc_clear(UC_WHITE, UC_BLUE);

    # 命令面板窗口
    uc_window(3, 1, 34, 10, "Command Palette", UC_WHITE, UC_BLUE);

    # 搜索框
    uc_search_box(5, 3, 28, "open", 1, UC_WHITE, UC_BLUE);

    # 命令列表（列表项用 | 分隔）
    uc_listbox(5, 5, 30, "Open File|Open Project|Open Settings|Open Terminal", 0, UC_WHITE, UC_BLUE);

    # 快捷键提示
    uc_kbd(5, 10, "Ctrl", UC_YELLOW, UC_BLUE);
    uc_text(11, 10, "Open", UC_YELLOW, UC_BLUE);
    uc_kbd(17, 10, "Esc", UC_YELLOW, UC_BLUE);
    uc_text(23, 10, "Close", UC_YELLOW, UC_BLUE);

    uc_render();
    return 0;
}