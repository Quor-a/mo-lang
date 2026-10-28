# lib/ui.mo —— ANSI 终端 UI 组件库
# 让墨语言可以绘制文本界面：清屏、光标定位、颜色、
# 文本、边框盒子、按钮、进度条、输入框、水平/垂直线。
# 全部基于 ANSI 转义序列，兼容绝大多数终端（xterm/linux）。
#
# 用法：import "ui.mo";
#   ui_clear();
#   ui_gotoxy(1, 1);
#   ui_color(32, 40);     # 绿字黑底
#   ui_text(2, 1, "Hello");
#   ui_reset();
#
# 坐标从 (1,1) 开始（终端惯例）。

import "str.mo";
import "io.mo";

# 全局输出缓冲（避免逐字节 syscall）
var UI_B: [512] byte = 0;
var UI_NB: [24] byte = 0;

# 清屏并归位
fn ui_clear() -> i64 {
    UI_B[0] = 27; UI_B[1] = 91; UI_B[2] = 50; UI_B[3] = 74;
    UI_B[4] = 27; UI_B[5] = 91; UI_B[6] = 72;
    UI_B[7] = 0;
    print(&UI_B);
    return 0;
}

# 光标定位到 (row, col)，1-based
fn ui_gotoxy(r: i64, c: i64) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    UI_B[0] = 27; UI_B[1] = 91;
    i = 2;
    utoa(r, &UI_NB, 10);
    k = 0;
    while UI_NB[k] != 0 {
        UI_B[i] = UI_NB[k];
        i = i + 1; k = k + 1;
    }
    UI_B[i] = 59; i = i + 1;
    utoa(c, &UI_NB, 10);
    k = 0;
    while UI_NB[k] != 0 {
        UI_B[i] = UI_NB[k];
        i = i + 1; k = k + 1;
    }
    UI_B[i] = 72; i = i + 1;
    UI_B[i] = 0;
    print(&UI_B);
    return 0;
}

# 设置前景/背景色（30-37 / 40-47）
fn ui_color(fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    UI_B[0] = 27; UI_B[1] = 91;
    i = 2;
    utoa(fg, &UI_NB, 10);
    k = 0;
    while UI_NB[k] != 0 {
        UI_B[i] = UI_NB[k];
        i = i + 1; k = k + 1;
    }
    UI_B[i] = 59; i = i + 1;
    utoa(bg, &UI_NB, 10);
    k = 0;
    while UI_NB[k] != 0 {
        UI_B[i] = UI_NB[k];
        i = i + 1; k = k + 1;
    }
    UI_B[i] = 109; i = i + 1;
    UI_B[i] = 0;
    print(&UI_B);
    return 0;
}

# 重置所有样式
fn ui_reset() -> i64 {
    UI_B[0] = 27; UI_B[1] = 91; UI_B[2] = 48; UI_B[3] = 109;
    UI_B[4] = 0;
    print(&UI_B);
    return 0;
}

# 在 (r,c) 绘制文本
fn ui_text(r: i64, c: i64, s: ptr) -> i64 {
    ui_gotoxy(r, c);
    print(s);
    return 0;
}

# 在 (r,c) 绘制一个数字
fn ui_num(r: i64, c: i64, v: i64) -> i64 {
    ui_gotoxy(r, c);
    print_i64(v);
    return 0;
}

# 绘制水平线：从 (r,c) 开始 w 个 '-'，两端用 '+'
fn ui_hline(r: i64, c: i64, w: i64) -> i64 {
    let i: i64 = 0;
    ui_gotoxy(r, c);
    print("+");
    i = 1;
    while i < w - 1 {
        print("-");
        i = i + 1;
    }
    print("+");
    return 0;
}

# 绘制垂直线：从 (r,c) 开始 h 个 '|'，两端用 '+'
fn ui_vline(r: i64, c: i64, h: i64) -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < h {
        ui_gotoxy(r + i, c);
        if i == 0 || i == h - 1 {
            print("+");
        } else {
            print("|");
        }
        i = i + 1;
    }
    return 0;
}

# 绘制一个带标题的边框盒子：
#   +-- title --+
#   |           |
#   |           |
#   +-----------+
# 盒子内部从 (r+1,c+1) 到 (r+h-1, c+w-1)
fn ui_box(r: i64, c: i64, w: i64, h: i64, title: ptr) -> i64 {
    let i: i64 = 0;
    let tl: i64 = 0;
    let tpos: i64 = 0;
    let k: i64 = 0;
    if w < 4 { w = 4; }
    if h < 3 { h = 3; }
    # 顶边
    ui_gotoxy(r, c);
    print("+");
    i = 1;
    while i < w - 1 {
        print("-");
        i = i + 1;
    }
    print("+");
    # 标题：放在顶边内部，格式 " title "
    tl = strlen(title);
    tpos = c + 2;
    if tpos + tl + 1 < c + w - 1 {
        ui_gotoxy(r, tpos);
        print(title);
    }
    # 左右边
    i = 1;
    while i < h - 1 {
        ui_gotoxy(r + i, c);
        print("|");
        ui_gotoxy(r + i, c + w - 1);
        print("|");
        i = i + 1;
    }
    # 底边
    ui_gotoxy(r + h - 1, c);
    print("+");
    i = 1;
    while i < w - 1 {
        print("-");
        i = i + 1;
    }
    print("+");
    return 0;
}

# 绘制一个按钮：[ label ]，可选高亮（背景色）
fn ui_button(r: i64, c: i64, label: ptr) -> i64 {
    ui_gotoxy(r, c);
    print("[");
    print(label);
    print("]");
    return 0;
}

# 绘制一个进度条：[====----]  pct 0-100，宽 w
fn ui_progress(r: i64, c: i64, w: i64, pct: i64) -> i64 {
    let filled: i64 = 0;
    let i: i64 = 0;
    if pct < 0 { pct = 0; }
    if pct > 100 { pct = 100; }
    if w < 3 { w = 3; }
    filled = (pct * (w - 2)) / 100;
    ui_gotoxy(r, c);
    print("[");
    i = 0;
    while i < w - 2 {
        if i < filled {
            print("=");
        } else {
            print("-");
        }
        i = i + 1;
    }
    print("]");
    return 0;
}

# 绘制一个输入框：[ placeholder____ ]，占位文本在方括号内
fn ui_input(r: i64, c: i64, w: i64, placeholder: ptr) -> i64 {
    let i: i64 = 0;
    let pl: i64 = 0;
    if w < 4 { w = 4; }
    ui_gotoxy(r, c);
    print("[");
    pl = strlen(placeholder);
    i = 0;
    while i < w - 2 {
        if i < pl {
            print(placeholder + i);
        } else {
            print("_");
        }
        i = i + 1;
    }
    print("]");
    return 0;
}

# 绘制一个菜单：若干选项，当前项高亮
# items: 逗号分隔的标签字符串；cur: 当前索引（0-based）
fn ui_menu(r: i64, c: i64, items: ptr, cur: i64) -> i64 {
    let buf: [256] byte = 0;
    let i: i64 = 0;
    let k: i64 = 0;
    let idx: i64 = 0;
    let start: i64 = 0;
    let len: i64 = 0;
    len = strlen(items);
    i = 0;
    while i <= len {
        if items[i] == 44 || items[i] == 0 {   # ',' 或结束
            buf[k] = 0;
            if idx == cur {
                ui_color(30, 47);   # 黑字白底
            }
            ui_gotoxy(r + idx, c);
            print(&buf);
            ui_reset();
            idx = idx + 1;
            k = 0;
        } else {
            buf[k] = items[i];
            k = k + 1;
        }
        i = i + 1;
    }
    return 0;
}