# 墨语言 字符画布标准库 (lib/uic.mo) 参考

`uic` 是墨语言的**完整 UI 绘图标准库**。它把终端当作一块字符画布，
开发者用基本原语自由组合出**任何形式的 UI、组件、图标、样式、图形**。

## 快速开始

```mo
import "uic.mo";
fn main() -> i64 {
    uc_init(60, 20);            # 画布 60x20
    uc_clear(UC_WHITE, UC_BLUE); # 白字蓝底
    uc_window(1, 1, 30, 8, " 标题 ", UC_CYAN, UC_WHITE);
    uc_text(3, 2, "Hello", UC_YELLOW, UC_BLUE);
    uc_render();                 # 一次性渲染到终端
    return 0;
}
```

## 画布管理

| 函数 | 说明 |
|------|------|
| `uc_init(w,h)` | 初始化画布（上限 120x50） |
| `uc_clear(fg,bg)` | 清空画布为前景/背景色 |
| `uc_set(x,y,ch,fg,bg)` | 设置单个单元（字符+前景+背景） |
| `uc_get(x,y)` | 读取单元字符 |
| `uc_render()` | 一次性渲染整个画布到终端 |
| `uc_render_at(row,col)` | 增量渲染到指定位置 |
| `uc_dump_text()` | 输出纯文本（无颜色） |
| `uc_dump_file(path)` | 保存为纯文本文件 |
| `uc_dump_html(path)` | 导出为彩色 HTML 文件 |

## 颜色

8 基础色常量：`UC_BLACK UC_RED UC_GREEN UC_YELLOW UC_BLUE UC_MAGENTA UC_CYAN UC_WHITE`。

256 色：`uc_color256` 自动在 `uc_render` 中使用。前景/背景值 >7 时输出 ANSI 256 色序列。

## 文本与样式

| 函数 | 说明 |
|------|------|
| `uc_text(x,y,s,fg,bg)` | 绘制字符串 |
| `uc_style(x,y,st)` | 设置单元样式：1=粗体 2=下划线 4=闪烁 |
| `uc_style_text(x,y,s,st)` | 给整段文本设置样式 |
| `uc_label(x,y,text,fg,bg,border)` | 带边框标签 `[ON]` |

## 图形

| 函数 | 说明 |
|------|------|
| `uc_rect(x,y,w,h,ch,fg,bg)` | 矩形边框 |
| `uc_fill(x,y,w,h,ch,fg,bg)` | 填充矩形 |
| `uc_hline / uc_vline` | 水平/垂直直线 |
| `uc_line(x1,y1,x2,y2,ch,fg,bg)` | Bresenham 任意直线 |
| `uc_circle(cx,cy,r,ch,fg,bg)` | 圆 |
| `uc_fill_circle(cx,cy,r,ch,fg,bg)` | 实心圆 |
| `uc_tri(x0,y0,x1,y1,x2,y2,ch,fg,bg)` | 三角形边框 |
| `uc_polygon(xs,ys,n,ch,fg,bg)` | 任意多边形（顶点列表） |
| `uc_sprite(x,y,pattern,fg,bg)` | 字符图案（`.`=透明） |
| `uc_chart(x,y,values,max_h,fg,bg)` | 条形图 |

## 组件

| 函数 | 说明 |
|------|------|
| `uc_window(x,y,w,h,title,bfg,tbg)` | 带标题栏窗口 |
| `uc_panel(x,y,w,h,title,fg,bg)` | 面板 |
| `uc_gauge(x,y,w,pct,fg,bg)` | 水平仪表盘 |
| `uc_scrollbar(x,y,h,pos,thumb_h,fg,bg)` | 垂直滚动条 |
| `uc_checkbox(x,y,text,checked,fg,bg)` | 复选框 `[x]` |
| `uc_radio(x,y,text,selected,fg,bg)` | 单选 `(o)` |
| `uc_input(x,y,value,width,fg,bg)` | 输入框 |
| `uc_slider(x,y,width,value,fg,bg)` | 滑块 |

## 布局

| 函数 | 说明 |
|------|------|
| `uc_layout_h(x,y,count,w,gap,fg,bg)` | 水平排列面板 |
| `uc_layout_v(x,y,count,h,gap,fg,bg)` | 垂直排列面板 |

## 图标

`uc_icon_check` `uc_icon_cross` `uc_icon_warn` `uc_icon_search`
`uc_icon_lock` `uc_icon_file` `uc_icon_folder` `uc_icon_heart`

## 主题

| 函数 | 说明 |
|------|------|
| `uc_theme_dark()` | 深色主题 |
| `uc_theme_light()` | 浅色主题 |
| `uc_theme_custom(tc,tb,ac,sb,sc,wb)` | 自定义主题 |
| `uc_apply_theme()` | 应用主题到画布背景 |

## 示例

- `examples/uic_demo.mo`：基础画布演示（窗口+图标+按钮+进度条）
- `examples/uic_dashboard.mo`：完整 TUI 仪表盘（菜单+表格+条形图+状态栏）
