# examples/uic_files.mo —— 文件管理器 UI 示例
# 用画布组件组合一个迷你文件管理器：
# 面包屑导航 + 树形目录 + 文件表格 + 状态栏。
# 展示墨语言画布标准库的组合能力。
#
# 编译：./bin/moc examples/uic_files.mo uic_files.elf && ./uic_files.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(50, 16);
    uc_clear(UC_WHITE, UC_BLUE);
    # 面包屑导航
    uc_breadcrumb(1, 1, "Home|Documents|Work", 2, UC_WHITE, UC_BLUE);
    # 左侧目录树
    uc_text(2, 3, "Files", UC_YELLOW, UC_BLUE);
    uc_tree(2, 4, "src|  main.mo|  lib.mo|docs|README.md", UC_GREEN, UC_BLUE);
    # 右侧文件表格
    uc_table(18, 3, 10, "Name|Size", "main.mo|2KB;lib.mo|4KB;README|1KB", UC_WHITE, UC_BLUE);
    # 底部状态栏
    uc_status_bar(1, 14, 48, "3 files", 4, 5, 100, UC_WHITE, UC_BLUE);
    # 工具栏按钮
    uc_button(1, 12, 6, "打开", UC_GREEN, UC_BLUE, 0);
    uc_button(9, 12, 6, "复制", UC_CYAN, UC_BLUE, 0);
    uc_button(17, 12, 6, "删除", UC_RED, UC_BLUE, 0);
    uc_render();
    return 0;
}