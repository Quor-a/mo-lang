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
