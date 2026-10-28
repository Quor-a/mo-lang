# examples/uic_demo.mo —— 字符画布演示
# 用墨语言的画布标准库（lib/uic.mo）自由绘制任意界面：
# 窗口、图标、图形、进度、配色。
#
# 编译：./bin/moc examples/uic_demo.mo uic_demo.elf && ./uic_demo.elf

import "uic.mo";

fn main() -> i64 {
    # 初始化 60x24 画布，蓝色背景
    uc_init(60, 24);
    uc_clear(UC_WHITE, UC_BLUE);

    # 主窗口边框（青色）
    uc_rect(0, 0, 60, 24, '+', UC_CYAN, UC_BLUE);

    # 标题栏（黄色文本）
    uc_text(3, 0, " Mo 画布演示 ", UC_YELLOW, UC_BLUE);

    # 内部区域：白色背景的工作区
    uc_fill(1, 2, 58, 18, 32, UC_BLACK, UC_WHITE);

    # 图标：房子（红色）
    uc_text(3, 3, "/\\", UC_RED, UC_WHITE);
    uc_text(3, 4, "/  \\", UC_RED, UC_WHITE);
    uc_text(3, 5, "/----\\", UC_RED, UC_WHITE);
    uc_text(3, 6, "|    |", UC_RED, UC_WHITE);

    # 图标：心形（品红）
    uc_text(14, 3, " ** ** ", UC_MAGENTA, UC_WHITE);
    uc_text(14, 4, "*******", UC_MAGENTA, UC_WHITE);
    uc_text(14, 5, " ***** ", UC_MAGENTA, UC_WHITE);
    uc_text(14, 6, "  ***  ", UC_MAGENTA, UC_WHITE);
    uc_text(14, 7, "   *   ", UC_MAGENTA, UC_WHITE);

    # 文本标签
    uc_text(3, 10, "姓名:", UC_BLACK, UC_WHITE);
    uc_text(9, 10, "Tom", UC_GREEN, UC_WHITE);
    uc_text(3, 11, "年龄:", UC_BLACK, UC_WHITE);
    uc_text(9, 11, "20", UC_GREEN, UC_WHITE);

    # 按钮（绿色边框 + 黑色文字）
    uc_rect(3, 13, 12, 3, '#', UC_GREEN, UC_WHITE);
    uc_text(6, 14, "确定", UC_BLACK, UC_WHITE);

    # 按钮（红色边框）
    uc_rect(18, 13, 12, 3, '#', UC_RED, UC_WHITE);
    uc_text(21, 14, "取消", UC_BLACK, UC_WHITE);

    # 进度条（用字符块 █ 填充，仅演示，终端可能不支持；用 # 更通用）
    uc_text(3, 17, "进度:", UC_BLACK, UC_WHITE);
    uc_fill(9, 17, 20, 1, '=', UC_GREEN, UC_WHITE);
    uc_text(30, 17, "65%", UC_BLACK, UC_WHITE);

    # 底部状态栏（黄色背景）
    uc_fill(1, 21, 58, 2, 32, UC_BLACK, UC_YELLOW);
    uc_text(2, 22, "F1:帮助  F2:保存  F3:退出", UC_BLACK, UC_YELLOW);

    # 渲染到终端
    uc_render();
    return 0;
}