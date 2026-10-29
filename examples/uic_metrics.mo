# examples/uic_metrics.mo —— 指标监控面板示例
# 用画布组件组合一个实时指标监控面板：
# 统计卡片 + 仪表盘 + 柱状图 + 评分 + 状态栏。
# 展示墨语言画布标准库的数据可视化能力。
#
# 编译：./bin/moc examples/uic_metrics.mo uic_metrics.elf && ./uic_metrics.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(50, 18);
    uc_clear(UC_WHITE, UC_BLUE);
    # 标题
    uc_text(1, 1, "Server Metrics", UC_YELLOW, UC_BLUE);
    uc_separator(1, 2, 48, "", UC_CYAN, UC_BLUE);
    # 统计卡片行
    uc_stat_card(1, 3, 9, "CPU", "45%", 1, UC_WHITE, UC_BLUE);
    uc_stat_card(13, 3, 9, "MEM", "68%", -1, UC_WHITE, UC_BLUE);
    uc_stat_card(25, 3, 9, "DISK", "82%", 1, UC_WHITE, UC_BLUE);
    uc_stat_card(37, 3, 9, "NET", "12%", 1, UC_WHITE, UC_BLUE);
    # 仪表盘
    uc_text(2, 9, "CPU Gauge", UC_GREEN, UC_BLUE);
    uc_gauge(2, 10, 10, 45, UC_GREEN, UC_BLUE);
    # 柱状图
    uc_text(20, 9, "Requests", UC_CYAN, UC_BLUE);
    uc_chart(20, 10, "3 5 2 7 4 6 3 8", 5, UC_GREEN, UC_BLUE);
    # 评分
    uc_text(2, 13, "Health", UC_YELLOW, UC_BLUE);
    uc_stars(10, 13, 4, 5, UC_GREEN, UC_BLUE);
    # 状态栏
    uc_status_bar(1, 16, 48, "All systems operational", 5, 5, 95, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}