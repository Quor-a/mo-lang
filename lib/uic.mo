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
