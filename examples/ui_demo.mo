# examples/ui_demo.mo —— 终端 UI 组件演示
# 用墨语言的 lib/ui.mo 绘制：标题、盒子、按钮、进度条、
# 输入框、菜单、水平/垂直线。
#
# 编译：./bin/moc examples/ui_demo.mo ui_demo.elf && ./ui_demo.elf

import "ui.mo";

fn main() -> i64 {
    let i: i64 = 0;
    ui_clear();
    ui_reset();

    # 标题
    ui_color(36, 40);          # 青色字
    ui_text(1, 1, "== Mo 终端 UI 演示 ==");
    ui_reset();

    # 主盒子
    ui_box(2, 1, 30, 12, " main ");

    # 盒子内文本
    ui_text(3, 3, "Mo UI 组件库:");
    ui_text(4, 3, "box / button / progress");
    ui_text(5, 3, "input / menu / text");

    # 按钮
    ui_text(7, 3, "按钮:");
    ui_button(7, 9, "确定");
    ui_button(7, 17, "取消");

    # 进度条
    ui_text(9, 3, "进度:");
    ui_progress(9, 9, 15, 65);
    ui_text(9, 26, "65%");

    # 输入框
    ui_text(11, 3, "输入:");
    ui_input(11, 9, 16, "用户名");

    # 菜单（右侧第二个盒子）
    ui_box(2, 35, 20, 8, " menu ");
    ui_menu(4, 37, "新建,打开,保存,退出", 1);

    # 表格（下方）
    ui_text(14, 1, "表格:");
    ui_table(15, 1, "ID,Name,Age", "1,Tom,20;2,Ann,21;3,Leo,22", 3, 6);

    # 带百分比进度条
    ui_text(20, 1, "下载:");
    ui_progress_pct(20, 7, 20, 78);

    # 底部水平线
    ui_hline(25, 1, 54);
    ui_text(26, 1, "按 Ctrl+C 退出");

    # 光标归位
    ui_gotoxy(28, 1);
    ui_reset();
    return 0;
}