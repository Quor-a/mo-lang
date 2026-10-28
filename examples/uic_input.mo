# examples/uic_input.mo —— 交互式画布：按键移动角色
# 用键盘 w/a/s/d 控制 @ 在画布上移动，q 退出。
# 演示画布 + 键盘交互（uc_read_key / uc_has_key）。
#
# 编译：./bin/moc examples/uic_input.mo uic_input.elf && ./uic_input.elf

import "uic.mo";

fn main() -> i64 {
    let px: i64 = 10;
    let py: i64 = 5;
    let key: i64 = 0;
    uc_init(30, 10);
    uc_clear(UC_WHITE, UC_BLUE);
    uc_text(8, 1, "w/a/s/d 移动, q 退出", UC_YELLOW, UC_BLUE);
    while 1 == 1 {
        uc_clear(UC_WHITE, UC_BLUE);
        uc_text(8, 1, "w/a/s/d 移动, q 退出", UC_YELLOW, UC_BLUE);
        uc_round_rect(2, 2, 26, 7, UC_CYAN, UC_BLUE);
        uc_set(px, py, '@', UC_GREEN, UC_BLUE);
        uc_render_at(1, 1);
        key = uc_read_key();
        if key == 113 { break; }       # q
        if key < 0 { break; }          # EOF
        if key == 119 { py = py - 1; } # w 上
        if key == 115 { py = py + 1; } # s 下
        if key == 97 { px = px - 1; }  # a 左
        if key == 100 { px = px + 1; } # d 右
        if px < 3 { px = 3; }
        if px > 27 { px = 27; }
        if py < 3 { py = 3; }
        if py > 8 { py = 8; }
    }
    return 0;
}