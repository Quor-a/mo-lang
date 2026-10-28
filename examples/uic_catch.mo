# examples/uic_catch.mo —— 迷你收集游戏
# 用键盘 w/a/s/d 控制 @ 移动，收集 * 得分。
# 演示画布交互 + 碰撞检测 + 实时刷新。
#
# 编译：./bin/moc examples/uic_catch.mo uic_catch.elf && ./uic_catch.elf

import "uic.mo";

fn main() -> i64 {
    let px: i64 = 10;
    let py: i64 = 5;
    let fx: i64 = 20;
    let fy: i64 = 3;
    let score: i64 = 0;
    let key: i64 = 0;
    uc_init(32, 10);
    while 1 == 1 {
        uc_clear(UC_WHITE, UC_BLUE);
        uc_round_rect(1, 1, 30, 8, UC_CYAN, UC_BLUE);
        uc_text(3, 1, "收集 *  (w/a/s/d)", UC_YELLOW, UC_BLUE);
        # 显示得分
        uc_text(3, 9, "得分: ", UC_WHITE, UC_BLUE);
        uc_set(9, 9, 48 + score, UC_GREEN, UC_BLUE);
        # 食物
        uc_set(fx, fy, '*', UC_MAGENTA, UC_BLUE);
        # 玩家
        uc_set(px, py, '@', UC_GREEN, UC_BLUE);
        uc_render_at(1, 1);
        # 碰撞检测
        if px == fx {
            if py == fy {
                score = score + 1;
                fx = px + 5;
                if fx > 29 { fx = 3; }
                fy = py + 3;
                if fy > 8 { fy = 3; }
            }
        }
        key = uc_read_key();
        if key == 113 { break; }       # q
        if key < 0 { break; }          # EOF
        if key == 119 { py = py - 1; } # w 上
        if key == 115 { py = py + 1; } # s 下
        if key == 97 { px = px - 1; }  # a 左
        if key == 100 { px = px + 1; } # d 右
        if px < 2 { px = 2; }
        if px > 29 { px = 29; }
        if py < 2 { py = 2; }
        if py > 8 { py = 8; }
    }
    return 0;
}