# examples/uic_dclock.mo —— 动态数字时钟（实时刷新）
# 用墨语言画布标准库 + cstd 系统时间，每秒刷新显示当前时间。
# 按 Ctrl+C 退出（终端程序）。
#
# 编译：./bin/moc examples/uic_dclock.mo uic_dclock.elf && ./uic_dclock.elf

import "uic.mo";
import "cstd.mo";

fn main() -> i64 {
    let t: i64 = 0;
    let hh: i64 = 0;
    let mm: i64 = 0;
    let ss: i64 = 0;
    uc_init(40, 8);
    uc_theme_dark();
    uc_apply_theme();
    uc_text(12, 1, "实时时钟", UC_YELLOW, 0);
    uc_style_text(12, 1, "实时时钟", 1);
    uc_panel(6, 3, 28, 5, " TIME ", UC_CYAN, 0);
    while 1 == 1 {
        t = time_secs();
        # 北京时间 UTC+8
        t = t + 8 * 3600;
        hh = t % 86400 / 3600;
        mm = (t % 3600) / 60;
        ss = t % 60;
        # 绘制小时:分钟
        uc_digit2(9, 4, hh, UC_GREEN, 0);
        uc_set(17, 4, ':', UC_WHITE, 0);
        uc_digit2(19, 4, mm, UC_GREEN, 0);
        # 秒（小号）
        uc_digit2(28, 4, ss, UC_YELLOW, 0);
        # 日期（简单显示纪元日）
        uc_text(10, 6, "Unix 秒: ", UC_WHITE, 0);
        uc_set(19, 6, 32, UC_WHITE, 0);
        # 渲染到固定区域（增量）
        uc_render_at(1, 1);
        sleep_ms(1000);
    }
    return 0;
}