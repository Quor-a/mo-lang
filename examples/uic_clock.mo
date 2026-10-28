# examples/uic_clock.mo —— 数字时钟示例
# 用墨语言画布标准库绘制一个数字时钟界面：
# 点阵数字显示时间 + 日期 + 动态进度条。
#
# 编译：./bin/moc examples/uic_clock.mo uic_clock.elf && ./uic_clock.elf

import "uic.mo";

# 获取当前时间的全局缓冲（time.mo 或手动 syscall）
# 这里用简化：展示静态时钟（演示画布能力）
fn main() -> i64 {
    uc_init(50, 16);
    uc_theme_dark();
    uc_apply_theme();

    # 标题栏
    uc_text(15, 1, "数字时钟", UC_YELLOW, 0);
    uc_style_text(15, 1, "数字时钟", 1);

    # 时钟边框
    uc_panel(8, 3, 34, 8, " TIME ", UC_CYAN, 0);

    # 12:34 点阵数字
    uc_digit2(12, 5, 12, UC_GREEN, 0);
    uc_set(20, 5, ':', UC_WHITE, 0);
    uc_digit2(22, 5, 34, UC_GREEN, 0);

    # 秒（小号）
    uc_text(34, 7, "56", UC_YELLOW, 0);

    # 日期
    uc_text(10, 9, "2026-10-28", UC_WHITE, 0);

    # 动态进度条（模拟系统负载）
    uc_text(10, 12, "CPU:", UC_WHITE, 0);
    uc_progress_anim(15, 12, 20, 45, UC_GREEN, 0);

    # 状态
    uc_text(10, 14, "运行中", UC_GREEN, 0);
    uc_style_text(10, 14, "运行中", 1);

    uc_render();
    return 0;
}