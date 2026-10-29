
# ============ v1.457 电池状态行 ============

# uc_battery_row：绘制电池状态行 Battery [####....] 80%
# percent 为电量百分比，charging=1 显示充电中。
# 用于系统状态、电源管理。
fn uc_battery_row(x: i64, y: i64, percent: i64, charging: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let filled: i64 = 0;
    let p: i64 = 0;
    if charging != 0 {
        uc_set(x, y, 'B', UC_GREEN, bg);
        uc_set(x + 1, y, 'a', UC_GREEN, bg);
        uc_set(x + 2, y, 't', UC_GREEN, bg);
        uc_set(x + 3, y, '+', UC_GREEN, bg);
    } else {
        uc_set(x, y, 'B', UC_YELLOW, bg);
        uc_set(x + 1, y, 'a', UC_YELLOW, bg);
        uc_set(x + 2, y, 't', UC_YELLOW, bg);
    }
    uc_set(x + 6, y, ' ', fg, bg);
    filled = percent * 8 / 100;
    if filled > 8 {
        filled = 8;
    }
    uc_set(x + 7, y, '[', fg, bg);
    i = 0;
    while i < 8 {
        if i < filled {
            uc_set(x + 8 + i, y, '#', UC_GREEN, bg);
        } else {
            uc_set(x + 8 + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + 16, y, ']', fg, bg);
    p = percent;
    uc_set(x + 19, y, ' ', fg, bg);
    if p >= 100 {
        uc_set(x + 20, y, '1', UC_GREEN, bg);
        p = p % 100;
        uc_set(x + 21, y, '0' + p / 10, UC_GREEN, bg);
        uc_set(x + 22, y, '0' + p % 10, UC_GREEN, bg);
    } else {
        if p >= 10 {
            uc_set(x + 20, y, '0' + p / 10, UC_GREEN, bg);
            uc_set(x + 21, y, '0' + p % 10, UC_GREEN, bg);
        } else {
            uc_set(x + 20, y, '0' + p, UC_GREEN, bg);
        }
    }
    uc_set(x + 23, y, '%', UC_GREEN, bg);
    return 0;
}
