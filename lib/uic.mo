# lib/uic.mo —— 字符画布库（完整 UI 绘图标准库）
#
# 把终端当成一块字符画布：开发者用基本原语在画布上任意绘制
# 字符、颜色、样式，最后一次性渲染。任何组件（表格、弹窗、
# 图标、仪表盘、图形）都由开发者用原语自由组合。
#
# 画布大小默认 80x25（终端常见尺寸），可 uc_init(w,h) 重置。
# 每个单元 = 一个字符 + 前景色 + 背景色。
#
# 用法：
#   import "uic.mo";
#   uc_init(80, 25);
#   uc_clear(UC_WHITE, UC_BLUE);
#   uc_rect(2, 2, 20, 5, '+', UC_CYAN, UC_BLACK);
#   uc_text(4, 4, "Hello", UC_WHITE, UC_BLUE);
#   uc_render();
#
# 颜色常量（ANSI 前景/背景基础值）：
#   UC_BLACK=30/40  UC_RED=31/41  UC_GREEN=32/42  UC_YELLOW=33/43
#   UC_BLUE=34/44   UC_MAGENTA=35/45  UC_CYAN=36/46  UC_WHITE=37/47

import "str.mo";
import "io.mo";
import "ui.mo";

# 画布大小上限
var UC_MAXW: i64 = 120;
var UC_MAXH: i64 = 50;

# 画布尺寸（当前）
var UC_W: i64 = 80;
var UC_H: i64 = 25;

# 画布缓冲：字符矩阵 + 前景色 + 背景色
var UC_CH: [6000] byte = 0;    # 120*50
var UC_FG: [6000] byte = 0;
var UC_BG: [6000] byte = 0;

# 颜色常量
var UC_BLACK: i64 = 0;
var UC_RED: i64 = 1;
var UC_GREEN: i64 = 2;
var UC_YELLOW: i64 = 3;
var UC_BLUE: i64 = 4;
var UC_MAGENTA: i64 = 5;
var UC_CYAN: i64 = 6;
var UC_WHITE: i64 = 7;

# 渲染时按字符生成 ANSI 转义序列
var UC_RB: [1024] byte = 0;
var UC_NB: [16] byte = 0;

# 初始化画布大小（不超过上限）
fn uc_init(w: i64, h: i64) -> i64 {
    if w < 1 { w = 1; }
    if h < 1 { h = 1; }
    if w > UC_MAXW { w = UC_MAXW; }
    if h > UC_MAXH { h = UC_MAXH; }
    UC_W = w;
    UC_H = h;
    return 0;
}

# 清空画布（所有单元设为空格 + 指定颜色）
fn uc_clear(fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let total: i64 = UC_W * UC_H;
    i = 0;
    while i < total {
        UC_CH[i] = 32;
        UC_FG[i] = fg;
        UC_BG[i] = bg;
        i = i + 1;
    }
    return 0;
}

# 画布坐标检查：返回 1 表示越界
fn uc_oob(x: i64, y: i64) -> i64 {
    if x < 0 { return 1; }
    if y < 0 { return 1; }
    if x >= UC_W { return 1; }
    if y >= UC_H { return 1; }
    return 0;
}

# 在画布 (x,y) 设一个单元（字符 + 颜色），越界忽略
fn uc_set(x: i64, y: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    if uc_oob(x, y) == 1 { return 0; }
    let idx: i64 = y * UC_W + x;
    UC_CH[idx] = ch;
    UC_FG[idx] = fg;
    UC_BG[idx] = bg;
    return 0;
}

# 读取画布单元字符（越界返回空格）
fn uc_get(x: i64, y: i64) -> i64 {
    if uc_oob(x, y) == 1 { return 32; }
    return UC_CH[y * UC_W + x];
}

# 在画布 (x,y) 绘制字符串（越界自动裁剪）
fn uc_text(x: i64, y: i64, s: ptr, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let len: i64 = 0;
    len = strlen(s);
    i = 0;
    while i < len {
        if x + i >= 0 && x + i < UC_W {
            uc_set(x + i, y, s[i], fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# 在画布绘制一个矩形边框（ch 为边框字符，默认可传 '+'）
fn uc_rect(x: i64, y: i64, w: i64, h: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if w < 2 { w = 2; }
    if h < 2 { h = 2; }
    i = 0;
    while i < w {
        uc_set(x + i, y, ch, fg, bg);
        uc_set(x + i, y + h - 1, ch, fg, bg);
        i = i + 1;
    }
    i = 0;
    while i < h {
        uc_set(x, y + i, ch, fg, bg);
        uc_set(x + w - 1, y + i, ch, fg, bg);
        i = i + 1;
    }
    return 0;
}

# 填充矩形区域（ch 为填充字符）
fn uc_fill(x: i64, y: i64, w: i64, h: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            uc_set(x + i, y + j, ch, fg, bg);
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# 绘制水平直线（从 x1 到 x2，在 y 行）
fn uc_hline(x1: i64, x2: i64, y: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if x1 > x2 {
        let t: i64 = x1; x1 = x2; x2 = t;
    }
    i = x1;
    while i <= x2 {
        uc_set(i, y, ch, fg, bg);
        i = i + 1;
    }
    return 0;
}

# 绘制垂直直线（从 y1 到 y2，在 x 列）
fn uc_vline(x: i64, y1: i64, y2: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if y1 > y2 {
        let t: i64 = y1; y1 = y2; y2 = t;
    }
    i = y1;
    while i <= y2 {
        uc_set(x, i, ch, fg, bg);
        i = i + 1;
    }
    return 0;
}

# 一次性渲染整块画布到终端
fn uc_render() -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let lastfg: i64 = -1;
    let lastbg: i64 = -1;
    ui_clear();
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            let fg: i64 = UC_FG[idx];
            let bg: i64 = UC_BG[idx];
            if fg != lastfg || bg != lastbg {
                ui_color(30 + fg, 40 + bg);
                lastfg = fg;
                lastbg = bg;
            }
            # 输出字符（用单字节输出）
            let c: i64 = UC_CH[idx];
            UC_RB[0] = c;
            UC_RB[1] = 0;
            print(&UC_RB);
            x = x + 1;
        }
        print_nl();
        y = y + 1;
    }
    ui_reset();
    return 0;
}

# 渲染一行到终端指定行（增量渲染，先 gotoxy）
fn uc_render_at(row: i64, col: i64) -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let lastfg: i64 = -1;
    let lastbg: i64 = -1;
    y = 0;
    while y < UC_H {
        ui_gotoxy(row + y, col);
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            let fg: i64 = UC_FG[idx];
            let bg: i64 = UC_BG[idx];
            if fg != lastfg || bg != lastbg {
                ui_color(30 + fg, 40 + bg);
                lastfg = fg;
                lastbg = bg;
            }
            let c: i64 = UC_CH[idx];
            UC_RB[0] = c;
            UC_RB[1] = 0;
            print(&UC_RB);
            x = x + 1;
        }
        ui_reset();
        y = y + 1;
    }
    ui_reset();
    return 0;
}
# v1.338:任意两点直线（Bresenham 画线）—— 让开发者能画任意图形
fn uc_line(x0: i64, y0: i64, x1: i64, y1: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let dx: i64 = 0;
    let dy: i64 = 0;
    let sx: i64 = 0;
    let sy: i64 = 0;
    let err: i64 = 0;
    let e2: i64 = 0;
    dx = x1 - x0; if dx < 0 { dx = 0 - dx; }
    dy = y1 - y0; if dy < 0 { dy = 0 - dy; }
    if x0 < x1 { sx = 1; } else { sx = -1; }
    if y0 < y1 { sy = 1; } else { sy = -1; }
    err = dx - dy;
    while 1 == 1 {
        uc_set(x0, y0, ch, fg, bg);
        if x0 == x1 && y0 == y1 { break; }
        e2 = 2 * err;
        if e2 > 0 - dy {
            err = err - dy;
            x0 = x0 + sx;
        }
        if e2 < dx {
            err = err + dx;
            y0 = y0 + sy;
        }
    }
    return 0;
}

# v1.338:圆（中点画圆法）
fn uc_circle(cx: i64, cy: i64, r: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let x: i64 = 0;
    let y: i64 = 0;
    let d: i64 = 0;
    if r < 1 { r = 1; }
    x = 0;
    y = r;
    d = 1 - r;
    while x <= y {
        uc_set(cx + x, cy + y, ch, fg, bg);
        uc_set(cx + y, cy + x, ch, fg, bg);
        uc_set(cx - x, cy + y, ch, fg, bg);
        uc_set(cx - y, cy + x, ch, fg, bg);
        uc_set(cx + x, cy - y, ch, fg, bg);
        uc_set(cx + y, cy - x, ch, fg, bg);
        uc_set(cx - x, cy - y, ch, fg, bg);
        uc_set(cx - y, cy - x, ch, fg, bg);
        if d < 0 {
            d = d + 2 * x + 3;
        } else {
            d = d + 2 * (x - y) + 5;
            y = y - 1;
        }
        x = x + 1;
    }
    return 0;
}

# v1.338:三角形边框（三顶点连线）
fn uc_tri(x0: i64, y0: i64, x1: i64, y1: i64, x2: i64, y2: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    uc_line(x0, y0, x1, y1, ch, fg, bg);
    uc_line(x1, y1, x2, y2, ch, fg, bg);
    uc_line(x2, y2, x0, y0, ch, fg, bg);
    return 0;
}

# v1.338:绘制图案 —— 用逗号分隔的多行字符矩阵绘制任意图标
# pattern 形如 ".##.,#..#,#..#,.##."，'.'=透明(跳过), 其他字符=绘制
fn uc_sprite(x: i64, y: i64, pattern: ptr, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let row: i64 = 0;
    let col: i64 = 0;
    let len: i64 = 0;
    len = strlen(pattern);
    i = 0;
    row = 0;
    col = 0;
    while i < len {
        let c: i64 = pattern[i];
        if c == 44 {   # ','
            row = row + 1;
            col = 0;
        } else {
            if c != 46 {   # 不是 '.'
                uc_set(x + col, y + row, c, fg, bg);
            }
            col = col + 1;
        }
        i = i + 1;
    }
    return 0;
}
