# site —— 静态站点生成器（用墨语言自己写的）
#
#   ./site <posts目录> <输出目录>
#
# 输入：目录下若干 .md，带 front-matter
#
#   ---
#   title: 标题
#   date: 2026-10-09
#   ---
#
#   ## 小节
#   正文段落，**粗体**、`行内代码`。
#   - 列表项
#   ``` 代码块 ```
#
# 输出：<输出目录>/index.html、posts/<slug>.html、rss.xml
#
# 这不是玩具：它有 front-matter 解析、Markdown 子集渲染、
# 按日期倒序的索引页、RSS 生成、HTML 转义。
import "io.mo";
import "str.mo";
import "fs.mo";
import "dir.mo";
import "vec.mo";
import "mem.mo";

var SRC: [256] byte = 0;
var OUT: [256] byte = 0;

var TITLE: [128] byte = 0;
var DATE: [32] byte = 0;

# 文章列表：标题/日期/文件名的堆字符串，存在各自的 vec 里，
# 索引一一对应（没有结构体数组，用平行数组代替）
var V_TITLE: i64 = 0;
var V_DATE: i64 = 0;
var V_SLUG: i64 = 0;
var V_FILE: i64 = 0;

var BODY: [16384] byte = 0;     # 原始 markdown
var HTML: [32768] byte = 0;     # 渲染结果
var LINE: [1024] byte = 0;
var PATH: [256] byte = 0;
var TMP: [512] byte = 0;

fn die(msg: i64) -> i64 {
    print("site: ");
    print(msg);
    print_nl();
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

# ---------------- HTML 转义 ----------------
# 不转义的话，正文里的 < & 会破坏页面结构。这是真实的安全问题，
# 不是"锦上添花"。
# 返回**转义后的新字符串**（而不是追加到 dst）。
# sfmt 只能插值"值"，所以需要这个返回版本。
# 调用方负责用完后不必释放（沿用 bump 分配器的策略）。
fn esc_str(s: i64) -> i64 {
    let out: i64 = alloc(4096);
    if out == 0 { return s; }
    store8(out, 0);
    esc_append(out, s);
    return out;
}

fn esc_append(dst: i64, s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        let c: i64 = load8(s + i);
        if c == 60 { strcat(dst, "&lt;"); }
        else {
            if c == 62 { strcat(dst, "&gt;"); }
            else {
                if c == 38 { strcat(dst, "&amp;"); }
                else {
                    if c == 34 { strcat(dst, "&quot;"); }
                    else {
                        let one: [2] byte = 0;
                        store8(&one, c);
                        store8(&one + 1, 0);
                        strcat(dst, &one);
                    }
                }
            }
        }
        i = i + 1;
    }
    return 0;
}

# ---------------- front-matter ----------------

# 解析 --- 之间的 key: value。返回正文起始下标；没有 front-matter 则返回 0
fn parse_front(src: i64) -> i64 {
    if str_starts_with(src, "---") == 0 { return 0; }
    let i: i64 = 3;
    let ln: i64 = 0;
    while load8(src + i) != 0 {
        # 收集一行
        ln = 0;
        while load8(src + i + ln) != 10 {
            if load8(src + i + ln) == 0 { break; }
            ln = ln + 1;
        }
        if ln >= 1024 { ln = 1023; }
        memcpy(&LINE, src + i + ln - ln, 0);
        let j: i64 = 0;
        while j < ln {
            store8(&LINE + j, load8(src + i + j));
            j = j + 1;
        }
        store8(&LINE + ln, 0);
        if str_starts_with(&LINE, "---") == 1 {
            return i + ln + 1;
        }
        # key: value
        let c: i64 = strchr(&LINE, 58);
        if c >= 0 {
            store8(&LINE + c, 0);
            let key: i64 = str_trim(&LINE);
            let val: i64 = str_trim(&LINE + c + 1);
            if streq(key, "title") == 1 { strcpy(&TITLE, val); }
            if streq(key, "date") == 1 { strcpy(&DATE, val); }
        }
        i = i + ln + 1;
    }
    return 0;
}

# ---------------- Markdown 渲染 ----------------

var INCODE: i64 = 0;

# 行内：**粗体**、`代码`
fn render_inline(dst: i64, s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        if load8(s + i) == 96 {                     # ` 行内代码
            # strchr 返回的是相对 s+i+1 的下标，-1 才是没找到
            let e: i64 = strchr(s + i + 1, 96);
            if e >= 0 {
                strcat(dst, "<code>");
                let k: i64 = 0;
                while k < e {
                    esc_one(dst, load8(s + i + 1 + k));
                    k = k + 1;
                }
                strcat(dst, "</code>");
                i = i + 1 + e + 1;
            } else { esc_one(dst, load8(s + i)); i = i + 1; }
        } else {
            if load8(s + i) == 42 {                 # ** 粗体
                if load8(s + i + 1) == 42 {
                    # strstr 同理：相对 s+i+2 的下标。
                    # 特别小心：返回 0 表示"就在开头找到"，不是"没找到"——
                    # 这是同项目里踩过一次的坑（grep.mo）。
                    let e2: i64 = strstr(s + i + 2, "**");
                    if e2 >= 0 {
                        strcat(dst, "<strong>");
                        let k2: i64 = 0;
                        while k2 < e2 {
                            esc_one(dst, load8(s + i + 2 + k2));
                            k2 = k2 + 1;
                        }
                        strcat(dst, "</strong>");
                        i = i + 2 + e2 + 2;
                    } else { esc_one(dst, load8(s + i)); i = i + 1; }
                } else { esc_one(dst, load8(s + i)); i = i + 1; }
            } else {
                esc_one(dst, load8(s + i));
                i = i + 1;
            }
        }
    }
    return 0;
}

fn esc_one(dst: i64, c: i64) -> i64 {
    if c == 60 { strcat(dst, "&lt;"); return 0; }
    if c == 62 { strcat(dst, "&gt;"); return 0; }
    if c == 38 { strcat(dst, "&amp;"); return 0; }
    let one: [2] byte = 0;
    store8(&one, c);
    store8(&one + 1, 0);
    strcat(dst, &one);
    return 0;
}

# 块级：# 标题 / ``` 代码块 / - 列表 / 空行分段 / 普通段落
fn render_body(dst: i64, src: i64) -> i64 {
    let i: i64 = 0;
    let ln: i64 = 0;
    let in_para: i64 = 0;
    while load8(src + i) != 0 {
        ln = 0;
        while load8(src + i + ln) != 10 {
            if load8(src + i + ln) == 0 { break; }
            ln = ln + 1;
        }
        if ln >= 1024 { ln = 1023; }
        let j: i64 = 0;
        while j < ln {
            store8(&LINE + j, load8(src + i + j));
            j = j + 1;
        }
        store8(&LINE + ln, 0);
        let L: i64 = str_trim(&LINE);

        if str_starts_with(L, "```") == 1 {
            if INCODE == 1 {
                strcat(dst, "</code></pre>\n");
                INCODE = 0;
            } else {
                if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                strcat(dst, "<pre><code>");
                let lang: i64 = L + 3;
                strcat(dst, "\n");
                INCODE = 1;
            }
        } else {
            if INCODE == 1 {
                esc_append(dst, L);
                strcat(dst, "\n");
            } else {
                if strlen(L) == 0 {
                    if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                } else {
                    if str_starts_with(L, "### ") == 1 {
                        if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                        sfmt(dst, f"<h3>{ptr(L + 4)}</h3>\n");
                    } else {
                        if str_starts_with(L, "## ") == 1 {
                            if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                            sfmt(dst, f"<h2>{ptr(L + 3)}</h2>\n");
                        } else {
                            if str_starts_with(L, "# ") == 1 {
                                if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                                sfmt(dst, f"<h1>{ptr(L + 2)}</h1>\n");
                            } else {
                                if str_starts_with(L, "- ") == 1 {
                                    if in_para == 1 { strcat(dst, "</p>\n"); in_para = 0; }
                                    sfmt(dst, f"<li>{ptr(L + 2)}</li>\n");
                                } else {
                                    if in_para == 0 { strcat(dst, "<p>"); in_para = 1; }
                                    else { strcat(dst, " "); }
                                    render_inline(dst, L);
                                }
                            }
                        }
                    }
                }
            }
        }
        i = i + ln + 1;
    }
    if INCODE == 1 { strcat(dst, "</code></pre>\n"); INCODE = 0; }
    if in_para == 1 { strcat(dst, "</p>\n"); }
    return 0;
}

# ---------------- HTML 页面 ----------------

fn page_head(dst: i64, t: i64) -> i64 {
    strcat(dst, "<!doctype html><html><head><meta charset=\"utf-8\">\n");
    strcat(dst, "<title>");
    esc_append(dst, t);
    strcat(dst, "</title>\n");
    strcat(dst, "<style>body{max-width:44rem;margin:2rem auto;padding:0 1rem;");
    strcat(dst, "font-family:system-ui,sans-serif;line-height:1.65}");
    strcat(dst, "pre{background:#f5f5f5;padding:.8rem;overflow-x:auto}");
    strcat(dst, "code{font-family:ui-monospace,monospace}</style>\n");
    strcat(dst, "</head><body>\n");
    return 0;
}

fn page_foot(dst: i64) -> i64 {
    strcat(dst, "\n<hr><p><em>由墨语言 site.mo 生成</em></p>\n");
    strcat(dst, "</body></html>\n");
    return 0;
}

# ---------------- 输出 ----------------

fn write_file(path: i64, data: i64) -> i64 {
    let fd: i64 = fopen(path, 577, 420);
    if fd < 0 { return -1; }
    fwrite(fd, data, strlen(data));
    fclose(fd);
    return 0;
}

# slug：文件名去扩展名
fn make_slug(dst: i64, fname: i64) -> i64 {
    strcpy(dst, fname);
    let n: i64 = strlen(dst);
    let i: i64 = n - 1;
    while i >= 0 {
        if load8(dst + i) == 46 {
            store8(dst + i, 0);
            return 0;
        }
        i = i - 1;
    }
    return 0;
}

# ---------------- 主流程 ----------------

fn scan_posts() -> i64 {
    V_TITLE = vec_new();
    V_DATE = vec_new();
    V_SLUG = vec_new();
    V_FILE = vec_new();
    let fd: i64 = dir_open(&SRC);
    if fd < 0 { return die("cannot open source directory"); }
    let name: [256] byte = 0;
    let ty: i64 = 0;
    # 注意 dir_next 的返回约定：1 = 取到一个条目，0 = 遍历结束。
    # 与"0 表示成功"的直觉相反，写反了会静默得到空列表。
    while dir_next(&name, &ty) == 1 {
        if str_ends_with(&name, ".md") == 1 {
            vec_push(V_FILE, str_dup(&name));
        }
    }
    dir_close();
    return 0;
}

fn load_post(fname: i64) -> i64 {
    path_join(&PATH, &SRC, fname);
    store8(&TITLE, 0);
    store8(&DATE, 0);
    let n: i64 = read_file(&PATH, &BODY, 16383);
    if n < 0 { return -1; }
    store8(&BODY + n, 0);
    let st: i64 = parse_front(&BODY);
    if strlen(&TITLE) == 0 { strcpy(&TITLE, "(untitled)"); }
    if strlen(&DATE) == 0 { strcpy(&DATE, "1970-01-01"); }
    return st;
}

fn emit_one(fname: i64) -> i64 {
    if load_post(fname) < 0 { return -1; }
    let slug: [128] byte = 0;
    make_slug(&slug, fname);
    store8(&HTML, 0);
    page_head(&HTML, &TITLE);
    strcat(&HTML, "<h1>");
    esc_append(&HTML, &TITLE);
    strcat(&HTML, "</h1>\n<p><small>");
    esc_append(&HTML, &DATE);
    strcat(&HTML, "</small></p>\n");
    render_body(&HTML, &BODY + parse_front(&BODY));
    strcat(&HTML, "<p><a href=\"../index.html\">← 返回</a></p>");
    page_foot(&HTML);

    path_join(&PATH, &OUT, "posts");
    mkdir(&PATH, 493);
    path_join(&PATH, &PATH, &slug);
    strcat(&PATH, ".html");
    if write_file(&PATH, &HTML) < 0 { return -1; }
    return 0;
}

# 按日期字符串升序排（插入排序，规模小）。
# 目录遍历顺序**不是**日期顺序，只是倒着遍历也不等于排序 ——
# 实测就把 10-05 排到了 10-09 后面。必须真的比一次。
# 四个 vec 是平行数组，交换时四个一起换。
fn sort_posts() -> i64 {
    let n: i64 = vec_len(V_DATE);
    let i: i64 = 1;
    while i < n {
        let kd: i64 = vec_get(V_DATE, i);
        let kt: i64 = vec_get(V_TITLE, i);
        let ks: i64 = vec_get(V_SLUG, i);
        let kf: i64 = vec_get(V_FILE, i);
        let j: i64 = i - 1;
        while j >= 0 {
            if strcmp(vec_get(V_DATE, j), kd) <= 0 { break; }
            vec_set(V_DATE, j + 1, vec_get(V_DATE, j));
            vec_set(V_TITLE, j + 1, vec_get(V_TITLE, j));
            vec_set(V_SLUG, j + 1, vec_get(V_SLUG, j));
            vec_set(V_FILE, j + 1, vec_get(V_FILE, j));
            j = j - 1;
        }
        vec_set(V_DATE, j + 1, kd);
        vec_set(V_TITLE, j + 1, kt);
        vec_set(V_SLUG, j + 1, ks);
        vec_set(V_FILE, j + 1, kf);
        i = i + 1;
    }
    return 0;
}

fn emit_index() -> i64 {
    store8(&HTML, 0);
    page_head(&HTML, "文章索引");
    strcat(&HTML, "<h1>文章索引</h1>\n<ul>\n");
    let n: i64 = vec_len(V_TITLE);
    # 倒序：最新的在前。文件名按 YYYY-MM-DD- 开头，所以字符串倒序即日期倒序
    let i: i64 = n - 1;
    while i >= 0 {
        let t: i64 = vec_get(V_TITLE, i);
        let d: i64 = vec_get(V_DATE, i);
        let s: i64 = vec_get(V_SLUG, i);
        let d2: i64 = esc_str(d);
        let s3: i64 = esc_str(s);
        let t3: i64 = esc_str(t);
        sfmt(&HTML, f"<li><small>{ptr(d2)}</small> <a href=\"posts/{ptr(s3)}.html\">{ptr(t3)}</a></li>\n");
        i = i - 1;
    }
    strcat(&HTML, "</ul>\n");
    page_foot(&HTML);
    path_join(&PATH, &OUT, "index.html");
    return write_file(&PATH, &HTML);
}

fn emit_rss() -> i64 {
    store8(&HTML, 0);
    strcat(&HTML, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    strcat(&HTML, "<rss version=\"2.0\"><channel>\n");
    strcat(&HTML, "<title>文章索引</title>\n");
    strcat(&HTML, "<description>由墨语言生成</description>\n");
    let n: i64 = vec_len(V_TITLE);
    let i: i64 = n - 1;
    while i >= 0 {
        let t2: i64 = esc_str(vec_get(V_TITLE, i));
        let s2: i64 = esc_str(vec_get(V_SLUG, i));
        sfmt(&HTML, f"<item><title>{ptr(t2)}</title><link>posts/{ptr(s2)}.html</link></item>\n");
        i = i - 1;
    }
    strcat(&HTML, "</channel></rss>\n");
    path_join(&PATH, &OUT, "rss.xml");
    return write_file(&PATH, &HTML);
}

fn main() -> i64 {
    if argc() < 3 {
        print("usage: site <posts目录> <输出目录>\n");
        return 2;
    }
    strcpy(&SRC, argv(1));
    strcpy(&OUT, argv(2));
    heap_init();
    mkdir(&OUT, 493);

    if scan_posts() != 0 { return 1; }
    let n: i64 = vec_len(V_FILE);
    if n == 0 { return die("source directory has no .md files"); }

    # 文件名以 YYYY-MM-DD- 开头，字符串升序 = 日期升序
    let i: i64 = 0;
    while i < n {
        let f: i64 = vec_get(V_FILE, i);
        if load_post(f) < 0 { return die("cannot read a post"); }
        vec_push(V_TITLE, str_dup(&TITLE));
        vec_push(V_DATE, str_dup(&DATE));
        let slug: [128] byte = 0;
        make_slug(&slug, f);
        vec_push(V_SLUG, str_dup(&slug));
        i = i + 1;
    }

    i = 0;
    while i < n {
        if emit_one(vec_get(V_FILE, i)) < 0 { return die("cannot write a post"); }
        i = i + 1;
    }
    sort_posts();
    if emit_index() < 0 { return die("cannot write index"); }
    if emit_rss() < 0 { return die("cannot write rss"); }
    print("生成完成：");
    print_i64(n);
    print(" 篇文章 -> ");
    print(&OUT);
    print_nl();
    return 0;
}
