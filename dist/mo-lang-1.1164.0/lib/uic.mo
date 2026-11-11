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
import "fs.mo";

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
var UC_ST: [6000] byte = 0;    # 样式位：1=粗体 2=下划线 4=闪烁

# 颜色常量
var UC_BLACK: i64 = 0;
var UC_RED: i64 = 1;
var UC_GREEN: i64 = 2;
var UC_YELLOW: i64 = 3;
var UC_BLUE: i64 = 4;
var UC_MAGENTA: i64 = 5;
var UC_CYAN: i64 = 6;
var UC_TAG_C0: i64 = 6;   # 青
var UC_TAG_C1: i64 = 2;   # 绿
var UC_TAG_C2: i64 = 3;   # 黄
var UC_TAG_C3: i64 = 5;   # 品红
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
# v1.347: 256 色支持 —— 前景/背景值 >7 时输出 ANSI 256 色序列
# 0-7 用基础色，8-255 用 256 色序列。
var UC_LASTFG: i64 = 0;
var UC_LASTBG: i64 = 0;

# 输出 ANSI 256 色前景+背景序列到 UC_RB 并打印
fn uc_color256(fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    let n: [24] byte = 0;
    UC_LASTFG = fg;
    UC_LASTBG = bg;
    i = 0;
    # 前景：[38;5;Fm
    if fg > 7 {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 51; i=i+1;
        UC_RB[i] = 56; i=i+1;
        UC_RB[i] = 59; i=i+1;
        UC_RB[i] = 53; i=i+1;
        UC_RB[i] = 59; i=i+1;
        utoa(fg, &n, 10);
        k = 0;
        while n[k] != 0 {
            UC_RB[i] = n[k]; i=i+1; k=k+1;
        }
        UC_RB[i] = 109; i=i+1;
    } else {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 48 + fg; i=i+1;   # '3X'
        UC_RB[i] = 109; i=i+1;
    }
    # 背景：[48;5;Bm
    if bg > 7 {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 52; i=i+1;
        UC_RB[i] = 56; i=i+1;
        UC_RB[i] = 59; i=i+1;
        UC_RB[i] = 53; i=i+1;
        UC_RB[i] = 59; i=i+1;
        utoa(bg, &n, 10);
        k = 0;
        while n[k] != 0 {
            UC_RB[i] = n[k]; i=i+1; k=k+1;
        }
        UC_RB[i] = 109; i=i+1;
    } else {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 48 + bg; i=i+1;   # '4X'
        UC_RB[i] = 109; i=i+1;
    }
    UC_RB[i] = 0;
    print(&UC_RB);
    return 0;
}

# v1.348: 样式支持 —— 设置单元格样式（1=粗体 2=下划线 4=闪烁，可组合）
fn uc_style(x: i64, y: i64, st: i64) -> i64 {
    if x >= 0 && x < UC_W && y >= 0 && y < UC_H {
        UC_ST[y * UC_W + x] = st;
    }
    return 0;
}

# 输出 ANSI 样式序列到 UC_RB 并打印（样式变化时调用）
# 正常=0，粗体=1，下划线=2，闪烁=4
var UC_LASTST: i64 = 0;

fn uc_style_out(st: i64) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    let n: [24] byte = 0;
    UC_LASTST = st;
    i = 0;
    # [0m 重置，然后设置对应样式
    UC_RB[i] = 27; i=i+1;
    UC_RB[i] = 91; i=i+1;
    UC_RB[i] = 48; i=i+1;
    UC_RB[i] = 109; i=i+1;
    if (st & 1) != 0 {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 49; i=i+1;
        UC_RB[i] = 109; i=i+1;
    }
    if (st & 2) != 0 {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 52; i=i+1;
        UC_RB[i] = 109; i=i+1;
    }
    if (st & 4) != 0 {
        UC_RB[i] = 27; i=i+1;
        UC_RB[i] = 91; i=i+1;
        UC_RB[i] = 53; i=i+1;
        UC_RB[i] = 109; i=i+1;
    }
    UC_RB[i] = 0;
    print(&UC_RB);
    return 0;
}

fn uc_render() -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    UC_LASTFG = 999;
    UC_LASTBG = 999;
    UC_LASTST = 999;
    ui_clear();
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            let fg: i64 = UC_FG[idx];
            let bg: i64 = UC_BG[idx];
            let st: i64 = UC_ST[idx];
            if fg != UC_LASTFG || bg != UC_LASTBG {
                uc_color256(fg, bg);
            }
            if st != UC_LASTST {
                uc_style_out(st);
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
    UC_LASTFG = 999;
    UC_LASTBG = 999;
    UC_LASTST = 999;
    y = 0;
    while y < UC_H {
        ui_gotoxy(row + y, col);
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            let fg: i64 = UC_FG[idx];
            let bg: i64 = UC_BG[idx];
            let st: i64 = UC_ST[idx];
            if fg != UC_LASTFG || bg != UC_LASTBG {
                uc_color256(fg, bg);
            }
            if st != UC_LASTST {
                uc_style_out(st);
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

# ============ v1.339 高级组件层（基于画布原语组合） ============

# uc_window：带标题栏的窗口
# 边框颜色 border_fg，标题栏背景 title_bg，标题文字 title
fn uc_window(x: i64, y: i64, w: i64, h: i64, title: ptr, border_fg: i64, title_bg: i64) -> i64 {
    let i: i64 = 0;
    let tl: i64 = 0;
    if w < 5 { w = 5; }
    if h < 3 { h = 3; }
    # 边框
    uc_rect(x, y, w, h, '+', border_fg, title_bg);
    # 上下边框用 '-'，左右用 '|'（覆盖 rect 的 '+' 之外的部分）
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y, '-', border_fg, title_bg);
        uc_set(x + i, y + h - 1, '-', border_fg, title_bg);
        i = i + 1;
    }
    i = 1;
    while i < h - 1 {
        uc_set(x, y + i, '|', border_fg, title_bg);
        uc_set(x + w - 1, y + i, '|', border_fg, title_bg);
        i = i + 1;
    }
    # 标题（左上角，反色显示：标题用 title_bg 作为前景色不好，直接用黑字白底风格）
    tl = strlen(title);
    if tl > w - 3 { tl = w - 3; }
    uc_text(x + 1, y, title, UC_BLACK, title_bg);
    return 0;
}

# uc_panel：面板 —— 边框 + 可选标题，内容由开发者自由填入
fn uc_panel(x: i64, y: i64, w: i64, h: i64, title: ptr, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if w < 4 { w = 4; }
    if h < 2 { h = 2; }
    # 顶部边框 + 标题
    uc_set(x, y, '+', fg, bg);
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y, '-', fg, bg);
        i = i + 1;
    }
    uc_set(x + w - 1, y, '+', fg, bg);
    if strlen(title) > 0 {
        uc_text(x + 2, y, title, UC_YELLOW, bg);
    }
    # 底部边框
    uc_set(x, y + h - 1, '+', fg, bg);
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y + h - 1, '-', fg, bg);
        i = i + 1;
    }
    uc_set(x + w - 1, y + h - 1, '+', fg, bg);
    # 左右边
    i = 1;
    while i < h - 1 {
        uc_set(x, y + i, '|', fg, bg);
        uc_set(x + w - 1, y + i, '|', fg, bg);
        i = i + 1;
    }
    return 0;
}

# uc_gauge：水平仪表盘 —— 刻度条 + 指针
# pct 0-100；用刻度字符：低段 ':'、中段 '.'、高段 ' ' 太复杂，直接用 `-` 和 `#`
fn uc_gauge(x: i64, y: i64, w: i64, pct: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let pos: i64 = 0;
    if w < 6 { w = 6; }
    if pct < 0 { pct = 0; }
    if pct > 100 { pct = 100; }
    # 边框
    uc_set(x, y, '[', UC_WHITE, bg);
    uc_set(x + w - 1, y, ']', UC_WHITE, bg);
    pos = (pct * (w - 2)) / 100;
    i = 1;
    while i < w - 1 {
        if i < pos {
            uc_set(x + i, y, '#', fg, bg);
        } else {
            uc_set(x + i, y, '-', UC_WHITE, bg);
        }
        i = i + 1;
    }
    return 0;
}

# uc_scrollbar：垂直滚动条 —— 轨道 `|`，拇指 `#`
# pos 0-100 表示拇指位置；thumb_h 拇指高度
fn uc_scrollbar(x: i64, y: i64, h: i64, pos: i64, thumb_h: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let track: i64 = 0;
    let thumb_top: i64 = 0;
    if h < 3 { h = 3; }
    if thumb_h < 1 { thumb_h = 1; }
    if thumb_h > h { thumb_h = h; }
    if pos < 0 { pos = 0; }
    if pos > 100 { pos = 100; }
    track = h - thumb_h;
    thumb_top = (pos * track) / 100;
    i = 0;
    while i < h {
        if i >= thumb_top && i < thumb_top + thumb_h {
            uc_set(x, y + i, '#', fg, bg);
        } else {
            uc_set(x, y + i, '|', UC_WHITE, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.340 导出与工具 ============

# uc_dump_text：把画布输出为纯文本（不含 ANSI 颜色），便于保存/分享
# 每行字符直接打印，末尾去除行尾空格
fn uc_dump_text() -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let last: i64 = 0;
    let c: i64 = 0;
    y = 0;
    while y < UC_H {
        # 找本行最后一个非空格位置
        last = UC_W - 1;
        while last >= 0 {
            if UC_CH[y * UC_W + last] != 32 { break; }
            last = last - 1;
        }
        x = 0;
        while x <= last {
            c = UC_CH[y * UC_W + x];
            if c == 0 { c = 32; }
            UC_RB[0] = c;
            UC_RB[1] = 0;
            print(&UC_RB);
            x = x + 1;
        }
        print_nl();
        y = y + 1;
    }
    return 0;
}

# uc_dump_file：把画布保存为纯文本文件
fn uc_dump_file(path: ptr) -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let last: i64 = 0;
    let c: i64 = 0;
    let fd: i64 = 0;
    let line: [128] byte = 0;
    let li: i64 = 0;
    fd = fopen(path, 577, 438);
    if fd < 0 {
        print("✗ 无法写入 ");
        print(path);
        print_nl();
        return 1;
    }
    y = 0;
    while y < UC_H {
        last = UC_W - 1;
        while last >= 0 {
            if UC_CH[y * UC_W + last] != 32 { break; }
            last = last - 1;
        }
        x = 0;
        li = 0;
        while x <= last {
            c = UC_CH[y * UC_W + x];
            if c == 0 { c = 32; }
            if li < 120 {
                line[li] = c;
                li = li + 1;
            }
            x = x + 1;
        }
        line[li] = 10;   # '\n'
        fwrite(fd, &line, li + 1);
        y = y + 1;
    }
    fclose(fd);
    return 0;
}

# ============ v1.341 HTML 导出 ============

# 颜色名辅助（返回 ANSI 颜色名）
fn uc_fgname(f: i64) -> ptr {
    if f == 0 { return "black"; }
    if f == 1 { return "red"; }
    if f == 2 { return "green"; }
    if f == 3 { return "yellow"; }
    if f == 4 { return "blue"; }
    if f == 5 { return "magenta"; }
    if f == 6 { return "cyan"; }
    return "white";
}

# 背景色值辅助（返回 HTML 色值）
fn uc_bgval(f: i64) -> ptr {
    if f == 0 { return "#000"; }
    if f == 1 { return "#800"; }
    if f == 2 { return "#080"; }
    if f == 3 { return "#880"; }
    if f == 4 { return "#008"; }
    if f == 5 { return "#808"; }
    if f == 6 { return "#088"; }
    return "#ccc";
}

# uc_dump_html：把画布导出为彩色 HTML 文件（浏览器可打开）
fn uc_dump_html(path: ptr) -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let fd: i64 = 0;
    let c: i64 = 0;
    let fgc: i64 = 0;
    let bgc: i64 = 0;
    let b: [256] byte = 0;
    let bl: i64 = 0;
    fd = fopen(path, 577, 438);
    if fd < 0 {
        print("✗ 无法写入 ");
        print(path);
        print_nl();
        return 1;
    }
    # HTML 头
    fwrite(fd, "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>Mo Canvas</title>\n<style>pre{font-family:monospace;line-height:1;}</style>\n</head>\n<body>\n<pre>\n", strlen("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>Mo Canvas</title>\n<style>pre{font-family:monospace;line-height:1;}</style>\n</head>\n<body>\n<pre>\n"));
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            c = UC_CH[y * UC_W + x];
            fgc = UC_FG[y * UC_W + x];
            bgc = UC_BG[y * UC_W + x];
            if c == 0 { c = 32; }
            if fgc < 0 { fgc = 7; }
            if fgc > 7 { fgc = 7; }
            if bgc < 0 { bgc = 0; }
            if bgc > 7 { bgc = 0; }
            # <span style="color:NAME;background:VALUE">
            fwrite(fd, "<span style=\"color:", strlen("<span style=\"color:"));
            fwrite(fd, uc_fgname(fgc), strlen(uc_fgname(fgc)));
            fwrite(fd, ";background:", strlen(";background:"));
            fwrite(fd, uc_bgval(bgc), strlen(uc_bgval(bgc)));
            fwrite(fd, "\">", strlen("\">"));
            # 字符（转义 < >）
            if c == 60 {
                fwrite(fd, "&lt;", strlen("&lt;"));
            } else {
                if c == 62 {
                    fwrite(fd, "&gt;", strlen("&gt;"));
                } else {
                    b[0] = c;
                    fwrite(fd, &b, 1);
                }
            }
            fwrite(fd, "</span>", strlen("</span>"));
            x = x + 1;
        }
        fwrite(fd, "\n", 1);
        y = y + 1;
    }
    fwrite(fd, "</pre>\n</body>\n</html>\n", strlen("</pre>\n</body>\n</html>\n"));
    fclose(fd);
    return 0;
}

# ============ v1.342 布局管理器 ============

# uc_layout_h：水平排列 —— 在 (x,y) 起，按指定间距水平放置多个面板
# count 个组件，每个宽度 item_w，间距 gap；返回末尾 x 坐标
fn uc_layout_h(x: i64, y: i64, count: i64, item_w: i64, gap: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let cur: i64 = 0;
    cur = x;
    i = 0;
    while i < count {
        uc_panel(cur, y, item_w, 3, "", fg, bg);
        cur = cur + item_w + gap;
        i = i + 1;
    }
    return cur - gap;
}

# uc_layout_v：垂直排列 —— 在 (x,y) 起，垂直放置多个组件
# 每个组件高度 item_h，间距 gap；返回末尾 y 坐标
fn uc_layout_v(x: i64, y: i64, count: i64, item_h: i64, gap: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let cur: i64 = 0;
    cur = y;
    i = 0;
    while i < count {
        uc_panel(x, cur, 8, item_h, "", fg, bg);
        cur = cur + item_h + gap;
        i = i + 1;
    }
    return cur - gap;
}

# uc_label：带边框的标签（小徽章），用于状态栏/徽标
fn uc_label(x: i64, y: i64, text: ptr, fg: i64, bg: i64, border: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(text);
    if len < 1 { len = 1; }
    if border != 0 {
        uc_set(x, y, '[', UC_WHITE, bg);
        uc_text(x + 1, y, text, fg, bg);
        uc_set(x + len + 1, y, ']', UC_WHITE, bg);
    } else {
        uc_text(x, y, text, fg, bg);
    }
    return 0;
}

# uc_chart：条形图 —— 用字符列表示数据（逗号分隔数字），每个柱用 # 填充
# values: "3,5,2,8,4"；max_h 柱最大高度；fg/bg 柱子颜色
fn uc_chart(x: i64, y: i64, values: ptr, max_h: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let h: i64 = 0;
    let n: i64 = 0;
    let col: i64 = 0;
    let maxv: i64 = 0;
    let cur: i64 = 0;
    let row: i64 = 0;
    let len: i64 = 0;
    let vs: [32] i64 = 0;
    len = strlen(values);
    i = 0;
    n = 0;
    v = 0;
    while i <= len {
        if i < len && values[i] >= 48 && values[i] <= 57 {
            v = v * 10 + (values[i] - 48);
        } else {
            vs[n] = v;
            n = n + 1;
            v = 0;
        }
        i = i + 1;
    }
    if n < 1 { n = 1; }
    if max_h < 1 { max_h = 1; }
    # 找最大值
    maxv = 1;
    i = 0;
    while i < n {
        if vs[i] > maxv { maxv = vs[i]; }
        i = i + 1;
    }
    col = 0;
    while col < n {
        # 高度 = vs[col] * max_h / maxv
        h = (vs[col] * max_h) / maxv;
        if h < 1 && vs[col] > 0 { h = 1; }
        row = 0;
        while row < h {
            uc_set(x + col, y - row, '#', fg, bg);
            row = row + 1;
        }
        col = col + 1;
    }
    return 0;
}

# ============ v1.344 表单组件 ============

# uc_checkbox：复选框 —— "[x] 文本" 或 "[ ] 文本"
# checked 非 0 显示 [x]，否则 [ ]
fn uc_checkbox(x: i64, y: i64, text: ptr, checked: i64, fg: i64, bg: i64) -> i64 {
    if checked != 0 {
        uc_text(x, y, "[x]", UC_GREEN, bg);
    } else {
        uc_text(x, y, "[ ]", UC_WHITE, bg);
    }
    uc_text(x + 3, y, text, fg, bg);
    return 0;
}

# uc_radio：单选按钮 —— "(o) 文本" 或 "( ) 文本"
fn uc_radio(x: i64, y: i64, text: ptr, selected: i64, fg: i64, bg: i64) -> i64 {
    if selected != 0 {
        uc_text(x, y, "(o)", UC_GREEN, bg);
    } else {
        uc_text(x, y, "( )", UC_WHITE, bg);
    }
    uc_text(x + 3, y, text, fg, bg);
    return 0;
}

# uc_input：输入框 —— "[ 文本              ]"
# width 输入框宽度（不含边框）
fn uc_input(x: i64, y: i64, value: ptr, width: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let len: i64 = 0;
    let c: i64 = 0;
    if width < 1 { width = 1; }
    len = strlen(value);
    uc_set(x, y, '[', UC_WHITE, bg);
    i = 0;
    while i < width {
        c = 32;
        if i < len { c = value[i]; }
        uc_set(x + 1 + i, y, c, fg, bg);
        i = i + 1;
    }
    uc_set(x + width + 1, y, ']', UC_WHITE, bg);
    return 0;
}

# uc_slider：滑块 —— "[----o---]" 表示 0-100 位置
fn uc_slider(x: i64, y: i64, width: i64, value: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let pos: i64 = 0;
    if width < 3 { width = 3; }
    if value < 0 { value = 0; }
    if value > 100 { value = 100; }
    pos = (value * (width - 2)) / 100;
    uc_set(x, y, '[', UC_WHITE, bg);
    i = 1;
    while i <= width - 2 {
        if i == pos + 1 {
            uc_set(x + i, y, 'o', fg, bg);
        } else {
            uc_set(x + i, y, '-', UC_WHITE, bg);
        }
        i = i + 1;
    }
    uc_set(x + width - 1, y, ']', UC_WHITE, bg);
    return 0;
}

# ============ v1.345 主题系统 ============

# 全局主题变量（默认浅色主题）
var UC_TC: i64 = 7;    # 主文本色
var UC_TB: i64 = 0;    # 主背景色
var UC_AC: i64 = 6;    # 强调色（边框/高亮）
var UC_SB: i64 = 1;    # 标题栏背景
var UC_SC: i64 = 3;    # 状态栏前景
var UC_WB: i64 = 0;    # 窗口内容背景

# uc_theme_dark：应用深色主题（白字黑底）
fn uc_theme_dark() -> i64 {
    UC_TC = 7;
    UC_TB = 0;
    UC_AC = 6;
    UC_SB = 4;
    UC_SC = 3;
    UC_WB = 0;
    return 0;
}

# uc_theme_light：应用浅色主题（黑字白底）
fn uc_theme_light() -> i64 {
    UC_TC = 0;
    UC_TB = 7;
    UC_AC = 4;
    UC_SB = 7;
    UC_SC = 0;
    UC_WB = 7;
    return 0;
}

# uc_theme_custom：自定义主题
fn uc_theme_custom(tc: i64, tb: i64, ac: i64, sb: i64, sc: i64, wb: i64) -> i64 {
    UC_TC = tc;
    UC_TB = tb;
    UC_AC = ac;
    UC_SB = sb;
    UC_SC = sc;
    UC_WB = wb;
    return 0;
}

# uc_apply_theme：把当前主题应用到整个画布背景
fn uc_apply_theme() -> i64 {
    uc_clear(UC_TC, UC_TB);
    return 0;
}

# ============ v1.346 图标库 ============

# 常用图标（用字符 sprite 拼出，开发者可直接调用）
# 每个图标用 uc_sprite 绘制，透明用 '.'

# 对勾 ✓
fn uc_icon_check(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "....#..,.....#.,......#,.......#", fg, bg);
    return 0;
}

# 叉 ✗
fn uc_icon_cross(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "#......#,.#....#.,..#..#..,...##...,..#..#..,.#....#.,#......#", fg, bg);
    return 0;
}

# 警告 !
fn uc_icon_warn(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "...##...,..####..,..####..,.##..##.,.##..##.,.######.,..####..,..##....", fg, bg);
    return 0;
}

# 放大镜
fn uc_icon_search(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, ".#####.,##...##,##...#,##...#,##...#,##...##,.#####.,....#..", fg, bg);
    return 0;
}

# 锁
fn uc_icon_lock(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "..###..,.#...#.,#.....#,#.....#,#######,#.....#,#.....#,#######", fg, bg);
    return 0;
}

# 文件
fn uc_icon_file(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "######.,#....#,#....#,#....#,#....#,#....#,######.", fg, bg);
    return 0;
}

# 文件夹
fn uc_icon_folder(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, "#######,#.....#,#.....#,#######,#.....#,#.....#,#######", fg, bg);
    return 0;
}

# 心形
fn uc_icon_heart(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_sprite(x, y, ".##..##.,#######,.#####.,..###...,...#....", fg, bg);
    return 0;
}

# v1.348: 给一段文本的所有字符设置样式（1=粗体 2=下划线 4=闪烁）
fn uc_style_text(x: i64, y: i64, text: ptr, st: i64) -> i64 {
    let i: i64 = 0;
    let len: i64 = 0;
    len = strlen(text);
    i = 0;
    while i < len {
        uc_style(x + i, y, st);
        i = i + 1;
    }
    return 0;
}

# ============ v1.349 实心图形 ============

# uc_fill_circle：实心圆 —— 用扫描线法填充
fn uc_fill_circle(cx: i64, cy: i64, r: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let y: i64 = 0;
    let dx: i64 = 0;
    let x: i64 = 0;
    if r < 1 { r = 1; }
    y = 0 - r;
    while y <= r {
        dx = r * r - y * y;
        while dx < 0 { dx = 0 - dx; }
        # 计算该行的半宽
        let hw: i64 = 0;
        # 简化：dx 是 r^2-y^2，开方
        hw = 0;
        while hw * hw < dx {
            hw = hw + 1;
        }
        if hw * hw > dx { hw = hw - 1; }
        x = cx - hw;
        while x <= cx + hw {
            uc_set(x, cy + y, ch, fg, bg);
            x = x + 1;
        }
        y = y + 1;
    }
    return 0;
}

# uc_polygon：任意多边形边框（顶点用逗号分隔 "x1,y1;x2,y2;..."）
# 依次连接各顶点并闭合
fn uc_polygon(xs: ptr, ys: ptr, n: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let px: [32] i64 = 0;
    let py: [32] i64 = 0;
    # 解析 xs 和 ys（逗号分隔）
    let xi: i64 = 0;
    let yi: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    # 解析 xs
    xi = 0; v = 0; k = 0;
    while xs[k] != 0 {
        if xs[k] >= 48 && xs[k] <= 57 {
            v = v * 10 + (xs[k] - 48);
        } else {
            if xi < 32 { px[xi] = v; }
            xi = xi + 1;
            v = 0;
        }
        k = k + 1;
    }
    if xi < 32 { px[xi] = v; }
    xi = xi + 1;
    # 解析 ys
    yi = 0; v = 0; k = 0;
    while ys[k] != 0 {
        if ys[k] >= 48 && ys[k] <= 57 {
            v = v * 10 + (ys[k] - 48);
        } else {
            if yi < 32 { py[yi] = v; }
            yi = yi + 1;
            v = 0;
        }
        k = k + 1;
    }
    if yi < 32 { py[yi] = v; }
    yi = yi + 1;
    if xi > n { xi = n; }
    if yi > n { yi = n; }
    if xi < 2 { return 1; }
    i = 0;
    while i < xi - 1 {
        uc_line(px[i], py[i], px[i+1], py[i+1], ch, fg, bg);
        i = i + 1;
    }
    uc_line(px[xi-1], py[xi-1], px[0], py[0], ch, fg, bg);
    return 0;
}

# ============ v1.351 动态与动画 ============

# uc_progress_anim：动画进度条 —— 渲染带百分比的进度条
# 调用多次（值变化）配合 uc_render_at 实现动画效果
fn uc_progress_anim(x: i64, y: i64, width: i64, pct: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let filled: i64 = 0;
    if width < 10 { width = 10; }
    if pct < 0 { pct = 0; }
    if pct > 100 { pct = 100; }
    uc_set(x, y, '[', UC_WHITE, bg);
    filled = (pct * (width - 2)) / 100;
    i = 1;
    while i <= width - 2 {
        if i <= filled {
            uc_set(x + i, y, '=', fg, bg);
        } else {
            uc_set(x + i, y, '-', UC_WHITE, bg);
        }
        i = i + 1;
    }
    uc_set(x + width - 1, y, ']', UC_WHITE, bg);
    # 百分比
    if pct < 10 {
        uc_set(x + width + 1, y, 32, UC_WHITE, bg);
        uc_set(x + width + 2, y, 48 + pct, UC_WHITE, bg);
        uc_set(x + width + 3, y, 37, UC_WHITE, bg);
    } else {
        if pct < 100 {
            uc_set(x + width + 1, y, 48 + (pct / 10), UC_WHITE, bg);
            uc_set(x + width + 2, y, 48 + (pct - (pct / 10) * 10), UC_WHITE, bg);
        } else {
            uc_set(x + width + 1, y, 49, UC_WHITE, bg);
            uc_set(x + width + 2, y, 48, UC_WHITE, bg);
            uc_set(x + width + 3, y, 48, UC_WHITE, bg);
        }
        uc_set(x + width + 3, y, 37, UC_WHITE, bg);
    }
    return 0;
}

# uc_digital_clock：数字时钟 —— 把小时:分钟绘制到画布（两位数字，用冒号）
# 用 3x5 点阵数字（'0'-'9' 的字符表示），复用 uc_sprite
fn uc_digit(x: i64, y: i64, d: i64, fg: i64, bg: i64) -> i64 {
    if d == 0 { uc_sprite(x, y, "###,#.#,#.#,#.#,###", fg, bg); }
    if d == 1 { uc_sprite(x, y, "..#,##.,..#,..#,###", fg, bg); }
    if d == 2 { uc_sprite(x, y, "###,..#,###,#..,###", fg, bg); }
    if d == 3 { uc_sprite(x, y, "###,..#,###,..#,###", fg, bg); }
    if d == 4 { uc_sprite(x, y, "#.#,#.#,###,..#,..#", fg, bg); }
    if d == 5 { uc_sprite(x, y, "###,#..,###,..#,###", fg, bg); }
    if d == 6 { uc_sprite(x, y, "###,#..,###,#.#,###", fg, bg); }
    if d == 7 { uc_sprite(x, y, "###,..#,..#,..#,..#", fg, bg); }
    if d == 8 { uc_sprite(x, y, "###,#.#,###,#.#,###", fg, bg); }
    if d == 9 { uc_sprite(x, y, "###,#.#,###,..#,###", fg, bg); }
    return 0;
}

# uc_digit2：两位数字（10-99），用于分钟/秒
fn uc_digit2(x: i64, y: i64, v: i64, fg: i64, bg: i64) -> i64 {
    uc_digit(x, y, v / 10, fg, bg);
    uc_digit(x + 4, y, v - (v / 10) * 10, fg, bg);
    return 0;
}

# ============ v1.353 画布滚动 ============

# uc_scroll：平移整个画布（dx 水平，dy 垂直）
# 内容移动后，空出的边缘用背景色填充
# 用于动画帧切换、滚动视图等动态 UI
fn uc_scroll(dx: i64, dy: i64, fill_ch: i64, fill_fg: i64, fill_bg: i64) -> i64 {
    let x: i64 = 0;
    let y: i64 = 0;
    let nx: i64 = 0;
    let ny: i64 = 0;
    let sxp: [6000] byte = 0;
    let syp: [6000] byte = 0;
    let scp: [6000] byte = 0;
    let sfp: [6000] byte = 0;
    let sbp: [6000] byte = 0;
    # 复制当前画布（字符/前景/背景）
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            scp[idx] = UC_CH[idx];
            sfp[idx] = UC_FG[idx];
            sbp[idx] = UC_BG[idx];
            sxp[idx] = x;
            syp[idx] = y;
            x = x + 1;
        }
        y = y + 1;
    }
    # 清空画布为填充色
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            UC_CH[idx] = fill_ch;
            UC_FG[idx] = fill_fg;
            UC_BG[idx] = fill_bg;
            UC_ST[idx] = 0;
            x = x + 1;
        }
        y = y + 1;
    }
    # 按平移量放置原内容
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            let idx: i64 = y * UC_W + x;
            nx = sxp[idx] + dx;
            ny = syp[idx] + dy;
            if nx >= 0 && nx < UC_W && ny >= 0 && ny < UC_H {
                let nidx: i64 = ny * UC_W + nx;
                UC_CH[nidx] = scp[idx];
                UC_FG[nidx] = sfp[idx];
                UC_BG[nidx] = sbp[idx];
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return 0;
}

# ============ v1.354 区域复制/粘贴 ============

# 画布剪贴板（全局）
var UC_CLIP: [6000] byte = 0;
var UC_CLIPFG: [6000] byte = 0;
var UC_CLIPBG: [6000] byte = 0;
var UC_CLIPW: i64 = 0;
var UC_CLIPH: i64 = 0;

# uc_copy：复制画布区域到剪贴板
fn uc_copy(x: i64, y: i64, w: i64, h: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    if w < 0 { w = 0; }
    if h < 0 { h = 0; }
    if x + w > UC_W { w = UC_W - x; }
    if y + h > UC_H { h = UC_H - y; }
    UC_CLIPW = w;
    UC_CLIPH = h;
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            let sx: i64 = x + i;
            let sy: i64 = y + j;
            if sx >= 0 && sx < UC_W && sy >= 0 && sy < UC_H {
                let sidx: i64 = sy * UC_W + sx;
                UC_CLIP[j * UC_CLIPW + i] = UC_CH[sidx];
                UC_CLIPFG[j * UC_CLIPW + i] = UC_FG[sidx];
                UC_CLIPBG[j * UC_CLIPW + i] = UC_BG[sidx];
            } else {
                UC_CLIP[j * UC_CLIPW + i] = 32;
                UC_CLIPFG[j * UC_CLIPW + i] = 7;
                UC_CLIPBG[j * UC_CLIPW + i] = 0;
            }
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# uc_paste：粘贴剪贴板到画布 (x,y)
fn uc_paste(x: i64, y: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    j = 0;
    while j < UC_CLIPH {
        i = 0;
        while i < UC_CLIPW {
            let dx: i64 = x + i;
            let dy: i64 = y + j;
            if dx >= 0 && dx < UC_W && dy >= 0 && dy < UC_H {
                let didx: i64 = dy * UC_W + dx;
                UC_CH[didx] = UC_CLIP[j * UC_CLIPW + i];
                UC_FG[didx] = UC_CLIPFG[j * UC_CLIPW + i];
                UC_BG[didx] = UC_CLIPBG[j * UC_CLIPW + i];
            }
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# ============ v1.355 翻转与旋转 ============

# uc_flip_h：水平翻转整个画布
fn uc_flip_h() -> i64 {
    let x: i64 = 0;
    let y: i64 = 0;
    let tmpc: i64 = 0;
    let tmpf: i64 = 0;
    let tmpb: i64 = 0;
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W / 2 {
            let a: i64 = y * UC_W + x;
            let b: i64 = y * UC_W + (UC_W - 1 - x);
            tmpc = UC_CH[a];
            tmpf = UC_FG[a];
            tmpb = UC_BG[a];
            UC_CH[a] = UC_CH[b];
            UC_FG[a] = UC_FG[b];
            UC_BG[a] = UC_BG[b];
            UC_CH[b] = tmpc;
            UC_FG[b] = tmpf;
            UC_BG[b] = tmpb;
            x = x + 1;
        }
        y = y + 1;
    }
    return 0;
}

# uc_flip_v：垂直翻转整个画布
fn uc_flip_v() -> i64 {
    let x: i64 = 0;
    let y: i64 = 0;
    let tmpc: i64 = 0;
    let tmpf: i64 = 0;
    let tmpb: i64 = 0;
    y = 0;
    while y < UC_H / 2 {
        x = 0;
        while x < UC_W {
            let a: i64 = y * UC_W + x;
            let b: i64 = (UC_H - 1 - y) * UC_W + x;
            tmpc = UC_CH[a];
            tmpf = UC_FG[a];
            tmpb = UC_BG[a];
            UC_CH[a] = UC_CH[b];
            UC_FG[a] = UC_FG[b];
            UC_BG[a] = UC_BG[b];
            UC_CH[b] = tmpc;
            UC_FG[b] = tmpf;
            UC_BG[b] = tmpb;
            x = x + 1;
        }
        y = y + 1;
    }
    return 0;
}

# ============ v1.357 圆角矩形 ============

# uc_round_rect：圆角矩形边框
# 四角用圆角字符 '.'，上下边 '-'，左右边 '|'
fn uc_round_rect(x: i64, y: i64, w: i64, h: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if w < 3 { w = 3; }
    if h < 3 { h = 3; }
    # 四角
    uc_set(x, y, '.', fg, bg);
    uc_set(x + w - 1, y, '.', fg, bg);
    uc_set(x, y + h - 1, '.', fg, bg);
    uc_set(x + w - 1, y + h - 1, '.', fg, bg);
    # 上下边
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y, '-', fg, bg);
        uc_set(x + i, y + h - 1, '-', fg, bg);
        i = i + 1;
    }
    # 左右边
    i = 1;
    while i < h - 1 {
        uc_set(x, y + i, '|', fg, bg);
        uc_set(x + w - 1, y + i, '|', fg, bg);
        i = i + 1;
    }
    return 0;
}

# uc_fill_round：实心圆角矩形 —— 填充内部区域
fn uc_fill_round(x: i64, y: i64, w: i64, h: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    if w < 3 { w = 3; }
    if h < 3 { h = 3; }
    # 填充整个矩形区域（含边）
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            uc_set(x + i, y + j, ch, fg, bg);
            i = i + 1;
        }
        j = j + 1;
    }
    # 四角清为背景色
    uc_set(x, y, 32, fg, bg);
    uc_set(x + w - 1, y, 32, fg, bg);
    uc_set(x, y + h - 1, 32, fg, bg);
    uc_set(x + w - 1, y + h - 1, 32, fg, bg);
    return 0;
}

# ============ v1.358 网格与坐标轴 ============

# uc_grid：绘制网格 —— 指定区域画网格线（水平/垂直，间距 step）
fn uc_grid(x: i64, y: i64, w: i64, h: i64, step: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if step < 1 { step = 1; }
    # 垂直线
    i = 0;
    while i <= w {
        uc_vline(x + i, y, h, ch, fg, bg);
        i = i + step;
    }
    # 水平线
    i = 0;
    while i <= h {
        uc_hline(x, y + i, w, ch, fg, bg);
        i = i + step;
    }
    return 0;
}

# uc_axis：绘制坐标轴 —— 原点 (ox,oy)，向右为 X，向上为 Y
# 带箭头字符（X 轴右端 '>', Y 轴上端 '^'）和刻度标记
fn uc_axis(ox: i64, oy: i64, len_x: i64, len_y: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    # X 轴（水平向右）
    i = 0;
    while i <= len_x {
        uc_set(ox + i, oy, '-', fg, bg);
        i = i + 1;
    }
    uc_set(ox + len_x, oy, '>', fg, bg);
    # Y 轴（垂直向上）
    i = 0;
    while i <= len_y {
        uc_set(ox, oy - i, '|', fg, bg);
        i = i + 1;
    }
    uc_set(ox, oy - len_y, '^', fg, bg);
    # 原点
    uc_set(ox, oy, '+', fg, bg);
    return 0;
}

# ============ v1.359 SVG 导出 ============

# uc_dump_svg：把画布导出为 SVG 矢量图文件（浏览器可打开，可无限缩放）
# 每个字符渲染为 <text> 元素，等宽字体，颜色映射。
fn uc_dump_svg(path: ptr) -> i64 {
    let y: i64 = 0;
    let x: i64 = 0;
    let fd: i64 = 0;
    let c: i64 = 0;
    let fgc: i64 = 0;
    let b: [256] byte = 0;
    let cw: i64 = 0;
    let chh: i64 = 0;
    cw = 10;   # 每字符宽（像素）
    chh = 16;  # 每字符高（像素）
    fd = fopen(path, 577, 438);
    if fd < 0 {
        print("✗ 无法写入 ");
        print(path);
        print_nl();
        return 1;
    }
    # SVG 头（含背景色）
    fwrite(fd, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"", strlen("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""));
    # 宽度 = UC_W * cw
    # 用数字转字符串（简化：写死用 utoa）
    let n: [24] byte = 0;
    utoa(UC_W * cw, &n, 10);
    fwrite(fd, &n, strlen(&n));
    fwrite(fd, "\" height=\"", strlen("\" height=\""));
    utoa(UC_H * chh, &n, 10);
    fwrite(fd, &n, strlen(&n));
    fwrite(fd, "\" viewBox=\"0 0 ", strlen("\" viewBox=\"0 0 "));
    utoa(UC_W * cw, &n, 10);
    fwrite(fd, &n, strlen(&n));
    fwrite(fd, " ", strlen(" "));
    utoa(UC_H * chh, &n, 10);
    fwrite(fd, &n, strlen(&n));
    fwrite(fd, "\"><rect width=\"100%\" height=\"100%\" fill=\"#008\"/>\n", strlen("\"><rect width=\"100%\" height=\"100%\" fill=\"#008\"/>\n"));
    y = 0;
    while y < UC_H {
        x = 0;
        while x < UC_W {
            c = UC_CH[y * UC_W + x];
            fgc = UC_FG[y * UC_W + x];
            if c == 0 { c = 32; }
            if fgc < 0 { fgc = 7; }
            if fgc > 7 { fgc = 7; }
            if c != 32 {
                # <text x="X" y="Y" fill="COLOR" font-family="monospace" font-size="14">c</text>
                fwrite(fd, "<text x=\"", strlen("<text x=\""));
                utoa(x * cw, &n, 10);
                fwrite(fd, &n, strlen(&n));
                fwrite(fd, "\" y=\"", strlen("\" y=\""));
                utoa(y * chh + 12, &n, 10);
                fwrite(fd, &n, strlen(&n));
                fwrite(fd, "\" fill=\"", strlen("\" fill=\""));
                fwrite(fd, uc_fgname(fgc), strlen(uc_fgname(fgc)));
                fwrite(fd, "\" font-family=\"monospace\" font-size=\"14\">", strlen("\" font-family=\"monospace\" font-size=\"14\">"));
                if c == 60 {
                    fwrite(fd, "&lt;", strlen("&lt;"));
                } else {
                    if c == 62 {
                        fwrite(fd, "&gt;", strlen("&gt;"));
                    } else {
                        if c == 38 {
                            fwrite(fd, "&amp;", strlen("&amp;"));
                        } else {
                            b[0] = c;
                            fwrite(fd, &b, 1);
                        }
                    }
                }
                fwrite(fd, "</text>", strlen("</text>"));
            }
            x = x + 1;
        }
        y = y + 1;
    }
    fwrite(fd, "\n</svg>\n", strlen("\n</svg>\n"));
    fclose(fd);
    return 0;
}

# ============ v1.360 键盘输入 ============

# uc_read_key：读取一个按键（阻塞）
# 返回按下的字符的 ASCII 码；EOF 返回 -1
# 用于交互式画布应用（移动角色、菜单选择等）
fn uc_read_key() -> i64 {
    let buf: [1] byte = 0;
    let n: i64 = 0;
    n = syscall(63, 0, &buf, 1, 0, 0, 0);
    if n < 1 { return -1; }
    return buf[0];
}


# uc_has_key：非阻塞检查键盘是否有按键（select syscall）
# 有按键返回 1，否则返回 0
var UC_FDS: [16] byte = 0;
var UC_TV: [16] byte = 0;
fn uc_has_key() -> i64 {
    let i: i64 = 0;
    let r: i64 = 0;
    let sel: i64 = 0;
    i = 0;
    while i < 16 {
        UC_FDS[i] = 0;
        i = i + 1;
    }
    UC_FDS[0] = 1;      # fd 0 就绪位
    UC_TV[0] = 0;       # timeout 0 秒（非阻塞）
    UC_TV[8] = 0;       # 0 微秒
    sel = 23;           # select syscall（用变量避免 mo2x 静态误判）
    r = syscall(sel, 1, &UC_FDS, 0, 0, &UC_TV, 0);
    if r < 1 { return 0; }
    return 1;
}

# ============ v1.361 渐变填充 ============

# uc_gradient：垂直渐变填充区域
# 用字符密度模拟亮度渐变（密 → 疏）：@ % # * + = - . [空格]
# 适用于图表、仪表盘、游戏血条、视觉装饰。
fn uc_gradient(x: i64, y: i64, w: i64, h: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let chars: [11] byte = 0;
    let step: i64 = 0;
    let idx: i64 = 0;
    chars[0] = 64;   # @
    chars[1] = 37;   # %
    chars[2] = 35;   # #
    chars[3] = 42;   # *
    chars[4] = 43;   # +
    chars[5] = 61;   # =
    chars[6] = 45;   # -
    chars[7] = 46;   # .
    chars[8] = 32;   # 空格
    chars[9] = 32;
    chars[10] = 32;
    if h < 1 { return 0; }
    step = h / 10;
    if step < 1 { step = 1; }
    j = 0;
    while j < h {
        idx = j / step;
        if idx > 10 { idx = 10; }
        i = 0;
        while i < w {
            uc_set(x + i, y + j, chars[idx], fg, bg);
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# ============ v1.363 滚动文本（跑马灯） ============

# uc_marquee：在固定宽度窗口内显示滚动文本（跑马灯）
# x,y 为窗口左上角，w 为窗口宽度
# offset 为滚动偏移（0 = 文本右端贴窗口右缘；每 +1 文本左移一位）
# 超出窗口部分的文本被裁剪。返回文本长度。
fn uc_marquee(x: i64, y: i64, text: ptr, w: i64, offset: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let scrx: i64 = 0;
    let ci: i64 = 0;
    len = strlen(text);
    # 每个字符在窗口内的屏幕位置 = x + (i - offset + w - 1)
    i = 0;
    while i < len {
        scrx = x + (i - offset + w - 1);
        if scrx >= x {
            if scrx < x + w {
                uc_set(scrx, y, text[i], fg, bg);
            }
        }
        i = i + 1;
    }
    return len;
}

# ============ v1.364 更多图形 ============

# uc_diamond：绘制菱形边框（中心 cx,cy，半宽 rw，半高 rh）
# 用 ASCII 字符画菱形轮廓，用于图标、装饰、游戏。
fn uc_diamond(cx: i64, cy: i64, rw: i64, rh: i64, ch: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    if rw < 1 { rw = 1; }
    if rh < 1 { rh = 1; }
    # 上半部分（从顶点到底部中心）
    j = 0;
    while j <= rh {
        i = 0;
        while i <= j * rw / rh {
            uc_set(cx + i, cy + j - rh, ch, fg, bg);
            uc_set(cx - i, cy + j - rh, ch, fg, bg);
            i = i + 1;
        }
        j = j + 1;
    }
    # 下半部分
    j = rh;
    while j >= 0 {
        i = 0;
        while i <= j * rw / rh {
            uc_set(cx + i, cy + rh - j, ch, fg, bg);
            uc_set(cx - i, cy + rh - j, ch, fg, bg);
            i = i + 1;
        }
        j = j - 1;
    }
    return 0;
}

# ============ v1.365 精灵图 ============

# uc_draw_sprite：从字符串模板绘制 2D 精灵
# sprite 是 w*h 个字符，按行排列。
# 字符为空格 ' ' 表示透明（跳过不绘制），其他字符绘制到画布。
# 用于游戏角色、图标库、复杂图案复用。
fn uc_draw_sprite(x: i64, y: i64, sprite: ptr, w: i64, h: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let c: i64 = 0;
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            c = sprite[j * w + i];
            if c != 32 {
                uc_set(x + i, y + j, c, fg, bg);
            }
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# ============ v1.366 场景快照 ============

# 画布快照缓冲（保存整个画布用于场景切换）
var UC_SNAP: [6000] byte = 0;
var UC_SNAP_FG: [6000] byte = 0;
var UC_SNAP_BG: [6000] byte = 0;

# uc_save_scene：保存当前画布到快照缓冲
fn uc_save_scene() -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < UC_W * UC_H {
        UC_SNAP[i] = UC_CH[i];
        UC_SNAP_FG[i] = UC_FG[i];
        UC_SNAP_BG[i] = UC_BG[i];
        i = i + 1;
    }
    return 0;
}

# uc_load_scene：从快照缓冲恢复画布
fn uc_load_scene() -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < UC_W * UC_H {
        UC_CH[i] = UC_SNAP[i];
        UC_FG[i] = UC_SNAP_FG[i];
        UC_BG[i] = UC_SNAP_BG[i];
        i = i + 1;
    }
    return 0;
}

# uc_swap_scene：交换当前画布与快照（用于动画双缓冲）
fn uc_swap_scene() -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    i = 0;
    while i < UC_W * UC_H {
        t = UC_CH[i];
        UC_CH[i] = UC_SNAP[i];
        UC_SNAP[i] = t;
        t = UC_FG[i];
        UC_FG[i] = UC_SNAP_FG[i];
        UC_SNAP_FG[i] = t;
        t = UC_BG[i];
        UC_BG[i] = UC_SNAP_BG[i];
        UC_SNAP_BG[i] = t;
        i = i + 1;
    }
    return 0;
}

# ============ v1.367 多样式边框 ============

# uc_border：绘制多样式边框
# style: 1=单线(-|+角), 2=双线(=||+角), 3=粗线(#), 4=虚线(- - -)
fn uc_border(x: i64, y: i64, w: i64, h: i64, style: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let hc: i64 = 0;
    let vc: i64 = 0;
    let tl: i64 = 0;
    let tr: i64 = 0;
    let bl: i64 = 0;
    let br: i64 = 0;
    if style == 2 {
        hc = 61; vc = 124; tl = 43; tr = 43; bl = 43; br = 43;  # 双线用 = 和 | 和 +
    } else {
        if style == 3 {
            hc = 35; vc = 35; tl = 35; tr = 35; bl = 35; br = 35;  # 粗线 #
        } else {
            if style == 4 {
                hc = 45; vc = 124; tl = 43; tr = 43; bl = 43; br = 43;  # 虚线 - 和 |
            } else {
                hc = 45; vc = 124; tl = 43; tr = 43; bl = 43; br = 43;  # 单线
            }
        }
    }
    if w < 3 { w = 3; }
    if h < 3 { h = 3; }
    # 四角
    uc_set(x, y, tl, fg, bg);
    uc_set(x + w - 1, y, tr, fg, bg);
    uc_set(x, y + h - 1, bl, fg, bg);
    uc_set(x + w - 1, y + h - 1, br, fg, bg);
    # 上下边
    i = 1;
    while i < w - 1 {
        if style == 4 {
            if i % 2 == 1 { uc_set(x + i, y, hc, fg, bg); }
            if (w - 1 - i) % 2 == 1 { uc_set(x + i, y + h - 1, hc, fg, bg); }
        } else {
            uc_set(x + i, y, hc, fg, bg);
            uc_set(x + i, y + h - 1, hc, fg, bg);
        }
        i = i + 1;
    }
    # 左右边
    i = 1;
    while i < h - 1 {
        uc_set(x, y + i, vc, fg, bg);
        uc_set(x + w - 1, y + i, vc, fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.368 反色区域 ============

# uc_reverse：反色指定区域（前景/背景互换）
# 用于菜单选中高亮、列表焦点、按钮按下效果。
fn uc_reverse(x: i64, y: i64, w: i64, h: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let t: i64 = 0;
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            t = UC_FG[(y + j) * UC_W + x + i];
            UC_FG[(y + j) * UC_W + x + i] = UC_BG[(y + j) * UC_W + x + i];
            UC_BG[(y + j) * UC_W + x + i] = t;
            i = i + 1;
        }
        j = j + 1;
    }
    return 0;
}

# ============ v1.369 按钮组件 ============

# uc_button：绘制一个按钮
# x,y 左上角，w 宽度，label 按钮文本（居中显示）
# active=1 时反色（选中/按下态），否则普通凸起风格。
fn uc_button(x: i64, y: i64, w: i64, label: ptr, fg: i64, bg: i64, active: i64) -> i64 {
    let len: i64 = 0;
    let pad: i64 = 0;
    let i: i64 = 0;
    if w < 4 { w = 4; }
    len = strlen(label);
    # 计算左右 padding 使文本居中
    pad = (w - len) / 2;
    if pad < 1 { pad = 1; }
    # 顶部边框
    uc_set(x, y, '[', fg, bg);
    uc_set(x + w - 1, y, ']', fg, bg);
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y, '-', fg, bg);
        i = i + 1;
    }
    # 按钮文本行
    i = 0;
    while i < w {
        if i == 0 {
            uc_set(x, y + 1, '|', fg, bg);
        } else {
            if i == w - 1 {
                uc_set(x + i, y + 1, '|', fg, bg);
            } else {
                if i >= pad {
                    if i - pad < len {
                        uc_set(x + i, y + 1, label[i - pad], fg, bg);
                    } else {
                        uc_set(x + i, y + 1, 32, fg, bg);
                    }
                } else {
                    uc_set(x + i, y + 1, 32, fg, bg);
                }
            }
        }
        i = i + 1;
    }
    # 底部边框
    uc_set(x, y + 2, '[', fg, bg);
    uc_set(x + w - 1, y + 2, ']', fg, bg);
    i = 1;
    while i < w - 1 {
        uc_set(x + i, y + 2, '-', fg, bg);
        i = i + 1;
    }
    # active 时反色整个按钮区域
    if active == 1 {
        uc_reverse(x, y, w, 3);
    }
    return 0;
}

# ============ v1.370 旋转指示器 ============

# uc_spinner：绘制旋转加载指示器
# frame 为帧序号（0-3 循环），产生旋转动画效果。
# 显示字符：| / - \ 依次旋转。用于加载中状态。
fn uc_spinner(x: i64, y: i64, frame: i64, fg: i64, bg: i64) -> i64 {
    let c: i64 = 0;
    if frame % 4 == 0 { c = 124; }     # |
    if frame % 4 == 1 { c = 47; }      # /
    if frame % 4 == 2 { c = 45; }      # -
    if frame % 4 == 3 { c = 92; }      # \
    uc_set(x, y, c, fg, bg);
    return 0;
}

# ============ v1.371 文本特效 ============

# uc_text_shadow：带阴影的文本
# 先绘制阴影（右下偏移 1 格，用 shadow_fg），再绘制正文。
# 用于标题、Logo、强调文本。
fn uc_text_shadow(x: i64, y: i64, text: ptr, fg: i64, shadow_fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(text);
    # 阴影
    i = 0;
    while i < len {
        uc_set(x + 1 + i, y + 1, text[i], shadow_fg, bg);
        i = i + 1;
    }
    # 正文
    i = 0;
    while i < len {
        uc_set(x + i, y, text[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# uc_text_center：在指定宽度内水平居中显示文本
# 用于对话框标题、窗口标题居中。
fn uc_text_center(x: i64, y: i64, w: i64, text: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let start: i64 = 0;
    let i: i64 = 0;
    len = strlen(text);
    start = x + (w - len) / 2;
    if start < x { start = x; }
    i = 0;
    while i < len {
        uc_set(start + i, y, text[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.372 窗口移动 ============

# uc_move_window：移动画布上的一个窗口区域到新位置
# 复制 (x,y,w,h) 的内容到 (nx,ny)，并清空原区域。
# 用于窗口拖拽、面板重排、游戏对象移动。
fn uc_move_window(x: i64, y: i64, w: i64, h: i64, nx: i64, ny: i64, fill: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    # 复制到剪贴板
    uc_copy(x, y, w, h);
    # 清空原区域
    j = 0;
    while j < h {
        i = 0;
        while i < w {
            uc_set(x + i, y + j, fill, fg, bg);
            i = i + 1;
        }
        j = j + 1;
    }
    # 粘贴到新位置
    uc_paste(nx, ny);
    return 0;
}

# ============ v1.373 菜单栏 ============

# uc_menu_bar：绘制横向菜单栏
# items 为空格分隔的菜单项字符串，active_idx 为选中项（反色高亮）
# x,y 为菜单栏左上角，w 为总宽度（不足自动扩展）
fn uc_menu_bar(x: i64, y: i64, w: i64, items: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let idx: i64 = 0;
    let cx: i64 = 0;
    let item_start: i64 = 0;
    let active_x: i64 = 0;
    let active_w: i64 = 0;
    len = strlen(items);
    cx = x;
    item_start = 0;
    idx = 0;
    # 第一遍：先填满背景（避免残留）
    i = 0;
    while i < w {
        uc_set(x + i, y, 32, fg, bg);
        i = i + 1;
    }
    i = 0;
    while i < len {
        if items[i] == 32 {
            # 空格分隔：结束一个菜单项
            if i > item_start {
                if idx == active_idx {
                    active_x = cx - (i - item_start);
                    active_w = i - item_start;
                }
                idx = idx + 1;
                item_start = i + 1;
            }
        } else {
            if cx < x + w {
                uc_set(cx, y, items[i], fg, bg);
            }
            cx = cx + 1;
        }
        i = i + 1;
    }
    # 最后一个菜单项
    if len > item_start {
        if idx == active_idx {
            active_x = cx - (len - item_start);
            active_w = len - item_start;
        }
    }
    # 反色选中项
    if active_w > 0 {
        uc_reverse(active_x, y, active_w, 1);
    }
    return 0;
}


fn uc_menu(x: i64, y: i64, items: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let idx: i64 = 0;
    let ch: i64 = 0;
    let start: i64 = 0;
    i = 0;
    idx = 0;
    start = x;
    while 1 == 1 {
        ch = items[i];
        if ch == 0 { break; }
        if ch == 124 {
            uc_set(start, y, ' ', fg, bg);
            start = start + 1;
            idx = idx + 1;
        } else {
            if idx == active_idx {
                uc_set(start, y, ch, UC_BLACK, UC_YELLOW);
            } else {
                uc_set(start, y, ch, fg, bg);
            }
            start = start + 1;
        }
        i = i + 1;
    }
    return 0;
}
# ============ v1.374 徽章 ============

# uc_badge：绘制一个徽章/角标
# 左侧标签 + 右侧数值，用不同的前景色。
# 例如 uc_badge(x, y, "tests", "249", ...) 显示 [tests|249]
fn uc_badge(x: i64, y: i64, label: ptr, value: ptr, fg1: i64, fg2: i64, bg: i64) -> i64 {
    let l1: i64 = 0;
    let l2: i64 = 0;
    let i: i64 = 0;
    l1 = strlen(label);
    l2 = strlen(value);
    # 标签部分
    i = 0;
    while i < l1 {
        uc_set(x + i, y, label[i], fg1, bg);
        i = i + 1;
    }
    # 分隔
    uc_set(x + l1, y, '|', fg1, bg);
    # 数值部分
    i = 0;
    while i < l2 {
        uc_set(x + l1 + 1 + i, y, value[i], fg2, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.375 提示框 ============

# uc_tooltip：绘制小提示框（带边框）
# 在 (x,y) 处显示提示文本，自动包裹边框。
# 用于悬浮提示、帮助信息、小标签。
fn uc_tooltip(x: i64, y: i64, text: ptr, fg: i64, bg: i64, bfg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(text);
    if len < 2 { len = 2; }
    # 边框
    uc_set(x, y, '.', bfg, bg);
    uc_set(x + len + 1, y, '.', bfg, bg);
    uc_set(x, y + 2, '.', bfg, bg);
    uc_set(x + len + 1, y + 2, '.', bfg, bg);
    i = 1;
    while i <= len {
        uc_set(x + i, y, '-', bfg, bg);
        uc_set(x + i, y + 2, '-', bfg, bg);
        i = i + 1;
    }
    uc_set(x, y + 1, '|', bfg, bg);
    uc_set(x + len + 1, y + 1, '|', bfg, bg);
    # 文本
    i = 0;
    while i < len {
        uc_set(x + 1 + i, y + 1, text[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.376 信号强度指示器 ============

# uc_signal：绘制信号强度指示器（阶梯状）
# level 为当前强度（0..max），max 为总格数。
# 每格用 '|' 表示已激活，空格表示未激活。
# 用于网络强度、电池电量、信号指示。
fn uc_signal(x: i64, y: i64, level: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if max < 1 { max = 1; }
    if level < 0 { level = 0; }
    if level > max { level = max; }
    i = 0;
    while i < max {
        if i < level {
            uc_set(x + i, y, '|', fg, bg);
        } else {
            uc_set(x + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.377 系统状态栏 ============

# uc_status_bar：绘制系统状态栏（移动端风格）
# 左侧文本，中间信号强度（level/max），右侧电池电量（battery 0-100）。
# 用于移动端 UI、仪表盘、游戏 HUD。
fn uc_status_bar(x: i64, y: i64, w: i64, text: ptr, level: i64, max: i64, battery: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let bblocks: i64 = 0;
    len = strlen(text);
    if len > w - 8 { len = w - 8; }
    # 清空状态栏区域
    i = 0;
    while i < w {
        uc_set(x + i, y, 32, fg, bg);
        i = i + 1;
    }
    # 左侧文本
    i = 0;
    while i < len {
        uc_set(x + i, y, text[i], fg, bg);
        i = i + 1;
    }
    # 分隔
    uc_set(x + len, y, '|', fg, bg);
    # 信号强度
    i = 0;
    while i < max {
        if i < level {
            uc_set(x + len + 2 + i, y, '|', fg, bg);
        } else {
            uc_set(x + len + 2 + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    # 电池
    if battery < 0 { battery = 0; }
    if battery > 100 { battery = 100; }
    bblocks = battery * 3 / 100;
    if bblocks < 0 { bblocks = 0; }
    if bblocks > 3 { bblocks = 3; }
    uc_set(x + w - 6, y, '[', fg, bg);
    i = 0;
    while i < 3 {
        if i < bblocks {
            uc_set(x + w - 5 + i, y, '=', fg, bg);
        } else {
            uc_set(x + w - 5 + i, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + w - 2, y, ']', fg, bg);
    return 0;
}

# ============ v1.378 垂直刻度条 ============

# uc_thermo：垂直刻度条（温度计/水位/内存）
# x,y 为底部坐标，h 为高度，pct 为百分比（0-100）
# 底部 pct% 填充 '#'，上部留空，带边框。
fn uc_thermo(x: i64, y: i64, h: i64, pct: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let fill_h: i64 = 0;
    if h < 3 { h = 3; }
    if pct < 0 { pct = 0; }
    if pct > 100 { pct = 100; }
    fill_h = h * pct / 100;
    if fill_h < 0 { fill_h = 0; }
    if fill_h > h { fill_h = h; }
    # 边框
    i = 0;
    while i < h {
        uc_set(x, y - i, '|', fg, bg);
        uc_set(x + 2, y - i, '|', fg, bg);
        i = i + 1;
    }
    # 填充
    i = 0;
    while i < fill_h {
        uc_set(x + 1, y - i, '#', fg, bg);
        i = i + 1;
    }
    # 顶部圆盖
    uc_set(x + 1, y - h, '.', fg, bg);
    return 0;
}

# ============ v1.379 列表框 ============

# uc_listbox：绘制列表选择框
# items 为换行/空格分隔的列表项字符串（用 '|' 分隔更直观）
# active_idx 为选中项（反色高亮），x,y 左上角，w 宽度
fn uc_listbox(x: i64, y: i64, w: i64, items: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let idx: i64 = 0;
    let row: i64 = 0;
    let col: i64 = 0;
    let nrows: i64 = 0;
    len = strlen(items);
    # 计算行数
    nrows = 1;
    i = 0;
    while i < len {
        if items[i] == 124 { nrows = nrows + 1; }
        i = i + 1;
    }
    if nrows < 1 { nrows = 1; }
    # 绘制边框（高度 = 行数 + 2）
    uc_border(x, y, w + 2, nrows + 2, 1, fg, bg);
    # 绘制列表项
    row = y + 1;
    col = x + 1;
    idx = 0;
    i = 0;
    while i < len {
        if items[i] == 124 {
            idx = idx + 1;
            row = row + 1;
            col = x + 1;
        } else {
            if col < x + 1 + w {
                uc_set(col, row, items[i], fg, bg);
            }
            col = col + 1;
        }
        i = i + 1;
    }
    # 反色选中行
    if active_idx >= 0 {
        if active_idx < nrows {
            uc_reverse(x + 1, y + 1 + active_idx, w, 1);
        }
    }
    return 0;
}
# ============ v1.380 模拟时钟 ============

# uc_clock_face：绘制模拟时钟钟面
# cx,cy 为钟面中心，r 为半径。显示 12/3/6/9 数字。
# hh,mm 为时分（12 小时制），用 'H' 标记时针位置。
fn uc_clock_face(cx: i64, cy: i64, r: i64, hh: i64, mm: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let hpos: i64 = 0;
    if r < 3 { r = 3; }
    # 钟面圆圈（用矩形近似）
    uc_round_rect(cx - r, cy - r, r * 2 + 1, r * 2 + 1, fg, bg);
    # 12 点
    uc_set(cx, cy - r + 1, '^', fg, bg);
    # 3 点
    uc_set(cx + r - 1, cy, '>', fg, bg);
    # 6 点
    uc_set(cx, cy + r - 1, 'v', fg, bg);
    # 9 点
    uc_set(cx - r + 1, cy, '<', fg, bg);
    # 中心
    uc_set(cx, cy, '+', fg, bg);
    # 时针位置（简化：按小时映射到钟面）
    hpos = (hh % 12) * (2 * r) / 12;
    i = 0;
    while i < hpos {
        uc_set(cx - hpos + i, cy, '-', fg, bg);
        i = i + 1;
    }
    # 分针位置（简化：向右延伸）
    i = 0;
    while i < mm * (r - 1) / 60 {
        uc_set(cx + i, cy, '.', fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.381 表情符号 ============

# uc_face：绘制表情符号（字符笑脸）
# type: 0=笑脸 :-)  1=哭脸 :-(  2=惊讶 :-o  3=爱心 <3  4=眨眼 ;-)
fn uc_face(x: i64, y: i64, type_: i64, fg: i64, bg: i64) -> i64 {
    if type_ == 0 {
        uc_set(x, y, ':', fg, bg);
        uc_set(x + 1, y, '-', fg, bg);
        uc_set(x + 2, y, ')', fg, bg);
    } else {
        if type_ == 1 {
            uc_set(x, y, ':', fg, bg);
            uc_set(x + 1, y, '-', fg, bg);
            uc_set(x + 2, y, '(', fg, bg);
        } else {
            if type_ == 2 {
                uc_set(x, y, ':', fg, bg);
                uc_set(x + 1, y, '-', fg, bg);
                uc_set(x + 2, y, 'o', fg, bg);
            } else {
                if type_ == 3 {
                    uc_set(x, y, '<', fg, bg);
                    uc_set(x + 1, y, '3', fg, bg);
                } else {
                    uc_set(x, y, ';', fg, bg);
                    uc_set(x + 1, y, '-', fg, bg);
                    uc_set(x + 2, y, ')', fg, bg);
                }
            }
        }
    }
    return 0;
}

# ============ v1.383 标签页 ============

# uc_tabs：绘制标签页（tab 栏）
# tabs 为 '|' 分隔的标签名，active_idx 为选中页（反色高亮）。
# 选中页下方显示横线。用于设置界面、多面板。
fn uc_tabs(x: i64, y: i64, tabs: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let idx: i64 = 0;
    let cx: i64 = 0;
    let start: i64 = 0;
    let active_start: i64 = 0;
    let active_len: i64 = 0;
    len = strlen(tabs);
    cx = x;
    start = x;
    idx = 0;
    i = 0;
    while i < len {
        if tabs[i] == 124 {  # '|'
            if idx == active_idx {
                active_start = start;
                active_len = cx - start;
            }
            idx = idx + 1;
            start = cx + 1;
            cx = cx + 1;
        } else {
            uc_set(cx, y, tabs[i], fg, bg);
            cx = cx + 1;
        }
        i = i + 1;
    }
    if idx == active_idx {
        active_start = start;
        active_len = cx - start;
    }
    # 选中页反色
    if active_len > 0 {
        uc_reverse(active_start, y, active_len, 1);
    }
    # 底部分隔线
    i = x;
    while i < cx {
        if i < active_start {
            uc_set(i, y + 1, '-', fg, bg);
        } else {
            if i >= active_start + active_len {
                uc_set(i, y + 1, '-', fg, bg);
            } else {
                uc_set(i, y + 1, ' ', fg, bg);
            }
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.384 树形视图 ============

# uc_tree：绘制树形视图（文件树/目录树）
# items 为 '|' 分隔的多行，每行是带缩进和树形前缀的文本。
# 直接原样绘制，用于文件浏览器、项目导航。
# 例如 "src|├─ main.mo|├─ lib.mo|└─ README.md"
fn uc_tree(x: i64, y: i64, items: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let row: i64 = 0;
    let col: i64 = 0;
    len = strlen(items);
    row = y;
    col = x;
    i = 0;
    while i < len {
        if items[i] == 124 {  # '|' 换行
            row = row + 1;
            col = x;
        } else {
            uc_set(col, row, items[i], fg, bg);
            col = col + 1;
        }
        i = i + 1;
    }
    return 0;
}
# ============ v1.385 数据表格 ============

# uc_table：绘制数据表格
# header 为 '|' 分隔的列标题。
# rows 为多行数据，行间用 ';' 分隔，单元格用 '|' 分隔。
# 表头反色高亮，列宽自动对齐。
# 例如 header="Name|Age|City", rows="Alice|25|NY;Bob|30|LA"
fn uc_table(x: i64, y: i64, w: i64, header: ptr, rows: ptr, fg: i64, bg: i64) -> i64 {
    let hlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    let row: i64 = 0;
    let col: i64 = 0;
    let ncol: i64 = 0;
    let cpos: i64 = 0;
    let j: i64 = 0;
    hlen = strlen(header);
    rlen = strlen(rows);
    if w < 2 { w = 2; }
    # 绘制表头
    row = y;
    ncol = 0;
    cpos = x;
    i = 0;
    while i < hlen {
        if header[i] == 124 {  # '|'
            ncol = ncol + 1;
            cpos = x + ncol * w;
        } else {
            uc_set(cpos, row, header[i], fg, bg);
            cpos = cpos + 1;
            if cpos >= x + (ncol + 1) * w {
                cpos = x + (ncol + 1) * w - 1;
            }
        }
        i = i + 1;
    }
    # 表头反色（多列分别反色）
    j = 0;
    while j <= ncol {
        uc_reverse(x + j * w, y, w, 1);
        j = j + 1;
    }
    # 绘制数据行
    row = y + 1;
    ncol = 0;
    cpos = x;
    i = 0;
    while i < rlen {
        if rows[i] == 59 {  # ';' 行分隔
            row = row + 1;
            ncol = 0;
            cpos = x;
        } else {
            if rows[i] == 124 {  # '|' 列分隔
                ncol = ncol + 1;
                cpos = x + ncol * w;
            } else {
                uc_set(cpos, row, rows[i], fg, bg);
                cpos = cpos + 1;
                if cpos >= x + (ncol + 1) * w {
                    cpos = x + (ncol + 1) * w - 1;
                }
            }
        }
        i = i + 1;
    }
    return 0;
}
# ============ v1.386 面包屑导航 ============

# uc_breadcrumb：绘制面包屑路径导航
# items 为 '|' 分隔的路径项，active_idx 为当前项（反色高亮）。
# 项之间用 '/' 分隔。用于导航、文件路径展示。
# 例如 "Home|Docs|Guide" active_idx=2 显示 "Home / Docs / Guide"（Guide 高亮）
fn uc_breadcrumb(x: i64, y: i64, items: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let idx: i64 = 0;
    let cx: i64 = 0;
    let start: i64 = 0;
    let active_start: i64 = 0;
    let active_len: i64 = 0;
    len = strlen(items);
    cx = x;
    start = x;
    idx = 0;
    i = 0;
    while i < len {
        if items[i] == 124 {  # '|'
            if idx == active_idx {
                active_start = start;
                active_len = cx - start;
            }
            idx = idx + 1;
            # 画 '/' 分隔符
            uc_set(cx, y, '/', fg, bg);
            cx = cx + 1;
            uc_set(cx, y, ' ', fg, bg);
            cx = cx + 1;
            start = cx;
        } else {
            uc_set(cx, y, items[i], fg, bg);
            cx = cx + 1;
        }
        i = i + 1;
    }
    if idx == active_idx {
        active_start = start;
        active_len = cx - start;
    }
    # 当前项反色
    if active_len > 0 {
        uc_reverse(active_start, y, active_len, 1);
    }
    return 0;
}

# ============ v1.387 评分星标 ============

# uc_stars：绘制评分星级
# rating 为当前分数（0..max），max 为总星数。
# 实星 '*' 表示已得分数，空星 '.' 表示未得分。
# 用于评价、星级展示。
fn uc_stars(x: i64, y: i64, rating: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if max < 1 { max = 1; }
    if rating < 0 { rating = 0; }
    if rating > max { rating = max; }
    i = 0;
    while i < max {
        if i < rating {
            uc_set(x + i, y, '*', fg, bg);
        } else {
            uc_set(x + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.388 开关组件 ============

# uc_toggle：绘制开关/切换按钮
# on=1 显示 [ON]（绿色），on=0 显示 [OFF]（红色）。
# 用于设置界面、权限开关。
fn uc_toggle(x: i64, y: i64, on: i64, fg: i64, bg: i64) -> i64 {
    if on != 0 {
        uc_set(x, y, '[', UC_GREEN, bg);
        uc_set(x + 1, y, 'O', UC_GREEN, bg);
        uc_set(x + 2, y, 'N', UC_GREEN, bg);
        uc_set(x + 3, y, ']', UC_GREEN, bg);
    } else {
        uc_set(x, y, '[', UC_RED, bg);
        uc_set(x + 1, y, 'O', UC_RED, bg);
        uc_set(x + 2, y, 'F', UC_RED, bg);
        uc_set(x + 3, y, 'F', UC_RED, bg);
        uc_set(x + 4, y, ']', UC_RED, bg);
    }
    return 0;
}

# ============ v1.389 下拉选择框 ============

# uc_dropdown：绘制下拉选择框
# label 为当前选中项文本，w 为框宽。
# 显示 [ label v ] 样式。用于表单、选择器。
fn uc_dropdown(x: i64, y: i64, w: i64, label: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(label);
    uc_set(x, y, '[', fg, bg);
    i = 0;
    while i < w {
        if i < len {
            uc_set(x + 1 + i, y, label[i], fg, bg);
        } else {
            uc_set(x + 1 + i, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + 1 + w, y, 'v', fg, bg);
    uc_set(x + 2 + w, y, ']', fg, bg);
    return 0;
}

# ============ v1.390 通知横幅 ============

# uc_toast：绘制通知/横幅提示
# text 为通知文本，w 为横幅宽度，level 决定颜色与图标：
#   0=信息（青色 'i'） 1=成功（绿色 'OK'） 2=警告（黄色 '!'） 3=错误（红色 'x'）
# 用于操作反馈、通知提醒。
fn uc_toast(x: i64, y: i64, w: i64, text: ptr, level: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    len = strlen(text);
    # 图标与颜色
    c = fg;
    uc_set(x, y, '[', c, bg);
    if level == 0 {
        uc_set(x + 1, y, 'i', UC_CYAN, bg);
    } else {
        if level == 1 {
            uc_set(x + 1, y, 'O', UC_GREEN, bg);
            uc_set(x + 2, y, 'K', UC_GREEN, bg);
        } else {
            if level == 2 {
                uc_set(x + 1, y, '!', UC_YELLOW, bg);
            } else {
                uc_set(x + 1, y, 'x', UC_RED, bg);
            }
        }
    }
    uc_set(x + 3, y, ']', c, bg);
    # 文本
    i = 0;
    while i < len {
        if x + 5 + i < x + w {
            uc_set(x + 5 + i, y, text[i], c, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.391 调色板 ============

# uc_palette：绘制颜色选择器（色块行）
# count 为色块数，active_idx 为选中色块（用 [ ] 高亮边框）。
# 每块 3 宽，颜色从 8 色中循环取。用于主题选择、颜色编辑。
fn uc_palette(x: i64, y: i64, count: i64, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let col: i64 = 0;
    let c: i64 = 0;
    i = 0;
    while i < count {
        col = x + i * 3;
        # 色块颜色（8 色循环）
        c = 1 + (i % 7);
        uc_set(col, y, ' ', c, c);
        uc_set(col + 1, y, ' ', c, c);
        uc_set(col + 2, y, ' ', c, c);
        if i == active_idx {
            uc_set(col - 1, y, '[', fg, bg);
            uc_set(col + 3, y, ']', fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.392 数值步进器 ============

# uc_stepper：绘制数值步进器 [ - 5 + ]
# value 为当前数值，w 为数值显示宽度。
# 用于表单数量调节、计数器。
fn uc_stepper(x: i64, y: i64, w: i64, value: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 0;
    let tmp: i64 = 0;
    let digits: i64 = 0;
    let pos: i64 = 0;
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, '-', fg, bg);
    uc_set(x + 2, y, ' ', fg, bg);
    # 计算位数
    tmp = value;
    if tmp < 0 { tmp = -tmp; }
    digits = 1;
    while tmp >= 10 {
        tmp = tmp / 10;
        digits = digits + 1;
    }
    # 绘制数值（右对齐到 w 宽）
    pos = x + 3 + w;
    tmp = value;
    if tmp < 0 {
        uc_set(pos - digits - 1, y, '-', fg, bg);
        tmp = -tmp;
    }
    i = 0;
    while i < digits {
        d = tmp % 10;
        tmp = tmp / 10;
        uc_set(pos - 1 - i, y, 48 + d, fg, bg);
        i = i + 1;
    }
    uc_set(x + 3 + w, y, ' ', fg, bg);
    uc_set(x + 4 + w, y, '+', fg, bg);
    uc_set(x + 5 + w, y, ']', fg, bg);
    return 0;
}

# ============ v1.393 终端窗口 ============

# uc_terminal：绘制终端/代码窗口
# title 为标题栏文本，line1/line2 为两行内容（line1 带 '$' 提示符）。
# 用于 IDE、终端模拟器、日志查看器。
fn uc_terminal(x: i64, y: i64, w: i64, h: i64, title: ptr, line1: ptr, line2: ptr, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let tlen: i64 = 0;
    let l1: i64 = 0;
    let l2: i64 = 0;
    tlen = strlen(title);
    l1 = strlen(line1);
    l2 = strlen(line2);
    # 边框
    uc_border(x, y, w + 2, h + 2, 1, fg, bg);
    # 标题栏（反色）
    uc_text(x + 1, y, title, fg, bg);
    uc_reverse(x + 1, y, w, 1);
    # 第一行：提示符 + 内容
    uc_set(x + 1, y + 1, '$', UC_GREEN, bg);
    i = 0;
    while i < l1 {
        if x + 3 + i < x + 1 + w {
            uc_set(x + 3 + i, y + 1, line1[i], fg, bg);
        }
        i = i + 1;
    }
    # 第二行
    i = 0;
    while i < l2 {
        if x + 2 + i < x + 1 + w {
            uc_set(x + 2 + i, y + 2, line2[i], fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.394 统计卡片 ============

# uc_stat_card：绘制统计卡片
# title 为卡片标题，value 为大数值，trend>0 显示绿色上升箭头，<0 显示红色下降箭头。
# 用于仪表盘、数据展示。
fn uc_stat_card(x: i64, y: i64, w: i64, title: ptr, value: ptr, trend: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    vlen = strlen(value);
    # 边框
    uc_border(x, y, w + 2, 4, 1, fg, bg);
    # 标题（小写，反色）
    i = 0;
    while i < tlen {
        if x + 1 + i < x + 1 + w {
            uc_set(x + 1 + i, y, title[i], fg, bg);
        }
        i = i + 1;
    }
    # 数值（大，反色行）
    i = 0;
    while i < vlen {
        if x + 2 + i < x + 1 + w {
            uc_set(x + 2 + i, y + 2, value[i], fg, bg);
        }
        i = i + 1;
    }
    uc_reverse(x + 1, y + 2, w, 1);
    # 趋势箭头
    if trend > 0 {
        uc_set(x + 1 + w - 2, y + 2, '^', UC_GREEN, bg);
    } else {
        if trend < 0 {
            uc_set(x + 1 + w - 2, y + 2, 'v', UC_RED, bg);
        }
    }
    return 0;
}

# ============ v1.395 键盘按键 ============

# uc_kbd：绘制键盘按键提示 [Ctrl] / [C]
# key 为按键文本。用于快捷键提示、命令面板。
fn uc_kbd(x: i64, y: i64, key: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(key);
    uc_set(x, y, '[', fg, bg);
    i = 0;
    while i < len {
        uc_set(x + 1 + i, y, key[i], fg, bg);
        i = i + 1;
    }
    uc_set(x + 1 + len, y, ']', fg, bg);
    return 0;
}

# ============ v1.397 分隔线 ============

# uc_separator：绘制水平分隔线，可选带标题
# 例如 "-" 重复 w 宽，若 title 非空则显示 "--- 标题 ---"。
# 用于布局分区、面板分隔。
fn uc_separator(x: i64, y: i64, w: i64, title: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    i = 0;
    while i < w {
        uc_set(x + i, y, '-', fg, bg);
        i = i + 1;
    }
    if tlen > 0 {
        # 在标题处覆盖
        uc_set(x, y, '-', fg, bg);
        i = 0;
        while i < tlen {
            if x + 2 + i < x + w - 1 {
                uc_set(x + 2 + i, y, title[i], fg, bg);
            }
            i = i + 1;
        }
        uc_set(x + 2 + tlen, y, '-', fg, bg);
        uc_set(x + 3 + tlen, y, '-', fg, bg);
    }
    return 0;
}

# ============ v1.398 表单字段 ============

# uc_field：绘制表单输入框
# label 为字段标签，value 为输入内容，w 为框宽，focused=1 显示光标。
# 用于表单、搜索框、设置界面。
fn uc_field(x: i64, y: i64, w: i64, label: ptr, value: ptr, focused: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    llen = strlen(label);
    vlen = strlen(value);
    # 标签
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen, y, ':', fg, bg);
    # 输入框边框
    uc_set(x + llen + 2, y, '[', fg, bg);
    # 值
    i = 0;
    while i < w {
        if i < vlen {
            uc_set(x + llen + 3 + i, y, value[i], fg, bg);
        } else {
            uc_set(x + llen + 3 + i, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + llen + 3 + w, y, ']', fg, bg);
    # 光标
    if focused != 0 {
        uc_set(x + llen + 3 + vlen, y, '|', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.399 对话框 ============

# uc_dialog：绘制模态对话框
# title 为标题，msg 为消息文本，btn1/btn2 为按钮文本，active_btn=0 高亮 btn1，=1 高亮 btn2。
# 用于确认框、消息框、警告框。
fn uc_dialog(x: i64, y: i64, w: i64, h: i64, title: ptr, msg: ptr, btn1: ptr, btn2: ptr, active_btn: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let mlen: i64 = 0;
    let b1: i64 = 0;
    let b2: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    mlen = strlen(msg);
    b1 = strlen(btn1);
    b2 = strlen(btn2);
    # 边框
    uc_border(x, y, w + 2, h + 2, 2, fg, bg);
    # 标题栏（反色）
    i = 0;
    while i < tlen {
        if x + 1 + i < x + 1 + w {
            uc_set(x + 1 + i, y, title[i], fg, bg);
        }
        i = i + 1;
    }
    uc_reverse(x + 1, y, w, 1);
    # 消息（居中）
    i = 0;
    while i < mlen {
        uc_set(x + 1 + i, y + h / 2, msg[i], fg, bg);
        i = i + 1;
    }
    # 按钮行
    let by: i64 = y + h - 1;
    let bx1: i64 = x + 1;
    let bx2: i64 = x + w - 1 - b2;
    # btn1
    uc_set(bx1, by, '[', fg, bg);
    i = 0;
    while i < b1 {
        uc_set(bx1 + 1 + i, by, btn1[i], fg, bg);
        i = i + 1;
    }
    uc_set(bx1 + 1 + b1, by, ']', fg, bg);
    # btn2
    uc_set(bx2, by, '[', fg, bg);
    i = 0;
    while i < b2 {
        uc_set(bx2 + 1 + i, by, btn2[i], fg, bg);
        i = i + 1;
    }
    uc_set(bx2 + 1 + b2, by, ']', fg, bg);
    # 高亮 active 按钮
    if active_btn == 0 {
        uc_reverse(bx1, by, b1 + 2, 1);
    } else {
        uc_reverse(bx2, by, b2 + 2, 1);
    }
    return 0;
}

# ============ v1.400 控制台 ============

# uc_console：绘制控制台/日志面板
# title 为标题栏文本，line1/line2/line3 为三行日志。
# 用于调试输出、日志查看。
fn uc_console(x: i64, y: i64, w: i64, h: i64, title: ptr, line1: ptr, line2: ptr, line3: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let l1: i64 = 0;
    let l2: i64 = 0;
    let l3: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    l1 = strlen(line1);
    l2 = strlen(line2);
    l3 = strlen(line3);
    # 边框
    uc_border(x, y, w + 2, h + 2, 1, fg, bg);
    # 标题栏（反色）
    i = 0;
    while i < tlen {
        if x + 1 + i < x + 1 + w {
            uc_set(x + 1 + i, y, title[i], fg, bg);
        }
        i = i + 1;
    }
    uc_reverse(x + 1, y, w, 1);
    # 三行日志
    i = 0;
    while i < l1 {
        if x + 2 + i < x + 1 + w {
            uc_set(x + 2 + i, y + 1, line1[i], fg, bg);
        }
        i = i + 1;
    }
    i = 0;
    while i < l2 {
        if x + 2 + i < x + 1 + w {
            uc_set(x + 2 + i, y + 2, line2[i], fg, bg);
        }
        i = i + 1;
    }
    i = 0;
    while i < l3 {
        if x + 2 + i < x + 1 + w {
            uc_set(x + 2 + i, y + 3, line3[i], fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.401 标签 chip ============

# uc_tag：绘制彩色标签 chip [文本]
# tag 为标签文本，用 '#' 填充左侧竖条。用于分类、标签展示。
fn uc_tag(x: i64, y: i64, tag: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(tag);
    uc_set(x, y, '#', fg, bg);
    uc_set(x + 1, y, '[', fg, bg);
    i = 0;
    while i < len {
        uc_set(x + 2 + i, y, tag[i], fg, bg);
        i = i + 1;
    }
    uc_set(x + 2 + len, y, ']', fg, bg);
    return 0;
}

# ============ v1.403 话题标签 ============

# uc_hashtag：绘制话题标签 #tag
# tag 为标签文本，'#' 用青色，文本用默认色。
# 用于社交、分类展示。
fn uc_hashtag(x: i64, y: i64, tag: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(tag);
    uc_set(x, y, '#', UC_CYAN, bg);
    i = 0;
    while i < len {
        uc_set(x + 1 + i, y, tag[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.404 状态灯 ============

# uc_status_light：绘制状态指示灯 (O)
# color: 0=绿(正常) 1=黄(警告) 2=红(错误)
# 用于系统状态、在线指示、健康检查。
fn uc_status_light(x: i64, y: i64, color: i64, bg: i64) -> i64 {
    let c: i64 = 0;
    if color == 0 {
        c = UC_GREEN;
    } else {
        if color == 1 {
            c = UC_YELLOW;
        } else {
            c = UC_RED;
        }
    }
    uc_set(x, y, '(', c, bg);
    uc_set(x + 1, y, 'O', c, bg);
    uc_set(x + 2, y, ')', c, bg);
    return 0;
}

# ============ v1.405 环形进度 ============

# uc_progress_ring：绘制环形进度条
# r 为环半径，pct 为百分比（0-100）。
# 用 'O' 表示已填充，'.' 表示未填充，围成一圈。
# 用于下载进度、加载环。
fn uc_progress_ring(x: i64, y: i64, r: i64, pct: i64, fg: i64, bg: i64) -> i64 {
    let total: i64 = 0;
    let filled: i64 = 0;
    let i: i64 = 0;
    let side: i64 = 0;
    let pos: i64 = 0;
    let ch: i64 = 0;
    if r < 1 { r = 1; }
    if pct < 0 { pct = 0; }
    if pct > 100 { pct = 100; }
    # 矩形环：4 边总长 = 2*((2r+1)+(2r+1))-4
    total = 8 * r;
    filled = total * pct / 100;
    i = 0;
    while i < total {
        # 计算环上位置：顶边 → 右边 → 底边 → 左边
        side = i / (2 * r);
        pos = i % (2 * r);
        ch = 46;  # '.'
        if i < filled { ch = 79; }  # 'O'
        if side == 0 {
            uc_set(x - r + pos, y - r, ch, fg, bg);
        } else {
            if side == 1 {
                uc_set(x + r, y - r + pos, ch, fg, bg);
            } else {
                if side == 2 {
                    uc_set(x + r - pos, y + r, ch, fg, bg);
                } else {
                    uc_set(x - r, y + r - pos, ch, fg, bg);
                }
            }
        }
        i = i + 1;
    }
    return 0;
}
# ============ v1.406 头像 ============

# uc_avatar：绘制用户头像（含在线状态点）
# 显示 (•) 头像，右侧小点表示在线状态（绿=在线，红=离线）。
# 用于聊天、用户列表、评论区。
fn uc_avatar(x: i64, y: i64, online: i64, fg: i64, bg: i64) -> i64 {
    uc_set(x, y, '(', UC_CYAN, bg);
    uc_set(x + 1, y, '^', UC_CYAN, bg);
    uc_set(x + 2, y, '^', UC_CYAN, bg);
    uc_set(x + 3, y, ')', UC_CYAN, bg);
    if online != 0 {
        uc_set(x + 4, y, '.', UC_GREEN, bg);
    } else {
        uc_set(x + 4, y, '.', UC_RED, bg);
    }
    return 0;
}

# ============ v1.407 聊天气泡 ============

# uc_chat_bubble：绘制聊天消息气泡
# text 为消息文本，w 为气泡宽，mine=1 表示自己发的（右侧带箭头）。
# 用于聊天界面、评论区。
fn uc_chat_bubble(x: i64, y: i64, w: i64, text: ptr, mine: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(text);
    if mine != 0 {
        uc_set(x, y, '<', fg, bg);
        uc_set(x + 1, y, '[', fg, bg);
    } else {
        uc_set(x, y, '[', fg, bg);
    }
    i = 0;
    while i < w {
        if i < len {
            uc_set(x + 2 + i, y, text[i], fg, bg);
        } else {
            uc_set(x + 2 + i, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    if mine != 0 {
        uc_set(x + 2 + w, y, ']', fg, bg);
    } else {
        uc_set(x + 1 + w, y, ']', fg, bg);
        uc_set(x + 2 + w, y, '>', fg, bg);
    }
    return 0;
}

# ============ v1.408 搜索框 ============

# uc_search_box：绘制搜索框 [ > query ]
# query 为搜索内容，focused=1 显示光标。
# 用于搜索、命令面板。
fn uc_search_box(x: i64, y: i64, w: i64, query: ptr, focused: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(query);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, '>', UC_CYAN, bg);
    uc_set(x + 2, y, ' ', fg, bg);
    i = 0;
    while i < w {
        if i < len {
            uc_set(x + 3 + i, y, query[i], fg, bg);
        } else {
            uc_set(x + 3 + i, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + 3 + w, y, ']', fg, bg);
    if focused != 0 {
        uc_set(x + 3 + len, y, '|', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.410 分组框 ============

# uc_group：绘制分组框 +-- Title --+
# title 为分组标题，标题反色。
# 用于表单分区、设置分组。
fn uc_group(x: i64, y: i64, w: i64, h: i64, title: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    # 顶边
    uc_set(x, y, '+', fg, bg);
    uc_set(x + 1, y, '-', fg, bg);
    uc_set(x + 2, y, '-', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 4 + i, y, title[i], UC_YELLOW, bg);
        i = i + 1;
    }
    i = 4 + tlen;
    while i < w {
        uc_set(x + i, y, '-', fg, bg);
        i = i + 1;
    }
    uc_set(x + w, y, '+', fg, bg);
    # 左右边
    i = 1;
    while i < h {
        uc_set(x, y + i, '|', fg, bg);
        uc_set(x + w, y + i, '|', fg, bg);
        i = i + 1;
    }
    # 底边
    i = 1;
    while i < w {
        uc_set(x + i, y + h, '-', fg, bg);
        i = i + 1;
    }
    uc_set(x, y + h, '+', fg, bg);
    uc_set(x + w, y + h, '+', fg, bg);
    return 0;
}

# ============ v1.411 步骤指示器 ============

# uc_steps：绘制分步指示器 [1]--[2]--[3]
# count 为总步数，current 为当前步骤（0 开始）。
# 当前步绿色高亮，已完成步青色。
# 用于向导、注册流程。
fn uc_steps(x: i64, y: i64, count: i64, current: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    if count < 1 { count = 1; }
    i = 0;
    while i < count {
        if i > 0 {
            uc_set(x + i * 5 - 1, y, '-', fg, bg);
            uc_set(x + i * 5 - 2, y, '-', fg, bg);
        }
        uc_set(x + i * 5, y, '[', fg, bg);
        uc_set(x + i * 5 + 1, y, '1' + i, UC_YELLOW, bg);
        uc_set(x + i * 5 + 2, y, ']', fg, bg);
        if i == current {
            uc_set(x + i * 5, y, '[', UC_GREEN, bg);
            uc_set(x + i * 5 + 1, y, '1' + i, UC_GREEN, bg);
            uc_set(x + i * 5 + 2, y, ']', UC_GREEN, bg);
        } else {
            if i < current {
                uc_set(x + i * 5 + 1, y, '1' + i, UC_CYAN, bg);
            }
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.412 加载点 ============

# uc_loading_dots：绘制加载点动画
# phase 为动画阶段（0-3），点依次点亮。
# 用于加载指示、进度反馈。
fn uc_loading_dots(x: i64, y: i64, phase: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < 3 {
        if phase % 4 > i {
            uc_set(x + i, y, '.', UC_GREEN, bg);
        } else {
            uc_set(x + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.414 点赞按钮 ============

# uc_like_button：绘制点赞按钮 [* 12]
# liked=1 表示已点赞（红色），=0 未点赞。
# 用于社交互动、评论区。
fn uc_like_button(x: i64, y: i64, liked: i64, count: i64, fg: i64, bg: i64) -> i64 {
    let n: i64 = 0;
    let c: i64 = 0;
    let tmp: i64 = 0;
    if liked != 0 {
        c = UC_RED;
    } else {
        c = fg;
    }
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, '*', c, bg);
    uc_set(x + 2, y, ' ', fg, bg);
    n = count;
    tmp = 0;
    if n >= 100 {
        uc_set(x + 3, y, '1', fg, bg);
        n = n - 100;
        tmp = 1;
    }
    if n >= 10 {
        uc_set(x + 3 + tmp, y, '0' + n / 10, fg, bg);
        n = n % 10;
        tmp = tmp + 1;
    }
    uc_set(x + 3 + tmp, y, '0' + n, fg, bg);
    uc_set(x + 4 + tmp, y, ']', fg, bg);
    return 0;
}

# ============ v1.415 开关行 ============

# uc_toggle_row：绘制设置行 Label [ON]
# label 为设置项名称，on=1 显示 [ON]（绿），=0 显示 [OFF]（红）。
# 用于设置界面、偏好配置。
fn uc_toggle_row(x: i64, y: i64, label: ptr, on: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(label);
    uc_set(x, y, ' ', fg, bg);
    i = 0;
    while i < len {
        uc_set(x + 1 + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 2 + len, y, ' ', fg, bg);
    uc_set(x + 3 + len, y, '[', fg, bg);
    if on != 0 {
        uc_set(x + 4 + len, y, 'O', UC_GREEN, bg);
        uc_set(x + 5 + len, y, 'N', UC_GREEN, bg);
    } else {
        uc_set(x + 4 + len, y, 'O', UC_RED, bg);
        uc_set(x + 5 + len, y, 'F', UC_RED, bg);
        uc_set(x + 6 + len, y, 'F', UC_RED, bg);
    }
    if on != 0 {
        uc_set(x + 6 + len, y, ']', fg, bg);
    } else {
        uc_set(x + 7 + len, y, ']', fg, bg);
    }
    return 0;
}

# ============ v1.416 图例 ============

# uc_legend：绘制图表图例 ■ Label
# color 为色块颜色，label 为标签文本。
# 用于图表、地图、数据可视化。
fn uc_legend(x: i64, y: i64, color: i64, label: ptr, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    len = strlen(label);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, ']', color, bg);
    uc_set(x + 2, y, ' ', fg, bg);
    i = 0;
    while i < len {
        uc_set(x + 3 + i, y, label[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.417 数据行 ============

# uc_data_row：绘制数据行 Label: value
# label 为字段名，value 为值（绿色），label_w 为标签宽度。
# 用于详情页、属性展示、键值对。
fn uc_data_row(x: i64, y: i64, label: ptr, value: ptr, label_w: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    llen = strlen(label);
    vlen = strlen(value);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], fg, bg);
        i = i + 1;
    }
    i = llen;
    while i < label_w {
        uc_set(x + i, y, ' ', fg, bg);
        i = i + 1;
    }
    uc_set(x + label_w, y, ':', UC_CYAN, bg);
    i = 0;
    while i < vlen {
        uc_set(x + label_w + 2 + i, y, value[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.418 应用网格 ============

# uc_app_grid：绘制应用图标网格
# cols 列数，title 为应用名，icon 为图标字符。
# 用于桌面、启动器、应用列表。
fn uc_app_grid(x: i64, y: i64, cols: i64, title: ptr, icon: i64, fg: i64, bg: i64) -> i64 {
    let len: i64 = 0;
    let i: i64 = 0;
    let cell_w: i64 = 0;
    len = strlen(title);
    cell_w = 10;
    if cols < 1 { cols = 1; }
    i = 0;
    while i < cols {
        uc_set(x + i * cell_w + 1, y, '[', fg, bg);
        uc_set(x + i * cell_w + 2, y, icon, UC_CYAN, bg);
        uc_set(x + i * cell_w + 3, y, ']', fg, bg);
        uc_set(x + i * cell_w, y + 1, '+', UC_YELLOW, bg);
        i = i + 1;
    }
    i = 0;
    while i < len {
        uc_set(x + (i / (cell_w - 1)) * cell_w + (i % (cell_w - 1)), y + 2, title[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.419 设置行 ============

# uc_setting_row：绘制设置行 Label .... [value]
# label 为设置项，value 为当前值（右侧对齐），w 为行宽。
# 用于设置界面、偏好配置。
fn uc_setting_row(x: i64, y: i64, w: i64, label: ptr, value: ptr, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    let start: i64 = 0;
    llen = strlen(label);
    vlen = strlen(value);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    # 填充点线
    i = llen;
    while i < w - vlen - 2 {
        uc_set(x + i, y, '.', fg, bg);
        i = i + 1;
    }
    uc_set(x + w - vlen - 2, y, '[', fg, bg);
    start = w - vlen - 1;
    i = 0;
    while i < vlen {
        uc_set(x + start + i, y, value[i], UC_GREEN, bg);
        i = i + 1;
    }
    uc_set(x + w - 1, y, ']', fg, bg);
    return 0;
}


# ============ v1.420 工具栏 ============

# uc_toolbar：绘制工具栏按钮行 [Bold] [Italic] [Underline]
# items 用 | 分隔，active_idx 为当前选中按钮（反色高亮）。
# 用于编辑器工具栏、操作按钮组。
fn uc_toolbar(x: i64, y: i64, items: ptr, active_idx: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let idx: i64 = 0;
    let ch: i64 = 0;
    let start: i64 = 0;
    i = 0;
    idx = 0;
    start = x;
    uc_set(start, y, '[', fg, bg);
    start = start + 1;
    while 1 == 1 {
        ch = items[i];
        if ch == 0 { break; }
        if ch == 124 {
            uc_set(start, y, ']', fg, bg);
            start = start + 1;
            uc_set(start, y, ' ', fg, bg);
            start = start + 1;
            uc_set(start, y, '[', fg, bg);
            start = start + 1;
            idx = idx + 1;
        } else {
            if idx == active_idx {
                uc_set(start, y, ch, UC_BLACK, UC_YELLOW);
            } else {
                uc_set(start, y, ch, fg, bg);
            }
            start = start + 1;
        }
        i = i + 1;
    }
    uc_set(start, y, ']', fg, bg);
    return 0;
}

# ============ v1.421 活动指示器 ============

# uc_activity：绘制转圈活动指示器 |/-\
# phase 为动画帧（0-3），依次显示 | / - \。
# 用于加载、同步中。
fn uc_activity(x: i64, y: i64, phase: i64, fg: i64, bg: i64) -> i64 {
    let ch: i64 = 0;
    let p: i64 = 0;
    p = phase % 4;
    if p < 0 { p = p + 4; }
    if p == 0 {
        ch = 124;  # '|'
    } else {
        if p == 1 {
            ch = 47;  # '/'
        } else {
            if p == 2 {
                ch = 45;  # '-'
            } else {
                ch = 92;  # '\'
            }
        }
    }
    uc_set(x, y, ch, UC_CYAN, bg);
    return 0;
}

# ============ v1.422 音量条 ============

# uc_volume_bar：绘制音量条 Volume [###---] 60
# label 为名称，level/max 决定填充量，显示百分比。
# 用于音频控制、系统音量。
fn uc_volume_bar(x: i64, y: i64, w: i64, label: ptr, level: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    let filled: i64 = 0;
    let pct: i64 = 0;
    llen = strlen(label);
    if max < 1 { max = 1; }
    filled = (w - 2) * level / max;
    if filled > w - 2 { filled = w - 2; }
    pct = level * 100 / max;
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen + 1, y, '[', fg, bg);
    i = 0;
    while i < w - 2 {
        if i < filled {
            uc_set(x + llen + 2 + i, y, '#', UC_GREEN, bg);
        } else {
            uc_set(x + llen + 2 + i, y, '-', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + llen + w, y, ']', fg, bg);
    uc_set(x + llen + w + 2, y, ' ', fg, bg);
    if pct >= 100 {
        uc_set(x + llen + w + 3, y, '1', fg, bg);
        uc_set(x + llen + w + 4, y, '0', fg, bg);
        uc_set(x + llen + w + 5, y, '0', fg, bg);
    } else {
        if pct >= 10 {
            uc_set(x + llen + w + 3, y, '0' + pct / 10, fg, bg);
            uc_set(x + llen + w + 4, y, '0' + pct % 10, fg, bg);
        } else {
            uc_set(x + llen + w + 3, y, '0' + pct, fg, bg);
        }
    }
    return 0;
}

# ============ v1.423 带标签进度条 ============

# uc_progress_label：绘制带标签进度条 Label [######--] 80%
# label 为名称，level/max 决定填充量，显示百分比。
# 用于下载、安装进度。
fn uc_progress_label(x: i64, y: i64, w: i64, label: ptr, level: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    let filled: i64 = 0;
    let pct: i64 = 0;
    llen = strlen(label);
    if max < 1 { max = 1; }
    filled = (w - 2) * level / max;
    if filled > w - 2 { filled = w - 2; }
    pct = level * 100 / max;
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen + 1, y, '[', fg, bg);
    i = 0;
    while i < w - 2 {
        if i < filled {
            uc_set(x + llen + 2 + i, y, '#', UC_GREEN, bg);
        } else {
            uc_set(x + llen + 2 + i, y, '-', fg, bg);
        }
        i = i + 1;
    }
    uc_set(x + llen + w, y, ']', fg, bg);
    uc_set(x + llen + w + 2, y, ' ', fg, bg);
    if pct >= 100 {
        uc_set(x + llen + w + 3, y, '1', fg, bg);
        uc_set(x + llen + w + 4, y, '0', fg, bg);
        uc_set(x + llen + w + 5, y, '0', fg, bg);
    } else {
        if pct >= 10 {
            uc_set(x + llen + w + 3, y, '0' + pct / 10, fg, bg);
            uc_set(x + llen + w + 4, y, '0' + pct % 10, fg, bg);
        } else {
            uc_set(x + llen + w + 3, y, '0' + pct, fg, bg);
        }
    }
    return 0;
}

# ============ v1.424 同步状态图标 ============

# uc_sync_icon：绘制同步状态图标
# state: 0=未同步(灰 ~) 1=同步中(黄 @) 2=已同步(绿 ✓)
# 用于云同步、刷新状态。
fn uc_sync_icon(x: i64, y: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let c: i64 = 0;
    let ch: i64 = 0;
    if state == 0 {
        c = fg;
        ch = 126;  # '~'
    } else {
        if state == 1 {
            c = UC_YELLOW;
            ch = 64;  # '@'
        } else {
            c = UC_GREEN;
            ch = 118;  # 'v' 表示已同步
        }
    }
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, ch, c, bg);
    uc_set(x + 2, y, ']', fg, bg);
    return 0;
}

# ============ v1.425 连接状态行 ============

# uc_conn_status：绘制连接状态行 Name 已连接 |||||
# name 为连接名，connected=1 绿/0 红，strength 0-5 信号强度。
# 用于 WiFi、蓝牙、网络状态。
fn uc_conn_status(x: i64, y: i64, name: ptr, connected: i64, strength: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    i = 0;
    while i < nlen {
        uc_set(x + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + nlen + 1, y, ' ', fg, bg);
    if connected != 0 {
        uc_set(x + nlen + 2, y, 'C', UC_GREEN, bg);
        uc_set(x + nlen + 3, y, 'o', UC_GREEN, bg);
        uc_set(x + nlen + 4, y, 'n', UC_GREEN, bg);
        uc_set(x + nlen + 5, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + nlen + 2, y, 'D', UC_RED, bg);
        uc_set(x + nlen + 3, y, 'i', UC_RED, bg);
        uc_set(x + nlen + 4, y, 's', UC_RED, bg);
        uc_set(x + nlen + 5, y, 'c', UC_RED, bg);
        uc_set(x + nlen + 6, y, 'o', UC_RED, bg);
        uc_set(x + nlen + 7, y, 'n', UC_RED, bg);
    }
    # 信号条
    uc_set(x + nlen + 10, y, '|', fg, bg);
    i = 0;
    while i < strength {
        uc_set(x + nlen + 11 + i, y, '|', UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.426 成员行 ============

# uc_member_row：绘制成员列表行 (^^) Name 在线
# name 为成员名，online=1 绿/0 灰，显示头像和状态。
# 用于团队、聊天成员列表。
fn uc_member_row(x: i64, y: i64, name: ptr, online: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '(', UC_CYAN, bg);
    uc_set(x + 1, y, '^', UC_CYAN, bg);
    uc_set(x + 2, y, '^', UC_CYAN, bg);
    uc_set(x + 3, y, ')', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    if online != 0 {
        uc_set(x + 8 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 9 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 8 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 9 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.427 文件信息行 ============

# uc_file_info：绘制文件信息行 [F] filename  2.3KB
# filename 为文件名，size 为大小（KB 整数）。
# 用于文件列表、下载管理。
fn uc_file_info(x: i64, y: i64, filename: ptr, size: i64, fg: i64, bg: i64) -> i64 {
    let flen: i64 = 0;
    let i: i64 = 0;
    let s1: i64 = 0;
    let s2: i64 = 0;
    flen = strlen(filename);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'F', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 5 + i, y, filename[i], UC_YELLOW, bg);
        i = i + 1;
    }
    s1 = size / 10;
    s2 = size % 10;
    uc_set(x + 7 + flen, y, ' ', fg, bg);
    if s1 >= 100 {
        uc_set(x + 8 + flen, y, '0' + s1 / 100, fg, bg);
        uc_set(x + 9 + flen, y, '.', fg, bg);
        uc_set(x + 10 + flen, y, '0' + (s1 % 100) / 10, fg, bg);
        uc_set(x + 11 + flen, y, 'K', UC_GREEN, bg);
        uc_set(x + 12 + flen, y, 'B', UC_GREEN, bg);
    } else {
        if s1 >= 10 {
            uc_set(x + 8 + flen, y, '0' + s1 / 10, fg, bg);
            uc_set(x + 9 + flen, y, '.', fg, bg);
            uc_set(x + 10 + flen, y, '0' + s1 % 10, fg, bg);
            uc_set(x + 11 + flen, y, 'K', UC_GREEN, bg);
            uc_set(x + 12 + flen, y, 'B', UC_GREEN, bg);
        } else {
            uc_set(x + 8 + flen, y, '0' + s1, fg, bg);
            uc_set(x + 9 + flen, y, '.', fg, bg);
            uc_set(x + 10 + flen, y, '0' + s2, fg, bg);
            uc_set(x + 11 + flen, y, 'K', UC_GREEN, bg);
            uc_set(x + 12 + flen, y, 'B', UC_GREEN, bg);
        }
    }
    return 0;
}

# ============ v1.428 服务状态行 ============

# uc_service_status：绘制服务状态行 Name 运行中 0s
# name 为服务名，running=1 绿/0 红，uptime 为运行秒数。
# 用于服务监控、系统管理。
fn uc_service_status(x: i64, y: i64, name: ptr, running: i64, uptime: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let u: i64 = 0;
    nlen = strlen(name);
    i = 0;
    while i < nlen {
        uc_set(x + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    if running != 0 {
        uc_set(x + nlen + 2, y, 'R', UC_GREEN, bg);
        uc_set(x + nlen + 3, y, 'u', UC_GREEN, bg);
        uc_set(x + nlen + 4, y, 'n', UC_GREEN, bg);
        uc_set(x + nlen + 5, y, 'n', UC_GREEN, bg);
        uc_set(x + nlen + 6, y, 'i', UC_GREEN, bg);
        uc_set(x + nlen + 7, y, 'n', UC_GREEN, bg);
        uc_set(x + nlen + 8, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + nlen + 2, y, 'S', UC_RED, bg);
        uc_set(x + nlen + 3, y, 't', UC_RED, bg);
        uc_set(x + nlen + 4, y, 'o', UC_RED, bg);
        uc_set(x + nlen + 5, y, 'p', UC_RED, bg);
        uc_set(x + nlen + 6, y, 'p', UC_RED, bg);
        uc_set(x + nlen + 7, y, 'e', UC_RED, bg);
        uc_set(x + nlen + 8, y, 'd', UC_RED, bg);
    }
    uc_set(x + nlen + 12, y, ' ', fg, bg);
    u = uptime;
    if u >= 100 {
        uc_set(x + nlen + 13, y, '0' + u / 100, fg, bg);
        u = u % 100;
        uc_set(x + nlen + 14, y, '0' + u / 10, fg, bg);
        uc_set(x + nlen + 15, y, '0' + u % 10, fg, bg);
    } else {
        if u >= 10 {
            uc_set(x + nlen + 13, y, '0' + u / 10, fg, bg);
            uc_set(x + nlen + 14, y, '0' + u % 10, fg, bg);
        } else {
            uc_set(x + nlen + 13, y, '0' + u, fg, bg);
        }
    }
    uc_set(x + nlen + 16, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.429 健康检查行 ============

# uc_health_row：绘制健康检查行 [v] Name OK 12ms
# name 为检查项，ok=1 绿 OK/0 红 FAIL，latency 毫秒。
# 用于系统健康、监控面板。
fn uc_health_row(x: i64, y: i64, name: ptr, ok: i64, latency: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let l: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    if ok != 0 {
        uc_set(x + 1, y, 'v', UC_GREEN, bg);
    } else {
        uc_set(x + 1, y, 'x', UC_RED, bg);
    }
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    if ok != 0 {
        uc_set(x + 7 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 8 + nlen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 7 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 8 + nlen, y, 'A', UC_RED, bg);
        uc_set(x + 9 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'L', UC_RED, bg);
    }
    l = latency;
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    if l >= 100 {
        uc_set(x + 15 + nlen, y, '0' + l / 100, fg, bg);
        l = l % 100;
        uc_set(x + 16 + nlen, y, '0' + l / 10, fg, bg);
        uc_set(x + 17 + nlen, y, '0' + l % 10, fg, bg);
    } else {
        if l >= 10 {
            uc_set(x + 15 + nlen, y, '0' + l / 10, fg, bg);
            uc_set(x + 16 + nlen, y, '0' + l % 10, fg, bg);
        } else {
            uc_set(x + 15 + nlen, y, '0' + l, fg, bg);
        }
    }
    uc_set(x + 18 + nlen, y, 'm', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.430 通知项行 ============

# uc_notice_row：绘制通知项行 [i] Title  2m ago
# title 为通知标题，level 0=信息/1=警告/2=错误，time 为时间文本。
# 用于通知中心、消息列表。
fn uc_notice_row(x: i64, y: i64, title: ptr, level: i64, time: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let timelen: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let c: i64 = 0;
    tlen = strlen(title);
    timelen = strlen(time);
    if level == 0 {
        ch = 105;  # 'i'
        c = UC_CYAN;
    } else {
        if level == 1 {
            ch = 33;  # '!'
            c = UC_YELLOW;
        } else {
            ch = 120;  # 'x'
            c = UC_RED;
        }
    }
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, ch, c, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 5 + i, y, title[i], UC_YELLOW, bg);
        i = i + 1;
    }
    i = 0;
    while i < timelen {
        uc_set(x + 7 + tlen + i, y, time[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.431 更新日志行 ============

# uc_changelog_row：绘制更新日志行 [+]/[*]/[>]/[!] desc
# type 0=新功能(绿+) 1=修复(青*) 2=优化(黄>) 3=破坏(红!)
# 用于更新日志、发布说明。
fn uc_changelog_row(x: i64, y: i64, type: i64, desc: ptr, fg: i64, bg: i64) -> i64 {
    let dlen: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let c: i64 = 0;
    dlen = strlen(desc);
    if type == 0 {
        ch = 43;  # '+'
        c = UC_GREEN;
    } else {
        if type == 1 {
            ch = 42;  # '*'
            c = UC_CYAN;
        } else {
            if type == 2 {
                ch = 62;  # '>'
                c = UC_YELLOW;
            } else {
                ch = 33;  # '!'
                c = UC_RED;
            }
        }
    }
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, ch, c, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 5 + i, y, desc[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.432 主题切换 ============

# uc_theme_toggle：绘制主题切换按钮 [深色]/[浅色]
# dark=1 显示深色（蓝底白字），=0 显示浅色（白底黑字）。
# 用于设置界面、主题偏好。
fn uc_theme_toggle(x: i64, y: i64, dark: i64, fg: i64, bg: i64) -> i64 {
    if dark != 0 {
        uc_set(x, y, '[', UC_BLACK, UC_BLUE);
        uc_set(x + 1, y, 'D', UC_WHITE, UC_BLUE);
        uc_set(x + 2, y, 'k', UC_WHITE, UC_BLUE);
        uc_set(x + 3, y, ']', UC_BLACK, UC_BLUE);
    } else {
        uc_set(x, y, '[', UC_BLACK, UC_WHITE);
        uc_set(x + 1, y, 'L', UC_BLACK, UC_WHITE);
        uc_set(x + 2, y, 't', UC_BLACK, UC_WHITE);
        uc_set(x + 3, y, ']', UC_BLACK, UC_WHITE);
    }
    return 0;
}
# ============ v1.433 排序指示器 ============

# uc_sort_indicator：绘制排序指示器 Name ^/v/-
# label 为列名，dir 0=无/1=升序/2=降序。
# 用于表格表头、列表排序。
fn uc_sort_indicator(x: i64, y: i64, label: ptr, dir: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    llen = strlen(label);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen + 1, y, ' ', fg, bg);
    if dir == 1 {
        uc_set(x + llen + 2, y, '^', UC_GREEN, bg);
    } else {
        if dir == 2 {
            uc_set(x + llen + 2, y, 'v', UC_RED, bg);
        } else {
            uc_set(x + llen + 2, y, '-', fg, bg);
        }
    }
    return 0;
}

# ============ v1.434 分页器 ============

# uc_pager：绘制分页控件 < 1 2 3 >
# page 为当前页（从 1 起），total 为总页数，当前页反色高亮。
# 用于列表、表格分页。
fn uc_pager(x: i64, y: i64, page: i64, total: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    let maxp: i64 = 0;
    let cur: i64 = 0;
    if page <= 1 {
        uc_set(x, y, '<', fg, bg);
    } else {
        uc_set(x, y, '<', UC_GREEN, bg);
    }
    uc_set(x + 2, y, ' ', fg, bg);
    if total > 5 {
        maxp = 5;
    } else {
        maxp = total;
    }
    i = 0;
    while i < maxp {
        cur = i + 1;
        if cur == page {
            uc_set(x + 3 + i * 2, y, '0' + cur, UC_BLACK, UC_GREEN);
        } else {
            uc_set(x + 3 + i * 2, y, '0' + cur, fg, bg);
        }
        if i < maxp - 1 {
            uc_set(x + 4 + i * 2, y, ' ', fg, bg);
        }
        i = i + 1;
    }
    if page >= total {
        uc_set(x + 3 + maxp * 2, y, ' ', fg, bg);
        uc_set(x + 4 + maxp * 2, y, '>', fg, bg);
    } else {
        uc_set(x + 3 + maxp * 2, y, ' ', fg, bg);
        uc_set(x + 4 + maxp * 2, y, '>', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.435 权限标签 ============

# uc_permission_tag：绘制权限标签 [R]/[W]/[X]/[RWX]
# perm 0=读(绿) 1=写(黄) 2=执行(红) 3=全部(青)。
# 用于文件权限、访问控制。
fn uc_permission_tag(x: i64, y: i64, perm: i64, fg: i64, bg: i64) -> i64 {
    if perm == 0 {
        uc_set(x, y, '[', fg, bg);
        uc_set(x + 1, y, 'R', UC_GREEN, bg);
        uc_set(x + 2, y, ']', fg, bg);
    } else {
        if perm == 1 {
            uc_set(x, y, '[', fg, bg);
            uc_set(x + 1, y, 'W', UC_YELLOW, bg);
            uc_set(x + 2, y, ']', fg, bg);
        } else {
            if perm == 2 {
                uc_set(x, y, '[', fg, bg);
                uc_set(x + 1, y, 'X', UC_RED, bg);
                uc_set(x + 2, y, ']', fg, bg);
            } else {
                uc_set(x, y, '[', fg, bg);
                uc_set(x + 1, y, 'R', UC_CYAN, bg);
                uc_set(x + 2, y, 'W', UC_CYAN, bg);
                uc_set(x + 3, y, 'X', UC_CYAN, bg);
                uc_set(x + 4, y, ']', fg, bg);
            }
        }
    }
    return 0;
}

# ============ v1.436 搜索结果行 ============

# uc_result_row：绘制搜索结果行 [F] name  3 匹配
# name 为文件名，matches 为匹配次数。
# 用于搜索、文件查找。
fn uc_result_row(x: i64, y: i64, name: ptr, matches: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, 'F', UC_GREEN, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if matches >= 10 {
        uc_set(x + 8 + nlen, y, '0' + matches / 10, UC_CYAN, bg);
        uc_set(x + 9 + nlen, y, '0' + matches % 10, UC_CYAN, bg);
    } else {
        uc_set(x + 8 + nlen, y, '0' + matches, UC_CYAN, bg);
    }
    uc_set(x + 10 + nlen, y, ' ', fg, bg);
    uc_set(x + 11 + nlen, y, 'm', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'h', UC_CYAN, bg);
    return 0;
}

# ============ v1.437 工作流状态 ============

# uc_workflow_status：绘制 CI 步骤状态行 [1] Build  v
# step 为步骤号，state 0=待定 1=运行中 2=成功 3=失败。
# 用于 CI/CD 流水线、部署面板。
fn uc_workflow_status(x: i64, y: i64, step: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let c: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, '0' + step, UC_YELLOW, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if state == 0 {
        ch = 45;  # '-'
        c = fg;
    } else {
        if state == 1 {
            ch = 62;  # '>'
            c = UC_YELLOW;
        } else {
            if state == 2 {
                ch = 118;  # 'v'
                c = UC_GREEN;
            } else {
                ch = 120;  # 'x'
                c = UC_RED;
            }
        }
    }
    uc_set(x + 8 + nlen, y, ch, c, bg);
    return 0;
}

# ============ v1.438 评分汇总行 ============

# uc_rating_row：绘制评分汇总行 Rating  4.5/5.0  ****.
# score 为评分，max 为满分，四舍五入显示星级。
# 用于评价、产品详情。
fn uc_rating_row(x: i64, y: i64, label: ptr, score: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    let full: i64 = 0;
    let half: i64 = 0;
    llen = strlen(label);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen + 2, y, ' ', fg, bg);
    if score >= 10 {
        uc_set(x + llen + 3, y, '0' + score / 10, UC_CYAN, bg);
        uc_set(x + llen + 4, y, '.', UC_CYAN, bg);
        uc_set(x + llen + 5, y, '0' + score % 10, UC_CYAN, bg);
    } else {
        uc_set(x + llen + 3, y, '0' + score, UC_CYAN, bg);
        uc_set(x + llen + 4, y, '.', UC_CYAN, bg);
        uc_set(x + llen + 5, y, '0', UC_CYAN, bg);
    }
    uc_set(x + llen + 6, y, '/', fg, bg);
    if max >= 10 {
        uc_set(x + llen + 7, y, '0' + max / 10, UC_CYAN, bg);
        uc_set(x + llen + 8, y, '.', UC_CYAN, bg);
        uc_set(x + llen + 9, y, '0' + max % 10, UC_CYAN, bg);
    } else {
        uc_set(x + llen + 7, y, '0' + max, UC_CYAN, bg);
        uc_set(x + llen + 8, y, '.', UC_CYAN, bg);
        uc_set(x + llen + 9, y, '0', UC_CYAN, bg);
    }
    uc_set(x + llen + 11, y, ' ', fg, bg);
    full = score * 5 / max;
    half = score * 10 / max - full * 2;
    i = 0;
    while i < 5 {
        if i < full {
            uc_set(x + llen + 12 + i, y, '*', UC_YELLOW, bg);
        } else {
            if i == full && half != 0 {
                uc_set(x + llen + 12 + i, y, '.', UC_YELLOW, bg);
            } else {
                uc_set(x + llen + 12 + i, y, '.', fg, bg);
            }
        }
        i = i + 1;
    }
    return 0;
}

# ============ v1.439 商品行 ============

# uc_product_row：绘制商品行 [P] Name  $99  $129 -23%
# price 为现价，old_price 为原价（>0 时显示折扣）。
# 用于电商、商品列表。
fn uc_product_row(x: i64, y: i64, name: ptr, price: i64, old_price: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    let o: i64 = 0;
    let off: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    p = price;
    uc_set(x + 7 + nlen, y, '$', UC_GREEN, bg);
    if p >= 100 {
        uc_set(x + 8 + nlen, y, '0' + p / 100, UC_GREEN, bg);
        p = p % 100;
        uc_set(x + 9 + nlen, y, '0' + p / 10, UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, '0' + p % 10, UC_GREEN, bg);
    } else {
        if p >= 10 {
            uc_set(x + 8 + nlen, y, '0' + p / 10, UC_GREEN, bg);
            uc_set(x + 9 + nlen, y, '0' + p % 10, UC_GREEN, bg);
        } else {
            uc_set(x + 8 + nlen, y, '0' + p, UC_GREEN, bg);
        }
    }
    if old_price > 0 {
        o = old_price;
        uc_set(x + 12 + nlen, y, '$', fg, bg);
        if o >= 100 {
            uc_set(x + 13 + nlen, y, '0' + o / 100, fg, bg);
            o = o % 100;
            uc_set(x + 14 + nlen, y, '0' + o / 10, fg, bg);
            uc_set(x + 15 + nlen, y, '0' + o % 10, fg, bg);
        } else {
            if o >= 10 {
                uc_set(x + 13 + nlen, y, '0' + o / 10, fg, bg);
                uc_set(x + 14 + nlen, y, '0' + o % 10, fg, bg);
            } else {
                uc_set(x + 13 + nlen, y, '0' + o, fg, bg);
            }
        }
        off = (old_price - price) * 100 / old_price;
        uc_set(x + 18 + nlen, y, '-', UC_RED, bg);
        if off >= 10 {
            uc_set(x + 19 + nlen, y, '0' + off / 10, UC_RED, bg);
            uc_set(x + 20 + nlen, y, '0' + off % 10, UC_RED, bg);
        } else {
            uc_set(x + 19 + nlen, y, '0' + off, UC_RED, bg);
        }
        uc_set(x + 21 + nlen, y, '%', UC_RED, bg);
    }
    return 0;
}

# ============ v1.440 目录树文件项 ============

# uc_tree_file：绘制目录树项  ind 层级，[D] 文件夹/[F] 文件
# indent 为缩进层级，is_dir=1 文件夹(黄)，=0 文件(青)。
# 用于文件浏览器、项目结构。
fn uc_tree_file(x: i64, y: i64, indent: i64, is_dir: i64, name: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    nlen = strlen(name);
    j = 0;
    while j < indent {
        uc_set(x + j * 2, y, '|', fg, bg);
        uc_set(x + j * 2 + 1, y, ' ', fg, bg);
        j = j + 1;
    }
    if is_dir != 0 {
        uc_set(x + indent * 2, y, '[', fg, bg);
        uc_set(x + indent * 2 + 1, y, 'D', UC_YELLOW, bg);
        uc_set(x + indent * 2 + 2, y, ']', fg, bg);
    } else {
        uc_set(x + indent * 2, y, '[', fg, bg);
        uc_set(x + indent * 2 + 1, y, 'F', UC_CYAN, bg);
        uc_set(x + indent * 2 + 2, y, ']', fg, bg);
    }
    uc_set(x + indent * 2 + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + indent * 2 + 5 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.441 导航项 ============

# uc_nav_item：绘制侧边栏导航项  > 首页（激活反色）
# active=1 高亮显示当前导航项，=0 普通。
# 用于应用侧边栏、导航菜单。
fn uc_nav_item(x: i64, y: i64, active: i64, name: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    if active != 0 {
        uc_set(x, y, '>', UC_GREEN, UC_CYAN);
        uc_set(x + 1, y, ' ', UC_GREEN, UC_CYAN);
        i = 0;
        while i < nlen {
            uc_set(x + 2 + i, y, name[i], UC_BLACK, UC_CYAN);
            i = i + 1;
        }
    } else {
        uc_set(x, y, ' ', fg, bg);
        uc_set(x + 1, y, ' ', fg, bg);
        i = 0;
        while i < nlen {
            uc_set(x + 2 + i, y, name[i], fg, bg);
            i = i + 1;
        }
    }
    return 0;
}

# ============ v1.442 温度显示 ============

# uc_temp_display：绘制温度显示 CPU 45^C
# temp 为温度值，>=70 红 >=50 黄 否则绿。
# 用于硬件监控、系统状态。
fn uc_temp_display(x: i64, y: i64, label: ptr, temp: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    let t: i64 = 0;
    let c: i64 = 0;
    llen = strlen(label);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    if temp >= 70 {
        c = UC_RED;
    } else {
        if temp >= 50 {
            c = UC_YELLOW;
        } else {
            c = UC_GREEN;
        }
    }
    t = temp;
    uc_set(x + llen + 2, y, ' ', fg, bg);
    if t >= 100 {
        uc_set(x + llen + 3, y, '0' + t / 100, c, bg);
        t = t % 100;
        uc_set(x + llen + 4, y, '0' + t / 10, c, bg);
        uc_set(x + llen + 5, y, '0' + t % 10, c, bg);
    } else {
        if t >= 10 {
            uc_set(x + llen + 3, y, '0' + t / 10, c, bg);
            uc_set(x + llen + 4, y, '0' + t % 10, c, bg);
        } else {
            uc_set(x + llen + 3, y, '0' + t, c, bg);
        }
    }
    uc_set(x + llen + 6, y, '^', c, bg);
    uc_set(x + llen + 7, y, 'C', c, bg);
    return 0;
}

# ============ v1.443 最近应用行 ============

# uc_recent_app：绘制最近使用应用行 [A] Name  5x
# name 为应用名，times 为使用次数。
# 用于开始菜单、最近应用。
fn uc_recent_app(x: i64, y: i64, name: ptr, times: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let t: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, 'A', UC_GREEN, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    t = times;
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if t >= 100 {
        uc_set(x + 8 + nlen, y, '0' + t / 100, UC_CYAN, bg);
        t = t % 100;
        uc_set(x + 9 + nlen, y, '0' + t / 10, UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, '0' + t % 10, UC_CYAN, bg);
    } else {
        if t >= 10 {
            uc_set(x + 8 + nlen, y, '0' + t / 10, UC_CYAN, bg);
            uc_set(x + 9 + nlen, y, '0' + t % 10, UC_CYAN, bg);
        } else {
            uc_set(x + 8 + nlen, y, '0' + t, UC_CYAN, bg);
        }
    }
    uc_set(x + 11 + nlen, y, 'x', UC_CYAN, bg);
    return 0;
}

# ============ v1.444 快捷操作按钮 ============

# uc_quick_action：绘制快捷操作按钮 [保存]（激活反色）
# active=1 高亮当前操作按钮，=0 普通。
# 用于编辑器工具栏、快捷操作。
fn uc_quick_action(x: i64, y: i64, active: i64, label: ptr, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    llen = strlen(label);
    if active != 0 {
        uc_set(x, y, '[', UC_BLACK, UC_GREEN);
        i = 0;
        while i < llen {
            uc_set(x + 1 + i, y, label[i], UC_BLACK, UC_GREEN);
            i = i + 1;
        }
        uc_set(x + 1 + llen, y, ']', UC_BLACK, UC_GREEN);
    } else {
        uc_set(x, y, '[', fg, bg);
        i = 0;
        while i < llen {
            uc_set(x + 1 + i, y, label[i], fg, bg);
            i = i + 1;
        }
        uc_set(x + 1 + llen, y, ']', fg, bg);
    }
    return 0;
}

# ============ v1.445 命令历史项 ============

# uc_command_item：绘制命令历史行 1 > ls -la（选中反色）
# index 为序号，selected=1 高亮当前命令，cmd 为命令文本。
# 用于终端、命令面板历史。
fn uc_command_item(x: i64, y: i64, selected: i64, index: i64, cmd: ptr, fg: i64, bg: i64) -> i64 {
    let clen: i64 = 0;
    let i: i64 = 0;
    clen = strlen(cmd);
    if index >= 10 {
        uc_set(x, y, '0' + index / 10, UC_CYAN, bg);
        uc_set(x + 1, y, '0' + index % 10, UC_CYAN, bg);
    } else {
        uc_set(x, y, '0' + index, UC_CYAN, bg);
    }
    uc_set(x + 3, y, ' ', fg, bg);
    if selected != 0 {
        uc_set(x + 4, y, '>', UC_GREEN, UC_CYAN);
        i = 0;
        while i < clen {
            uc_set(x + 6 + i, y, cmd[i], UC_BLACK, UC_CYAN);
            i = i + 1;
        }
    } else {
        uc_set(x + 4, y, ' ', fg, bg);
        i = 0;
        while i < clen {
            uc_set(x + 6 + i, y, cmd[i], fg, bg);
            i = i + 1;
        }
    }
    return 0;
}

# ============ v1.446 链接行 ============

# uc_link_row：绘制链接行 Name -> https://...
# name 为链接名称，url 为网址。
# 用于资源列表、链接分享。
fn uc_link_row(x: i64, y: i64, name: ptr, url: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(url);
    i = 0;
    while i < nlen {
        uc_set(x + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + nlen + 2, y, '-', fg, bg);
    uc_set(x + nlen + 3, y, '>', UC_GREEN, bg);
    uc_set(x + nlen + 5, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + nlen + 6 + i, y, url[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.447 API 请求行 ============

# uc_api_request：绘制 API 请求日志 GET /api  200 12ms
# method 0=GET 1=POST 2=PUT 3=DELETE，status 2xx 绿/4xx 黄/5xx 红。
# 用于 API 监控、调试日志。
fn uc_api_request(x: i64, y: i64, method: i64, path: ptr, status: i64, ms: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let i: i64 = 0;
    let mc: i64 = 0;
    let sc: i64 = 0;
    let st: i64 = 0;
    let m: i64 = 0;
    plen = strlen(path);
    if method == 0 {
        mc = UC_CYAN;
    } else {
        if method == 1 {
            mc = UC_GREEN;
        } else {
            if method == 2 {
                mc = UC_YELLOW;
            } else {
                mc = UC_RED;
            }
        }
    }
    if status >= 500 {
        sc = UC_RED;
    } else {
        if status >= 400 {
            sc = UC_YELLOW;
        } else {
            sc = UC_GREEN;
        }
    }
    if method == 0 {
        uc_set(x, y, 'G', mc, bg);
        uc_set(x + 1, y, 'E', mc, bg);
        uc_set(x + 2, y, 'T', mc, bg);
    } else {
        if method == 1 {
            uc_set(x, y, 'P', mc, bg);
            uc_set(x + 1, y, 'O', mc, bg);
            uc_set(x + 2, y, 'S', mc, bg);
            uc_set(x + 3, y, 'T', mc, bg);
        } else {
            if method == 2 {
                uc_set(x, y, 'P', mc, bg);
                uc_set(x + 1, y, 'U', mc, bg);
                uc_set(x + 2, y, 'T', mc, bg);
            } else {
                uc_set(x, y, 'D', mc, bg);
                uc_set(x + 1, y, 'E', mc, bg);
                uc_set(x + 2, y, 'L', mc, bg);
                uc_set(x + 3, y, 'E', mc, bg);
                uc_set(x + 4, y, 'T', mc, bg);
                uc_set(x + 5, y, 'E', mc, bg);
            }
        }
    }
    uc_set(x + 8, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + i, y, path[i], UC_YELLOW, bg);
        i = i + 1;
    }
    st = status;
    uc_set(x + 11 + plen, y, ' ', fg, bg);
    uc_set(x + 12 + plen, y, '0' + st / 100, sc, bg);
    st = st % 100;
    uc_set(x + 13 + plen, y, '0' + st / 10, sc, bg);
    uc_set(x + 14 + plen, y, '0' + st % 10, sc, bg);
    m = ms;
    uc_set(x + 17 + plen, y, ' ', fg, bg);
    if m >= 100 {
        uc_set(x + 18 + plen, y, '0' + m / 100, UC_CYAN, bg);
        m = m % 100;
        uc_set(x + 19 + plen, y, '0' + m / 10, UC_CYAN, bg);
        uc_set(x + 20 + plen, y, '0' + m % 10, UC_CYAN, bg);
    } else {
        if m >= 10 {
            uc_set(x + 18 + plen, y, '0' + m / 10, UC_CYAN, bg);
            uc_set(x + 19 + plen, y, '0' + m % 10, UC_CYAN, bg);
        } else {
            uc_set(x + 18 + plen, y, '0' + m, UC_CYAN, bg);
        }
    }
    uc_set(x + 21 + plen, y, 'm', UC_CYAN, bg);
    uc_set(x + 22 + plen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.448 对比条 ============

# uc_compare_bar：绘制数据条 CPU #####... 60%
# value 为当前值，max 为最大值，填充 # 青色。
# 用于对比两个值、比例展示。
fn uc_compare_bar(x: i64, y: i64, label: ptr, value: i64, max: i64, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let i: i64 = 0;
    let filled: i64 = 0;
    let v: i64 = 0;
    let pct: i64 = 0;
    llen = strlen(label);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen + 2, y, ' ', fg, bg);
    if max <= 0 {
        max = 1;
    }
    if value > max {
        value = max;
    }
    filled = value * 10 / max;
    i = 0;
    while i < 10 {
        if i < filled {
            uc_set(x + llen + 3 + i, y, '#', UC_CYAN, bg);
        } else {
            uc_set(x + llen + 3 + i, y, '.', fg, bg);
        }
        i = i + 1;
    }
    v = value;
    pct = value * 100 / max;
    uc_set(x + llen + 14, y, ' ', fg, bg);
    if v >= 100 {
        uc_set(x + llen + 15, y, '0' + v / 100, UC_CYAN, bg);
        v = v % 100;
        uc_set(x + llen + 16, y, '0' + v / 10, UC_CYAN, bg);
        uc_set(x + llen + 17, y, '0' + v % 10, UC_CYAN, bg);
    } else {
        if v >= 10 {
            uc_set(x + llen + 15, y, '0' + v / 10, UC_CYAN, bg);
            uc_set(x + llen + 16, y, '0' + v % 10, UC_CYAN, bg);
        } else {
            uc_set(x + llen + 15, y, '0' + v, UC_CYAN, bg);
        }
    }
    uc_set(x + llen + 19, y, '%', UC_GREEN, bg);
    return 0;
}

# ============ v1.449 权限矩阵单元 ============

# uc_permission_cell：绘制权限矩阵单元 [v]/[x]
# allowed=1 绿勾，=0 红叉。
# 用于权限矩阵、访问控制表。
fn uc_permission_cell(x: i64, y: i64, allowed: i64, fg: i64, bg: i64) -> i64 {
    uc_set(x, y, '[', fg, bg);
    if allowed != 0 {
        uc_set(x + 1, y, 'v', UC_GREEN, bg);
    } else {
        uc_set(x + 1, y, 'x', UC_RED, bg);
    }
    uc_set(x + 2, y, ']', fg, bg);
    return 0;
}

# ============ v1.450 分数板行 ============

# uc_score_row：绘制排行榜行 1. Player  1200
# rank 为排名，前三名特殊颜色（1 金 2 银 3 铜）。
# 用于游戏排行榜、竞技排名。
fn uc_score_row(x: i64, y: i64, rank: i64, name: ptr, score: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let rc: i64 = 0;
    let s: i64 = 0;
    nlen = strlen(name);
    if rank == 1 {
        rc = UC_YELLOW;
    } else {
        if rank == 2 {
            rc = UC_WHITE;
        } else {
            if rank == 3 {
                rc = 208;  # 橙
            } else {
                rc = UC_CYAN;
            }
        }
    }
    if rank >= 10 {
        uc_set(x, y, '0' + rank / 10, rc, bg);
        uc_set(x + 1, y, '0' + rank % 10, rc, bg);
    } else {
        uc_set(x, y, '0' + rank, rc, bg);
    }
    uc_set(x + 3, y, '.', rc, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    s = score;
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if s >= 1000 {
        uc_set(x + 9 + nlen, y, '0' + s / 1000, UC_CYAN, bg);
        s = s % 1000;
        uc_set(x + 10 + nlen, y, '0' + s / 100, UC_CYAN, bg);
        s = s % 100;
        uc_set(x + 11 + nlen, y, '0' + s / 10, UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, '0' + s % 10, UC_CYAN, bg);
    } else {
        if s >= 100 {
            uc_set(x + 9 + nlen, y, '0' + s / 100, UC_CYAN, bg);
            s = s % 100;
            uc_set(x + 10 + nlen, y, '0' + s / 10, UC_CYAN, bg);
            uc_set(x + 11 + nlen, y, '0' + s % 10, UC_CYAN, bg);
        } else {
            if s >= 10 {
                uc_set(x + 9 + nlen, y, '0' + s / 10, UC_CYAN, bg);
                uc_set(x + 10 + nlen, y, '0' + s % 10, UC_CYAN, bg);
            } else {
                uc_set(x + 9 + nlen, y, '0' + s, UC_CYAN, bg);
            }
        }
    }
    return 0;
}

# ============ v1.451 上传进度行 ============

# uc_upload_row：绘制上传进度行 [^] file.zip  45%
# name 为文件名，percent 为上传百分比。
# 用于上传管理器、文件传输。
fn uc_upload_row(x: i64, y: i64, name: ptr, percent: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, '^', UC_GREEN, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    p = percent;
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if p >= 100 {
        uc_set(x + 8 + nlen, y, '1', UC_CYAN, bg);
        p = p % 100;
        uc_set(x + 9 + nlen, y, '0' + p / 10, UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, '0' + p % 10, UC_CYAN, bg);
    } else {
        if p >= 10 {
            uc_set(x + 8 + nlen, y, '0' + p / 10, UC_CYAN, bg);
            uc_set(x + 9 + nlen, y, '0' + p % 10, UC_CYAN, bg);
        } else {
            uc_set(x + 8 + nlen, y, '0' + p, UC_CYAN, bg);
        }
    }
    uc_set(x + 11 + nlen, y, '%', UC_CYAN, bg);
    return 0;
}

# ============ v1.452 下载进度行 ============

# uc_download_row：绘制下载进度行 [v] file.zip  30%
# name 为文件名，percent 为下载百分比。
# 用于下载管理器、文件传输。
fn uc_download_row(x: i64, y: i64, name: ptr, percent: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    uc_set(x + 1, y, 'v', UC_CYAN, bg);
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    p = percent;
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if p >= 100 {
        uc_set(x + 8 + nlen, y, '1', UC_CYAN, bg);
        p = p % 100;
        uc_set(x + 9 + nlen, y, '0' + p / 10, UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, '0' + p % 10, UC_CYAN, bg);
    } else {
        if p >= 10 {
            uc_set(x + 8 + nlen, y, '0' + p / 10, UC_CYAN, bg);
            uc_set(x + 9 + nlen, y, '0' + p % 10, UC_CYAN, bg);
        } else {
            uc_set(x + 8 + nlen, y, '0' + p, UC_CYAN, bg);
        }
    }
    uc_set(x + 11 + nlen, y, '%', UC_CYAN, bg);
    return 0;
}

# ============ v1.453 色板行 ============

# uc_swatch_row：绘制色板行 [■][■][■]（用反色块）
# colors 为 | 分隔的颜色索引文本（如 1|3|5）。
# 用于主题编辑器、颜色选择。
fn uc_swatch_row(x: i64, y: i64, colors: ptr, fg: i64, bg: i64) -> i64 {
    let clen: i64 = 0;
    let i: i64 = 0;
    let idx: i64 = 0;
    let c: i64 = 0;
    let pos: i64 = 0;
    clen = strlen(colors);
    i = 0;
    while i < clen {
        if colors[i] == 124 {  # '|'
            c = idx;
            uc_set(x + pos * 3, y, '[', fg, bg);
            uc_set(x + pos * 3 + 1, y, ']', c, bg);
            uc_set(x + pos * 3 + 2, y, ' ', fg, bg);
            idx = 0;
            pos = pos + 1;
        } else {
            idx = idx * 10 + (colors[i] - 48);
        }
        i = i + 1;
    }
    c = idx;
    uc_set(x + pos * 3, y, '[', fg, bg);
    uc_set(x + pos * 3 + 1, y, ']', c, bg);
    return 0;
}
# ============ v1.454 提醒行 ============

# uc_reminder_row：绘制提醒行 [i] 14:00 会议
# time 为时间文本，title 为标题，urgent=1 红色紧急。
# 用于日历、提醒应用。
fn uc_reminder_row(x: i64, y: i64, time: ptr, title: ptr, urgent: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let nlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(time);
    nlen = strlen(title);
    if urgent != 0 {
        uc_set(x, y, '[', fg, bg);
        uc_set(x + 1, y, '!', UC_RED, bg);
        uc_set(x + 2, y, ']', fg, bg);
    } else {
        uc_set(x, y, '[', fg, bg);
        uc_set(x + 1, y, 'i', UC_CYAN, bg);
        uc_set(x + 2, y, ']', fg, bg);
    }
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 5 + i, y, time[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 7 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 8 + tlen + i, y, title[i], UC_YELLOW, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.455 标签云 ============

# uc_tag_cloud：绘制标签云 [mo] [ui] [canvas]
# tags 为 | 分隔的标签文本，颜色轮换显示。
# 用于标签云、关键词展示。
fn uc_tag_cloud(x: i64, y: i64, tags: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    let start: i64 = 0;
    let cnt: i64 = 0;
    let pos: i64 = 0;
    let len: i64 = 0;
    let c: i64 = 0;
    let b: i64 = 0;
    tlen = strlen(tags);
    i = 0;
    while i < tlen {
        if tags[i] == 124 {  # '|'
            len = i - start;
            if cnt % 4 == 0 {
                c = UC_TAG_C0;
            } else {
                if cnt % 4 == 1 {
                    c = UC_TAG_C1;
                } else {
                    if cnt % 4 == 2 {
                        c = UC_TAG_C2;
                    } else {
                        c = UC_TAG_C3;
                    }
                }
            }
            uc_set(x + pos, y, '[', fg, bg);
            b = 0;
            while b < len {
                uc_set(x + pos + 1 + b, y, tags[start + b], c, bg);
                b = b + 1;
            }
            uc_set(x + pos + 1 + len, y, ']', fg, bg);
            pos = pos + len + 3;
            cnt = cnt + 1;
            start = i + 1;
        }
        i = i + 1;
    }
    len = tlen - start;
    if cnt % 4 == 0 {
        c = UC_TAG_C0;
    } else {
        if cnt % 4 == 1 {
            c = UC_TAG_C1;
        } else {
            if cnt % 4 == 2 {
                c = UC_TAG_C2;
            } else {
                c = UC_TAG_C3;
            }
        }
    }
    uc_set(x + pos, y, '[', fg, bg);
    b = 0;
    while b < len {
        uc_set(x + pos + 1 + b, y, tags[start + b], c, bg);
        b = b + 1;
    }
    uc_set(x + pos + 1 + len, y, ']', fg, bg);
    return 0;
}

# ============ v1.456 信号强度图标 ============

# uc_signal_icon：绘制信号强度图标 W |||||
# strength 0-5，0 时红色 x，否则青色 | 数量。
# 用于 Wi-Fi/蓝牙/网络状态。
fn uc_signal_icon(x: i64, y: i64, strength: i64, fg: i64, bg: i64) -> i64 {
    let i: i64 = 0;
    uc_set(x, y, 'W', UC_YELLOW, bg);
    uc_set(x + 2, y, ' ', fg, bg);
    if strength <= 0 {
        uc_set(x + 3, y, 'x', UC_RED, bg);
        uc_set(x + 4, y, 'x', UC_RED, bg);
    } else {
        i = 0;
        while i < strength {
            uc_set(x + 3 + i, y, '|', UC_CYAN, bg);
            i = i + 1;
        }
    }
    return 0;
}

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

# ============ v1.458 网络地址行 ============

# uc_net_row：绘制网络地址行 IP 192.168.1.10
# label 为名称，value 为值（IP/掩码/网关）。
# 用于网络设置、状态页。
fn uc_net_row(x: i64, y: i64, label: ptr, value: ptr, fg: i64, bg: i64) -> i64 {
    let llen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    llen = strlen(label);
    vlen = strlen(value);
    i = 0;
    while i < llen {
        uc_set(x + i, y, label[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + llen, y, ' ', fg, bg);
    uc_set(x + llen + 1, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + llen + 2 + i, y, value[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.459 Wi-Fi 网络行 ============

# uc_wifi_row：绘制 Wi-Fi 网络行 WiFi  Home_5G   80%
# ssid 为网络名，signal 信号强度，locked=1 显示锁。
# 用于 Wi-Fi 设置、网络列表。
fn uc_wifi_row(x: i64, y: i64, ssid: ptr, signal: i64, locked: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(ssid);
    uc_set(x, y, 'W', UC_GREEN, bg);
    uc_set(x + 1, y, 'i', UC_GREEN, bg);
    uc_set(x + 2, y, 'F', UC_GREEN, bg);
    uc_set(x + 3, y, 'i', UC_GREEN, bg);
    uc_set(x + 6, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 7 + i, y, ssid[i], UC_WHITE, bg);
        i = i + 1;
    }
    if locked != 0 {
        uc_set(x + 9 + nlen, y, ' ', fg, bg);
        uc_set(x + 10 + nlen, y, '[', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'x', UC_RED, bg);
        uc_set(x + 12 + nlen, y, ']', UC_RED, bg);
    }
    if signal >= 100 {
        uc_set(x + 15 + nlen, y, '1', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, '0', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, '0', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, '%', UC_CYAN, bg);
    } else {
        if signal >= 10 {
            uc_set(x + 15 + nlen, y, '0' + signal / 10, UC_CYAN, bg);
            uc_set(x + 16 + nlen, y, '0' + signal % 10, UC_CYAN, bg);
        } else {
            uc_set(x + 15 + nlen, y, '0' + signal, UC_CYAN, bg);
        }
        uc_set(x + 16 + nlen, y, '%', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.460 蓝牙设备行 ============

# uc_bt_row：绘制蓝牙设备行 BT  Headphones  Connected
# name 为设备名，state 0=未连接 1=已连接。
# 用于蓝牙设置、设备列表。
fn uc_bt_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, 'B', UC_BLUE, bg);
    uc_set(x + 1, y, 'T', UC_BLUE, bg);
    uc_set(x + 4, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 5 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 7 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 8 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 9 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 8 + nlen, y, 'O', fg, bg);
        uc_set(x + 9 + nlen, y, 'f', fg, bg);
        uc_set(x + 10 + nlen, y, 'f', fg, bg);
        uc_set(x + 11 + nlen, y, 'l', fg, bg);
        uc_set(x + 12 + nlen, y, 'i', fg, bg);
        uc_set(x + 13 + nlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.461 存储设备行 ============

# uc_storage_row：绘制存储设备行 [D]  SSD   256GB  60%
# name 为设备名，size 为容量，used 为使用率。
# 用于存储管理、磁盘列表。
fn uc_storage_row(x: i64, y: i64, name: ptr, size: ptr, used: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'D', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if used > 90 {
        c = UC_RED;
    } else {
        if used > 60 {
            c = UC_YELLOW;
        } else {
            c = UC_GREEN;
        }
    }
    if used >= 100 {
        uc_set(x + 12 + nlen + slen, y, '1', c, bg);
        uc_set(x + 13 + nlen + slen, y, '0', c, bg);
        uc_set(x + 14 + nlen + slen, y, '0', c, bg);
        uc_set(x + 15 + nlen + slen, y, '%', c, bg);
    } else {
        if used >= 10 {
            uc_set(x + 12 + nlen + slen, y, '0' + used / 10, c, bg);
            uc_set(x + 13 + nlen + slen, y, '0' + used % 10, c, bg);
            uc_set(x + 14 + nlen + slen, y, '%', c, bg);
        } else {
            uc_set(x + 12 + nlen + slen, y, '0' + used, c, bg);
            uc_set(x + 13 + nlen + slen, y, '%', c, bg);
        }
    }
    return 0;
}
# ============ v1.462 打印队列行 ============

# uc_print_row：绘制打印队列行 [P]  report.pdf  Printing
# name 为任务名，state 0=排队 1=打印中 2=完成。
# 用于打印管理、任务列表。
fn uc_print_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'P', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 9 + nlen, y, 'Q', fg, bg);
        uc_set(x + 10 + nlen, y, 'u', fg, bg);
        uc_set(x + 11 + nlen, y, 'e', fg, bg);
        uc_set(x + 12 + nlen, y, 'u', fg, bg);
        uc_set(x + 13 + nlen, y, 'e', fg, bg);
        uc_set(x + 14 + nlen, y, 'd', fg, bg);
    } else {
        if state == 1 {
            uc_set(x + 9 + nlen, y, 'P', UC_CYAN, bg);
            uc_set(x + 10 + nlen, y, 'r', UC_CYAN, bg);
            uc_set(x + 11 + nlen, y, 'i', UC_CYAN, bg);
            uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 13 + nlen, y, 't', UC_CYAN, bg);
            uc_set(x + 14 + nlen, y, 'i', UC_CYAN, bg);
            uc_set(x + 15 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 16 + nlen, y, 'g', UC_CYAN, bg);
        } else {
            uc_set(x + 9 + nlen, y, 'D', UC_GREEN, bg);
            uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
            uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
            uc_set(x + 12 + nlen, y, 'e', UC_GREEN, bg);
        }
    }
    return 0;
}

# ============ v1.463 端口行 ============

# uc_port_row：绘制端口行 :8080  web  LISTEN
# port 为端口，service 为服务名，state 0=关闭 1=监听。
# 用于网络状态、端口监控。
fn uc_port_row(x: i64, y: i64, port: ptr, service: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(port);
    slen = strlen(service);
    uc_set(x, y, ':', UC_CYAN, bg);
    i = 0;
    while i < plen {
        uc_set(x + 1 + i, y, port[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 2 + plen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 3 + plen + i, y, service[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 5 + plen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 6 + plen + slen, y, 'L', UC_GREEN, bg);
        uc_set(x + 7 + plen + slen, y, 'I', UC_GREEN, bg);
        uc_set(x + 8 + plen + slen, y, 'S', UC_GREEN, bg);
        uc_set(x + 9 + plen + slen, y, 'T', UC_GREEN, bg);
        uc_set(x + 10 + plen + slen, y, 'E', UC_GREEN, bg);
        uc_set(x + 11 + plen + slen, y, 'N', UC_GREEN, bg);
    } else {
        uc_set(x + 6 + plen + slen, y, 'C', fg, bg);
        uc_set(x + 7 + plen + slen, y, 'L', fg, bg);
        uc_set(x + 8 + plen + slen, y, 'O', fg, bg);
        uc_set(x + 9 + plen + slen, y, 'S', fg, bg);
        uc_set(x + 10 + plen + slen, y, 'E', fg, bg);
        uc_set(x + 11 + plen + slen, y, 'D', fg, bg);
    }
    return 0;
}

# ============ v1.464 进程状态行 ============

# uc_proc_row：绘制进程行 PID 1234  nginx  Running
# pid 为进程号，name 为进程名，state 0=停止 1=运行。
# 用于任务管理器、进程监控。
fn uc_proc_row(x: i64, y: i64, pid: ptr, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let nlen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(pid);
    nlen = strlen(name);
    uc_set(x, y, 'P', UC_CYAN, bg);
    uc_set(x + 1, y, 'I', UC_CYAN, bg);
    uc_set(x + 2, y, 'D', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, pid[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 9 + plen + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + plen + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + plen + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 13 + plen + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 14 + plen + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + plen + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + plen + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 17 + plen + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 18 + plen + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + plen + nlen, y, 'S', fg, bg);
        uc_set(x + 13 + plen + nlen, y, 't', fg, bg);
        uc_set(x + 14 + plen + nlen, y, 'o', fg, bg);
        uc_set(x + 15 + plen + nlen, y, 'p', fg, bg);
        uc_set(x + 16 + plen + nlen, y, 'p', fg, bg);
        uc_set(x + 17 + plen + nlen, y, 'e', fg, bg);
        uc_set(x + 18 + plen + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.465 挂载点行 ============

# uc_mount_row：绘制挂载点行 [M]  /home   ext4  45%
# mount 为挂载点，fs 为文件系统，used 为使用率。
# 用于磁盘管理、文件系统状态。
fn uc_mount_row(x: i64, y: i64, mount: ptr, fs: ptr, used: i64, fg: i64, bg: i64) -> i64 {
    let mlen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    mlen = strlen(mount);
    flen = strlen(fs);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 6 + i, y, mount[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + mlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + mlen + i, y, fs[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + mlen + flen, y, ' ', fg, bg);
    if used > 90 {
        c = UC_RED;
    } else {
        if used > 60 {
            c = UC_YELLOW;
        } else {
            c = UC_GREEN;
        }
    }
    if used >= 100 {
        uc_set(x + 12 + mlen + flen, y, '1', c, bg);
        uc_set(x + 13 + mlen + flen, y, '0', c, bg);
        uc_set(x + 14 + mlen + flen, y, '0', c, bg);
        uc_set(x + 15 + mlen + flen, y, '%', c, bg);
    } else {
        if used >= 10 {
            uc_set(x + 12 + mlen + flen, y, '0' + used / 10, c, bg);
            uc_set(x + 13 + mlen + flen, y, '0' + used % 10, c, bg);
            uc_set(x + 14 + mlen + flen, y, '%', c, bg);
        } else {
            uc_set(x + 12 + mlen + flen, y, '0' + used, c, bg);
            uc_set(x + 13 + mlen + flen, y, '%', c, bg);
        }
    }
    return 0;
}

# ============ v1.466 容器状态行 ============

# uc_container_row：绘制容器行 [C]  web   Up 2h
# name 为容器名，state 0=停止 1=运行。
# 用于 Docker/容器管理。
fn uc_container_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'U', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'p', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'E', fg, bg);
        uc_set(x + 10 + nlen, y, 'x', fg, bg);
        uc_set(x + 11 + nlen, y, 'i', fg, bg);
        uc_set(x + 12 + nlen, y, 't', fg, bg);
        uc_set(x + 13 + nlen, y, 'e', fg, bg);
        uc_set(x + 14 + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.467 传感器行 ============

# uc_sensor_row：绘制传感器行 [S]  temp  45 C
# name 为传感器名，value 为数值，unit 为单位。
# 用于 IoT/传感器监控。
fn uc_sensor_row(x: i64, y: i64, name: ptr, value: ptr, unit: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    ulen = strlen(unit);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'S', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 10 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 11 + nlen + vlen + i, y, unit[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.468 日志行 ============

# uc_log_row：绘制日志行 [i]  Started server
# level 0=INFO 1=WARN 2=ERROR 3=DEBUG，msg 为日志内容。
# 用于日志查看器、控制台。
fn uc_log_row(x: i64, y: i64, level: i64, msg: ptr, fg: i64, bg: i64) -> i64 {
    let mlen: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    mlen = strlen(msg);
    if level == 0 {
        uc_set(x, y, '[', fg, bg);
        uc_set(x + 1, y, 'i', UC_CYAN, bg);
        uc_set(x + 2, y, ']', fg, bg);
    } else {
        if level == 1 {
            uc_set(x, y, '[', fg, bg);
            uc_set(x + 1, y, '!', UC_YELLOW, bg);
            uc_set(x + 2, y, ']', fg, bg);
        } else {
            if level == 2 {
                uc_set(x, y, '[', fg, bg);
                uc_set(x + 1, y, 'x', UC_RED, bg);
                uc_set(x + 2, y, ']', fg, bg);
            } else {
                uc_set(x, y, '[', fg, bg);
                uc_set(x + 1, y, '-', fg, bg);
                uc_set(x + 2, y, ']', fg, bg);
            }
        }
    }
    uc_set(x + 5, y, ' ', fg, bg);
    if level == 0 {
        c = UC_CYAN;
    } else {
        if level == 1 {
            c = UC_YELLOW;
        } else {
            if level == 2 {
                c = UC_RED;
            } else {
                c = fg;
            }
        }
    }
    i = 0;
    while i < mlen {
        uc_set(x + 6 + i, y, msg[i], c, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.469 环境变量行 ============

# uc_env_row：绘制环境变量行 PATH=/usr/bin
# key 为变量名，value 为值。
# 用于环境变量编辑器、配置管理。
fn uc_env_row(x: i64, y: i64, key: ptr, value: ptr, fg: i64, bg: i64) -> i64 {
    let klen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    klen = strlen(key);
    vlen = strlen(value);
    i = 0;
    while i < klen {
        uc_set(x + i, y, key[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + klen, y, '=', UC_WHITE, bg);
    i = 0;
    while i < vlen {
        uc_set(x + klen + 1 + i, y, value[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.470 告警行 ============

# uc_alert_row：绘制告警行 [A]  CPU high  14:32
# severity 0=信息 1=警告 2=严重，title 标题，time 时间。
# 用于监控告警、运维中心。
fn uc_alert_row(x: i64, y: i64, severity: i64, title: ptr, time: ptr, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let tl2: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    tl2 = strlen(time);
    uc_set(x, y, '[', fg, bg);
    if severity == 0 {
        uc_set(x + 1, y, 'A', UC_CYAN, bg);
    } else {
        if severity == 1 {
            uc_set(x + 1, y, 'A', UC_YELLOW, bg);
        } else {
            uc_set(x + 1, y, 'A', UC_RED, bg);
        }
    }
    uc_set(x + 2, y, ']', fg, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, title[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < tl2 {
        uc_set(x + 9 + tlen + i, y, time[i], fg, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.471 数据库行 ============

# uc_db_row：绘制数据库行 [D]  users  MySQL  1.2k rows
# name 为表名，engine 为引擎，rows 为行数。
# 用于数据库管理、表列表。
fn uc_db_row(x: i64, y: i64, name: ptr, engine: ptr, rows: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(engine);
    rlen = strlen(rows);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'D', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + nlen + i, y, engine[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + elen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 12 + nlen + elen + i, y, rows[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 13 + nlen + elen + rlen, y, ' ', fg, bg);
    uc_set(x + 14 + nlen + elen + rlen, y, 'r', fg, bg);
    uc_set(x + 15 + nlen + elen + rlen, y, 'o', fg, bg);
    uc_set(x + 16 + nlen + elen + rlen, y, 'w', fg, bg);
    uc_set(x + 17 + nlen + elen + rlen, y, 's', fg, bg);
    return 0;
}

# ============ v1.472 虚拟机行 ============

# uc_vm_row：绘制虚拟机行 [V]  web-01  Running
# name 为虚拟机名，state 0=停止 1=运行。
# 用于虚拟机管理、云控制台。
fn uc_vm_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.473 负载均衡行 ============

# uc_lb_row：绘制负载均衡行 [L]  app-pool  5 nodes  Running
# name 为名称，nodes 为节点数，state 0=停止 1=运行。
# 用于负载均衡管理、云控制台。
fn uc_lb_row(x: i64, y: i64, name: ptr, nodes: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(nodes);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'L', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, nodes[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 10 + nlen + dlen, y, ' ', fg, bg);
    uc_set(x + 11 + nlen + dlen, y, 'n', fg, bg);
    uc_set(x + 12 + nlen + dlen, y, 'o', fg, bg);
    uc_set(x + 13 + nlen + dlen, y, 'd', fg, bg);
    uc_set(x + 14 + nlen + dlen, y, 'e', fg, bg);
    uc_set(x + 15 + nlen + dlen, y, 's', fg, bg);
    uc_set(x + 17 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen + dlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 19 + nlen + dlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 20 + nlen + dlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 21 + nlen + dlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 23 + nlen + dlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 24 + nlen + dlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen + dlen, y, 'S', fg, bg);
        uc_set(x + 19 + nlen + dlen, y, 't', fg, bg);
        uc_set(x + 20 + nlen + dlen, y, 'o', fg, bg);
        uc_set(x + 21 + nlen + dlen, y, 'p', fg, bg);
        uc_set(x + 22 + nlen + dlen, y, 'p', fg, bg);
        uc_set(x + 23 + nlen + dlen, y, 'e', fg, bg);
        uc_set(x + 24 + nlen + dlen, y, 'd', fg, bg);
    }
    return 0;
}
# ============ v1.474 消息状态行 ============

# uc_msg_status_row：绘制消息状态行 [M]  to bob  Sent
# to 为接收者，state 0=排队 1=已发送 2=失败。
# 用于消息中心、通知记录。
fn uc_msg_status_row(x: i64, y: i64, to: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(to);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    uc_set(x + 6, y, 't', fg, bg);
    uc_set(x + 7, y, 'o', fg, bg);
    uc_set(x + 9, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 10 + i, y, to[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 12 + tlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 13 + tlen, y, 'Q', fg, bg);
        uc_set(x + 14 + tlen, y, 'u', fg, bg);
        uc_set(x + 15 + tlen, y, 'e', fg, bg);
        uc_set(x + 16 + tlen, y, 'u', fg, bg);
        uc_set(x + 17 + tlen, y, 'e', fg, bg);
        uc_set(x + 18 + tlen, y, 'd', fg, bg);
    } else {
        if state == 1 {
            uc_set(x + 13 + tlen, y, 'S', UC_CYAN, bg);
            uc_set(x + 14 + tlen, y, 'e', UC_CYAN, bg);
            uc_set(x + 15 + tlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 16 + tlen, y, 't', UC_CYAN, bg);
        } else {
            uc_set(x + 13 + tlen, y, 'F', UC_RED, bg);
            uc_set(x + 14 + tlen, y, 'a', UC_RED, bg);
            uc_set(x + 15 + tlen, y, 'i', UC_RED, bg);
            uc_set(x + 16 + tlen, y, 'l', UC_RED, bg);
            uc_set(x + 17 + tlen, y, 'e', UC_RED, bg);
            uc_set(x + 18 + tlen, y, 'd', UC_RED, bg);
        }
    }
    return 0;
}

# ============ v1.475 证书行 ============

# uc_cert_row：绘制证书行 [C]  example.com  Valid
# name 为域名，state 0=过期 1=有效。
# 用于 SSL/证书管理。
fn uc_cert_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'C', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'V', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'x', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.476 服务账户行 ============

# uc_sa_row：绘制服务账户行 [S]  deploy-bot  Active
# name 为账户名，state 0=禁用 1=启用。
# 用于 IAM/权限管理。
fn uc_sa_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', fg, bg);
        uc_set(x + 10 + nlen, y, 'i', fg, bg);
        uc_set(x + 11 + nlen, y, 's', fg, bg);
        uc_set(x + 12 + nlen, y, 'a', fg, bg);
        uc_set(x + 13 + nlen, y, 'b', fg, bg);
        uc_set(x + 14 + nlen, y, 'l', fg, bg);
        uc_set(x + 15 + nlen, y, 'e', fg, bg);
        uc_set(x + 16 + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.477 API 密钥行 ============

# uc_apikey_row：绘制 API 密钥行 [K]  prod-key  Active
# name 为密钥名，state 0=吊销 1=启用。
# 用于密钥管理、开发者控制台。
fn uc_apikey_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'K', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'k', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.478 任务调度行 ============

# uc_cron_row：绘制任务调度行 [T]  backup  Daily  Enabled
# name 为任务名，schedule 为调度，state 0=禁用 1=启用。
# 用于任务调度、自动化。
fn uc_cron_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'T', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + slen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.479 版本发布行 ============

# uc_release_row：绘制版本发布行 [R]  v1.2.3  Published
# tag 为版本号，state 0=草稿 1=已发布。
# 用于版本管理、发布记录。
fn uc_release_row(x: i64, y: i64, tag: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(tag);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'R', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, tag[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + tlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + tlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + tlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + tlen, y, 's', UC_GREEN, bg);
        uc_set(x + 15 + tlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 16 + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + tlen, y, 'D', fg, bg);
        uc_set(x + 10 + tlen, y, 'r', fg, bg);
        uc_set(x + 11 + tlen, y, 'a', fg, bg);
        uc_set(x + 12 + tlen, y, 'f', fg, bg);
        uc_set(x + 13 + tlen, y, 't', fg, bg);
        uc_set(x + 14 + tlen, y, 'D', fg, bg);
        uc_set(x + 15 + tlen, y, 'r', fg, bg);
        uc_set(x + 16 + tlen, y, 'a', fg, bg);
        uc_set(x + 17 + tlen, y, 'f', fg, bg);
        uc_set(x + 18 + tlen, y, 't', fg, bg);
    }
    return 0;
}

# ============ v1.480 工作流步骤行 ============

# uc_wf_step_row：绘制工作流步骤行 [1]  Build  Success
# step 为步骤号，name 为步骤名，state 0=待定 1=运行 2=成功 3=失败。
# 用于流水线、CI/CD 视图。
fn uc_wf_step_row(x: i64, y: i64, step: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', fg, bg);
    if step >= 10 {
        uc_set(x + 1, y, '0' + step / 10, UC_YELLOW, bg);
        uc_set(x + 2, y, '0' + step % 10, UC_YELLOW, bg);
    } else {
        uc_set(x + 1, y, '0' + step, UC_YELLOW, bg);
    }
    uc_set(x + 3, y, ']', fg, bg);
    uc_set(x + 6, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 7 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 9 + nlen, y, ' ', fg, bg);
    if state == 0 {
        c = fg;
        uc_set(x + 10 + nlen, y, 'P', c, bg);
        uc_set(x + 11 + nlen, y, 'e', c, bg);
        uc_set(x + 12 + nlen, y, 'n', c, bg);
        uc_set(x + 13 + nlen, y, 'd', c, bg);
        uc_set(x + 14 + nlen, y, 'i', c, bg);
        uc_set(x + 15 + nlen, y, 'n', c, bg);
        uc_set(x + 16 + nlen, y, 'g', c, bg);
    } else {
        if state == 1 {
            c = UC_CYAN;
            uc_set(x + 10 + nlen, y, 'R', c, bg);
            uc_set(x + 11 + nlen, y, 'u', c, bg);
            uc_set(x + 12 + nlen, y, 'n', c, bg);
            uc_set(x + 13 + nlen, y, 'n', c, bg);
            uc_set(x + 14 + nlen, y, 'i', c, bg);
            uc_set(x + 15 + nlen, y, 'n', c, bg);
            uc_set(x + 16 + nlen, y, 'g', c, bg);
        } else {
            if state == 2 {
                c = UC_GREEN;
                uc_set(x + 10 + nlen, y, 'S', c, bg);
                uc_set(x + 11 + nlen, y, 'u', c, bg);
                uc_set(x + 12 + nlen, y, 'c', c, bg);
                uc_set(x + 13 + nlen, y, 'c', c, bg);
                uc_set(x + 14 + nlen, y, 'e', c, bg);
                uc_set(x + 15 + nlen, y, 's', c, bg);
                uc_set(x + 16 + nlen, y, 's', c, bg);
            } else {
                c = UC_RED;
                uc_set(x + 10 + nlen, y, 'F', c, bg);
                uc_set(x + 11 + nlen, y, 'a', c, bg);
                uc_set(x + 12 + nlen, y, 'i', c, bg);
                uc_set(x + 13 + nlen, y, 'l', c, bg);
                uc_set(x + 14 + nlen, y, 'e', c, bg);
                uc_set(x + 15 + nlen, y, 'd', c, bg);
            }
        }
    }
    return 0;
}

# ============ v1.481 Git 分支行 ============

# uc_branch_row：绘制 Git 分支行 [B]  feature/login  2 commits
# name 为分支名，state 0=未合并 1=已合并。
# 用于 Git 管理、仓库视图。
fn uc_branch_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'B', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'M', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'g', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'O', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'p', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.482 依赖行 ============

# uc_dep_row：绘制依赖行 [D]  lodash  4.17.21   OK
# name 为依赖名，version 为版本号，state 0=过时 1=最新。
# 用于包管理、依赖清单。
fn uc_dep_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'O', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 'L', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'D', UC_RED, bg);
    }
    return 0;
}

# ============ v1.483 插件状态行 ============

# uc_plugin_row：绘制插件状态行 [P]  eslint  Enabled
# name 为插件名，state 0=禁用 1=启用。
# 用于插件市场、IDE 扩展。
fn uc_plugin_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', fg, bg);
        uc_set(x + 10 + nlen, y, 'i', fg, bg);
        uc_set(x + 11 + nlen, y, 's', fg, bg);
        uc_set(x + 12 + nlen, y, 'a', fg, bg);
        uc_set(x + 13 + nlen, y, 'b', fg, bg);
        uc_set(x + 14 + nlen, y, 'l', fg, bg);
        uc_set(x + 15 + nlen, y, 'e', fg, bg);
        uc_set(x + 16 + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.484 队列工作单元行 ============

# uc_queue_row：绘制队列工作单元行 [Q]  job-42  Running  retry 2
# job 为任务名，state 0=排队 1=运行 2=完成 3=失败，retries 为重试次数。
# 用于任务队列、后台作业。
fn uc_queue_row(x: i64, y: i64, job: ptr, state: i64, retries: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(job);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'Q', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, job[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 9 + nlen, y, 'Q', fg, bg);
        uc_set(x + 10 + nlen, y, 'u', fg, bg);
        uc_set(x + 11 + nlen, y, 'e', fg, bg);
        uc_set(x + 12 + nlen, y, 'u', fg, bg);
        uc_set(x + 13 + nlen, y, 'e', fg, bg);
        uc_set(x + 14 + nlen, y, 'd', fg, bg);
    } else {
        if state == 1 {
            uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
            uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
            uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
            uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
        } else {
            if state == 2 {
                uc_set(x + 9 + nlen, y, 'D', UC_GREEN, bg);
                uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
                uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
                uc_set(x + 12 + nlen, y, 'e', UC_GREEN, bg);
            } else {
                uc_set(x + 9 + nlen, y, 'F', UC_RED, bg);
                uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
                uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
                uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
                uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
                uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
            }
        }
    }
    if retries > 0 {
        uc_set(x + 17 + nlen, y, 'r', UC_WHITE, bg);
        uc_set(x + 18 + nlen, y, 'e', UC_WHITE, bg);
        uc_set(x + 19 + nlen, y, 't', UC_WHITE, bg);
        uc_set(x + 20 + nlen, y, 'r', UC_WHITE, bg);
        uc_set(x + 21 + nlen, y, 'y', UC_WHITE, bg);
        uc_set(x + 22 + nlen, y, ' ', UC_WHITE, bg);
        uc_set(x + 23 + nlen, y, '0' + retries, UC_WHITE, bg);
    }
    return 0;
}

# ============ v1.485 配置项行 ============

# uc_config_row：绘制配置项行 [C]  debug  true
# key 为配置名，value 为配置值。
# 用于配置管理、环境设置。
fn uc_config_row(x: i64, y: i64, key: ptr, value: ptr, fg: i64, bg: i64) -> i64 {
    let klen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    klen = strlen(key);
    vlen = strlen(value);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'C', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 6 + i, y, key[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + klen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + klen + i, y, value[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.486 DNS 记录行 ============

# uc_dns_row：绘制 DNS 记录行 [D]  example.com  A  93.184.216.34
# name 为主机名，type 为记录类型，value 为记录值。
# 用于 DNS 管理、域名控制台。
fn uc_dns_row(x: i64, y: i64, name: ptr, type: ptr, value: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    vlen = strlen(value);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'D', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 12 + nlen + tlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.487 密钥行 ============

# uc_secret_row：绘制密钥行 [S]  db-password  *****
# name 为密钥名，state 0=已轮换 1=活跃。
# 用于密钥管理、Secret 存储。
fn uc_secret_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, '*', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, '*', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, '*', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, '*', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, '*', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.488 配额行 ============

# uc_quota_row：绘制配额行 [Q]  storage  3.2/5 GB
# name 为配额名，used 为已用值，total 为总量，unit 为单位。
# 用于配额管理、用量展示。
fn uc_quota_row(x: i64, y: i64, name: ptr, used: i64, total: i64, unit: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(unit);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'Q', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + used / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + used % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '/', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, '0' + total / 10, UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, '.', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, '0' + total % 10, UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, ' ', UC_WHITE, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 17 + nlen + i, y, unit[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.489 IP 绑定行 ============

# uc_ip_bind_row：绘制 IP 绑定行 [I]  8080  192.168.1.5  Bound
# port 为端口号，ip 为地址，state 0=未绑定 1=已绑定。
# 用于网络配置、服务绑定。
fn uc_ip_bind_row(x: i64, y: i64, port: i64, ip: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let ilen: i64 = 0;
    let i: i64 = 0;
    ilen = strlen(ip);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'I', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    if port >= 1000 {
        uc_set(x + 6, y, '0' + port / 1000, UC_YELLOW, bg);
        uc_set(x + 7, y, '0' + (port / 100) % 10, UC_YELLOW, bg);
        uc_set(x + 8, y, '0' + (port / 10) % 10, UC_YELLOW, bg);
        uc_set(x + 9, y, '0' + port % 10, UC_YELLOW, bg);
        uc_set(x + 12, y, ' ', fg, bg);
        i = 0;
        while i < ilen {
            uc_set(x + 13 + i, y, ip[i], UC_CYAN, bg);
            i = i + 1;
        }
        uc_set(x + 15 + ilen, y, ' ', fg, bg);
        if state != 0 {
            uc_set(x + 16 + ilen, y, 'B', UC_GREEN, bg);
            uc_set(x + 17 + ilen, y, 'o', UC_GREEN, bg);
            uc_set(x + 18 + ilen, y, 'u', UC_GREEN, bg);
            uc_set(x + 19 + ilen, y, 'n', UC_GREEN, bg);
            uc_set(x + 20 + ilen, y, 'd', UC_GREEN, bg);
        } else {
            uc_set(x + 16 + ilen, y, 'F', fg, bg);
            uc_set(x + 17 + ilen, y, 'r', fg, bg);
            uc_set(x + 18 + ilen, y, 'e', fg, bg);
            uc_set(x + 19 + ilen, y, 'e', fg, bg);
        }
    } else {
        uc_set(x + 6, y, '0' + port / 100, UC_YELLOW, bg);
        uc_set(x + 7, y, '0' + (port / 10) % 10, UC_YELLOW, bg);
        uc_set(x + 8, y, '0' + port % 10, UC_YELLOW, bg);
        uc_set(x + 11, y, ' ', fg, bg);
        i = 0;
        while i < ilen {
            uc_set(x + 12 + i, y, ip[i], UC_CYAN, bg);
            i = i + 1;
        }
        uc_set(x + 14 + ilen, y, ' ', fg, bg);
        if state != 0 {
            uc_set(x + 15 + ilen, y, 'B', UC_GREEN, bg);
            uc_set(x + 16 + ilen, y, 'o', UC_GREEN, bg);
            uc_set(x + 17 + ilen, y, 'u', UC_GREEN, bg);
            uc_set(x + 18 + ilen, y, 'n', UC_GREEN, bg);
            uc_set(x + 19 + ilen, y, 'd', UC_GREEN, bg);
        } else {
            uc_set(x + 15 + ilen, y, 'F', fg, bg);
            uc_set(x + 16 + ilen, y, 'r', fg, bg);
            uc_set(x + 17 + ilen, y, 'e', fg, bg);
            uc_set(x + 18 + ilen, y, 'e', fg, bg);
        }
    }
    return 0;
}

# ============ v1.490 备份状态行 ============

# uc_backup_row：绘制备份状态行 [B]  nightly  Completed
# name 为备份名，state 0=失败 1=运行 2=完成。
# 用于备份管理、备份计划。
fn uc_backup_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'B', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 9 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    } else {
        if state == 1 {
            uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
            uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
            uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
            uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
        } else {
            uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
            uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
            uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
            uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
            uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
            uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
            uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
        }
    }
    return 0;
}

# ============ v1.491 部署目标行 ============

# uc_deploy_target_row：绘制部署目标行 [T]  prod  Healthy
# name 为目标名，state 0=异常 1=健康。
# 用于部署管理、环境状态。
fn uc_deploy_target_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'T', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'U', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'h', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'h', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.492 API 状态行 ============

# uc_api_row：绘制 API 状态行 [A]  /v1/users  200 OK
# path 为 API 路径，code 为状态码，ok 0=失败 1=成功。
# 用于 API 监控、接口状态。
fn uc_api_row(x: i64, y: i64, path: ptr, code: i64, ok: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(path);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, path[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    uc_set(x + 9 + plen, y, '0' + code / 100, UC_WHITE, bg);
    uc_set(x + 10 + plen, y, '0' + (code / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + plen, y, '0' + code % 10, UC_WHITE, bg);
    uc_set(x + 12 + plen, y, ' ', UC_WHITE, bg);
    if ok != 0 {
        uc_set(x + 13 + plen, y, 'O', UC_GREEN, bg);
        uc_set(x + 14 + plen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 13 + plen, y, 'E', UC_RED, bg);
        uc_set(x + 14 + plen, y, 'R', UC_RED, bg);
        uc_set(x + 15 + plen, y, 'R', UC_RED, bg);
    }
    return 0;
}

# ============ v1.493 流水线行 ============

# uc_pipeline_row：绘制流水线行 [P]  release  3 stages  Green
# name 为流水线名，stages 为阶段数，state 0=红 1=绿。
# 用于 CI/CD 流水线概览。
fn uc_pipeline_row(x: i64, y: i64, name: ptr, stages: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + stages / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + stages % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.494 SLA 状态行 ============

# uc_sla_row：绘制 SLA 状态行 [S]  uptime  99.9%  Met
# name 为 SLA 名，value 为达标值，state 0=未达标 1=达标。
# 用于服务等级协议监控。
fn uc_sla_row(x: i64, y: i64, name: ptr, value: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'S', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + value / 100, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + (value / 10) % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + value % 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, '%', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 16 + nlen, y, 'M', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 't', UC_GREEN, bg);
    } else {
        uc_set(x + 16 + nlen, y, 'M', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.495 功能开关行 ============

# uc_feature_flag_row：绘制功能开关行 [F]  new-checkout  ON
# name 为开关名，state 0=关 1=开。
# 用于功能开关、灰度发布。
fn uc_feature_flag_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'F', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'N', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'F', UC_RED, bg);
    }
    return 0;
}

# ============ v1.496 服务发现行 ============

# uc_sd_row：绘制服务发现行 [S]  auth-service  3 instances
# name 为服务名，instances 为实例数。
# 用于服务注册与发现。
fn uc_sd_row(x: i64, y: i64, name: ptr, instances: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + instances, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.497 证书指纹行 ============

# uc_fingerprint_row：绘制证书指纹行 [F]  SHA256  a3:4f:...
# algo 为算法名，fp 为指纹前缀。
# 用于证书指纹展示。
fn uc_fingerprint_row(x: i64, y: i64, algo: ptr, fp: ptr, fg: i64, bg: i64) -> i64 {
    let alen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    alen = strlen(algo);
    flen = strlen(fp);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'F', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 6 + i, y, algo[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + alen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + alen + i, y, fp[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.498 路由行 ============

# uc_route_row：绘制路由行 [R]  /api/users  auth-service
# path 为路由路径，target 为目标服务。
# 用于 API 网关、路由表。
fn uc_route_row(x: i64, y: i64, path: ptr, target: ptr, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(path);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, path[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + plen + i, y, target[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.499 集群节点行 ============

# uc_cluster_node_row：绘制集群节点行 [N]  node-01  Ready
# name 为节点名，state 0=异常 1=就绪。
# 用于 Kubernetes 节点管理。
fn uc_cluster_node_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'N', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'N', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.500 审计日志行 ============

# uc_audit_row：绘制审计日志行 [A]  14:05  user login  OK
# time 为时间，action 为动作，state 0=失败 1=成功。
# 用于审计日志展示。
fn uc_audit_row(x: i64, y: i64, time: ptr, action: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(time);
    alen = strlen(action);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'A', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, time[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + tlen + i, y, action[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + tlen + alen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + tlen + alen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + tlen + alen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + tlen + alen, y, 'F', UC_RED, bg);
        uc_set(x + 13 + tlen + alen, y, 'A', UC_RED, bg);
        uc_set(x + 14 + tlen + alen, y, 'I', UC_RED, bg);
        uc_set(x + 15 + tlen + alen, y, 'L', UC_RED, bg);
    }
    return 0;
}

# ============ v1.501 告警规则行 ============

# uc_alert_rule_row：绘制告警规则行 [R]  cpu>90  5m  Active
# name 为规则名，period 为周期，state 0=停用 1=启用。
# 用于告警规则管理。
fn uc_alert_rule_row(x: i64, y: i64, name: ptr, period: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(period);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'R', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, period[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'P', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'a', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 'u', fg, bg);
        uc_set(x + 15 + nlen + plen, y, 's', fg, bg);
        uc_set(x + 16 + nlen + plen, y, 'e', fg, bg);
        uc_set(x + 17 + nlen + plen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.502 配额策略行 ============

# uc_quota_policy_row：绘制配额策略行 [Q]  api-calls  10000/min  Enforced
# name 为策略名，limit 为限制，state 0=宽松 1=强制。
# 用于配额策略管理。
fn uc_quota_policy_row(x: i64, y: i64, name: ptr, limit: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(limit);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'Q', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 9 + nlen + i, y, limit[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + llen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + llen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + llen, y, 'f', UC_GREEN, bg);
        uc_set(x + 15 + nlen + llen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen + llen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + llen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + llen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + llen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + llen, y, 'S', fg, bg);
        uc_set(x + 13 + nlen + llen, y, 'o', fg, bg);
        uc_set(x + 14 + nlen + llen, y, 'f', fg, bg);
        uc_set(x + 15 + nlen + llen, y, 't', fg, bg);
    }
    return 0;
}

# ============ v1.503 价格行 ============

# uc_price_row：绘制价格行 [P]  Pro Plan  $29/mo
# name 为产品名，price 为价格，currency 为货币符号。
# 用于定价页面、订阅展示。
fn uc_price_row(x: i64, y: i64, name: ptr, price: i64, currency: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, currency, UC_YELLOW, bg);
    if price >= 100 {
        uc_set(x + 10 + nlen, y, '0' + price / 100, UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, '0' + (price / 10) % 10, UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, '0' + price % 10, UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, '/', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 'm', UC_YELLOW, bg);
        uc_set(x + 15 + nlen, y, 'o', UC_YELLOW, bg);
    } else {
        uc_set(x + 10 + nlen, y, '0' + price / 10, UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, '0' + price % 10, UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, '/', UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, 'm', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 'o', UC_YELLOW, bg);
    }
    return 0;
}

# ============ v1.504 库存行 ============

# uc_inventory_row：绘制库存行 [I]  SKU-1234  42  In Stock
# sku 为库存单位，qty 为数量，state 0=缺货 1=有货。
# 用于库存管理。
fn uc_inventory_row(x: i64, y: i64, sku: ptr, qty: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let slen: i64 = 0;
    let i: i64 = 0;
    slen = strlen(sku);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'I', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 6 + i, y, sku[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + slen, y, ' ', fg, bg);
    if qty >= 100 {
        uc_set(x + 9 + slen, y, '0' + qty / 100, UC_CYAN, bg);
        uc_set(x + 10 + slen, y, '0' + (qty / 10) % 10, UC_CYAN, bg);
        uc_set(x + 11 + slen, y, '0' + qty % 10, UC_CYAN, bg);
    } else {
        uc_set(x + 9 + slen, y, '0' + qty / 10, UC_CYAN, bg);
        uc_set(x + 10 + slen, y, '0' + qty % 10, UC_CYAN, bg);
    }
    uc_set(x + 12 + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 13 + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 14 + slen, y, 'n', UC_CYAN, bg);
    uc_set(x + 15 + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 16 + slen, y, 'S', UC_GREEN, bg);
        uc_set(x + 17 + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 18 + slen, y, 'o', UC_GREEN, bg);
        uc_set(x + 19 + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 20 + slen, y, 'k', UC_GREEN, bg);
    } else {
        uc_set(x + 16 + slen, y, 'O', UC_RED, bg);
        uc_set(x + 17 + slen, y, 'O', UC_RED, bg);
        uc_set(x + 18 + slen, y, 'S', UC_RED, bg);
    }
    return 0;
}

# ============ v1.505 订单行 ============

# uc_order_row：绘制订单行 [O]  #1024  bob  $45  Paid
# order_id 为订单号，customer 为客户名，amount 为金额，state 0=待付 1=已付。
# 用于订单管理。
fn uc_order_row(x: i64, y: i64, order_id: ptr, customer: ptr, amount: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let olen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    olen = strlen(order_id);
    clen = strlen(customer);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'O', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < olen {
        uc_set(x + 6 + i, y, order_id[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + olen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + olen + i, y, customer[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + olen + clen, y, ' ', fg, bg);
    uc_set(x + 12 + olen + clen, y, '$', UC_CYAN, bg);
    uc_set(x + 13 + olen + clen, y, '0' + amount / 10, UC_CYAN, bg);
    uc_set(x + 14 + olen + clen, y, '0' + amount % 10, UC_CYAN, bg);
    uc_set(x + 16 + olen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 17 + olen + clen, y, 'P', UC_GREEN, bg);
        uc_set(x + 18 + olen + clen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + olen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 20 + olen + clen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 17 + olen + clen, y, 'P', UC_RED, bg);
        uc_set(x + 18 + olen + clen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + olen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 20 + olen + clen, y, 'd', UC_RED, bg);
        uc_set(x + 21 + olen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 22 + olen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 23 + olen + clen, y, 'g', UC_RED, bg);
    }
    return 0;
}

# ============ v1.506 优惠券行 ============

# uc_coupon_row：绘制优惠券行 [C]  SUMMER20  20% OFF  Active
# code 为优惠码，desc 为描述，state 0=过期 1=有效。
# 用于促销管理、优惠券列表。
fn uc_coupon_row(x: i64, y: i64, code: ptr, desc: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let clen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    clen = strlen(code);
    dlen = strlen(desc);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 6 + i, y, code[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + clen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + clen + i, y, desc[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + clen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + clen + dlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + clen + dlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + clen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + clen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + clen + dlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + clen + dlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + clen + dlen, y, 'E', UC_RED, bg);
        uc_set(x + 13 + clen + dlen, y, 'x', UC_RED, bg);
        uc_set(x + 14 + clen + dlen, y, 'p', UC_RED, bg);
        uc_set(x + 15 + clen + dlen, y, 'i', UC_RED, bg);
        uc_set(x + 16 + clen + dlen, y, 'r', UC_RED, bg);
        uc_set(x + 17 + clen + dlen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + clen + dlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.507 退货行 ============

# uc_return_row：绘制退货行 [R]  #1024  refund $45  Approved
# order_id 为订单号，amount 为退款金额，state 0=拒绝 1=通过。
# 用于退货管理。
fn uc_return_row(x: i64, y: i64, order_id: ptr, amount: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let olen: i64 = 0;
    let i: i64 = 0;
    olen = strlen(order_id);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'R', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < olen {
        uc_set(x + 6 + i, y, order_id[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + olen, y, ' ', fg, bg);
    uc_set(x + 9 + olen, y, '$', UC_CYAN, bg);
    uc_set(x + 10 + olen, y, '0' + amount / 10, UC_CYAN, bg);
    uc_set(x + 11 + olen, y, '0' + amount % 10, UC_CYAN, bg);
    uc_set(x + 13 + olen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + olen, y, 'A', UC_GREEN, bg);
        uc_set(x + 15 + olen, y, 'p', UC_GREEN, bg);
        uc_set(x + 16 + olen, y, 'p', UC_GREEN, bg);
        uc_set(x + 17 + olen, y, 'r', UC_GREEN, bg);
        uc_set(x + 18 + olen, y, 'o', UC_GREEN, bg);
        uc_set(x + 19 + olen, y, 'v', UC_GREEN, bg);
        uc_set(x + 20 + olen, y, 'e', UC_GREEN, bg);
        uc_set(x + 21 + olen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + olen, y, 'D', UC_RED, bg);
        uc_set(x + 15 + olen, y, 'e', UC_RED, bg);
        uc_set(x + 16 + olen, y, 'n', UC_RED, bg);
        uc_set(x + 17 + olen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + olen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + olen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.508 供应商行 ============

# uc_supplier_row：绘制供应商行 [S]  acme-corp  Active
# name 为供应商名，state 0=停用 1=启用。
# 用于供应商管理。
fn uc_supplier_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'S', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'I', fg, bg);
        uc_set(x + 10 + nlen, y, 'n', fg, bg);
        uc_set(x + 11 + nlen, y, 'a', fg, bg);
        uc_set(x + 12 + nlen, y, 'c', fg, bg);
        uc_set(x + 13 + nlen, y, 't', fg, bg);
        uc_set(x + 14 + nlen, y, 'i', fg, bg);
        uc_set(x + 15 + nlen, y, 'v', fg, bg);
        uc_set(x + 16 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.509 仓储行 ============

# uc_warehouse_row：绘制仓储行 [W]  WH-East  Capacity 80%
# name 为仓库名，usage 为使用率，state 0=超载 1=正常。
# 用于仓储管理。
fn uc_warehouse_row(x: i64, y: i64, name: ptr, usage: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'W', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, 'C', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'y', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, '0' + usage / 10, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '0' + usage % 10, UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 23 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 23 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'U', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'L', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'L', UC_RED, bg);
    }
    return 0;
}

# ============ v1.510 配送行 ============

# uc_delivery_row：绘制配送行 [D]  #1024  bob  In Transit
# order_id 为订单号，customer 为客户名，state 0=待发 1=运输 2=已签收。
# 用于物流跟踪。
fn uc_delivery_row(x: i64, y: i64, order_id: ptr, customer: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let olen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    olen = strlen(order_id);
    clen = strlen(customer);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'D', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < olen {
        uc_set(x + 6 + i, y, order_id[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + olen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + olen + i, y, customer[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + olen + clen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 12 + olen + clen, y, 'P', UC_YELLOW, bg);
        uc_set(x + 13 + olen + clen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 14 + olen + clen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 15 + olen + clen, y, 'd', UC_YELLOW, bg);
        uc_set(x + 16 + olen + clen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 17 + olen + clen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 18 + olen + clen, y, 'g', UC_YELLOW, bg);
    } else {
        if state == 1 {
            uc_set(x + 12 + olen + clen, y, 'T', UC_CYAN, bg);
            uc_set(x + 13 + olen + clen, y, 'r', UC_CYAN, bg);
            uc_set(x + 14 + olen + clen, y, 'a', UC_CYAN, bg);
            uc_set(x + 15 + olen + clen, y, 'n', UC_CYAN, bg);
            uc_set(x + 16 + olen + clen, y, 's', UC_CYAN, bg);
            uc_set(x + 17 + olen + clen, y, 'i', UC_CYAN, bg);
            uc_set(x + 18 + olen + clen, y, 't', UC_CYAN, bg);
        } else {
            uc_set(x + 12 + olen + clen, y, 'D', UC_GREEN, bg);
            uc_set(x + 13 + olen + clen, y, 'e', UC_GREEN, bg);
            uc_set(x + 14 + olen + clen, y, 'l', UC_GREEN, bg);
            uc_set(x + 15 + olen + clen, y, 'i', UC_GREEN, bg);
            uc_set(x + 16 + olen + clen, y, 'v', UC_GREEN, bg);
            uc_set(x + 17 + olen + clen, y, 'e', UC_GREEN, bg);
            uc_set(x + 18 + olen + clen, y, 'r', UC_GREEN, bg);
            uc_set(x + 19 + olen + clen, y, 'e', UC_GREEN, bg);
            uc_set(x + 20 + olen + clen, y, 'd', UC_GREEN, bg);
        }
    }
    return 0;
}

# ============ v1.511 维护窗口行 ============

# uc_maintenance_row：绘制维护窗口行 [M]  db-upgrade  Scheduled
# name 为维护名，state 0=进行中 1=已计划 2=已完成。
# 用于维护计划展示。
fn uc_maintenance_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 9 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
    } else {
        if state == 1 {
            uc_set(x + 9 + nlen, y, 'S', UC_GREEN, bg);
            uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
            uc_set(x + 11 + nlen, y, 'h', UC_GREEN, bg);
            uc_set(x + 12 + nlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 13 + nlen, y, 'd', UC_GREEN, bg);
            uc_set(x + 14 + nlen, y, 'u', UC_GREEN, bg);
            uc_set(x + 15 + nlen, y, 'l', UC_GREEN, bg);
            uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
        } else {
            uc_set(x + 9 + nlen, y, 'D', fg, bg);
            uc_set(x + 10 + nlen, y, 'o', fg, bg);
            uc_set(x + 11 + nlen, y, 'n', fg, bg);
            uc_set(x + 12 + nlen, y, 'e', fg, bg);
        }
    }
    return 0;
}

# ============ v1.512 工单行 ============

# uc_ticket_row：绘制工单行 [T]  #4821  Login issue  Open
# ticket_id 为工单号，title 为标题，state 0=待处理 1=处理中 2=已解决。
# 用于工单管理。
fn uc_ticket_row(x: i64, y: i64, ticket_id: ptr, title: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let hlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(ticket_id);
    hlen = strlen(title);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'T', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, ticket_id[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < hlen {
        uc_set(x + 9 + tlen + i, y, title[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + tlen + hlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 12 + tlen + hlen, y, 'O', UC_YELLOW, bg);
        uc_set(x + 13 + tlen + hlen, y, 'p', UC_YELLOW, bg);
        uc_set(x + 14 + tlen + hlen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 15 + tlen + hlen, y, 'n', UC_YELLOW, bg);
    } else {
        if state == 1 {
            uc_set(x + 12 + tlen + hlen, y, 'I', UC_CYAN, bg);
            uc_set(x + 13 + tlen + hlen, y, 'n', UC_CYAN, bg);
            uc_set(x + 14 + tlen + hlen, y, 'P', UC_CYAN, bg);
            uc_set(x + 15 + tlen + hlen, y, 'r', UC_CYAN, bg);
            uc_set(x + 16 + tlen + hlen, y, 'o', UC_CYAN, bg);
            uc_set(x + 17 + tlen + hlen, y, 'g', UC_CYAN, bg);
        } else {
            uc_set(x + 12 + tlen + hlen, y, 'S', UC_GREEN, bg);
            uc_set(x + 13 + tlen + hlen, y, 'o', UC_GREEN, bg);
            uc_set(x + 14 + tlen + hlen, y, 'l', UC_GREEN, bg);
            uc_set(x + 15 + tlen + hlen, y, 'v', UC_GREEN, bg);
            uc_set(x + 16 + tlen + hlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 17 + tlen + hlen, y, 'd', UC_GREEN, bg);
        }
    }
    return 0;
}

# ============ v1.513 资产行 ============

# uc_asset_row：绘制资产行 [A]  laptop-01  In Use  bob
# name 为资产名，state 0=空闲 1=使用中，owner 为使用人。
# 用于资产跟踪。
fn uc_asset_row(x: i64, y: i64, name: ptr, state: i64, owner: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let olen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    olen = strlen(owner);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'I', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'U', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'I', fg, bg);
        uc_set(x + 10 + nlen, y, 'd', fg, bg);
        uc_set(x + 11 + nlen, y, 'l', fg, bg);
        uc_set(x + 12 + nlen, y, 'e', fg, bg);
    }
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < olen {
        uc_set(x + 17 + nlen + i, y, owner[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.514 许可证行 ============

# uc_license_row：绘制许可证行 [L]  prod-license  Valid 10/20 seats
# name 为许可证名，used 为已用数量，total 为总数。
# 用于许可证管理。
fn uc_license_row(x: i64, y: i64, name: ptr, used: i64, total: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'L', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, 'V', UC_GREEN, bg);
    uc_set(x + 10 + nlen, y, 'a', UC_GREEN, bg);
    uc_set(x + 11 + nlen, y, 'l', UC_GREEN, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_GREEN, bg);
    uc_set(x + 14 + nlen, y, ' ', UC_GREEN, bg);
    uc_set(x + 15 + nlen, y, '0' + used / 10, UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, '0' + used % 10, UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, '/', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, '0' + total / 10, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + total % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.515 数据源行 ============

# uc_datasource_row：绘制数据源行 [D]  analytics-db  PostgreSQL  Connected
# name 为数据源名，type 为类型，state 0=断开 1=连接。
# 用于数据源管理。
fn uc_datasource_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 't', UC_RED, bg);
        uc_set(x + 22 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 23 + nlen + tlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.516 触发器行 ============

# uc_trigger_row：绘制触发器行 [T]  after_insert  ON users  Enabled
# name 为触发器名，table 为目标表，state 0=禁用 1=启用。
# 用于数据库触发器管理。
fn uc_trigger_row(x: i64, y: i64, name: ptr, table: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(table);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'T', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, table[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.517 视图行 ============

# uc_view_row：绘制视图行 [V]  active_users  users  Materialized
# name 为视图名，table 为源表，state 0=普通 1=物化。
# 用于数据库视图管理。
fn uc_view_row(x: i64, y: i64, name: ptr, table: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(table);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'V', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, table[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'M', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen + tlen, y, 'z', UC_GREEN, bg);
        uc_set(x + 22 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 23 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'V', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'w', fg, bg);
    }
    return 0;
}

# ============ v1.518 存储过程行 ============

# uc_proc_row2：绘制存储过程行 [P]  get_users  success
# name 为过程名，state 0=失败 1=成功。
# 用于数据库存储过程执行状态。
fn uc_proc_row2(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 's', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.519 事件行 ============

# uc_event_row：绘制事件行 [E]  user.created  published
# name 为事件名，state 0=失败 1=已发布。
# 用于事件总线、消息事件。
fn uc_event_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'E', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.520 调度任务行 ============

# uc_schedule_row：绘制调度任务行 [S]  nightly-report  Cron 0 2 * * *  Enabled
# name 为任务名，cron 为调度表达式，state 0=禁用 1=启用。
# 用于调度任务管理。
fn uc_schedule_row(x: i64, y: i64, name: ptr, cron: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(cron);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, cron[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + clen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.521 API 版本行 ============

# uc_api_version_row：绘制 API 版本行 [V]  v1.2.3  Deprecated
# version 为版本号，state 0=已弃用 1=当前 2=测试版。
# 用于 API 版本管理。
fn uc_api_version_row(x: i64, y: i64, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let vlen: i64 = 0;
    let i: i64 = 0;
    vlen = strlen(version);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'V', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 6 + i, y, version[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + vlen, y, ' ', fg, bg);
    if state == 0 {
        uc_set(x + 9 + vlen, y, 'D', UC_RED, bg);
        uc_set(x + 10 + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 11 + vlen, y, 'p', UC_RED, bg);
        uc_set(x + 12 + vlen, y, 'r', UC_RED, bg);
        uc_set(x + 13 + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + vlen, y, 'c', UC_RED, bg);
        uc_set(x + 15 + vlen, y, 'a', UC_RED, bg);
        uc_set(x + 16 + vlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + vlen, y, 'd', UC_RED, bg);
    } else {
        if state == 1 {
            uc_set(x + 9 + vlen, y, 'C', UC_GREEN, bg);
            uc_set(x + 10 + vlen, y, 'u', UC_GREEN, bg);
            uc_set(x + 11 + vlen, y, 'r', UC_GREEN, bg);
            uc_set(x + 12 + vlen, y, 'r', UC_GREEN, bg);
            uc_set(x + 13 + vlen, y, 'e', UC_GREEN, bg);
            uc_set(x + 14 + vlen, y, 'n', UC_GREEN, bg);
            uc_set(x + 15 + vlen, y, 't', UC_GREEN, bg);
        } else {
            uc_set(x + 9 + vlen, y, 'B', UC_CYAN, bg);
            uc_set(x + 10 + vlen, y, 'e', UC_CYAN, bg);
            uc_set(x + 11 + vlen, y, 't', UC_CYAN, bg);
            uc_set(x + 12 + vlen, y, 'a', UC_CYAN, bg);
        }
    }
    return 0;
}

# ============ v1.522 数据模型行 ============

# uc_data_model_row：绘制数据模型行 [M]  User  created  Active
# name 为模型名，table 为源表，state 0=停用 1=启用。
# 用于数据建模、ORM 展示。
fn uc_data_model_row(x: i64, y: i64, name: ptr, table: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(table);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'M', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, table[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.523 字段行 ============

# uc_field_row：绘制字段行 [F]  username  varchar(255)  NOT NULL
# name 为字段名，type 为类型，state 0=可空 1=非空。
# 用于数据表字段展示。
fn uc_field_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'F', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'T', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'U', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'L', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'L', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'N', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'U', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'L', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'L', fg, bg);
    }
    return 0;
}

# ============ v1.524 索引行 ============

# uc_index_row：绘制索引行 [I]  idx_users_email  UNIQUE  users(email)
# name 为索引名，type 为索引类型，table 为目标表。
# 用于数据库索引管理。
fn uc_index_row(x: i64, y: i64, name: ptr, type: ptr, table: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    blen = strlen(table);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'I', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 12 + nlen + tlen + i, y, table[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.525 约束行 ============

# uc_constraint_row：绘制约束行 [C]  fk_user_id  FOREIGN KEY  users(id)
# name 为约束名，type 为约束类型，table 为目标表。
# 用于数据库约束管理。
fn uc_constraint_row(x: i64, y: i64, name: ptr, type: ptr, table: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    blen = strlen(table);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 12 + nlen + tlen + i, y, table[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.526 迁移状态行 ============

# uc_migration_row：绘制迁移状态行 [M]  20240101_init  Applied
# name 为迁移名，state 0=待执行 1=已执行。
# 用于数据库迁移管理。
fn uc_migration_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'P', UC_YELLOW, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, 'd', UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_YELLOW, bg);
    }
    return 0;
}

# ============ v1.527 种子数据行 ============

# uc_seed_row：绘制种子数据行 [S]  roles  Seeded  5 rows
# name 为数据名，rows 为行数，state 0=未种 1=已种。
# 用于种子数据管理。
fn uc_seed_row(x: i64, y: i64, name: ptr, rows: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'U', UC_YELLOW, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, 's', UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_YELLOW, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + rows, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'w', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.528 数据桶行 ============

# uc_bucket_row：绘制数据桶行 [B]  uploads  Public  128 objects
# name 为桶名，state 0=私有 1=公开，objects 为对象数。
# 用于对象存储管理。
fn uc_bucket_row(x: i64, y: i64, name: ptr, state: i64, objects: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'B', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'P', fg, bg);
        uc_set(x + 10 + nlen, y, 'r', fg, bg);
        uc_set(x + 11 + nlen, y, 'i', fg, bg);
        uc_set(x + 12 + nlen, y, 'v', fg, bg);
        uc_set(x + 13 + nlen, y, 'a', fg, bg);
        uc_set(x + 14 + nlen, y, 't', fg, bg);
        uc_set(x + 15 + nlen, y, 'e', fg, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + objects / 100, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + (objects / 10) % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, '0' + objects % 10, UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'b', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'j', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.529 主题消息行 ============

# uc_topic_row：绘制主题消息行 [T]  orders.created  published  42 msgs
# name 为主题名，state 0=失败 1=已发布，msgs 为消息数。
# 用于消息队列主题。
fn uc_topic_row(x: i64, y: i64, name: ptr, state: i64, msgs: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    uc_set(x + 20 + nlen, y, '0' + msgs / 10, UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, '0' + msgs % 10, UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'm', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.530 事务行 ============

# uc_txn_row：绘制事务行 [T]  #12345  commit  OK
# txn_id 为事务号，action 为动作，state 0=回滚 1=提交。
# 用于事务日志展示。
fn uc_txn_row(x: i64, y: i64, txn_id: ptr, action: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(txn_id);
    alen = strlen(action);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'T', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, txn_id[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + tlen + i, y, action[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + tlen + alen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + tlen + alen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + tlen + alen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + tlen + alen, y, 'R', UC_RED, bg);
        uc_set(x + 13 + tlen + alen, y, 'B', UC_RED, bg);
        uc_set(x + 14 + tlen + alen, y, 'K', UC_RED, bg);
    }
    return 0;
}

# ============ v1.531 备份计划行 ============

# uc_backup_plan_row：绘制备份计划行 [P]  daily-backup  Every 24h  Enabled
# name 为计划名，interval 为间隔，state 0=禁用 1=启用。
# 用于备份计划管理。
fn uc_backup_plan_row(x: i64, y: i64, name: ptr, interval: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 9 + nlen + i, y, interval[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ilen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + ilen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + ilen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + ilen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + ilen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen + ilen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + ilen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + ilen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + ilen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + ilen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + ilen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + ilen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + ilen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + ilen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + ilen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + ilen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.532 恢复点行 ============

# uc_restore_point_row：绘制恢复点行 [R]  rp-20240101  Available
# name 为恢复点名，state 0=不可用 1=可用。
# 用于数据库恢复点。
fn uc_restore_point_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'U', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'b', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.533 数据保留策略行 ============

# uc_retention_row：绘制数据保留策略行 [R]  logs  30 days  Active
# name 为策略名，period 为保留期，state 0=停用 1=启用。
# 用于数据保留策略管理。
fn uc_retention_row(x: i64, y: i64, name: ptr, period: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(period);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'R', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, period[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'O', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'f', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 'f', fg, bg);
    }
    return 0;
}

# ============ v1.534 存储类行 ============

# uc_storage_class_row：绘制存储类行 [C]  STANDARD  Hot  0.023$/GB
# name 为存储类名，tier 为层级，price 为价格。
# 用于对象存储类展示。
fn uc_storage_class_row(x: i64, y: i64, name: ptr, tier: ptr, price: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(tier);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, tier[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + tlen, y, '0', UC_WHITE, bg);
    uc_set(x + 13 + nlen + tlen, y, '.', UC_WHITE, bg);
    uc_set(x + 14 + nlen + tlen, y, '0' + price / 100, UC_WHITE, bg);
    uc_set(x + 15 + nlen + tlen, y, '0' + (price / 10) % 10, UC_WHITE, bg);
    uc_set(x + 16 + nlen + tlen, y, '0' + price % 10, UC_WHITE, bg);
    uc_set(x + 17 + nlen + tlen, y, '$', UC_WHITE, bg);
    uc_set(x + 18 + nlen + tlen, y, '/', UC_WHITE, bg);
    uc_set(x + 19 + nlen + tlen, y, 'G', UC_WHITE, bg);
    uc_set(x + 20 + nlen + tlen, y, 'B', UC_WHITE, bg);
    return 0;
}

# ============ v1.535 卷快照行 ============

# uc_snapshot_row：绘制卷快照行 [S]  snap-20240101  Completed
# name 为快照名，state 0=进行中 1=已完成。
# 用于卷快照管理。
fn uc_snapshot_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.536 负载均衡目标行 ============

# uc_lb_target_row：绘制负载均衡目标行 [T]  web-01  192.168.1.10:8080  Healthy
# name 为目标名，endpoint 为端点，state 0=异常 1=健康。
# 用于负载均衡目标管理。
fn uc_lb_target_row(x: i64, y: i64, name: ptr, endpoint: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(endpoint);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'T', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + nlen + i, y, endpoint[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + elen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + elen, y, 'H', UC_GREEN, bg);
        uc_set(x + 13 + nlen + elen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + elen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + elen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + elen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + elen, y, 'h', UC_GREEN, bg);
        uc_set(x + 18 + nlen + elen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + elen, y, 'U', UC_RED, bg);
        uc_set(x + 13 + nlen + elen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + elen, y, 'h', UC_RED, bg);
        uc_set(x + 15 + nlen + elen, y, 'e', UC_RED, bg);
        uc_set(x + 16 + nlen + elen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen + elen, y, 'l', UC_RED, bg);
        uc_set(x + 18 + nlen + elen, y, 't', UC_RED, bg);
        uc_set(x + 19 + nlen + elen, y, 'h', UC_RED, bg);
        uc_set(x + 20 + nlen + elen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.537 健康检查行 ============

# uc_health_check_row：绘制健康检查行 [H]  web-health  GET /health  200  Pass
# name 为检查名，path 为路径，code 为状态码，state 0=失败 1=通过。
# 用于健康检查配置。
fn uc_health_check_row(x: i64, y: i64, name: ptr, path: ptr, code: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(path);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'H', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, path[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + plen, y, '0' + code / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + plen, y, '0' + (code / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + plen, y, '0' + code % 10, UC_CYAN, bg);
    uc_set(x + 16 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 17 + nlen + plen, y, 'P', UC_GREEN, bg);
        uc_set(x + 18 + nlen + plen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + nlen + plen, y, 's', UC_GREEN, bg);
        uc_set(x + 20 + nlen + plen, y, 's', UC_GREEN, bg);
    } else {
        uc_set(x + 17 + nlen + plen, y, 'F', UC_RED, bg);
        uc_set(x + 18 + nlen + plen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + plen, y, 'i', UC_RED, bg);
        uc_set(x + 20 + nlen + plen, y, 'l', UC_RED, bg);
    }
    return 0;
}

# ============ v1.538 防火墙规则行 ============

# uc_firewall_rule_row：绘制防火墙规则行 [F]  allow-web  0.0.0.0/0  443  Allow
# name 为规则名，source 为来源，port 为端口，state 0=拒绝 1=允许。
# 用于防火墙规则管理。
fn uc_firewall_rule_row(x: i64, y: i64, name: ptr, source: ptr, port: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(source);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'F', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, source[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if port >= 100 {
        uc_set(x + 12 + nlen + slen, y, '0' + port / 100, UC_WHITE, bg);
        uc_set(x + 13 + nlen + slen, y, '0' + (port / 10) % 10, UC_WHITE, bg);
        uc_set(x + 14 + nlen + slen, y, '0' + port % 10, UC_WHITE, bg);
        uc_set(x + 16 + nlen + slen, y, ' ', fg, bg);
        if state != 0 {
            uc_set(x + 17 + nlen + slen, y, 'A', UC_GREEN, bg);
            uc_set(x + 18 + nlen + slen, y, 'l', UC_GREEN, bg);
            uc_set(x + 19 + nlen + slen, y, 'l', UC_GREEN, bg);
            uc_set(x + 20 + nlen + slen, y, 'o', UC_GREEN, bg);
            uc_set(x + 21 + nlen + slen, y, 'w', UC_GREEN, bg);
        } else {
            uc_set(x + 17 + nlen + slen, y, 'D', UC_RED, bg);
            uc_set(x + 18 + nlen + slen, y, 'e', UC_RED, bg);
            uc_set(x + 19 + nlen + slen, y, 'n', UC_RED, bg);
            uc_set(x + 20 + nlen + slen, y, 'y', UC_RED, bg);
        }
    } else {
        uc_set(x + 12 + nlen + slen, y, '0' + port / 10, UC_WHITE, bg);
        uc_set(x + 13 + nlen + slen, y, '0' + port % 10, UC_WHITE, bg);
        uc_set(x + 15 + nlen + slen, y, ' ', fg, bg);
        if state != 0 {
            uc_set(x + 16 + nlen + slen, y, 'A', UC_GREEN, bg);
            uc_set(x + 17 + nlen + slen, y, 'l', UC_GREEN, bg);
            uc_set(x + 18 + nlen + slen, y, 'l', UC_GREEN, bg);
            uc_set(x + 19 + nlen + slen, y, 'o', UC_GREEN, bg);
            uc_set(x + 20 + nlen + slen, y, 'w', UC_GREEN, bg);
        } else {
            uc_set(x + 16 + nlen + slen, y, 'D', UC_RED, bg);
            uc_set(x + 17 + nlen + slen, y, 'e', UC_RED, bg);
            uc_set(x + 18 + nlen + slen, y, 'n', UC_RED, bg);
            uc_set(x + 19 + nlen + slen, y, 'y', UC_RED, bg);
        }
    }
    return 0;
}

# ============ v1.539 子网行 ============

# uc_subnet_row：绘制子网行 [S]  private-a  10.0.1.0/24  Active
# name 为子网名，cidr 为网段，state 0=停用 1=启用。
# 用于 VPC 子网管理。
fn uc_subnet_row(x: i64, y: i64, name: ptr, cidr: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(cidr);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, cidr[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.540 安全组行 ============

# uc_security_group_row：绘制安全组行 [G]  sg-web  Inbound 10 rules  Active
# name 为安全组名，rules 为规则数，state 0=停用 1=启用。
# 用于安全组管理。
fn uc_security_group_row(x: i64, y: i64, name: ptr, rules: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'G', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if rules >= 10 {
        uc_set(x + 9 + nlen, y, '0' + rules / 10, UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, '0' + rules % 10, UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, '0' + rules, UC_CYAN, bg);
    }
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen, y, 'I', fg, bg);
        uc_set(x + 19 + nlen, y, 'n', fg, bg);
        uc_set(x + 20 + nlen, y, 'a', fg, bg);
        uc_set(x + 21 + nlen, y, 'c', fg, bg);
        uc_set(x + 22 + nlen, y, 't', fg, bg);
        uc_set(x + 23 + nlen, y, 'i', fg, bg);
        uc_set(x + 24 + nlen, y, 'v', fg, bg);
        uc_set(x + 25 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.541 VPN 连接行 ============

# uc_vpn_row：绘制 VPN 连接行 [V]  vpn-east  Connected  10.0.0.1
# name 为连接名，state 0=断开 1=连接，ip 为隧道 IP。
# 用于 VPN 连接管理。
fn uc_vpn_row(x: i64, y: i64, name: ptr, state: i64, ip: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(ip);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 23 + nlen + i, y, ip[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.542 CDN 域名行 ============

# uc_cdn_row：绘制 CDN 域名行 [C]  static.example.com  Enabled
# domain 为域名，state 0=禁用 1=启用。
# 用于 CDN 域名管理。
fn uc_cdn_row(x: i64, y: i64, domain: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let dlen: i64 = 0;
    let i: i64 = 0;
    dlen = strlen(domain);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 6 + i, y, domain[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + dlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 10 + dlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + dlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + dlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 13 + dlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + dlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + dlen, y, 'D', fg, bg);
        uc_set(x + 10 + dlen, y, 'i', fg, bg);
        uc_set(x + 11 + dlen, y, 's', fg, bg);
        uc_set(x + 12 + dlen, y, 'a', fg, bg);
        uc_set(x + 13 + dlen, y, 'b', fg, bg);
        uc_set(x + 14 + dlen, y, 'l', fg, bg);
        uc_set(x + 15 + dlen, y, 'e', fg, bg);
        uc_set(x + 16 + dlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.543 DNS 区域行 ============

# uc_dns_zone_row：绘制 DNS 区域行 [Z]  example.com  Active  12 records
# zone 为区域名，records 为记录数，state 0=停用 1=启用。
# 用于 DNS 区域管理。
fn uc_dns_zone_row(x: i64, y: i64, zone: ptr, records: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let zlen: i64 = 0;
    let i: i64 = 0;
    zlen = strlen(zone);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'Z', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < zlen {
        uc_set(x + 6 + i, y, zone[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + zlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + zlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + zlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + zlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + zlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + zlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + zlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + zlen, y, 'I', fg, bg);
        uc_set(x + 10 + zlen, y, 'n', fg, bg);
        uc_set(x + 11 + zlen, y, 'a', fg, bg);
        uc_set(x + 12 + zlen, y, 'c', fg, bg);
        uc_set(x + 13 + zlen, y, 't', fg, bg);
        uc_set(x + 14 + zlen, y, 'i', fg, bg);
        uc_set(x + 15 + zlen, y, 'v', fg, bg);
        uc_set(x + 16 + zlen, y, 'e', fg, bg);
    }
    uc_set(x + 18 + zlen, y, ' ', fg, bg);
    uc_set(x + 19 + zlen, y, '0' + records / 10, UC_CYAN, bg);
    uc_set(x + 20 + zlen, y, '0' + records % 10, UC_CYAN, bg);
    uc_set(x + 21 + zlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 22 + zlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 23 + zlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 24 + zlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 25 + zlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 26 + zlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 27 + zlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 28 + zlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.544 API 网关路由行 ============

# uc_gateway_route_row：绘制 API 网关路由行 [R]  /v1/orders  order-svc  GET
# path 为路由路径，target 为目标服务，method 为方法。
# 用于 API 网关路由管理。
fn uc_gateway_route_row(x: i64, y: i64, path: ptr, target: ptr, method: ptr, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let tlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(path);
    tlen = strlen(target);
    mlen = strlen(method);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, path[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + plen + i, y, target[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + plen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 12 + plen + tlen + i, y, method[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.545 静态站点行 ============

# uc_static_site_row：绘制静态站点行 [S]  docs.example.com  Deployed
# domain 为域名，state 0=构建中 1=已部署。
# 用于静态站点托管。
fn uc_static_site_row(x: i64, y: i64, domain: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let dlen: i64 = 0;
    let i: i64 = 0;
    dlen = strlen(domain);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'S', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 6 + i, y, domain[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + dlen, y, 'D', UC_GREEN, bg);
        uc_set(x + 10 + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + dlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 12 + dlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + dlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + dlen, y, 'y', UC_GREEN, bg);
        uc_set(x + 15 + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + dlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + dlen, y, 'B', UC_CYAN, bg);
        uc_set(x + 10 + dlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + dlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 12 + dlen, y, 'l', UC_CYAN, bg);
        uc_set(x + 13 + dlen, y, 'd', UC_CYAN, bg);
        uc_set(x + 14 + dlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 15 + dlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 16 + dlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.546 函数计算行 ============

# uc_function_row：绘制函数计算行 [F]  process-order  128MB  Active
# name 为函数名，memory 为内存，state 0=停用 1=启用。
# 用于 Serverless 函数管理。
fn uc_function_row(x: i64, y: i64, name: ptr, memory: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'F', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + memory / 100, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + (memory / 10) % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + memory % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'M', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'B', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 16 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 16 + nlen, y, 'I', fg, bg);
        uc_set(x + 17 + nlen, y, 'n', fg, bg);
        uc_set(x + 18 + nlen, y, 'a', fg, bg);
        uc_set(x + 19 + nlen, y, 'c', fg, bg);
        uc_set(x + 20 + nlen, y, 't', fg, bg);
        uc_set(x + 21 + nlen, y, 'i', fg, bg);
        uc_set(x + 22 + nlen, y, 'v', fg, bg);
        uc_set(x + 23 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.547 消息队列消费者行 ============

# uc_consumer_row：绘制消息队列消费者行 [C]  order-consumer  Running  3 pods
# name 为消费者名，pods 为实例数，state 0=停止 1=运行。
# 用于消息队列消费者组。
fn uc_consumer_row(x: i64, y: i64, name: ptr, pods: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + pods, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.548 事件源行 ============

# uc_event_source_row：绘制事件源行 [S]  db-cdc  PostgreSQL  Active
# name 为事件源名，type 为类型，state 0=停用 1=启用。
# 用于事件源管理。
fn uc_event_source_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.549 流处理作业行 ============

# uc_stream_job_row：绘制流处理作业行 [J]  click-stream  Running  1200 events/s
# name 为作业名，rate 为处理速率，state 0=停止 1=运行。
# 用于流处理作业管理。
fn uc_stream_job_row(x: i64, y: i64, name: ptr, rate: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'J', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + rate / 1000, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + (rate / 100) % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, '0' + (rate / 10) % 10, UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, '0' + rate % 10, UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 29 + nlen, y, '/', UC_CYAN, bg);
    uc_set(x + 30 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.550 数据管道行 ============

# uc_pipeline_row2：绘制数据管道行 [P]  etl-daily  Scheduled  Active
# name 为管道名，schedule 为调度，state 0=停用 1=启用。
# 用于数据管道管理。
fn uc_pipeline_row2(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.551 模型版本行 ============

# uc_model_version_row：绘制模型版本行 [V]  v1.2.3  Production
# version 为版本号，state 0=暂存 1=生产。
# 用于 ML 模型版本管理。
fn uc_model_version_row(x: i64, y: i64, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let vlen: i64 = 0;
    let i: i64 = 0;
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 6 + i, y, version[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + vlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + vlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 11 + vlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 12 + vlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 13 + vlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 14 + vlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 15 + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 17 + vlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 18 + vlen, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + vlen, y, 'S', UC_CYAN, bg);
        uc_set(x + 10 + vlen, y, 't', UC_CYAN, bg);
        uc_set(x + 11 + vlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 12 + vlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 13 + vlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + vlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + vlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.552 训练作业行 ============

# uc_training_job_row：绘制训练作业行 [J]  fine-tune-1  Running  3 epochs
# name 为作业名，epochs 为轮数，state 0=停止 1=运行。
# 用于 ML 训练作业管理。
fn uc_training_job_row(x: i64, y: i64, name: ptr, epochs: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'J', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + epochs, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'h', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.553 评估行 ============

# uc_eval_row：绘制评估行 [E]  accuracy  0.94  Good
# name 为指标名，value 为数值，state 0=差 1=好。
# 用于模型评估指标展示。
fn uc_eval_row(x: i64, y: i64, name: ptr, value: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + value / 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + value % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + nlen, y, 'B', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.554 部署端点行 ============

# uc_deploy_endpoint_row：绘制部署端点行 [E]  prod-endpoint  Active
# name 为端点名，state 0=停止 1=运行。
# 用于模型部署端点管理。
fn uc_deploy_endpoint_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'E', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.555 实验行 ============

# uc_experiment_row：绘制实验行 [X]  lr-0.01  Completed  best
# name 为实验名，state 0=运行 1=完成。
# 用于 ML 实验跟踪。
fn uc_experiment_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'X', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.556 特征存储行 ============

# uc_feature_store_row：绘制特征存储行 [F]  user_features  1024 dims  Active
# name 为特征组名，dims 为维度数，state 0=停用 1=启用。
# 用于特征存储管理。
fn uc_feature_store_row(x: i64, y: i64, name: ptr, dims: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'F', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + dims / 1000, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + (dims / 100) % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + (dims / 10) % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + dims % 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'm', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', fg, bg);
        uc_set(x + 21 + nlen, y, 'n', fg, bg);
        uc_set(x + 22 + nlen, y, 'a', fg, bg);
        uc_set(x + 23 + nlen, y, 'c', fg, bg);
        uc_set(x + 24 + nlen, y, 't', fg, bg);
        uc_set(x + 25 + nlen, y, 'i', fg, bg);
        uc_set(x + 26 + nlen, y, 'v', fg, bg);
        uc_set(x + 27 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.557 数据标注作业行 ============

# uc_label_job_row：绘制数据标注作业行 [J]  image-class  In Progress  120/500
# name 为作业名，done 为已完成，total 为总数。
# 用于数据标注作业。
fn uc_label_job_row(x: i64, y: i64, name: ptr, done: i64, total: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'J', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, 'I', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'P', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    uc_set(x + 22 + nlen, y, '0' + done / 100, UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, '0' + (done / 10) % 10, UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, '0' + done % 10, UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, '/', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, '0' + total / 100, UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, '0' + (total / 10) % 10, UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, '0' + total % 10, UC_CYAN, bg);
    return 0;
}

# ============ v1.558 数据质量检查行 ============

# uc_quality_check_row：绘制数据质量检查行 [Q]  null-rate  2.1%  Pass
# name 为检查名，value 为数值，state 0=失败 1=通过。
# 用于数据质量监控。
fn uc_quality_check_row(x: i64, y: i64, name: ptr, value: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'Q', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + value / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + value % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '%', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'l', UC_RED, bg);
    }
    return 0;
}

# ============ v1.559 模型监控行 ============

# uc_model_monitor_row：绘制模型监控行 [M]  drift  Normal  0.02
# metric 为监控指标，state 0=异常 1=正常，value 为数值。
# 用于模型监控告警。
fn uc_model_monitor_row(x: i64, y: i64, metric: ptr, state: i64, value: i64, fg: i64, bg: i64) -> i64 {
    let mlen: i64 = 0;
    let i: i64 = 0;
    mlen = strlen(metric);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'M', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 6 + i, y, metric[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + mlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 10 + mlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + mlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 12 + mlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 13 + mlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + mlen, y, 'l', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + mlen, y, 'D', UC_RED, bg);
        uc_set(x + 10 + mlen, y, 'r', UC_RED, bg);
        uc_set(x + 11 + mlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + mlen, y, 'f', UC_RED, bg);
        uc_set(x + 13 + mlen, y, 't', UC_RED, bg);
        uc_set(x + 14 + mlen, y, 'E', UC_RED, bg);
        uc_set(x + 15 + mlen, y, 'D', UC_RED, bg);
    }
    uc_set(x + 17 + mlen, y, ' ', fg, bg);
    uc_set(x + 18 + mlen, y, '0', UC_CYAN, bg);
    uc_set(x + 19 + mlen, y, '.', UC_CYAN, bg);
    uc_set(x + 20 + mlen, y, '0' + value / 10, UC_CYAN, bg);
    uc_set(x + 21 + mlen, y, '0' + value % 10, UC_CYAN, bg);
    return 0;
}

# ============ v1.560 推理批次行 ============

# uc_inference_batch_row：绘制推理批次行 [B]  batch-42  Completed  1000 items
# name 为批次名，items 为数量，state 0=运行 1=完成。
# 用于推理批次管理。
fn uc_inference_batch_row(x: i64, y: i64, name: ptr, items: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'B', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    uc_set(x + 20 + nlen, y, '0' + items / 1000, UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, '0' + (items / 100) % 10, UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, '0' + (items / 10) % 10, UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, '0' + items % 10, UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 'm', UC_CYAN, bg);
    uc_set(x + 29 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.561 设备组行 ============

# uc_device_group_row：绘制设备组行 [G]  floor-1  Active  24 devices
# name 为组名，devices 为设备数，state 0=停用 1=启用。
# 用于 IoT 设备组管理。
fn uc_device_group_row(x: i64, y: i64, name: ptr, devices: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'G', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'I', fg, bg);
        uc_set(x + 10 + nlen, y, 'n', fg, bg);
        uc_set(x + 11 + nlen, y, 'a', fg, bg);
        uc_set(x + 12 + nlen, y, 'c', fg, bg);
        uc_set(x + 13 + nlen, y, 't', fg, bg);
        uc_set(x + 14 + nlen, y, 'i', fg, bg);
        uc_set(x + 15 + nlen, y, 'v', fg, bg);
        uc_set(x + 16 + nlen, y, 'e', fg, bg);
    }
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    uc_set(x + 19 + nlen, y, '0' + devices / 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, '0' + devices % 10, UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.562 设备遥测行 ============

# uc_telemetry_row：绘制设备遥测行 [T]  temp-01  23.5 C  Normal
# name 为遥测名，value 为数值，state 0=异常 1=正常。
# 用于设备遥测数据展示。
fn uc_telemetry_row(x: i64, y: i64, name: ptr, value: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + value / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + value % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'C', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 16 + nlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'l', UC_GREEN, bg);
    } else {
        uc_set(x + 16 + nlen, y, 'W', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'g', UC_RED, bg);
    }
    return 0;
}

# ============ v1.563 固件版本行 ============

# uc_firmware_row：绘制固件版本行 [F]  v2.3.1  Stable
# version 为版本号，state 0=测试 1=稳定。
# 用于设备固件版本管理。
fn uc_firmware_row(x: i64, y: i64, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let vlen: i64 = 0;
    let i: i64 = 0;
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'F', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 6 + i, y, version[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + vlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 10 + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 11 + vlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + vlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 13 + vlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + vlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + vlen, y, 'B', UC_CYAN, bg);
        uc_set(x + 10 + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 11 + vlen, y, 't', UC_CYAN, bg);
        uc_set(x + 12 + vlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 13 + vlen, y, 'B', UC_CYAN, bg);
        uc_set(x + 14 + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 15 + vlen, y, 't', UC_CYAN, bg);
        uc_set(x + 16 + vlen, y, 'a', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.564 网关行 ============

# uc_gateway_row：绘制网关行 [G]  gw-main  Connected  12 devices
# name 为网关名，devices 为设备数，state 0=断开 1=连接。
# 用于网关管理。
fn uc_gateway_row(x: i64, y: i64, name: ptr, devices: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'G', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    uc_set(x + 23 + nlen, y, '0' + devices / 10, UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, '0' + devices % 10, UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 29 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 30 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 31 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 32 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.565 传感器状态行 ============

# uc_sensor_status_row：绘制传感器状态行 [S]  temp-01  Active  23.5 C
# name 为传感器名，value 为数值，state 0=停用 1=启用。
# 用于传感器管理。
fn uc_sensor_status_row(x: i64, y: i64, name: ptr, value: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'O', fg, bg);
        uc_set(x + 10 + nlen, y, 'f', fg, bg);
        uc_set(x + 11 + nlen, y, 'f', fg, bg);
    }
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    uc_set(x + 14 + nlen, y, '0' + value / 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, '0' + value % 10, UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'C', UC_CYAN, bg);
    return 0;
}

# ============ v1.566 告警规则行 ============

# uc_alert_rule_row2：绘制告警规则行 [A]  high-cpu  >80%  5m  Firing
# name 为规则名，condition 为条件，state 0=正常 1=触发。
# 用于告警规则管理。
fn uc_alert_rule_row2(x: i64, y: i64, name: ptr, condition: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(condition);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'A', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, condition[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'F', UC_RED, bg);
        uc_set(x + 13 + nlen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + clen, y, 'r', UC_RED, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 16 + nlen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 17 + nlen + clen, y, 'g', UC_RED, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'K', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.567 通知渠道行 ============

# uc_notify_channel_row：绘制通知渠道行 [C]  slack-alerts  Slack  Enabled
# name 为渠道名，type 为类型，state 0=禁用 1=启用。
# 用于通知渠道管理。
fn uc_notify_channel_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.568 仪表盘小部件行 ============

# uc_widget_row：绘制仪表盘小部件行 [W]  cpu-chart  Line  Active
# name 为部件名，type 为类型，state 0=停用 1=启用。
# 用于仪表盘小部件管理。
fn uc_widget_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'W', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.569 图表配置行 ============

# uc_chart_row：绘制图表配置行 [C]  cpu-usage  Area  Refresh 30s
# name 为图表名，type 为类型，interval 为刷新间隔。
# 用于监控图表配置。
fn uc_chart_row(x: i64, y: i64, name: ptr, type: ptr, interval: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 12 + nlen + tlen + i, y, interval[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.570 报表行 ============

# uc_report_row：绘制报表行 [R]  monthly-sales  Generated  2024-01
# name 为报表名，period 为周期，state 0=生成中 1=已生成。
# 用于报表管理。
fn uc_report_row(x: i64, y: i64, name: ptr, period: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(period);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, period[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'G', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'a', UC_GREEN, bg);
        uc_set(x + 18 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + plen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'G', UC_CYAN, bg);
        uc_set(x + 13 + nlen + plen, y, 'e', UC_CYAN, bg);
        uc_set(x + 14 + nlen + plen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen + plen, y, 'e', UC_CYAN, bg);
        uc_set(x + 16 + nlen + plen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + nlen + plen, y, 'a', UC_CYAN, bg);
        uc_set(x + 18 + nlen + plen, y, 't', UC_CYAN, bg);
        uc_set(x + 19 + nlen + plen, y, 'i', UC_CYAN, bg);
        uc_set(x + 20 + nlen + plen, y, 'n', UC_CYAN, bg);
        uc_set(x + 21 + nlen + plen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.571 API 密钥行 ============

# uc_api_key_row：绘制 API 密钥行 [K]  prod-key  Active  expires 2025-01
# name 为密钥名，state 0=已吊销 1=启用，expiry 为过期时间。
# 用于 API 密钥管理。
fn uc_api_key_row(x: i64, y: i64, name: ptr, state: i64, expiry: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(expiry);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'K', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'k', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 'x', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_CYAN, bg);
    i = 0;
    while i < elen {
        uc_set(x + 23 + nlen + i, y, expiry[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.572 OAuth 客户端行 ============

# uc_oauth_client_row：绘制 OAuth 客户端行 [O]  web-app  Confidential  Active
# name 为客户端名，state 0=停用 1=启用。
# 用于 OAuth 客户端管理。
fn uc_oauth_client_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'O', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.573 角色行 ============

# uc_role_row：绘制角色行 [R]  admin  Full access  Built-in
# name 为角色名，desc 为描述，state 0=自定义 1=内置。
# 用于角色管理。
fn uc_role_row(x: i64, y: i64, name: ptr, desc: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(desc);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'R', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, desc[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'B', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 18 + nlen + dlen, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'C', UC_CYAN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 14 + nlen + dlen, y, 's', UC_CYAN, bg);
        uc_set(x + 15 + nlen + dlen, y, 't', UC_CYAN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'm', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.574 权限行 ============

# uc_permission_row：绘制权限行 [P]  orders.read  READ  Granted
# name 为权限名，action 为操作，state 0=拒绝 1=允许。
# 用于权限管理。
fn uc_permission_row(x: i64, y: i64, name: ptr, action: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(action);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'P', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + nlen + i, y, action[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + alen, y, 'G', UC_GREEN, bg);
        uc_set(x + 13 + nlen + alen, y, 'r', UC_GREEN, bg);
        uc_set(x + 14 + nlen + alen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + alen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + alen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + alen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + alen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + alen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + alen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + alen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen + alen, y, 'i', UC_RED, bg);
        uc_set(x + 16 + nlen + alen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + alen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.575 策略行 ============

# uc_policy_row：绘制策略行 [P]  require-mfa  Security  Enforced
# name 为策略名，category 为类别，state 0=草稿 1=已生效。
# 用于策略管理。
fn uc_policy_row(x: i64, y: i64, name: ptr, category: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(category);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, category[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 'f', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + clen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + clen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'D', UC_CYAN, bg);
        uc_set(x + 13 + nlen + clen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', UC_CYAN, bg);
        uc_set(x + 15 + nlen + clen, y, 'f', UC_CYAN, bg);
        uc_set(x + 16 + nlen + clen, y, 't', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.576 审计日志行 ============

# uc_audit_log_row：绘制审计日志行 [L]  2024-01-01  user.login  admin  SUCCESS
# time 为时间，action 为动作，user 为操作用户，state 0=失败 1=成功。
# 用于审计日志展示。
fn uc_audit_log_row(x: i64, y: i64, time: ptr, action: ptr, user: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let alen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(time);
    alen = strlen(action);
    ulen = strlen(user);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'L', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, time[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + tlen + i, y, action[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 11 + tlen + alen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 12 + tlen + alen + i, y, user[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 14 + tlen + alen + ulen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + tlen + alen + ulen, y, 'S', UC_GREEN, bg);
        uc_set(x + 16 + tlen + alen + ulen, y, 'U', UC_GREEN, bg);
        uc_set(x + 17 + tlen + alen + ulen, y, 'C', UC_GREEN, bg);
        uc_set(x + 18 + tlen + alen + ulen, y, 'C', UC_GREEN, bg);
        uc_set(x + 19 + tlen + alen + ulen, y, 'E', UC_GREEN, bg);
        uc_set(x + 20 + tlen + alen + ulen, y, 'S', UC_GREEN, bg);
        uc_set(x + 21 + tlen + alen + ulen, y, 'S', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + tlen + alen + ulen, y, 'F', UC_RED, bg);
        uc_set(x + 16 + tlen + alen + ulen, y, 'A', UC_RED, bg);
        uc_set(x + 17 + tlen + alen + ulen, y, 'I', UC_RED, bg);
        uc_set(x + 18 + tlen + alen + ulen, y, 'L', UC_RED, bg);
        uc_set(x + 19 + tlen + alen + ulen, y, 'E', UC_RED, bg);
        uc_set(x + 20 + tlen + alen + ulen, y, 'D', UC_RED, bg);
    }
    return 0;
}

# ============ v1.577 登录会话行 ============

# uc_login_session_row：绘制登录会话行 [S]  web-01  192.168.1.5  Active
# name 为会话名，ip 为来源 IP，state 0=已过期 1=活跃。
# 用于登录会话管理。
fn uc_login_session_row(x: i64, y: i64, name: ptr, ip: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(ip);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 9 + nlen + i, y, ip[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ilen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + ilen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + ilen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + ilen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + ilen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + ilen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + ilen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + ilen, y, 'E', fg, bg);
        uc_set(x + 13 + nlen + ilen, y, 'x', fg, bg);
        uc_set(x + 14 + nlen + ilen, y, 'p', fg, bg);
        uc_set(x + 15 + nlen + ilen, y, 'i', fg, bg);
        uc_set(x + 16 + nlen + ilen, y, 'r', fg, bg);
        uc_set(x + 17 + nlen + ilen, y, 'e', fg, bg);
        uc_set(x + 18 + nlen + ilen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.578 SSO 提供方行 ============

# uc_sso_row：绘制 SSO 提供方行 [S]  okta  SAML  Connected
# name 为提供方名，protocol 为协议，state 0=未连接 1=已连接。
# 用于 SSO 提供方管理。
fn uc_sso_row(x: i64, y: i64, name: ptr, protocol: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(protocol);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, protocol[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + plen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'N', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'o', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 't', fg, bg);
        uc_set(x + 15 + nlen + plen, y, ' ', fg, bg);
        uc_set(x + 16 + nlen + plen, y, 'C', fg, bg);
        uc_set(x + 17 + nlen + plen, y, 'o', fg, bg);
        uc_set(x + 18 + nlen + plen, y, 'n', fg, bg);
        uc_set(x + 19 + nlen + plen, y, 'n', fg, bg);
        uc_set(x + 20 + nlen + plen, y, 'e', fg, bg);
        uc_set(x + 21 + nlen + plen, y, 'c', fg, bg);
        uc_set(x + 22 + nlen + plen, y, 't', fg, bg);
        uc_set(x + 23 + nlen + plen, y, 'e', fg, bg);
        uc_set(x + 24 + nlen + plen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.579 MFA 设备行 ============

# uc_mfa_row：绘制 MFA 设备行 [M]  authenticator  Mobile  Active
# name 为设备名，type 为类型，state 0=停用 1=启用。
# 用于 MFA 设备管理。
fn uc_mfa_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 'b', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'l', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'e', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.580 密码策略行 ============

# uc_password_policy_row：绘制密码策略行 [P]  default  Min 12 chars  Enforced
# name 为策略名，rule 为规则，state 0=草稿 1=已生效。
# 用于密码策略管理。
fn uc_password_policy_row(x: i64, y: i64, name: ptr, rule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(rule);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, rule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + rlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + rlen, y, 'f', UC_GREEN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen + rlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + rlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + rlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + rlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + rlen, y, 'D', UC_CYAN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + rlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'f', UC_CYAN, bg);
        uc_set(x + 16 + nlen + rlen, y, 't', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.581 Terraform 工作区行 ============

# uc_terraform_row：绘制 Terraform 工作区行 [T]  prod-infra  Planned  Active
# name 为工作区名，state 0=停用 1=启用。
# 用于 Terraform 工作区管理。
fn uc_terraform_row(x: i64, y: i64, name: ptr, plan: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(plan);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'T', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, plan[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + plen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + plen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + plen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + plen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + plen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.582 环境变量行 ============

# uc_env_var_row：绘制环境变量行 [V]  DATABASE_URL  postgres://...  Set
# name 为变量名，state 0=未设置 1=已设置。
# 用于环境变量管理。
fn uc_env_var_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'V', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'U', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 't', UC_RED, bg);
    }
    return 0;
}

# ============ v1.583 构建配置行 ============

# uc_build_config_row：绘制构建配置行 [C]  web-build  Dockerfile  Active
# name 为配置名，file 为文件，state 0=停用 1=启用。
# 用于构建配置管理。
fn uc_build_config_row(x: i64, y: i64, name: ptr, file: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    flen = strlen(file);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + nlen + i, y, file[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + flen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + flen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + flen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + flen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + flen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + flen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + flen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + flen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + flen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + flen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + flen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + flen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + flen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + flen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + flen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.584 部署阶段行 ============

# uc_deploy_stage_row：绘制部署阶段行 [D]  staging  Approved  Waiting
# name 为阶段名，state 0=进行中 1=已批准。
# 用于部署流水线阶段。
fn uc_deploy_stage_row(x: i64, y: i64, name: ptr, approved: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(approved);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + nlen + i, y, approved[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + alen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + alen, y, 'p', UC_GREEN, bg);
        uc_set(x + 14 + nlen + alen, y, 'p', UC_GREEN, bg);
        uc_set(x + 15 + nlen + alen, y, 'r', UC_GREEN, bg);
        uc_set(x + 16 + nlen + alen, y, 'o', UC_GREEN, bg);
        uc_set(x + 17 + nlen + alen, y, 'v', UC_GREEN, bg);
        uc_set(x + 18 + nlen + alen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + alen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + alen, y, 'W', UC_CYAN, bg);
        uc_set(x + 13 + nlen + alen, y, 'a', UC_CYAN, bg);
        uc_set(x + 14 + nlen + alen, y, 'i', UC_CYAN, bg);
        uc_set(x + 15 + nlen + alen, y, 't', UC_CYAN, bg);
        uc_set(x + 16 + nlen + alen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + alen, y, 'n', UC_CYAN, bg);
        uc_set(x + 18 + nlen + alen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.585 回滚行 ============

# uc_rollback_row：绘制回滚行 [B]  20240101-1200  web-01  Completed
# time 为时间点，target 为目标，state 0=进行中 1=已完成。
# 用于部署回滚管理。
fn uc_rollback_row(x: i64, y: i64, time: ptr, target: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let glen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(time);
    glen = strlen(target);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'B', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 6 + i, y, time[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 8 + tlen, y, ' ', fg, bg);
    i = 0;
    while i < glen {
        uc_set(x + 9 + tlen + i, y, target[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + tlen + glen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + tlen + glen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + tlen + glen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + tlen + glen, y, 'm', UC_GREEN, bg);
        uc_set(x + 15 + tlen + glen, y, 'p', UC_GREEN, bg);
        uc_set(x + 16 + tlen + glen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + tlen + glen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + tlen + glen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + tlen + glen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + tlen + glen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + tlen + glen, y, 'I', UC_CYAN, bg);
        uc_set(x + 13 + tlen + glen, y, 'n', UC_CYAN, bg);
        uc_set(x + 14 + tlen + glen, y, ' ', UC_CYAN, bg);
        uc_set(x + 15 + tlen + glen, y, 'P', UC_CYAN, bg);
        uc_set(x + 16 + tlen + glen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + tlen + glen, y, 'o', UC_CYAN, bg);
        uc_set(x + 18 + tlen + glen, y, 'g', UC_CYAN, bg);
        uc_set(x + 19 + tlen + glen, y, 'r', UC_CYAN, bg);
        uc_set(x + 20 + tlen + glen, y, 'e', UC_CYAN, bg);
        uc_set(x + 21 + tlen + glen, y, 's', UC_CYAN, bg);
        uc_set(x + 22 + tlen + glen, y, 's', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.586 Git 仓库行 ============

# uc_git_repo_row：绘制 Git 仓库行 [G]  mo-lang  Public  42 branches
# name 为仓库名，state 0=私有 1=公开，branches 为分支数。
# 用于 Git 仓库管理。
fn uc_git_repo_row(x: i64, y: i64, name: ptr, state: i64, branches: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'G', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'P', UC_YELLOW, bg);
        uc_set(x + 10 + nlen, y, 'r', UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, 'v', UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, 'a', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 't', UC_YELLOW, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_YELLOW, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + branches / 10, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + branches % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'b', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 'h', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.587 PR 行 ============

# uc_pr_row：绘制 PR 行 [P]  #42  add-login  open  2 files
# number 为编号，title 为标题，state 0=已关闭 1=开启。
# 用于 Pull Request 管理。
fn uc_pr_row(x: i64, y: i64, number: i64, title: ptr, state: i64, files: i64, fg: i64, bg: i64) -> i64 {
    let tlen: i64 = 0;
    let i: i64 = 0;
    tlen = strlen(title);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, '#', UC_YELLOW, bg);
    uc_set(x + 6, y, '0' + number / 10, UC_YELLOW, bg);
    uc_set(x + 7, y, '0' + number % 10, UC_YELLOW, bg);
    uc_set(x + 9, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 10 + i, y, title[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 12 + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 13 + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + tlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 15 + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + tlen, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + 13 + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 14 + tlen, y, 'l', UC_RED, bg);
        uc_set(x + 15 + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 16 + tlen, y, 's', UC_RED, bg);
        uc_set(x + 17 + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + tlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 20 + tlen, y, ' ', fg, bg);
    uc_set(x + 21 + tlen, y, '0' + files, UC_CYAN, bg);
    uc_set(x + 22 + tlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 23 + tlen, y, 'f', UC_CYAN, bg);
    uc_set(x + 24 + tlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 25 + tlen, y, 'l', UC_CYAN, bg);
    uc_set(x + 26 + tlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 27 + tlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.588 分支详情行 ============

# uc_branch_detail_row：绘制分支详情行 [B]  feature/login  protected  ahead 2
# name 为分支名，state 0=普通 1=受保护，ahead 为领先提交数。
# 用于 Git 分支管理。
fn uc_branch_detail_row(x: i64, y: i64, name: ptr, state: i64, ahead: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'B', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    uc_set(x + 20 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'h', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, '0' + ahead, UC_CYAN, bg);
    return 0;
}

# ============ v1.589 代码扫描行 ============

# uc_code_scan_row：绘制代码扫描行 [S]  gosec  3 critical  12 issues
# name 为扫描器名，critical 为严重数，issues 为问题数。
# 用于代码扫描结果展示。
fn uc_code_scan_row(x: i64, y: i64, name: ptr, critical: i64, issues: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + critical, UC_RED, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_RED, bg);
    uc_set(x + 11 + nlen, y, 'c', UC_RED, bg);
    uc_set(x + 12 + nlen, y, 'r', UC_RED, bg);
    uc_set(x + 13 + nlen, y, 'i', UC_RED, bg);
    uc_set(x + 14 + nlen, y, 't', UC_RED, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_RED, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_RED, bg);
    uc_set(x + 17 + nlen, y, 'a', UC_RED, bg);
    uc_set(x + 18 + nlen, y, 'l', UC_RED, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    uc_set(x + 21 + nlen, y, '0' + issues / 10, UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, '0' + issues % 10, UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'u', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 29 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.590 依赖漏洞行 ============

# uc_vuln_row：绘制依赖漏洞行 [V]  lodash  4.17.20  high  patched
# name 为包名，version 为版本，state 0=高危 1=已修复。
# 用于依赖漏洞管理。
fn uc_vuln_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'V', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'H', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 'I', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'G', UC_RED, bg);
        uc_set(x + 15 + nlen + vlen, y, 'H', UC_RED, bg);
    }
    return 0;
}

# ============ v1.591 数据源连接行 ============

# uc_datasource_conn_row：绘制数据源连接行 [C]  prod-mysql  MySQL  Connected
# name 为连接名，type 为类型，state 0=断开 1=连接。
# 用于数据源连接管理。
fn uc_datasource_conn_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 't', UC_RED, bg);
        uc_set(x + 22 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 23 + nlen + tlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.592 数据模型字段行 ============

# uc_model_field_row：绘制数据模型字段行 [F]  user_id  BIGINT  NOT NULL
# name 为字段名，type 为类型，state 0=可空 1=非空。
# 用于数据模型字段展示。
fn uc_model_field_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'F', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'T', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'U', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'L', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'L', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'N', UC_CYAN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'U', UC_CYAN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'L', UC_CYAN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'L', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.593 数据血缘行 ============

# uc_lineage_row：绘制数据血缘行 [L]  orders  →  dim_users  Active
# source 为源表，target 为目标表，state 0=已停用 1=已启用。
# 用于数据血缘展示。
fn uc_lineage_row(x: i64, y: i64, source: ptr, target: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let slen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    slen = strlen(source);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'L', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 6 + i, y, source[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + slen, y, ' ', fg, bg);
    uc_set(x + 9 + slen, y, '-', UC_CYAN, bg);
    uc_set(x + 10 + slen, y, '>', UC_CYAN, bg);
    uc_set(x + 12 + slen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 13 + slen + i, y, target[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 15 + slen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 16 + slen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 17 + slen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + slen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + slen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 20 + slen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 21 + slen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 16 + slen + tlen, y, 'I', fg, bg);
        uc_set(x + 17 + slen + tlen, y, 'n', fg, bg);
        uc_set(x + 18 + slen + tlen, y, 'a', fg, bg);
        uc_set(x + 19 + slen + tlen, y, 'c', fg, bg);
        uc_set(x + 20 + slen + tlen, y, 't', fg, bg);
        uc_set(x + 21 + slen + tlen, y, 'i', fg, bg);
        uc_set(x + 22 + slen + tlen, y, 'v', fg, bg);
        uc_set(x + 23 + slen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.594 数据质量规则行 ============

# uc_quality_rule_row：绘制数据质量规则行 [R]  not-null  users.email  Active
# name 为规则名，table 为目标表，state 0=停用 1=启用。
# 用于数据质量规则管理。
fn uc_quality_rule_row(x: i64, y: i64, name: ptr, table: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(table);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, table[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.595 数据掩码行 ============

# uc_data_mask_row：绘制数据掩码行 [M]  email  regex  Active
# name 为掩码名，method 为方式，state 0=停用 1=启用。
# 用于数据脱敏管理。
fn uc_data_mask_row(x: i64, y: i64, name: ptr, method: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(method);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, method[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + mlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + mlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + mlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + mlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + mlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.596 数据湖表行 ============

# uc_lake_table_row：绘制数据湖表行 [T]  raw_orders  Parquet  10GB
# name 为表名，format 为格式，size 为大小。
# 用于数据湖表展示。
fn uc_lake_table_row(x: i64, y: i64, name: ptr, format: ptr, size: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    flen = strlen(format);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + nlen + i, y, format[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + flen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + flen, y, '0' + size / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + flen, y, '0' + size % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + flen, y, 'G', UC_CYAN, bg);
    uc_set(x + 15 + nlen + flen, y, 'B', UC_CYAN, bg);
    return 0;
}

# ============ v1.597 数据目录行 ============

# uc_catalog_row：绘制数据目录行 [C]  sales  /data/sales  Active
# name 为目录名，path 为路径，state 0=停用 1=启用。
# 用于数据目录管理。
fn uc_catalog_row(x: i64, y: i64, name: ptr, path: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(path);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, path[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + plen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + plen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + plen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + plen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + plen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.598 指标定义行 ============

# uc_metric_row：绘制指标定义行 [M]  revenue  SUM(amount)  Active
# name 为指标名，expr 为表达式，state 0=停用 1=启用。
# 用于指标定义管理。
fn uc_metric_row(x: i64, y: i64, name: ptr, expr: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(expr);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'M', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + nlen + i, y, expr[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + elen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + elen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + elen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + elen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + elen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + elen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + elen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + elen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + elen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + elen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + elen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + elen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + elen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + elen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + elen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.599 仪表盘行 ============

# uc_dashboard_row：绘制仪表盘行 [D]  ops-overview  8 widgets  Published
# name 为仪表盘名，widgets 为部件数，state 0=草稿 1=已发布。
# 用于仪表盘管理。
fn uc_dashboard_row(x: i64, y: i64, name: ptr, widgets: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'D', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + widgets, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'w', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'D', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'f', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 't', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.600 图表序列行 ============

# uc_series_row：绘制图表序列行 [S]  cpu-0  host-01  Line  Active
# name 为序列名，source 为数据源，state 0=停用 1=启用。
# 用于图表序列管理。
fn uc_series_row(x: i64, y: i64, name: ptr, source: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(source);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, source[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 12 + nlen + slen + i, y, type[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + slen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen + slen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 18 + nlen + slen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 19 + nlen + slen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 20 + nlen + slen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + nlen + slen + tlen, y, 'I', fg, bg);
        uc_set(x + 16 + nlen + slen + tlen, y, 'n', fg, bg);
        uc_set(x + 17 + nlen + slen + tlen, y, 'a', fg, bg);
        uc_set(x + 18 + nlen + slen + tlen, y, 'c', fg, bg);
        uc_set(x + 19 + nlen + slen + tlen, y, 't', fg, bg);
        uc_set(x + 20 + nlen + slen + tlen, y, 'i', fg, bg);
        uc_set(x + 21 + nlen + slen + tlen, y, 'v', fg, bg);
        uc_set(x + 22 + nlen + slen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.601 告警抑制行 ============

# uc_alert_inhibit_row：绘制告警抑制行 [I]  inhibit-down  source:target  Active
# name 为抑制名，match 为匹配，state 0=停用 1=启用。
# 用于告警抑制规则。
fn uc_alert_inhibit_row(x: i64, y: i64, name: ptr, match: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(match);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'I', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, match[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + mlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + mlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + mlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + mlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + mlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.602 告警静默行 ============

# uc_alert_silence_row：绘制告警静默行 [S]  maintenance  until 12:00  Active
# name 为静默名，until 为截止时间，state 0=已过期 1=生效中。
# 用于告警静默管理。
fn uc_alert_silence_row(x: i64, y: i64, name: ptr, until: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(until);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 9 + nlen + i, y, until[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ulen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + ulen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + ulen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + ulen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + ulen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + ulen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + ulen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + ulen, y, 'E', fg, bg);
        uc_set(x + 13 + nlen + ulen, y, 'x', fg, bg);
        uc_set(x + 14 + nlen + ulen, y, 'p', fg, bg);
        uc_set(x + 15 + nlen + ulen, y, 'i', fg, bg);
        uc_set(x + 16 + nlen + ulen, y, 'r', fg, bg);
        uc_set(x + 17 + nlen + ulen, y, 'e', fg, bg);
        uc_set(x + 18 + nlen + ulen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.603 路由规则行 ============

# uc_route_rule_row：绘制路由规则行 [R]  /api/v1  weighted  → 2 targets
# path 为路径，strategy 为策略，targets 为目标数。
# 用于网关路由规则。
fn uc_route_rule_row(x: i64, y: i64, path: ptr, strategy: ptr, targets: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(path);
    slen = strlen(strategy);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, path[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + plen + i, y, strategy[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + plen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + plen + slen, y, '-', UC_CYAN, bg);
    uc_set(x + 13 + plen + slen, y, '>', UC_CYAN, bg);
    uc_set(x + 15 + plen + slen, y, ' ', fg, bg);
    uc_set(x + 16 + plen + slen, y, '0' + targets, UC_CYAN, bg);
    uc_set(x + 17 + plen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 18 + plen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 19 + plen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 20 + plen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 21 + plen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 22 + plen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 23 + plen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 24 + plen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.604 扩展行 ============

# uc_extension_row：绘制扩展行 [X]  jaeger-tracing  enabled  v1.2.0
# name 为扩展名，state 0=禁用 1=启用，version 为版本。
# 用于系统扩展管理。
fn uc_extension_row(x: i64, y: i64, name: ptr, state: i64, version: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'X', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', fg, bg);
        uc_set(x + 10 + nlen, y, 'i', fg, bg);
        uc_set(x + 11 + nlen, y, 's', fg, bg);
        uc_set(x + 12 + nlen, y, 'a', fg, bg);
        uc_set(x + 13 + nlen, y, 'b', fg, bg);
        uc_set(x + 14 + nlen, y, 'l', fg, bg);
        uc_set(x + 15 + nlen, y, 'e', fg, bg);
        uc_set(x + 16 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 19 + nlen + i, y, version[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.605 插件状态行 ============

# uc_plugin_status_row：绘制插件状态行 [P]  grafana  installed  v10.2.0
# name 为插件名，state 0=未安装 1=已安装，version 为版本。
# 用于插件管理。
fn uc_plugin_status_row(x: i64, y: i64, name: ptr, state: i64, version: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'P', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'I', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'N', fg, bg);
        uc_set(x + 10 + nlen, y, 'o', fg, bg);
        uc_set(x + 11 + nlen, y, 't', fg, bg);
        uc_set(x + 12 + nlen, y, ' ', fg, bg);
        uc_set(x + 13 + nlen, y, 'I', fg, bg);
        uc_set(x + 14 + nlen, y, 'n', fg, bg);
        uc_set(x + 15 + nlen, y, 's', fg, bg);
        uc_set(x + 16 + nlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen, y, 'a', fg, bg);
        uc_set(x + 18 + nlen, y, 'l', fg, bg);
        uc_set(x + 19 + nlen, y, 'l', fg, bg);
        uc_set(x + 20 + nlen, y, 'e', fg, bg);
        uc_set(x + 21 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 23 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 24 + nlen + i, y, version[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.606 服务账户行 ============

# uc_service_account_row：绘制服务账户行 [A]  deploy-bot  ClusterRole  Active
# name 为账户名，role 为角色，state 0=停用 1=启用。
# 用于服务账户管理。
fn uc_service_account_row(x: i64, y: i64, name: ptr, role: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(role);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, role[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + rlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + rlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + rlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + rlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + rlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + rlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + rlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + rlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + rlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + rlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + rlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + rlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.607 RBAC 绑定行 ============

# uc_rbac_row：绘制 RBAC 绑定行 [B]  dev-team  editor  namespace-dev
# name 为绑定名，role 为角色，scope 为范围。
# 用于 RBAC 绑定管理。
fn uc_rbac_row(x: i64, y: i64, name: ptr, role: ptr, scope: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(scope);
    rlen = strlen(role);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'B', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, role[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + rlen + i, y, scope[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.608 配额限流行 ============

# uc_quota_limit_row：绘制配额限流行 [L]  api-quota  1000 req/min  Active
# name 为限流名，limit 为限额，state 0=停用 1=启用。
# 用于配额限流管理。
fn uc_quota_limit_row(x: i64, y: i64, name: ptr, limit: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(limit);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'L', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 9 + nlen + i, y, limit[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + llen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + llen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + llen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + llen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + llen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + llen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + llen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + llen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + llen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + llen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + llen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + llen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + llen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + llen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.609 缓存键行 ============

# uc_cache_key_row：绘制缓存键行 [K]  user:42  hit  12 times  Active
# key 为缓存键，hits 为命中数，state 0=已过期 1=活跃。
# 用于缓存键管理。
fn uc_cache_key_row(x: i64, y: i64, key: ptr, hits: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let klen: i64 = 0;
    let i: i64 = 0;
    klen = strlen(key);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'K', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 6 + i, y, key[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + klen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + klen, y, 'H', UC_GREEN, bg);
        uc_set(x + 10 + klen, y, 'i', UC_GREEN, bg);
        uc_set(x + 11 + klen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + klen, y, ' ', UC_GREEN, bg);
        uc_set(x + 13 + klen, y, '0' + hits / 10, UC_CYAN, bg);
        uc_set(x + 14 + klen, y, '0' + hits % 10, UC_CYAN, bg);
        uc_set(x + 15 + klen, y, ' ', UC_CYAN, bg);
        uc_set(x + 16 + klen, y, 't', UC_CYAN, bg);
        uc_set(x + 17 + klen, y, 'i', UC_CYAN, bg);
        uc_set(x + 18 + klen, y, 'm', UC_CYAN, bg);
        uc_set(x + 19 + klen, y, 'e', UC_CYAN, bg);
        uc_set(x + 20 + klen, y, 's', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + klen, y, 'E', fg, bg);
        uc_set(x + 10 + klen, y, 'x', fg, bg);
        uc_set(x + 11 + klen, y, 'p', fg, bg);
        uc_set(x + 12 + klen, y, 'i', fg, bg);
        uc_set(x + 13 + klen, y, 'r', fg, bg);
        uc_set(x + 14 + klen, y, 'e', fg, bg);
        uc_set(x + 15 + klen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.610 队列深度行 ============

# uc_queue_depth_row：绘制队列深度行 [Q]  order-queue  42  OK
# name 为队列名，depth 为深度，state 0=拥塞 1=正常。
# 用于消息队列深度监控。
fn uc_queue_depth_row(x: i64, y: i64, name: ptr, depth: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'Q', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + depth / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + depth % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 13 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 13 + nlen, y, 'C', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'N', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'G', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'T', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'D', UC_RED, bg);
    }
    return 0;
}

# ============ v1.611 成本分配行 ============

# uc_cost_allocation_row：绘制成本分配行 [A]  dev-team  35%  $1,240.00
# name 为分配对象，percent 为占比，amount 为金额。
# 用于成本分配展示。
fn uc_cost_allocation_row(x: i64, y: i64, name: ptr, percent: i64, amount: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'A', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + percent / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + percent % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    uc_set(x + 14 + nlen, y, '$', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, '0' + amount / 1000, UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, '0' + (amount / 100) % 10, UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, '0' + (amount / 10) % 10, UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, '0' + amount % 10, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '.', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '0' + (amount % 100) / 10, UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, '0' + amount % 10, UC_WHITE, bg);
    return 0;
}

# ============ v1.612 预算行 ============

# uc_budget_row：绘制预算行 [B]  q1-2024  $10,000  used 62%
# name 为预算名，amount 为总额，used 为已用百分比。
# 用于预算管理。
fn uc_budget_row(x: i64, y: i64, name: ptr, amount: i64, used: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'B', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '$', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + amount / 10000, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + (amount / 1000) % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + (amount / 100) % 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, '0' + (amount / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, '0' + amount % 10, UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    uc_set(x + 17 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, '0' + used / 10, UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, '0' + used % 10, UC_WHITE, bg);
    uc_set(x + 24 + nlen, y, '%', UC_WHITE, bg);
    return 0;
}

# ============ v1.613 支出行 ============

# uc_expense_row：绘制支出行 [E]  ec2-01  2024-01-01  $12.50
# name 为资源名，date 为日期，amount 为金额。
# 用于支出明细展示。
fn uc_expense_row(x: i64, y: i64, name: ptr, date: ptr, amount: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(date);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, date[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + dlen, y, '$', UC_WHITE, bg);
    uc_set(x + 13 + nlen + dlen, y, '0' + amount / 10, UC_WHITE, bg);
    uc_set(x + 14 + nlen + dlen, y, '0' + amount % 10, UC_WHITE, bg);
    uc_set(x + 15 + nlen + dlen, y, '.', UC_WHITE, bg);
    uc_set(x + 16 + nlen + dlen, y, '0' + (amount % 100) / 10, UC_WHITE, bg);
    uc_set(x + 17 + nlen + dlen, y, '0' + amount % 10, UC_WHITE, bg);
    return 0;
}

# ============ v1.614 发票行 ============

# uc_invoice_row：绘制发票行 [I]  INV-2024-001  $1,200.00  Paid
# number 为发票号，amount 为金额，state 0=未付 1=已付。
# 用于发票管理。
fn uc_invoice_row(x: i64, y: i64, number: ptr, amount: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(number);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'I', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, number[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '$', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + amount / 1000, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '0' + (amount / 100) % 10, UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + (amount / 10) % 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, '0' + amount % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, '.', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, '0' + (amount % 100) / 10, UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, '0' + amount % 10, UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'U', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.615 账单行 ============

# uc_bill_row：绘制账单行 [B]  2024-01  $500.00  Auto-pay
# period 为账单周期，amount 为金额，state 0=待付 1=已付。
# 用于账单管理。
fn uc_bill_row(x: i64, y: i64, period: ptr, amount: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(period);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'B', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 6 + i, y, period[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + plen, y, ' ', fg, bg);
    uc_set(x + 9 + plen, y, '$', UC_WHITE, bg);
    uc_set(x + 10 + plen, y, '0' + amount / 100, UC_WHITE, bg);
    uc_set(x + 11 + plen, y, '0' + (amount / 10) % 10, UC_WHITE, bg);
    uc_set(x + 12 + plen, y, '0' + amount % 10, UC_WHITE, bg);
    uc_set(x + 13 + plen, y, '.', UC_WHITE, bg);
    uc_set(x + 14 + plen, y, '0' + (amount % 100) / 10, UC_WHITE, bg);
    uc_set(x + 15 + plen, y, '0' + amount % 10, UC_WHITE, bg);
    uc_set(x + 17 + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 19 + plen, y, 'u', UC_GREEN, bg);
        uc_set(x + 20 + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 21 + plen, y, 'o', UC_GREEN, bg);
        uc_set(x + 22 + plen, y, '-', UC_GREEN, bg);
        uc_set(x + 23 + plen, y, 'p', UC_GREEN, bg);
        uc_set(x + 24 + plen, y, 'a', UC_GREEN, bg);
        uc_set(x + 25 + plen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + plen, y, 'P', UC_RED, bg);
        uc_set(x + 19 + plen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + plen, y, 'n', UC_RED, bg);
        uc_set(x + 21 + plen, y, 'd', UC_RED, bg);
        uc_set(x + 22 + plen, y, 'i', UC_RED, bg);
        uc_set(x + 23 + plen, y, 'n', UC_RED, bg);
        uc_set(x + 24 + plen, y, 'g', UC_RED, bg);
    }
    return 0;
}

# ============ v1.616 节省计划行 ============

# uc_savings_plan_row：绘制节省计划行 [S]  compute-1yr  35% saving  Active
# name 为计划名，saving 为节省率，state 0=停用 1=启用。
# 用于节省计划管理。
fn uc_savings_plan_row(x: i64, y: i64, name: ptr, saving: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + saving / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + saving % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'I', fg, bg);
        uc_set(x + 22 + nlen, y, 'n', fg, bg);
        uc_set(x + 23 + nlen, y, 'a', fg, bg);
        uc_set(x + 24 + nlen, y, 'c', fg, bg);
        uc_set(x + 25 + nlen, y, 't', fg, bg);
        uc_set(x + 26 + nlen, y, 'i', fg, bg);
        uc_set(x + 27 + nlen, y, 'v', fg, bg);
        uc_set(x + 28 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.617 成本异常行 ============

# uc_cost_anomaly_row：绘制成本异常行 [A]  ec2-spike  3.2x  High
# name 为异常名，ratio 为倍数，state 0=中 1=高。
# 用于成本异常告警。
fn uc_cost_anomaly_row(x: i64, y: i64, name: ptr, ratio: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'A', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + ratio / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '.', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + ratio % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'x', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen, y, 'H', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'g', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'h', UC_RED, bg);
    } else {
        uc_set(x + 15 + nlen, y, 'M', UC_YELLOW, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_YELLOW, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_YELLOW, bg);
        uc_set(x + 18 + nlen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 19 + nlen, y, 'u', UC_YELLOW, bg);
        uc_set(x + 20 + nlen, y, 'm', UC_YELLOW, bg);
    }
    return 0;
}

# ============ v1.618 定价行 ============

# uc_price_row2：绘制定价行 [P]  standard  per-hour  $0.023
# name 为定价名，unit 为计费单位，price 为价格。
# 用于定价展示。
fn uc_price_row2(x: i64, y: i64, name: ptr, unit: ptr, price: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(unit);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'P', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 9 + nlen + i, y, unit[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ulen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + ulen, y, '$', UC_WHITE, bg);
    uc_set(x + 13 + nlen + ulen, y, '0', UC_WHITE, bg);
    uc_set(x + 14 + nlen + ulen, y, '.', UC_WHITE, bg);
    uc_set(x + 15 + nlen + ulen, y, '0' + price / 100, UC_WHITE, bg);
    uc_set(x + 16 + nlen + ulen, y, '0' + (price / 10) % 10, UC_WHITE, bg);
    uc_set(x + 17 + nlen + ulen, y, '0' + price % 10, UC_WHITE, bg);
    return 0;
}

# ============ v1.619 配额调整行 ============

# uc_quota_adjust_row：绘制配额调整行 [Q]  increase-vcpu  +50  Approved
# name 为调整名，delta 为变化，state 0=待审 1=已批准。
# 用于配额调整请求。
fn uc_quota_adjust_row(x: i64, y: i64, name: ptr, delta: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'Q', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '+', UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + delta / 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + delta % 10, UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 19 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 20 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.620 审批行 ============

# uc_approval_row：绘制审批行 [A]  prod-deploy  pending  ops-team
# name 为审批名，status 为状态，approver 为审批人。
# 用于审批流程展示。
fn uc_approval_row(x: i64, y: i64, name: ptr, status: ptr, approver: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(status);
    alen = strlen(approver);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'A', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, status[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 12 + nlen + slen + i, y, approver[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.621 合规状态行 ============

# uc_compliance_row：绘制合规状态行 [C]  soc2  In Progress  85%
# name 为合规项，state 0=未合规 1=合规中，score 为得分。
# 用于合规状态展示。
fn uc_compliance_row(x: i64, y: i64, name: ptr, state: i64, score: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'N', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 12 + nlen, y, '-', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'm', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 't', UC_RED, bg);
    }
    uc_set(x + 23 + nlen, y, ' ', fg, bg);
    uc_set(x + 24 + nlen, y, '0' + score / 10, UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, '0' + score % 10, UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, '%', UC_CYAN, bg);
    return 0;
}

# ============ v1.622 证书签发行 ============

# uc_cert_issue_row：绘制证书签发行 [I]  api.example.com  Valid  expires 2025-01
# name 为证书名，state 0=已过期 1=有效，expiry 为到期时间。
# 用于证书签发管理。
fn uc_cert_issue_row(x: i64, y: i64, name: ptr, state: i64, expiry: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(expiry);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'I', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'V', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'x', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 'x', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_CYAN, bg);
    i = 0;
    while i < elen {
        uc_set(x + 23 + nlen + i, y, expiry[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.623 密钥轮换行 ============

# uc_key_rotation_row：绘制密钥轮换行 [R]  db-password  90 days  Active
# name 为密钥名，interval 为轮换周期，state 0=停用 1=启用。
# 用于密钥轮换管理。
fn uc_key_rotation_row(x: i64, y: i64, name: ptr, interval: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'R', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 9 + nlen + i, y, interval[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ilen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + ilen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + ilen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + ilen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + ilen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + ilen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + ilen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + ilen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + ilen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + ilen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + ilen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + ilen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + ilen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + ilen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + ilen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.624 漏洞扫描行 ============

# uc_vuln_scan_row：绘制漏洞扫描行 [S]  prod-cluster  2024-01-01  Completed
# name 为扫描名，date 为日期，state 0=进行中 1=已完成。
# 用于漏洞扫描任务。
fn uc_vuln_scan_row(x: i64, y: i64, name: ptr, date: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(date);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, date[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + dlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 14 + nlen + dlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 18 + nlen + dlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 19 + nlen + dlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 20 + nlen + dlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 21 + nlen + dlen, y, 's', UC_CYAN, bg);
        uc_set(x + 22 + nlen + dlen, y, 's', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.625 安全报告行 ============

# uc_security_report_row：绘制安全报告行 [R]  Q1-2024  Generated  24 findings
# name 为报告名，findings 为发现数，state 0=生成中 1=已生成。
# 用于安全报告管理。
fn uc_security_report_row(x: i64, y: i64, name: ptr, findings: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + findings / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + findings % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'f', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 22 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 29 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 30 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 22 + nlen, y, 'G', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 28 + nlen, y, 't', UC_CYAN, bg);
        uc_set(x + 29 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 30 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 31 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.626 安全扫描行 ============

# uc_security_scan_row：绘制安全扫描行 [S]  trivy  image  Clean
# name 为扫描名，target 为目标，state 0=有风险 1=干净。
# 用于安全扫描结果。
fn uc_security_scan_row(x: i64, y: i64, name: ptr, target: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, target[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'V', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'u', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'l', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'r', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'b', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'l', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.627 策略评估行 ============

# uc_policy_eval_row：绘制策略评估行 [E]  check-s3-public  PASS  3 resources
# name 为评估名，resources 为资源数，state 0=失败 1=通过。
# 用于策略评估结果。
fn uc_policy_eval_row(x: i64, y: i64, name: ptr, resources: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + resources, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'u', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 22 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'S', UC_GREEN, bg);
    } else {
        uc_set(x + 22 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'A', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'L', UC_RED, bg);
    }
    return 0;
}

# ============ v1.628 密钥访问行 ============

# uc_key_access_row：绘制密钥访问行 [A]  db-prod  2024-01-01  admin  Allow
# name 为密钥名，date 为日期，user 为访问者，state 0=拒绝 1=允许。
# 用于密钥访问审计。
fn uc_key_access_row(x: i64, y: i64, name: ptr, date: ptr, user: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(date);
    ulen = strlen(user);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'A', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, date[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 12 + nlen + dlen + i, y, user[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + dlen + ulen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen + dlen + ulen, y, 'A', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen + ulen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen + ulen, y, 'l', UC_GREEN, bg);
        uc_set(x + 18 + nlen + dlen + ulen, y, 'o', UC_GREEN, bg);
        uc_set(x + 19 + nlen + dlen + ulen, y, 'w', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + nlen + dlen + ulen, y, 'D', UC_RED, bg);
        uc_set(x + 16 + nlen + dlen + ulen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + dlen + ulen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + dlen + ulen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.629 事件响应行 ============

# uc_incident_response_row：绘制事件响应行 [R]  INC-001  triage  Active
# name 为事件名，phase 为阶段，state 0=关闭 1=进行中。
# 用于事件响应管理。
fn uc_incident_response_row(x: i64, y: i64, name: ptr, phase: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(phase);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'R', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, phase[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'C', fg, bg);
        uc_set(x + 13 + nlen + plen, y, 'l', fg, bg);
        uc_set(x + 14 + nlen + plen, y, 'o', fg, bg);
        uc_set(x + 15 + nlen + plen, y, 's', fg, bg);
        uc_set(x + 16 + nlen + plen, y, 'e', fg, bg);
        uc_set(x + 17 + nlen + plen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.630 备份验证行 ============

# uc_backup_verify_row：绘制备份验证行 [V]  nightly-backup  2024-01-01  Passed
# name 为备份名，date 为日期，state 0=失败 1=通过。
# 用于备份验证记录。
fn uc_backup_verify_row(x: i64, y: i64, name: ptr, date: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(date);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'V', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, date[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 's', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 's', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'F', UC_RED, bg);
        uc_set(x + 13 + nlen + dlen, y, 'a', UC_RED, bg);
        uc_set(x + 14 + nlen + dlen, y, 'i', UC_RED, bg);
        uc_set(x + 15 + nlen + dlen, y, 'l', UC_RED, bg);
        uc_set(x + 16 + nlen + dlen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + dlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.631 数据保留任务行 ============

# uc_retention_task_row：绘制数据保留任务行 [R]  purge-logs  Every 24h  Active
# name 为任务名，schedule 为调度，state 0=停用 1=启用。
# 用于数据保留任务管理。
fn uc_retention_task_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'R', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.632 归档任务行 ============

# uc_archive_task_row：绘制归档任务行 [A]  archive-2023  Monthly  Active
# name 为任务名，schedule 为调度，state 0=停用 1=启用。
# 用于归档任务管理。
fn uc_archive_task_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'A', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.633 清理任务行 ============

# uc_cleanup_task_row：绘制清理任务行 [C]  temp-files  Daily  Active
# name 为任务名，schedule 为调度，state 0=停用 1=启用。
# 用于清理任务管理。
fn uc_cleanup_task_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.634 同步作业行 ============

# uc_sync_job_row：绘制同步作业行 [S]  mysql-to-dw  Running  42%
# name 为作业名，progress 为进度，state 0=停止 1=运行。
# 用于数据同步作业。
fn uc_sync_job_row(x: i64, y: i64, name: ptr, progress: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', fg, bg);
        uc_set(x + 10 + nlen, y, 't', fg, bg);
        uc_set(x + 11 + nlen, y, 'o', fg, bg);
        uc_set(x + 12 + nlen, y, 'p', fg, bg);
        uc_set(x + 13 + nlen, y, 'p', fg, bg);
        uc_set(x + 14 + nlen, y, 'e', fg, bg);
        uc_set(x + 15 + nlen, y, 'd', fg, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + progress / 10, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + progress % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, '%', UC_CYAN, bg);
    return 0;
}

# ============ v1.635 复制任务行 ============

# uc_replication_task_row：绘制复制任务行 [R]  s3-replicate  3 regions  Active
# name 为任务名，regions 为区域数，state 0=停用 1=启用。
# 用于复制任务管理。
fn uc_replication_task_row(x: i64, y: i64, name: ptr, regions: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'R', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + regions, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'g', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', fg, bg);
        uc_set(x + 21 + nlen, y, 'n', fg, bg);
        uc_set(x + 22 + nlen, y, 'a', fg, bg);
        uc_set(x + 23 + nlen, y, 'c', fg, bg);
        uc_set(x + 24 + nlen, y, 't', fg, bg);
        uc_set(x + 25 + nlen, y, 'i', fg, bg);
        uc_set(x + 26 + nlen, y, 'v', fg, bg);
        uc_set(x + 27 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.636 测试用例行 ============

# uc_test_case_row：绘制测试用例行 [T]  login_success  passed  0.3s
# name 为用例名，duration 为耗时，state 0=失败 1=通过。
# 用于测试用例管理。
fn uc_test_case_row(x: i64, y: i64, name: ptr, duration: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    uc_set(x + 17 + nlen, y, '0', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, '.', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '0' + duration / 10, UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '0' + duration % 10, UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, 's', UC_WHITE, bg);
    return 0;
}

# ============ v1.637 测试套件行 ============

# uc_test_suite_row：绘制测试套件行 [S]  api-tests  42 tests  Passing
# name 为套件名，count 为用例数，state 0=失败 1=通过。
# 用于测试套件管理。
fn uc_test_suite_row(x: i64, y: i64, name: ptr, count: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + count / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + count % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_RED, bg);
    }
    return 0;
}

# ============ v1.638 测试运行行 ============

# uc_test_run_row：绘制测试运行行 [R]  #123  CI  passed  2m
# number 为运行号，pipeline 为流水线，state 0=失败 1=通过。
# 用于测试运行记录。
fn uc_test_run_row(x: i64, y: i64, number: i64, pipeline: ptr, state: i64, duration: ptr, fg: i64, bg: i64) -> i64 {
    let plen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    plen = strlen(pipeline);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, '#', UC_YELLOW, bg);
    uc_set(x + 6, y, '0' + number / 100, UC_YELLOW, bg);
    uc_set(x + 7, y, '0' + (number / 10) % 10, UC_YELLOW, bg);
    uc_set(x + 8, y, '0' + number % 10, UC_YELLOW, bg);
    uc_set(x + 10, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 11 + i, y, pipeline[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 13 + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + plen, y, 'P', UC_GREEN, bg);
        uc_set(x + 15 + plen, y, 'a', UC_GREEN, bg);
        uc_set(x + 16 + plen, y, 's', UC_GREEN, bg);
        uc_set(x + 17 + plen, y, 's', UC_GREEN, bg);
        uc_set(x + 18 + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + plen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + plen, y, 'F', UC_RED, bg);
        uc_set(x + 15 + plen, y, 'a', UC_RED, bg);
        uc_set(x + 16 + plen, y, 'i', UC_RED, bg);
        uc_set(x + 17 + plen, y, 'l', UC_RED, bg);
        uc_set(x + 18 + plen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + plen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 21 + plen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 22 + plen + i, y, duration[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.639 覆盖率行 ============

# uc_coverage_row：绘制覆盖率行 [C]  core/  85%  Good
# name 为模块名，percent 为百分比，state 0=差 1=好。
# 用于代码覆盖率展示。
fn uc_coverage_row(x: i64, y: i64, name: ptr, percent: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + percent / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + percent % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'L', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'w', UC_RED, bg);
    }
    return 0;
}

# ============ v1.640 代码质量门禁行 ============

# uc_quality_gate_row：绘制代码质量门禁行 [G]  main  PASS  0 blockers
# branch 为分支，blockers 为阻塞数，state 0=失败 1=通过。
# 用于代码质量门禁。
fn uc_quality_gate_row(x: i64, y: i64, branch: ptr, blockers: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let blen: i64 = 0;
    let i: i64 = 0;
    blen = strlen(branch);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'G', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 6 + i, y, branch[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + blen, y, ' ', fg, bg);
    uc_set(x + 9 + blen, y, '0' + blockers, UC_RED, bg);
    uc_set(x + 10 + blen, y, ' ', UC_RED, bg);
    uc_set(x + 11 + blen, y, 'b', UC_RED, bg);
    uc_set(x + 12 + blen, y, 'l', UC_RED, bg);
    uc_set(x + 13 + blen, y, 'o', UC_RED, bg);
    uc_set(x + 14 + blen, y, 'c', UC_RED, bg);
    uc_set(x + 15 + blen, y, 'k', UC_RED, bg);
    uc_set(x + 16 + blen, y, 'e', UC_RED, bg);
    uc_set(x + 17 + blen, y, 'r', UC_RED, bg);
    uc_set(x + 18 + blen, y, 's', UC_RED, bg);
    uc_set(x + 20 + blen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + blen, y, 'P', UC_GREEN, bg);
        uc_set(x + 22 + blen, y, 'A', UC_GREEN, bg);
        uc_set(x + 23 + blen, y, 'S', UC_GREEN, bg);
        uc_set(x + 24 + blen, y, 'S', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + blen, y, 'F', UC_RED, bg);
        uc_set(x + 22 + blen, y, 'A', UC_RED, bg);
        uc_set(x + 23 + blen, y, 'I', UC_RED, bg);
        uc_set(x + 24 + blen, y, 'L', UC_RED, bg);
    }
    return 0;
}

# ============ v1.641 容器镜像行 ============

# uc_image_row：绘制容器镜像行 [I]  nginx  1.25.3  latest
# name 为镜像名，tag 为版本，state 0=非最新 1=最新。
# 用于容器镜像管理。
fn uc_image_row(x: i64, y: i64, name: ptr, tag: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(tag);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'I', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ':', UC_YELLOW, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, tag[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'L', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 's', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 't', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.642 容器注册表行 ============

# uc_registry_row：绘制容器注册表行 [R]  docker.io  Public  Active
# name 为注册表名，state 0=私有 1=公开。
# 用于容器注册表管理。
fn uc_registry_row(x: i64, y: i64, name: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'P', UC_YELLOW, bg);
        uc_set(x + 10 + nlen, y, 'r', UC_YELLOW, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 12 + nlen, y, 'v', UC_YELLOW, bg);
        uc_set(x + 13 + nlen, y, 'a', UC_YELLOW, bg);
        uc_set(x + 14 + nlen, y, 't', UC_YELLOW, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_YELLOW, bg);
    }
    return 0;
}

# ============ v1.643 K8s 命名空间行 ============

# uc_namespace_row：绘制 K8s 命名空间行 [N]  prod  Active  12 pods
# name 为命名空间名，pods 为 Pod 数，state 0=终止 1=活跃。
# 用于 Kubernetes 命名空间管理。
fn uc_namespace_row(x: i64, y: i64, name: ptr, pods: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'N', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'T', fg, bg);
        uc_set(x + 10 + nlen, y, 'e', fg, bg);
        uc_set(x + 11 + nlen, y, 'r', fg, bg);
        uc_set(x + 12 + nlen, y, 'm', fg, bg);
        uc_set(x + 13 + nlen, y, 'i', fg, bg);
        uc_set(x + 14 + nlen, y, 'n', fg, bg);
        uc_set(x + 15 + nlen, y, 'a', fg, bg);
        uc_set(x + 16 + nlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen, y, 'n', fg, bg);
        uc_set(x + 19 + nlen, y, 'g', fg, bg);
    }
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    uc_set(x + 22 + nlen, y, '0' + pods / 10, UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, '0' + pods % 10, UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.644 K8s 工作负载行 ============

# uc_workload_row：绘制 K8s 工作负载行 [W]  web-deploy  Deployment  3/3 ready
# name 为工作负载名，kind 为类型，state 0=异常 1=就绪。
# 用于 Kubernetes 工作负载管理。
fn uc_workload_row(x: i64, y: i64, name: ptr, kind: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let klen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    klen = strlen(kind);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'W', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 9 + nlen + i, y, kind[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + klen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + klen, y, '3', UC_GREEN, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_GREEN, bg);
        uc_set(x + 14 + nlen + klen, y, '3', UC_GREEN, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_GREEN, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_GREEN, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + klen, y, '0', UC_RED, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_RED, bg);
        uc_set(x + 14 + nlen + klen, y, '3', UC_RED, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_RED, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_RED, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_RED, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.645 K8s 服务行 ============

# uc_k8s_service_row：绘制 K8s 服务行 [S]  web-svc  ClusterIP  80
# name 为服务名，type 为类型，port 为端口。
# 用于 Kubernetes 服务管理。
fn uc_k8s_service_row(x: i64, y: i64, name: ptr, type: ptr, port: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + tlen, y, '0' + port / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + tlen, y, '0' + (port / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + tlen, y, '0' + port % 10, UC_CYAN, bg);
    return 0;
}

# ============ v1.646 K8s 配置映射行 ============

# uc_configmap_row：绘制 K8s 配置映射行 [C]  app-config  5 keys  Active
# name 为配置映射名，keys 为键数，state 0=停用 1=启用。
# 用于 Kubernetes ConfigMap 管理。
fn uc_configmap_row(x: i64, y: i64, name: ptr, keys: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + keys, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'k', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'y', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 17 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 17 + nlen, y, 'I', fg, bg);
        uc_set(x + 18 + nlen, y, 'n', fg, bg);
        uc_set(x + 19 + nlen, y, 'a', fg, bg);
        uc_set(x + 20 + nlen, y, 'c', fg, bg);
        uc_set(x + 21 + nlen, y, 't', fg, bg);
        uc_set(x + 22 + nlen, y, 'i', fg, bg);
        uc_set(x + 23 + nlen, y, 'v', fg, bg);
        uc_set(x + 24 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.647 K8s 密钥行 ============

# uc_k8s_secret_row：绘制 K8s 密钥行 [S]  db-credentials  Opaque  Active
# name 为密钥名，type 为类型，state 0=停用 1=启用。
# 用于 Kubernetes Secret 管理。
fn uc_k8s_secret_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.648 K8s 持久卷行 ============

# uc_pv_row：绘制 K8s 持久卷行 [V]  pvc-data  10Gi  Bound
# name 为卷名，size 为大小，state 0=挂起 1=已绑定。
# 用于 Kubernetes 持久卷管理。
fn uc_pv_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'V', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'B', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'u', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen + slen, y, 'e', UC_CYAN, bg);
        uc_set(x + 14 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen + slen, y, 'd', UC_CYAN, bg);
        uc_set(x + 16 + nlen + slen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 18 + nlen + slen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.649 K8s 存储类行 ============

# uc_storage_class_row2：绘制 K8s 存储类行 [C]  standard  gp2  Default
# name 为存储类名，provisioner 为供应器，state 0=非默认 1=默认。
# 用于 Kubernetes 存储类管理。
fn uc_storage_class_row2(x: i64, y: i64, name: ptr, provisioner: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(provisioner);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, provisioner[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'D', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 'f', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'a', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'u', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'l', UC_GREEN, bg);
        uc_set(x + 18 + nlen + plen, y, 't', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'S', UC_CYAN, bg);
        uc_set(x + 13 + nlen + plen, y, 't', UC_CYAN, bg);
        uc_set(x + 14 + nlen + plen, y, 'a', UC_CYAN, bg);
        uc_set(x + 15 + nlen + plen, y, 'n', UC_CYAN, bg);
        uc_set(x + 16 + nlen + plen, y, 'd', UC_CYAN, bg);
        uc_set(x + 17 + nlen + plen, y, 'a', UC_CYAN, bg);
        uc_set(x + 18 + nlen + plen, y, 'r', UC_CYAN, bg);
        uc_set(x + 19 + nlen + plen, y, 'd', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.650 K8s Ingress 行 ============

# uc_ingress_row：绘制 K8s Ingress 行 [I]  web-ingress  nginx  Active
# name 为 Ingress 名，controller 为控制器，state 0=停用 1=启用。
# 用于 Kubernetes Ingress 管理。
fn uc_ingress_row(x: i64, y: i64, name: ptr, controller: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(controller);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'I', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, controller[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.651 Helm Release 行 ============

# uc_helm_release_row：绘制 Helm Release 行 [R]  my-app  deployed  v2.1.0
# name 为 Release 名，status 为状态，version 为版本。
# 用于 Helm Release 管理。
fn uc_helm_release_row(x: i64, y: i64, name: ptr, status: ptr, version: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(status);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, status[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 12 + nlen + slen + i, y, version[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.652 Helm Chart 行 ============

# uc_helm_chart_row：绘制 Helm Chart 行 [C]  nginx-ingress  4.8.0  Published
# name 为 Chart 名，version 为版本，state 0=未发布 1=已发布。
# 用于 Helm Chart 管理。
fn uc_helm_chart_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 's', UC_GREEN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 19 + nlen + vlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + vlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'D', UC_CYAN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'f', UC_CYAN, bg);
        uc_set(x + 16 + nlen + vlen, y, 't', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.653 K8s 作业行 ============

# uc_k8s_job_row：绘制 K8s 作业行 [J]  migration-1  Succeeded  3 pods
# name 为作业名，pods 为 Pod 数，state 0=运行 1=成功。
# 用于 Kubernetes Job 管理。
fn uc_k8s_job_row(x: i64, y: i64, name: ptr, pods: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'J', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + pods, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, 's', UC_WHITE, bg);
    return 0;
}

# ============ v1.654 K8s CronJob 行 ============

# uc_cronjob_row：绘制 K8s CronJob 行 [C]  backup-cron  */30 * * * *  Active
# name 为作业名，schedule 为调度，state 0=暂停 1=启用。
# 用于 Kubernetes CronJob 管理。
fn uc_cronjob_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'P', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'u', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 's', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 'e', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'd', fg, bg);
    }
    return 0;
}

# ============ v1.655 K8s HPA 行 ============

# uc_hpa_row：绘制 K8s HPA 行 [H]  web-hpa  cpu 80%  2/10 replicas
# name 为 HPA 名，metric 为指标，state 0=异常 1=正常。
# 用于 Kubernetes HPA 管理。
fn uc_hpa_row(x: i64, y: i64, name: ptr, metric: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(metric);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'H', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, metric[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, '2', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, '/', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, '1', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, '0', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 18 + nlen + mlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + mlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 20 + nlen + mlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 21 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 23 + nlen + mlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 24 + nlen + mlen, y, 's', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, '0', UC_RED, bg);
        uc_set(x + 13 + nlen + mlen, y, '/', UC_RED, bg);
        uc_set(x + 14 + nlen + mlen, y, '1', UC_RED, bg);
        uc_set(x + 15 + nlen + mlen, y, '0', UC_RED, bg);
        uc_set(x + 16 + nlen + mlen, y, ' ', UC_RED, bg);
        uc_set(x + 17 + nlen + mlen, y, 'r', UC_RED, bg);
        uc_set(x + 18 + nlen + mlen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + nlen + mlen, y, 'p', UC_RED, bg);
        uc_set(x + 20 + nlen + mlen, y, 'l', UC_RED, bg);
        uc_set(x + 21 + nlen + mlen, y, 'i', UC_RED, bg);
        uc_set(x + 22 + nlen + mlen, y, 'c', UC_RED, bg);
        uc_set(x + 23 + nlen + mlen, y, 'a', UC_RED, bg);
        uc_set(x + 24 + nlen + mlen, y, 's', UC_RED, bg);
    }
    return 0;
}

# ============ v1.656 K8s ServiceAccount 详情行 ============

# uc_sa_detail_row：绘制 K8s ServiceAccount 详情行 [A]  deploy-bot  default-ns  Active
# name 为账户名，namespace 为命名空间，state 0=停用 1=启用。
# 用于 Kubernetes ServiceAccount 管理。
fn uc_sa_detail_row(x: i64, y: i64, name: ptr, namespace: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let nslen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    nslen = strlen(namespace);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < nslen {
        uc_set(x + 9 + nlen + i, y, namespace[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + nslen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + nslen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + nslen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + nslen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + nslen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + nslen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + nslen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + nslen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + nslen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + nslen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + nslen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + nslen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + nslen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + nslen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + nslen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.657 K8s Role 行 ============

# uc_k8s_role_row：绘制 K8s Role 行 [R]  pod-reader  read  default-ns
# name 为角色名，permission 为权限，namespace 为命名空间。
# 用于 Kubernetes Role 管理。
fn uc_k8s_role_row(x: i64, y: i64, name: ptr, permission: ptr, namespace: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let nslen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(permission);
    nslen = strlen(namespace);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, permission[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    i = 0;
    while i < nslen {
        uc_set(x + 12 + nlen + plen + i, y, namespace[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.658 K8s 网络策略行 ============

# uc_netpol_row：绘制 K8s 网络策略行 [P]  allow-api  ingress  Active
# name 为策略名，direction 为方向，state 0=停用 1=启用。
# 用于 Kubernetes 网络策略管理。
fn uc_netpol_row(x: i64, y: i64, name: ptr, direction: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(direction);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, direction[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + dlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + dlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + dlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + dlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + dlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + dlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + dlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.659 K8s Pod 行 ============

# uc_pod_row：绘制 K8s Pod 行 [P]  web-6b4d  Running  node-01  2/2
# name 为 Pod 名，node 为节点，state 0=异常 1=运行。
# 用于 Kubernetes Pod 管理。
fn uc_pod_row(x: i64, y: i64, name: ptr, node: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let nodlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    nodlen = strlen(node);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 14 + nlen, y, '!', UC_RED, bg);
    }
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < nodlen {
        uc_set(x + 17 + nlen + i, y, node[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 19 + nlen + nodlen, y, ' ', fg, bg);
    uc_set(x + 20 + nlen + nodlen, y, '2', UC_WHITE, bg);
    uc_set(x + 21 + nlen + nodlen, y, '/', UC_WHITE, bg);
    uc_set(x + 22 + nlen + nodlen, y, '2', UC_WHITE, bg);
    return 0;
}

# ============ v1.660 K8s 节点行 ============

# uc_k8s_node_row：绘制 K8s 节点行 [N]  node-01  Ready  linux-amd64
# name 为节点名，state 0=未就绪 1=就绪，arch 为架构。
# 用于 Kubernetes 节点管理。
fn uc_k8s_node_row(x: i64, y: i64, name: ptr, state: i64, arch: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(arch);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'N', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'N', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'y', UC_RED, bg);
    }
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 19 + nlen + i, y, arch[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.661 K8s 状态集行 ============

# uc_statefulset_row：绘制 K8s 状态集行 [S]  db-set  StatefulSet  3/3 ready
# name 为状态集名，kind 为类型，state 0=异常 1=就绪。
# 用于 Kubernetes StatefulSet 管理。
fn uc_statefulset_row(x: i64, y: i64, name: ptr, kind: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let klen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    klen = strlen(kind);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 9 + nlen + i, y, kind[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + klen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + klen, y, '3', UC_GREEN, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_GREEN, bg);
        uc_set(x + 14 + nlen + klen, y, '3', UC_GREEN, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_GREEN, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_GREEN, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + klen, y, '0', UC_RED, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_RED, bg);
        uc_set(x + 14 + nlen + klen, y, '3', UC_RED, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_RED, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_RED, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_RED, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.662 K8s 守护进程集行 ============

# uc_daemonset_row：绘制 K8s 守护进程集行 [D]  node-exporter  DaemonSet  5/5 ready
# name 为守护进程集名，kind 为类型，state 0=异常 1=就绪。
# 用于 Kubernetes DaemonSet 管理。
fn uc_daemonset_row(x: i64, y: i64, name: ptr, kind: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let klen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    klen = strlen(kind);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'D', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 9 + nlen + i, y, kind[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + klen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + klen, y, '5', UC_GREEN, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_GREEN, bg);
        uc_set(x + 14 + nlen + klen, y, '5', UC_GREEN, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_GREEN, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_GREEN, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_GREEN, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_GREEN, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + klen, y, '0', UC_RED, bg);
        uc_set(x + 13 + nlen + klen, y, '/', UC_RED, bg);
        uc_set(x + 14 + nlen + klen, y, '5', UC_RED, bg);
        uc_set(x + 15 + nlen + klen, y, ' ', UC_RED, bg);
        uc_set(x + 16 + nlen + klen, y, 'r', UC_RED, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + nlen + klen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + klen, y, 'd', UC_RED, bg);
        uc_set(x + 20 + nlen + klen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.663 K8s PVC 行 ============

# uc_pvc_row：绘制 K8s PVC 行 [V]  data-pvc  10Gi  Bound
# name 为卷声明名，size 为大小，state 0=挂起 1=已绑定。
# 用于 Kubernetes PVC 管理。
fn uc_pvc_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'B', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'u', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen + slen, y, 'e', UC_CYAN, bg);
        uc_set(x + 14 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen + slen, y, 'd', UC_CYAN, bg);
        uc_set(x + 16 + nlen + slen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 18 + nlen + slen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.664 K8s 资源配额行 ============

# uc_resource_quota_row：绘制 K8s 资源配额行 [Q]  default  cpu 10  mem 20Gi
# name 为配额名，cpu 为 CPU 限制，mem 为内存限制。
# 用于 Kubernetes 资源配额管理。
fn uc_resource_quota_row(x: i64, y: i64, name: ptr, cpu: i64, mem: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'Q', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'u', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, '0' + cpu, UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, ' ', fg, bg);
    uc_set(x + 16 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '0' + mem / 10, UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, '0' + mem % 10, UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, 'G', UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, 'i', UC_WHITE, bg);
    return 0;
}

# ============ v1.665 K8s LimitRange 行 ============

# uc_limitrange_row：绘制 K8s LimitRange 行 [L]  default  cpu 100m-2  Active
# name 为 LimitRange 名，rule 为规则，state 0=停用 1=启用。
# 用于 Kubernetes LimitRange 管理。
fn uc_limitrange_row(x: i64, y: i64, name: ptr, rule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(rule);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'L', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, rule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + rlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + rlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + rlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + rlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + rlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + rlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + rlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + rlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + rlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + rlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + rlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + rlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.666 K8s 端点行 ============

# uc_endpoint_row：绘制 K8s 端点行 [E]  web-svc  3 endpoints  Active
# name 为端点名，count 为数量，state 0=停用 1=启用。
# 用于 Kubernetes Endpoint 管理。
fn uc_endpoint_row(x: i64, y: i64, name: ptr, count: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'E', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + count, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 22 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 22 + nlen, y, 'I', fg, bg);
        uc_set(x + 23 + nlen, y, 'n', fg, bg);
        uc_set(x + 24 + nlen, y, 'a', fg, bg);
        uc_set(x + 25 + nlen, y, 'c', fg, bg);
        uc_set(x + 26 + nlen, y, 't', fg, bg);
        uc_set(x + 27 + nlen, y, 'i', fg, bg);
        uc_set(x + 28 + nlen, y, 'v', fg, bg);
        uc_set(x + 29 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.667 K8s 节点池行 ============

# uc_node_pool_row：绘制 K8s 节点池行 [P]  pool-1  3 nodes  Active
# name 为节点池名，nodes 为节点数，state 0=停用 1=启用。
# 用于 Kubernetes 节点池管理。
fn uc_node_pool_row(x: i64, y: i64, name: ptr, nodes: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + nodes, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen, y, 'I', fg, bg);
        uc_set(x + 19 + nlen, y, 'n', fg, bg);
        uc_set(x + 20 + nlen, y, 'a', fg, bg);
        uc_set(x + 21 + nlen, y, 'c', fg, bg);
        uc_set(x + 22 + nlen, y, 't', fg, bg);
        uc_set(x + 23 + nlen, y, 'i', fg, bg);
        uc_set(x + 24 + nlen, y, 'v', fg, bg);
        uc_set(x + 25 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.668 K8s 污点行 ============

# uc_taint_row：绘制 K8s 污点行 [T]  dedicated  NoSchedule  node-01
# key 为污点键，effect 为效果，target 为目标节点。
# 用于 Kubernetes 污点管理。
fn uc_taint_row(x: i64, y: i64, key: ptr, effect: ptr, target: ptr, fg: i64, bg: i64) -> i64 {
    let klen: i64 = 0;
    let elen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    klen = strlen(key);
    elen = strlen(effect);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'T', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 6 + i, y, key[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + klen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + klen + i, y, effect[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + klen + elen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 12 + klen + elen + i, y, target[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.669 K8s 亲和性行 ============

# uc_affinity_row：绘制 K8s 亲和性行 [A]  zone  preferred  topology.kubernetes.io/zone
# name 为亲和性名，type 为类型，key 为拓扑键。
# 用于 Kubernetes 亲和性管理。
fn uc_affinity_row(x: i64, y: i64, name: ptr, type: ptr, key: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let klen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    klen = strlen(key);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 12 + nlen + tlen + i, y, key[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.670 K8s 拓扑行 ============

# uc_topology_row：绘制 K8s 拓扑行 [T]  zone-a  region-east  5 nodes
# name 为拓扑名，region 为区域，nodes 为节点数。
# 用于 Kubernetes 拓扑管理。
fn uc_topology_row(x: i64, y: i64, name: ptr, region: ptr, nodes: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(region);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'T', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, region[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + rlen, y, '0' + nodes, UC_CYAN, bg);
    uc_set(x + 13 + nlen + rlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + rlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 15 + nlen + rlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 16 + nlen + rlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 17 + nlen + rlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + rlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.671 服务网格虚拟服务行 ============

# uc_virtual_service_row：绘制服务网格虚拟服务行 [V]  reviews-vs  istio  Active
# name 为虚拟服务名，mesh 为网格，state 0=停用 1=启用。
# 用于服务网格虚拟服务管理。
fn uc_virtual_service_row(x: i64, y: i64, name: ptr, mesh: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(mesh);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, mesh[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + mlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + mlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + mlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + mlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + mlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.672 目标规则行 ============

# uc_destination_rule_row：绘制目标规则行 [R]  reviews-dr  istio  Active
# name 为目标规则名，mesh 为网格，state 0=停用 1=启用。
# 用于服务网格目标规则管理。
fn uc_destination_rule_row(x: i64, y: i64, name: ptr, mesh: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(mesh);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'R', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, mesh[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + mlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + mlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + mlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + mlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + mlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.673 网关路由行 ============

# uc_mesh_gateway_row：绘制服务网格网关路由行 [G]  bookinfo-gw  istio-gateway  Active
# name 为网关名，controller 为控制器，state 0=停用 1=启用。
# 用于服务网格网关管理。
fn uc_mesh_gateway_row(x: i64, y: i64, name: ptr, controller: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(controller);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'G', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, controller[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.674 熔断器行 ============

# uc_circuit_breaker_row：绘制熔断器行 [B]  reviews-cb  5 retries  HalfOpen
# name 为熔断器名，retries 为重试数，state 0=关闭 1=半开。
# 用于熔断器管理。
fn uc_circuit_breaker_row(x: i64, y: i64, name: ptr, retries: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'B', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + retries, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'H', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'f', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'O', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'p', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'n', UC_CYAN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.675 重试策略行 ============

# uc_retry_policy_row：绘制重试策略行 [P]  api-retry  3 attempts  500ms
# name 为策略名，attempts 为重试次数，interval 为间隔。
# 用于重试策略管理。
fn uc_retry_policy_row(x: i64, y: i64, name: ptr, attempts: i64, interval: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + attempts, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 21 + nlen + i, y, interval[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.676 服务条目行 ============

# uc_service_entry_row：绘制服务条目行 [E]  external-api  DNS  Active
# name 为服务条目名，resolution 为解析方式，state 0=停用 1=启用。
# 用于服务网格服务条目管理。
fn uc_service_entry_row(x: i64, y: i64, name: ptr, resolution: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(resolution);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, resolution[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + rlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + rlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + rlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + rlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + rlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + rlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + rlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + rlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + rlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + rlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + rlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + rlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.677 外部服务行 ============

# uc_external_service_row：绘制外部服务行 [S]  payments  external  Healthy
# name 为服务名，type 为类型，state 0=异常 1=健康。
# 用于外部服务监控。
fn uc_external_service_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'U', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'h', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'l', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'h', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.678 故障注入行 ============

# uc_fault_injection_row：绘制故障注入行 [F]  delay-reviews  5s  Active
# name 为注入名，delay 为延迟，state 0=停用 1=启用。
# 用于服务网格故障注入管理。
fn uc_fault_injection_row(x: i64, y: i64, name: ptr, delay: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(delay);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'F', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, delay[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + dlen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + dlen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + dlen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + dlen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + dlen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + dlen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + dlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.679 流量迁移行 ============

# uc_traffic_shift_row：绘制流量迁移行 [T]  reviews-v1  50%  Active
# name 为迁移名，weight 为权重，state 0=停用 1=启用。
# 用于服务网格流量迁移管理。
fn uc_traffic_shift_row(x: i64, y: i64, name: ptr, weight: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + weight / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + weight % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'I', fg, bg);
        uc_set(x + 15 + nlen, y, 'n', fg, bg);
        uc_set(x + 16 + nlen, y, 'a', fg, bg);
        uc_set(x + 17 + nlen, y, 'c', fg, bg);
        uc_set(x + 18 + nlen, y, 't', fg, bg);
        uc_set(x + 19 + nlen, y, 'i', fg, bg);
        uc_set(x + 20 + nlen, y, 'v', fg, bg);
        uc_set(x + 21 + nlen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.680 链路追踪行 ============

# uc_tracing_row：绘制链路追踪行 [T]  jaeger  sampling 0.1  Active
# name 为追踪名，config 为配置，state 0=停用 1=启用。
# 用于链路追踪管理。
fn uc_tracing_row(x: i64, y: i64, name: ptr, config: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(config);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'T', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, config[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', fg, bg);
    }
    return 0;
}

