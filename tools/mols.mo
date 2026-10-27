# mols.mo —— 墨语言的 Language Server（用墨语言自己写的）
#
# 为什么必须换成墨语言实现：
#   「自包含生态」要求编辑器智能提示也不借别人的手。此前 tools/mols.py
#   是 Python 写的 —— 工具链里最大的一块外部依赖。
#
# 能力（与 mols.py 对齐，用同一套 tools/lsptest.py 验证）：
#   1. 诊断 —— 调用真 moc 编译当前文件，把 file:line:col: error: 解析成
#      编辑器内联波浪线
#   2. 索引 —— 扫源码提取符号，供跳转 / 悬停 / 大纲 / 引用
#   3. 语义高亮 —— 区分关键字 / 类型 / 函数名 / 数字 / 字符串 / 注释
#
# ⚠️ 已知限制（不假装支持）：
#   - 诊断是整文件编译，不做增量
#   - 索引不做作用域消解，同名局部变量会有多个候选
#   - 没有自动补全（需要类型推导）
import "str.mo";
import "io.mo";
import "fs.mo";
import "json.mo";

# ============================================================ 缓冲

var MAXS: i64 = 1024;
var SNM: [32768] byte = 0;       # 1024 * 32
var SDT: [65536] byte = 0;       # 1024 * 64
var SKIND: [1024] i64 = 0;
var SLINE: [1024] i64 = 0;
var SCOL: [1024] i64 = 0;
var SURI: [1024] i64 = 0;
var NS: i64 = 0;
var NSDOC: i64 = 0;
var CURU: i64 = 0;

var UTAB: [4096] byte = 0;       # 8 * 512
var NU: i64 = 0;

var DOC: [32768] byte = 0;
var DOCN: i64 = 0;
var LIBT: [32768] byte = 0;

var TXT: i64 = 0;                # 当前正在索引的文本
var TXTN: i64 = 0;
var LOFF: [2048] i64 = 0;
var LLEN: [2048] i64 = 0;
var NLINE: i64 = 0;

var LN: [4096] byte = 0;         # 行原文
var CODE: [4096] byte = 0;       # 去掉行注释后的行
var CODEN: i64 = 0;

var LIBN: [4096] byte = 0;       # 8 * 512，import 的库名
var NLIB: i64 = 0;

var OUT: [65536] byte = 0;
var OUTN: i64 = 0;
var OHDR: [64] byte = 0;
var TB: [64] byte = 0;
var TB2: [512] byte = 0;
var ARGS: [512] byte = 0;
var TY: [128] byte = 0;

var INB: [65536] byte = 0;
var INP: i64 = 0;
var INL: i64 = 0;
var BODY: [65536] byte = 0;
var HDR: [512] byte = 0;

var METH: [64] byte = 0;
var REQURI: [512] byte = 0;
var POSL: i64 = 0;
var POSC: i64 = 0;
var MSID: i64 = 0;
var HASID: i64 = 0;

var ROOTP: [512] byte = 0;
var LIBDIR: [512] byte = 0;
var MOCP: [512] byte = 0;
var TMPD: [512] byte = 0;
var CAP: [32768] byte = 0;
var CAPN: i64 = 0;
var ST: i64 = 0;
var SYMRC: i64 = 0;

# ============================================================ 输出

fn o_reset() -> i64 {
    OUTN = 0;
    return 0;
}

fn o_c(c: i64) -> i64 {
    store8(&OUT + OUTN, c);
    OUTN = OUTN + 1;
    return 0;
}

fn o_str(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        store8(&OUT + OUTN, c);
        OUTN = OUTN + 1;
        i = i + 1;
        c = load8(s + i);
    }
    return 0;
}

fn o_int(v: i64) -> i64 {
    let n: i64 = utoa(v, &TB, 10);
    return o_str(&TB);
}

# JSON 字符串转义：引号 / 反斜杠 / 换行 / 制表 / 回车
fn o_esc_c(c: i64) -> i64 {
    if c == 34 { o_c(92); o_c(34); return 0; }
    if c == 92 { o_c(92); o_c(92); return 0; }
    if c == 10 { o_c(92); o_c(110); return 0; }
    if c == 9  { o_c(92); o_c(116); return 0; }
    if c == 13 { o_c(92); o_c(114); return 0; }
    o_c(c);
    return 0;
}

fn o_esc(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        o_esc_c(c);
        i = i + 1;
        c = load8(s + i);
    }
    return 0;
}

fn flush_msg() -> i64 {
    strcpy(&OHDR, "Content-Length: ");
    strcat_i64(&OHDR, OUTN);
    let l: i64 = strlen(&OHDR);
    store8(&OHDR + l, 13);
    store8(&OHDR + l + 1, 10);
    store8(&OHDR + l + 2, 13);
    store8(&OHDR + l + 3, 10);
    store8(&OHDR + l + 4, 0);
    syscall(1, 1, &OHDR, strlen(&OHDR), 0, 0, 0);
    syscall(1, 1, &OUT, OUTN, 0, 0, 0);
    return 0;
}

# ============================================================ 输入

fn rd_ch() -> i64 {
    if INP >= INL {
        INL = syscall(0, 0, &INB, 65536, 0, 0, 0);
        INP = 0;
        if INL <= 0 { return 0 - 1; }
    }
    let c: i64 = load8(&INB + INP);
    INP = INP + 1;
    return c;
}

# 读一行（吃掉 \n，去掉行尾 \r），返回长度；EOF 返回 -1
fn rd_line(dst: i64) -> i64 {
    let n: i64 = 0;
    let c: i64 = rd_ch();
    if c < 0 { return 0 - 1; }
    while c != 10 {
        if c < 0 {
            store8(dst + n, 0);
            return n;
        }
        if c != 13 {
            store8(dst + n, c);
            n = n + 1;
        }
        c = rd_ch();
    }
    store8(dst + n, 0);
    return n;
}

# JSON 字符串结束位置（处理 \\ 转义），p 指向开头引号
fn jstr_end(s: i64, p: i64) -> i64 {
    let e: i64 = p + 1;
    let c: i64 = load8(s + e);
    while c != 0 {
        if c == 92 {
            e = e + 2;
            c = load8(s + e);
        } else {
            if c == 34 { return e; }
            e = e + 1;
            c = load8(s + e);
        }
    }
    return e;
}

# 反转义：\\n \\t \\r \\\\ \\" \\uXXXX(按 4 字节跳过)
fn unesc(dst: i64, src: i64, n: i64) -> i64 {
    let i: i64 = 0;
    let o: i64 = 0;
    let c: i64 = 0;
    let d: i64 = 0;
    while i < n {
        c = load8(src + i);
        if c == 92 {
            d = load8(src + i + 1);
            if d == 110 { store8(dst + o, 10); i = i + 2; o = o + 1; }
            else {
                if d == 116 { store8(dst + o, 9); i = i + 2; o = o + 1; }
                else {
                    if d == 114 { store8(dst + o, 13); i = i + 2; o = o + 1; }
                    else {
                        if d == 117 { store8(dst + o, 63); i = i + 6; o = o + 1; }
                        else { store8(dst + o, d); i = i + 2; o = o + 1; }
                    }
                }
            }
        } else {
            store8(dst + o, c);
            i = i + 1;
            o = o + 1;
        }
    }
    store8(dst + o, 0);
    return o;
}

fn jget(key: i64, dst: i64) -> i64 {
    let p: i64 = find_key(&BODY, key, 0);
    if p < 0 { store8(dst, 0); return 0 - 1; }
    let e: i64 = jstr_end(&BODY, p);
    return unesc(dst, &BODY + p + 1, e - p - 1);
}

fn jint(key: i64) -> i64 {
    return json_int(&BODY, key);
}

fn jhas(key: i64) -> i64 {
    let p: i64 = find_key(&BODY, key, 0);
    if p < 0 { return 0; }
    return 1;
}

# ============================================================ 字符与行

fn is_al(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c >= 48 { if c <= 57 { return 1; } }
    if c == 95 { return 1; }
    return 0;
}

fn is_al_start(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c == 95 { return 1; }
    return 0;
}

fn is_dig(c: i64) -> i64 {
    if c >= 48 { if c <= 57 { return 1; } }
    return 0;
}

fn is_sp(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    return 0;
}

# s[i..] 是否以 kw 开头（且后一个字符不是标识符字符），返回结束下标或 0
fn kw_at(s: i64, i: i64, kw: i64) -> i64 {
    let j: i64 = 0;
    while load8(kw + j) != 0 {
        if load8(s + i + j) != load8(kw + j) { return 0; }
        j = j + 1;
    }
    if is_al(load8(s + i + j)) == 1 { return 0; }
    return i + j;
}

fn skip_sp(s: i64, i: i64) -> i64 {
    let c: i64 = load8(s + i);
    while is_sp(c) == 1 {
        i = i + 1;
        c = load8(s + i);
    }
    return i;
}

fn ident_copy(s: i64, i: i64, dst: i64) -> i64 {
    let j: i64 = 0;
    if is_al_start(load8(s + i)) == 0 { return 0 - 1; }
    while is_al(load8(s + i + j)) == 1 {
        store8(dst + j, load8(s + i + j));
        j = j + 1;
    }
    store8(dst + j, 0);
    return i + j;
}

fn set_txt(p: i64, n: i64) -> i64 {
    TXT = p;
    TXTN = n;
    return 0;
}

fn txt_split() -> i64 {
    NLINE = 0;
    let i: i64 = 0;
    let st: i64 = 0;
    while i <= TXTN {
        if i == TXTN {
            if NLINE < 2048 {
                LOFF[NLINE] = st;
                LLEN[NLINE] = i - st;
                NLINE = NLINE + 1;
            }
            i = i + 1;
        } else {
            if load8(TXT + i) == 10 {
                if NLINE < 2048 {
                    LOFF[NLINE] = st;
                    LLEN[NLINE] = i - st;
                    NLINE = NLINE + 1;
                }
                i = i + 1;
                st = i;
            } else {
                i = i + 1;
            }
        }
    }
    return NLINE;
}

fn line_copy(ln: i64, dst: i64) -> i64 {
    let n: i64 = LLEN[ln];
    let i: i64 = 0;
    if n > 4095 { n = 4095; }
    while i < n {
        store8(dst + i, load8(TXT + LOFF[ln] + i));
        i = i + 1;
    }
    store8(dst + n, 0);
    return n;
}

# 去掉行注释。**不能**简单找第一个 # —— 字符串里的 # 要保留。
fn strip_cmt(s: i64, dst: i64) -> i64 {
    let i: i64 = 0;
    let o: i64 = 0;
    let instr: i64 = 0;
    let c: i64 = 0;
    let prev: i64 = 0;
    while load8(s + i) != 0 {
        c = load8(s + i);
        prev = 0;
        if i > 0 { if load8(s + i - 1) == 92 { prev = 1; } }
        if c == 34 { if prev == 0 { instr = 1 - instr; } }
        if c == 35 {
            if instr == 0 {
                store8(dst + o, 0);
                return o;
            }
        }
        store8(dst + o, c);
        o = o + 1;
        i = i + 1;
    }
    store8(dst + o, 0);
    return o;
}

# ============================================================ 符号表

fn uri_add(s: i64) -> i64 {
    let i: i64 = 0;
    while i < NU {
        if streq(&UTAB + i * 512, s) == 1 { return i; }
        i = i + 1;
    }
    if NU >= 8 { return 0; }
    strcpy(&UTAB + NU * 512, s);
    NU = NU + 1;
    return NU - 1;
}

fn sym_add(name: i64, kind: i64, line: i64, col: i64, detail: i64) -> i64 {
    if NS >= MAXS { return 0 - 1; }
    let nb: i64 = NS * 32;
    let db: i64 = NS * 64;
    strcpy(&SNM + nb, name);
    strcpy(&SDT + db, detail);
    SKIND[NS] = kind;
    SLINE[NS] = line;
    SCOL[NS] = col;
    SURI[NS] = CURU;
    NS = NS + 1;
    return NS - 1;
}

# kind: 1=function 2=class 3=struct 4=enum 5=enumMember 6=variable

# ============================================================ 索引

fn idx_imports() -> i64 {
    NLIB = 0;
    let ln: i64 = 0;
    let p: i64 = 0;
    let e: i64 = 0;
    let q: i64 = 0;
    let r: i64 = 0;
    while ln < NLINE {
        line_copy(ln, &LN);
        strip_cmt(&LN, &CODE);
        p = skip_sp(&CODE, 0);
        e = kw_at(&CODE, p, "import");
        if e > 0 {
            q = skip_sp(&CODE, e);
            if load8(&CODE + q) == 34 {
                r = q + 1;
                while load8(&CODE + r) != 0 {
                    if load8(&CODE + r) == 34 { break; }
                    r = r + 1;
                }
                if NLIB < 8 {
                    let k: i64 = 0;
                    while q + 1 + k < r {
                        store8(&LIBN + NLIB * 512 + k, load8(&CODE + q + 1 + k));
                        k = k + 1;
                    }
                    store8(&LIBN + NLIB * 512 + k, 0);
                    NLIB = NLIB + 1;
                }
            }
        }
        ln = ln + 1;
    }
    return NLIB;
}

# 解析 [start, end) 内的一个整数字面量，返回结束下标；值放 IVAL
var IVAL: i64 = 0;
fn num_at(s: i64, i: i64, end: i64) -> i64 {
    let neg: i64 = 0;
    let v: i64 = 0;
    let j: i64 = skip_sp(s, i);
    IVAL = 0;
    if load8(s + j) == 45 { neg = 1; j = j + 1; }
    if is_dig(load8(s + j)) == 0 { return 0 - 1; }
    while j < end {
        if is_dig(load8(s + j)) == 0 { break; }
        v = v * 10 + (load8(s + j) - 48);
        j = j + 1;
    }
    if neg == 1 { v = 0 - v; }
    IVAL = v;
    return j;
}

# 枚举成员：从声明行本身开始扫（成员可能就写在同一行）
fn idx_enum(ln: i64, brace: i64, ename: i64) -> i64 {
    let k: i64 = ln;
    let done: i64 = 0;
    let auto: i64 = 0;
    let start: i64 = 0;
    let bend: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let r: i64 = 0;
    let c: i64 = 0;
    while k < NLINE {
        if done == 1 { k = NLINE; } else {
        line_copy(k, &LN);
        strip_cmt(&LN, &CODE);
        CODEN = strlen(&CODE);
        start = 0;
        if k == ln { start = brace + 1; }
        bend = CODEN;
        p = start;
        while p < CODEN {
            if load8(&CODE + p) == 125 { bend = p; done = 1; p = CODEN; }
            p = p + 1;
        }
        p = start;
        while p < bend {
            c = load8(&CODE + p);
            if is_sp(c) == 1 { p = p + 1; }
            else {
                if c == 44 { p = p + 1; }
                else {
                    if is_al_start(c) == 0 { p = p + 1; }
                    else {
                        q = ident_copy(&CODE, p, &TB2);
                        if q < 0 { p = p + 1; } else {
                            r = skip_sp(&CODE, q);
                            if r < bend {
                                if load8(&CODE + r) == 61 {
                                    r = num_at(&CODE, r + 1, bend);
                                    if r < 0 { auto = auto; } else { auto = IVAL; }
                                }
                            }
                            # 跳过到下一个 ';'
                            while r < bend {
                                if load8(&CODE + r) == 59 { break; }
                                r = r + 1;
                            }
                            strcpy(&TB, &TB2);
                            strcat(&TB, " = ");
                            strcat_i64(&TB, auto);
                            sym_add(&TB2, 5, k, p, &TB);
                            auto = auto + 1;
                            if r < bend { p = r + 1; } else { p = bend; }
                        }
                    }
                }
            }
        }
        k = k + 1;
        }
    }
    return 0;
}

# 结构体 / 类字段：NAME : TYPE ;
fn idx_fields(ln: i64, brace: i64, tn: i64) -> i64 {
    let k: i64 = ln;
    let done: i64 = 0;
    let start: i64 = 0;
    let bend: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let r: i64 = 0;
    let c: i64 = 0;
    while k < NLINE {
        if done == 1 { k = NLINE; } else {
        line_copy(k, &LN);
        strip_cmt(&LN, &CODE);
        CODEN = strlen(&CODE);
        start = 0;
        if k == ln { start = brace + 1; }
        bend = CODEN;
        p = start;
        while p < CODEN {
            if load8(&CODE + p) == 125 { bend = p; done = 1; p = CODEN; }
            p = p + 1;
        }
        p = start;
        while p < bend {
            c = load8(&CODE + p);
            if is_sp(c) == 1 { p = p + 1; }
            else {
                if c == 59 { p = p + 1; }
                else {
                    if c == 44 { p = p + 1; }
                    else {
                        if is_al_start(c) == 0 { p = p + 1; }
                        else {
                            q = ident_copy(&CODE, p, &TB2);
                            if q < 0 { p = p + 1; } else {
                                r = skip_sp(&CODE, q);
                                if r < bend {
                                    if load8(&CODE + r) == 58 {
                                        r = skip_sp(&CODE, r + 1);
                                        let te: i64 = ident_copy(&CODE, r, &TB);
                                        if te > 0 {
                                            sym_add(&TB2, 6, k, p, &TB);
                                            r = te;
                                        }
                                    }
                                }
                                while r < bend {
                                    if load8(&CODE + r) == 59 { break; }
                                    r = r + 1;
                                }
                                if r < bend { p = r + 1; } else { p = bend; }
                            }
                        }
                    }
                }
            }
        }
        k = k + 1;
        }
    }
    return 0;
}

# 函数参数：a: i64, b: i64
fn idx_params(ln: i64, astart: i64, aend: i64) -> i64 {
    let p: i64 = astart;
    let q: i64 = 0;
    let r: i64 = 0;
    while p < aend {
        if is_al_start(load8(&CODE + p)) == 1 {
            q = ident_copy(&CODE, p, &TB2);
            r = skip_sp(&CODE, q);
            if r < aend {
                if load8(&CODE + r) == 58 {
                    r = skip_sp(&CODE, r + 1);
                    let te: i64 = ident_copy(&CODE, r, &TB);
                    if te > 0 {
                        strcat(&TB, " (param)");
                        sym_add(&TB2, 6, ln, p, &TB);
                        p = te;
                    } else { p = q; }
                } else { p = q; }
            } else { p = q; }
        } else {
            p = p + 1;
        }
    }
    return 0;
}

# 一行里的 fn / var / let / struct / class / enum
fn idx_line(ln: i64) -> i64 {
    let p: i64 = 0;
    let e: i64 = 0;
    let q: i64 = 0;
    let r: i64 = 0;
    let t: i64 = 0;
    let ne: i64 = 0;
    let te: i64 = 0;
    let astart: i64 = 0;
    let aend: i64 = 0;
    p = skip_sp(&CODE, 0);
    e = kw_at(&CODE, p, "fn");
    if e > 0 {
        q = skip_sp(&CODE, e);
        ne = ident_copy(&CODE, q, &TB2);
        if ne > 0 {
            r = skip_sp(&CODE, ne);
            if load8(&CODE + r) == 40 {
                astart = r + 1;
                aend = r + 1;
                while load8(&CODE + aend) != 0 {
                    if load8(&CODE + aend) == 41 { break; }
                    aend = aend + 1;
                }
                let k: i64 = astart;
                let alen: i64 = aend - astart;
                strcpy(&ARGS, "");
                while k < aend {
                    store8(&ARGS + (k - astart), load8(&CODE + k));
                    k = k + 1;
                }
                store8(&ARGS + alen, 0);
                let s2: i64 = skip_sp(&CODE, aend + 1);
                if load8(&CODE + s2) == 45 {
                    if load8(&CODE + s2 + 1) == 62 {
                        t = skip_sp(&CODE, s2 + 2);
                        te = ident_copy(&CODE, t, &TY);
                        if te > 0 {
                            strcpy(&TB, "fn ");
                            strcat(&TB, &TB2);
                            strcat(&TB, "(");
                            strcat(&TB, &ARGS);
                            strcat(&TB, ") -> ");
                            strcat(&TB, &TY);
                            sym_add(&TB2, 1, ln, q, &TB);
                            idx_params(ln, astart, aend);
                            return 0;
                        }
                    }
                }
                strcpy(&TB, "fn ");
                strcat(&TB, &TB2);
                strcat(&TB, "(");
                strcat(&TB, &ARGS);
                strcat(&TB, ")");
                sym_add(&TB2, 1, ln, q, &TB);
                idx_params(ln, astart, aend);
                return 0;
            }
        }
    }
    e = kw_at(&CODE, p, "struct");
    if e > 0 { return idx_type(ln, e, 3, "struct"); }
    e = kw_at(&CODE, p, "class");
    if e > 0 { return idx_type(ln, e, 2, "class"); }
    e = kw_at(&CODE, p, "enum");
    if e > 0 { return idx_type(ln, e, 4, "enum"); }
    e = kw_at(&CODE, p, "var");
    if e > 0 { return idx_varlet(ln, e, "var"); }
    e = kw_at(&CODE, p, "let");
    if e > 0 { return idx_varlet(ln, e, "let"); }
    return 0;
}

fn idx_type(ln: i64, e: i64, kind: i64, kw: i64) -> i64 {
    let q: i64 = skip_sp(&CODE, e);
    let ne: i64 = ident_copy(&CODE, q, &TB2);
    if ne < 0 { return 0; }
    strcpy(&TB, kw);
    strcat(&TB, " ");
    strcat(&TB, &TB2);
    sym_add(&TB2, kind, ln, q, &TB);
    let r: i64 = skip_sp(&CODE, ne);
    if load8(&CODE + r) == 123 {
        if kind == 4 { idx_enum(ln, r, &TB2); } else { idx_fields(ln, r, &TB2); }
    }
    return 0;
}

# var NAME: TYPE —— 类型读到 '=' 或 ';' 为止
fn idx_varlet(ln: i64, e: i64, kw: i64) -> i64 {
    let q: i64 = skip_sp(&CODE, e);
    let ne: i64 = ident_copy(&CODE, q, &TB2);
    if ne < 0 { return 0; }
    let r: i64 = skip_sp(&CODE, ne);
    if load8(&CODE + r) != 58 { return 0; }
    r = skip_sp(&CODE, r + 1);
    let o: i64 = 0;
    let c: i64 = load8(&CODE + r);
    while c != 0 {
        if c == 59 { break; }
        if c == 61 { break; }
        store8(&TY + o, c);
        o = o + 1;
        r = r + 1;
        c = load8(&CODE + r);
    }
    store8(&TY + o, 0);
    let i: i64 = strlen(&TY) - 1;
    while i >= 0 {
        if is_sp(load8(&TY + i)) == 1 { store8(&TY + i, 0); i = i - 1; } else { i = 0 - 1; }
    }
    strcpy(&TB, kw);
    strcat(&TB, " ");
    strcat(&TB, &TB2);
    strcat(&TB, ": ");
    strcat(&TB, &TY);
    sym_add(&TB2, 6, ln, q, &TB);
    return 0;
}

fn index_pass() -> i64 {
    let ln: i64 = 0;
    while ln < NLINE {
        line_copy(ln, &LN);
        strip_cmt(&LN, &CODE);
        CODEN = strlen(&CODE);
        idx_line(ln);
        ln = ln + 1;
    }
    return 0;
}

fn reindex() -> i64 {
    NS = 0;
    NSDOC = 0;
    NU = 0;
    CURU = uri_add(&REQURI);
    set_txt(&DOC, DOCN);
    txt_split();
    idx_imports();
    index_pass();
    NSDOC = NS;
    # 索引 import 的库（只跟一层，与 mols.py 一致）
    let i: i64 = 0;
    while i < NLIB {
        let lp: i64 = 0;
        lp = lib_path(&LIBN + i * 512);
        if lp == 0 { i = i + 1; } else {
            let n: i64 = read_file(lp, &LIBT, 32767);
            if n > 0 {
                store8(&LIBT + n, 0);
                CURU = uri_add(lp);
                set_txt(&LIBT, n);
                txt_split();
                index_pass();
            }
            i = i + 1;
        }
    }
    return NS;
}

# import "io.mo" → <root>/lib/io.mo 或 <root>/io.mo
fn lib_path(name: i64) -> i64 {
    strcpy(&TB, &ROOTP);
    strcat(&TB, "/lib/");
    strcat(&TB, name);
    let fd: i64 = fopen(&TB, 0, 0);
    if fd >= 0 {
        fclose(fd);
        return &TB;
    }
    strcpy(&TB, &ROOTP);
    strcat(&TB, "/");
    strcat(&TB, name);
    fd = fopen(&TB, 0, 0);
    if fd >= 0 {
        fclose(fd);
        return &TB;
    }
    return 0;
}

# ============================================================ 诊断

fn cap_run() -> i64 {
    CAPN = 0;
    let pid: i64 = syscall(39, 0, 0, 0, 0, 0, 0);
    strcpy(&TMPD, "/tmp/mols-");
    strcat_i64(&TMPD, pid);
    syscall(83, &TMPD, 493, 0, 0, 0);
    # 写 test.mo —— 🔴 moc 的 inpath 硬编码为 "test.mo"，
    #    用别的名字会输出 "cannot open input"，于是任何文件都是 0 条诊断
    strcpy(&TB, &TMPD);
    strcat(&TB, "/test.mo");
    let fd: i64 = fopen(&TB, 577, 420);
    if fd < 0 { return 0 - 1; }
    fwrite(fd, &DOC, DOCN);
    fclose(fd);
    # lib 软链：moc 的 import 解析依赖 cwd
    strcpy(&TB2, &TMPD);
    strcat(&TB2, "/lib");
    SYMRC = syscall(88, &LIBDIR, &TB2, 0, 0, 0, 0);
    let raw: [8] byte = 0;
    let fds: [2] i64 = 0;
    let r: i64 = syscall(22, &raw, 0, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    let v: i64 = load64(&raw);
    store64(&fds, v & 4294967295);
    store64(&fds + 8, (v / 4294967296) & 4294967295);
    let ch: i64 = syscall(57, 0, 0, 0, 0, 0, 0);
    if ch == 0 {
        syscall(3, fds[0], 0, 0, 0, 0, 0);
        syscall(33, fds[1], 1, 0, 0, 0, 0);
        syscall(33, fds[1], 2, 0, 0, 0, 0);
        syscall(3, fds[1], 0, 0, 0, 0, 0);
        syscall(80, &TMPD, 0, 0, 0, 0, 0);
        let av: [2] i64 = 0;
        store64(&av, &MOCP);
        store64(&av + 8, 0);
        syscall(59, &MOCP, &av, 0, 0, 0, 0);
        syscall(60, 127, 0, 0, 0, 0, 0);
    }
    syscall(3, fds[1], 0, 0, 0, 0, 0);
    let buf: [4096] byte = 0;
    let n: i64 = 0;
    while 1 {
        n = syscall(0, fds[0], &buf, 4096, 0, 0, 0);
        if n <= 0 { break; }
        if CAPN + n < 32760 {
            memcpy(&CAP + CAPN, &buf, n);
            CAPN = CAPN + n;
        }
    }
    store8(&CAP + CAPN, 0);
    syscall(3, fds[0], 0, 0, 0, 0, 0);
    syscall(61, ch, &ST, 0, 0, 0, 0);
    # 清理
    strcpy(&TB, &TMPD);
    strcat(&TB, "/lib");
    syscall(87, &TB, 0, 0, 0, 0);
    strcpy(&TB, &TMPD);
    strcat(&TB, "/test.mo");
    syscall(87, &TB, 0, 0, 0, 0);
    syscall(84, &TMPD, 0, 0, 0, 0);
    return 0;
}

# 解析 file:line:col: error: msg
fn diag_emit() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let ln: i64 = 0;
    let col: i64 = 0;
    let first: i64 = 1;
    let p: i64 = 0;
    let q: i64 = 0;
    let l0: i64 = 0;
    let l1: i64 = 0;
    let c0: i64 = 0;
    let c1: i64 = 0;
    let s: i64 = 0;
    let sev: i64 = 0;
    let m0: i64 = 0;
    let m1: i64 = 0;
    let e: i64 = 0;
    let k: i64 = 0;
    o_str("{\"uri\":\"");
    o_esc(&REQURI);
    o_str("\",\"diagnostics\":[");
    # "cannot open input" = 工具问题，不是代码错误，必须区分开
    let bad: i64 = 0;
    if strstr(&CAP, "cannot open input") >= 0 { bad = 1; }
    if strstr(&CAP, "cannot open import") >= 0 { bad = 1; }
    if bad == 1 {
        o_str("{\"range\":{\"start\":{\"line\":0,\"character\":0},");
        o_str("\"end\":{\"line\":0,\"character\":1}},");
        o_str("\"severity\":2,\"source\":\"mols\",\"message\":");
        o_c(34);
        o_str("mols: moc 打不开输入或 import 的库（这是工具问题，非代码错误）");
        o_c(34);
        o_str("}]}");
        return 1;
    }
    i = 0;
    while i < CAPN {
        # 找行首
        p = i;
        # 第一个 ':'
        q = p;
        while q < CAPN {
            if load8(&CAP + q) == 58 { break; }
            if load8(&CAP + q) == 10 { break; }
            q = q + 1;
        }
        if q < CAPN {
            if load8(&CAP + q) == 58 {
                l0 = q + 1;
                l1 = l0;
                while l1 < CAPN {
                    if load8(&CAP + l1) == 58 { break; }
                    if load8(&CAP + l1) == 10 { break; }
                    l1 = l1 + 1;
                }
                if l1 < CAPN {
                    if load8(&CAP + l1) == 58 {
                        c0 = l1 + 1;
                        c1 = c0;
                        while c1 < CAPN {
                            if load8(&CAP + c1) == 58 { break; }
                            if load8(&CAP + c1) == 10 { break; }
                            c1 = c1 + 1;
                        }
                        if c1 < CAPN {
                            if load8(&CAP + c1) == 58 {
                                # 判断 error / warning
                                s = skip_sp(&CAP, c1 + 1);
                                sev = 0;
                                if kw_at(&CAP, s, "error") > 0 { sev = 1; }
                                if kw_at(&CAP, s, "warning") > 0 { sev = 2; }
                                if sev > 0 {
                                    m0 = s;
                                    while m0 < CAPN {
                                        if load8(&CAP + m0) == 58 { break; }
                                        m0 = m0 + 1;
                                    }
                                    m1 = m0 + 1;
                                    m1 = skip_sp(&CAP, m1);
                                    e = m1;
                                    while e < CAPN {
                                        if load8(&CAP + e) == 10 { break; }
                                        e = e + 1;
                                    }
                                    ln = atoi_at(&CAP, l0, l1);
                                    col = atoi_at(&CAP, c0, c1);
                                    if first == 0 { o_c(44); }
                                    first = 0;
                                    o_str("{\"range\":{\"start\":{\"line\":");
                                    if ln > 0 { o_int(ln - 1); } else { o_int(0); }
                                    o_str(",\"character\":");
                                    if col > 0 { o_int(col - 1); } else { o_int(0); }
                                    o_str("},\"end\":{\"line\":");
                                    if ln > 0 { o_int(ln - 1); } else { o_int(0); }
                                    o_str(",\"character\":");
                                    o_int(col);
                                    o_str("}},\"severity\":");
                                    o_int(sev);
                                    o_str(",\"source\":\"mo\",\"message\":");
                                    o_c(34);
                                    k = m1;
                                    while k < e { o_esc_c(load8(&CAP + k)); k = k + 1; }
                                    o_c(34);
                                    o_str("}");
                                    n = n + 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        # 跳到下一行
        while i < CAPN {
            if load8(&CAP + i) == 10 { break; }
            i = i + 1;
        }
        i = i + 1;
    }
    o_str("]}");
    return n;
}

fn atoi_at(s: i64, a: i64, b: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = a;
    while i < b {
        if is_dig(load8(s + i)) == 1 { v = v * 10 + (load8(s + i) - 48); }
        i = i + 1;
    }
    return v;
}

# ============================================================ 查询

# 取 (line, character) 处的标识符，写入 W
fn word_at(w: i64) -> i64 {
    let s: i64 = 0;
    let lo: i64 = 0;
    let hi: i64 = 0;
    if POSL >= NLINE { return 0; }
    line_copy(POSL, &LN);
    s = strlen(&LN);
    if POSC > s { POSC = s; }
    lo = POSC;
    while lo > 0 {
        if is_al(load8(&LN + lo - 1)) == 1 { lo = lo - 1; } else { lo = lo - 0 - 0; break; }
    }
    hi = POSC;
    while hi < s {
        if is_al(load8(&LN + hi)) == 1 { hi = hi + 1; } else { break; }
    }
    if hi <= lo { return 0; }
    let i: i64 = lo;
    while i < hi {
        store8(w + (i - lo), load8(&LN + i));
        i = i + 1;
    }
    store8(w + (hi - lo), 0);
    return hi - lo;
}

fn emit_range(line: i64, col: i64, len: i64) -> i64 {
    o_str("{\"start\":{\"line\":");
    o_int(line);
    o_str(",\"character\":");
    o_int(col);
    o_str("},\"end\":{\"line\":");
    o_int(line);
    o_str(",\"character\":");
    o_int(col + len);
    o_str("}}");
    return 0;
}

fn basename(s: i64, dst: i64) -> i64 {
    let n: i64 = strlen(s);
    let i: i64 = n - 1;
    let b: i64 = 0;
    while i >= 0 {
        if load8(s + i) == 47 { b = i + 1; i = 0 - 1; } else { i = i - 1; }
    }
    strcpy(dst, s + b);
    return 0;
}

fn do_definition() -> i64 {
    let n: i64 = word_at(&TB2);
    let i: i64 = 0;
    let first: i64 = 1;
    if n <= 0 { o_str("[]"); return 0; }
    o_str("[");
    while i < NS {
        if streq(&SNM + i * 32, &TB2) == 1 {
            if first == 0 { o_c(44); }
            first = 0;
            o_str("{\"uri\":");
            o_c(34);
            o_esc(&UTAB + SURI[i] * 512);
            o_c(34);
            o_str(",\"range\":");
            emit_range(SLINE[i], SCOL[i], strlen(&SNM + i * 32));
            o_str("}");
        }
        i = i + 1;
    }
    o_str("]");
    return 0;
}

fn do_hover() -> i64 {
    let n: i64 = word_at(&TB2);
    let i: i64 = 0;
    if n <= 0 { o_str("null"); return 0; }
    while i < NS {
        if streq(&SNM + i * 32, &TB2) == 1 {
            let kn: i64 = SKIND[i];
            basename(&UTAB + SURI[i] * 512, &TB);
            o_str("{\"contents\":{\"kind\":\"markdown\",\"value\":");
            o_c(34);
            o_str("```mo\\n");
            o_esc(&SDT + i * 64);
            o_str("\\n```\\n\\n");
            if kn == 1 { o_str("function"); }
            if kn == 2 { o_str("class"); }
            if kn == 3 { o_str("struct"); }
            if kn == 4 { o_str("enum"); }
            if kn == 5 { o_str("enumMember"); }
            if kn == 6 { o_str("variable"); }
            o_str(" (");
            o_esc(&TB);
            o_str(")");
            o_c(34);
            o_str("}}");
            return 0;
        }
        i = i + 1;
    }
    o_str("null");
    return 0;
}

fn do_symbols() -> i64 {
    let i: i64 = 0;
    let first: i64 = 1;
    o_str("[");
    while i < NSDOC {
        let nl: i64 = strlen(&SNM + i * 32);
        if first == 0 { o_c(44); }
        first = 0;
        o_str("{\"name\":");
        o_c(34);
        o_esc(&SNM + i * 32);
        o_c(34);
        o_str(",\"kind\":");
        o_int(SKIND[i]);
        o_str(",\"detail\":");
        o_c(34);
        o_esc(&SDT + i * 64);
        o_c(34);
        o_str(",\"range\":");
        emit_range(SLINE[i], 0, nl);
        o_str(",\"selectionRange\":");
        emit_range(SLINE[i], SCOL[i], nl);
        o_str("}");
        i = i + 1;
    }
    o_str("]");
    return 0;
}

fn do_references() -> i64 {
    let n: i64 = word_at(&TB2);
    let first: i64 = 1;
    let ln: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    if n <= 0 { o_str("[]"); return 0; }
    set_txt(&DOC, DOCN);
    txt_split();
    o_str("[");
    while ln < NLINE {
        line_copy(ln, &LN);
        strip_cmt(&LN, &CODE);
        CODEN = strlen(&CODE);
        p = 0;
        while p < CODEN {
            if is_al_start(load8(&CODE + p)) == 1 {
                let q: i64 = ident_copy(&CODE, p, &TB);
                if streq(&TB, &TB2) == 1 {
                    if first == 0 { o_c(44); }
                    first = 0;
                    o_str("{\"uri\":");
                    o_c(34);
                    o_esc(&UTAB + SURI[0] * 512);
                    o_c(34);
                    o_str(",\"range\":");
                    emit_range(ln, p, n);
                    o_str("}");
                }
                p = q;
            } else {
                p = p + 1;
            }
        }
        ln = ln + 1;
    }
    o_str("]");
    return 0;
}

# ============================================================ 语义高亮

fn is_kw(w: i64) -> i64 {
    if streq(w, "fn") == 1 { return 1; }
    if streq(w, "return") == 1 { return 1; }
    if streq(w, "let") == 1 { return 1; }
    if streq(w, "var") == 1 { return 1; }
    if streq(w, "struct") == 1 { return 1; }
    if streq(w, "class") == 1 { return 1; }
    if streq(w, "enum") == 1 { return 1; }
    if streq(w, "import") == 1 { return 1; }
    if streq(w, "if") == 1 { return 1; }
    if streq(w, "else") == 1 { return 1; }
    if streq(w, "while") == 1 { return 1; }
    if streq(w, "break") == 1 { return 1; }
    if streq(w, "continue") == 1 { return 1; }
    if streq(w, "for") == 1 { return 1; }
    if streq(w, "true") == 1 { return 1; }
    if streq(w, "false") == 1 { return 1; }
    return 0;
}

fn is_ty(w: i64) -> i64 {
    if streq(w, "i64") == 1 { return 1; }
    if streq(w, "byte") == 1 { return 1; }
    if streq(w, "ptr") == 1 { return 1; }
    if streq(w, "bool") == 1 { return 1; }
    if streq(w, "f64") == 1 { return 1; }
    return 0;
}

fn is_bi(w: i64) -> i64 {
    if streq(w, "load8") == 1 { return 1; }
    if streq(w, "load16") == 1 { return 1; }
    if streq(w, "load32") == 1 { return 1; }
    if streq(w, "load64") == 1 { return 1; }
    if streq(w, "store8") == 1 { return 1; }
    if streq(w, "store16") == 1 { return 1; }
    if streq(w, "store32") == 1 { return 1; }
    if streq(w, "store64") == 1 { return 1; }
    if streq(w, "syscall") == 1 { return 1; }
    if streq(w, "argc") == 1 { return 1; }
    if streq(w, "argv") == 1 { return 1; }
    if streq(w, "sizeof") == 1 { return 1; }
    if streq(w, "alignof") == 1 { return 1; }
    if streq(w, "print") == 1 { return 1; }
    if streq(w, "print_i64") == 1 { return 1; }
    if streq(w, "strlen") == 1 { return 1; }
    if streq(w, "streq") == 1 { return 1; }
    return 0;
}

fn is_known(w: i64) -> i64 {
    let i: i64 = 0;
    while i < NSDOC {
        if SKIND[i] <= 4 {
            if streq(&SNM + i * 32, w) == 1 { return 1; }
        }
        i = i + 1;
    }
    return 0;
}

fn is_op(c: i64) -> i64 {
    if c == 45 { return 1; }
    if c == 43 { return 1; }
    if c == 42 { return 1; }
    if c == 47 { return 1; }
    if c == 37 { return 1; }
    if c == 61 { return 1; }
    if c == 33 { return 1; }
    if c == 60 { return 1; }
    if c == 62 { return 1; }
    if c == 38 { return 1; }
    if c == 124 { return 1; }
    if c == 94 { return 1; }
    if c == 126 { return 1; }
    return 0;
}

var TK_PL: i64 = 0;
var TK_PC: i64 = 0;

fn tk(ln: i64, ch: i64, len: i64, ty: i64) -> i64 {
    o_int(ln - TK_PL);
    o_c(44);
    if ln == TK_PL { o_int(ch - TK_PC); } else { o_int(ch); }
    o_c(44);
    o_int(len);
    o_c(44);
    o_int(ty);
    o_c(44);
    o_int(0);
    TK_PL = ln;
    TK_PC = ch;
    return 0;
}

fn do_tokens() -> i64 {
    let ln: i64 = 0;
    let i: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let c: i64 = 0;
    let first: i64 = 1;
    let ty: i64 = 0;
    TK_PL = 0;
    TK_PC = 0;
    set_txt(&DOC, DOCN);
    txt_split();
    o_str("{\"data\":[");
    while ln < NLINE {
        line_copy(ln, &LN);
        i = 0;
        c = load8(&LN);
        if c == 32 { }
        p = skip_sp(&LN, 0);
        if load8(&LN + p) == 35 {
            if first == 0 { o_c(44); }
            first = 0;
            tk(ln, p, strlen(&LN) - p, 6);
            ln = ln + 1;
        } else {
            strip_cmt(&LN, &CODE);
            CODEN = strlen(&CODE);
            p = 0;
            while p < CODEN {
                c = load8(&CODE + p);
                if c == 34 {
                    q = p + 1;
                    while q < CODEN {
                        if load8(&CODE + q) == 92 { q = q + 2; } else {
                            if load8(&CODE + q) == 34 { break; }
                            q = q + 1;
                        }
                    }
                    if first == 0 { o_c(44); }
                    first = 0;
                    tk(ln, p, q - p + 1, 5);
                    p = q + 1;
                } else {
                    if is_dig(c) == 1 {
                        q = p;
                        while q < CODEN {
                            if is_dig(load8(&CODE + q)) == 0 { break; }
                            q = q + 1;
                        }
                        if first == 0 { o_c(44); }
                        first = 0;
                        tk(ln, p, q - p, 4);
                        p = q;
                    } else {
                        if is_al_start(c) == 1 {
                            q = ident_copy(&CODE, p, &TB);
                            ty = 0 - 1;
                            if is_kw(&TB) == 1 { ty = 0; }
                            if is_ty(&TB) == 1 { ty = 2; }
                            if is_bi(&TB) == 1 { ty = 1; }
                            if is_known(&TB) == 1 { ty = 1; }
                            if ty >= 0 {
                                if first == 0 { o_c(44); }
                                first = 0;
                                tk(ln, p, q - p, ty);
                            }
                            p = q;
                        } else {
                            if is_op(c) == 1 {
                                q = p;
                                while q < CODEN {
                                    if is_op(load8(&CODE + q)) == 0 { break; }
                                    q = q + 1;
                                }
                                if first == 0 { o_c(44); }
                                first = 0;
                                tk(ln, p, q - p, 7);
                                p = q;
                            } else {
                                p = p + 1;
                            }
                        }
                    }
                }
            }
            ln = ln + 1;
        }
    }
    o_str("]}");
    return 0;
}

# ============================================================ 协议

fn reply(id: i64) -> i64 {
    o_c(125);
    flush_msg();
    return 0;
}

fn begin_result(id: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"result\":");
    return 0;
}

fn handle() -> i64 {
    if streq(&METH, "initialize") == 1 {
        if HASID == 0 { return 0; }
        begin_result(MSID);
        o_str("{\"capabilities\":{");
        o_str("\"textDocumentSync\":1,");
        o_str("\"definitionProvider\":true,");
        o_str("\"hoverProvider\":true,");
        o_str("\"documentSymbolProvider\":true,");
        o_str("\"referencesProvider\":true,");
        o_str("\"semanticTokensProvider\":{\"legend\":{");
        o_str("\"tokenTypes\":[\"keyword\",\"function\",\"type\",\"variable\",");
        o_str("\"number\",\"string\",\"comment\",\"operator\",\"enumMember\",");
        o_str("\"class\",\"struct\"],");
        o_str("\"tokenModifiers\":[\"declaration\",\"definition\",\"readonly\"]},");
        o_str("\"full\":true}}");
        o_str(",\"serverInfo\":{\"name\":\"mols\",\"version\":\"1.0\"}}");
        reply(MSID);
        return 0;
    }
    if streq(&METH, "initialized") == 1 {
        if HASID == 1 { begin_result(MSID); o_str("null"); reply(MSID); }
        return 0;
    }
    if streq(&METH, "shutdown") == 1 {
        if HASID == 1 { begin_result(MSID); o_str("null"); reply(MSID); }
        return 0;
    }
    if streq(&METH, "exit") == 1 {
        syscall(60, 0, 0, 0, 0, 0, 0);
        return 1;
    }
    if streq(&METH, "textDocument/didOpen") == 1 {
        jget("uri", &REQURI);
        DOCN = jget("text", &DOC);
        reindex();
        publish();
        return 0;
    }
    if streq(&METH, "textDocument/didChange") == 1 {
        jget("uri", &REQURI);
        DOCN = jget("text", &DOC);
        reindex();
        publish();
        return 0;
    }
    if streq(&METH, "textDocument/definition") == 1 {
        if HASID == 0 { return 0; }
        jget("uri", &REQURI);
        POSL = jint("line");
        POSC = jint("character");
        set_txt(&DOC, DOCN);
        txt_split();
        begin_result(MSID);
        do_definition();
        reply(MSID);
        return 0;
    }
    if streq(&METH, "textDocument/hover") == 1 {
        if HASID == 0 { return 0; }
        jget("uri", &REQURI);
        POSL = jint("line");
        POSC = jint("character");
        set_txt(&DOC, DOCN);
        txt_split();
        begin_result(MSID);
        do_hover();
        reply(MSID);
        return 0;
    }
    if streq(&METH, "textDocument/documentSymbol") == 1 {
        if HASID == 0 { return 0; }
        jget("uri", &REQURI);
        begin_result(MSID);
        do_symbols();
        reply(MSID);
        return 0;
    }
    if streq(&METH, "textDocument/references") == 1 {
        if HASID == 0 { return 0; }
        jget("uri", &REQURI);
        POSL = jint("line");
        POSC = jint("character");
        begin_result(MSID);
        do_references();
        reply(MSID);
        return 0;
    }
    if streq(&METH, "textDocument/semanticTokens/full") == 1 {
        if HASID == 0 { return 0; }
        jget("uri", &REQURI);
        begin_result(MSID);
        do_tokens();
        reply(MSID);
        return 0;
    }
    if HASID == 1 { begin_result(MSID); o_str("null"); reply(MSID); }
    return 0;
}

fn publish() -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"method\":");
    o_str("\"textDocument/publishDiagnostics\",\"params\":");
    let n: i64 = cap_run();
    if n < 0 {
        o_str("{\"uri\":\"");
        o_esc(&REQURI);
        o_str("\",\"diagnostics\":[]}");
    } else {
        diag_emit();
    }
    o_c(125);
    flush_msg();
    return 0;
}

fn main() -> i64 {
    if argc() > 1 {
        strcpy(&ROOTP, argv(1));
    } else {
        strcpy(&ROOTP, ".");
    }
    strcpy(&LIBDIR, &ROOTP);
    strcat(&LIBDIR, "/lib");
    strcpy(&MOCP, &ROOTP);
    strcat(&MOCP, "/bin/moc");
    let l: i64 = 0;
    let ok: i64 = 0;
    let n: i64 = 0;
    let i: i64 = 0;
    let c: i64 = 0;
    while 1 {
        l = rd_line(&HDR);
        if l < 0 { return 0; }
        ok = str_starts_with(&HDR, "Content-Length:");
        if ok == 0 { ok = str_starts_with(&HDR, "content-length:"); }
        if ok == 0 { continue; }
        n = atoi_after_colon(&HDR);
        rd_line(&HDR);
        i = 0;
        while i < n {
            c = rd_ch();
            if c < 0 { return 0; }
            store8(&BODY + i, c);
            i = i + 1;
        }
        store8(&BODY + n, 0);
        jget("method", &METH);
        if jhas("id") == 1 { HASID = 1; MSID = jint("id"); } else { HASID = 0; MSID = 0; }
        let r: i64 = handle();
        if r == 1 { return 0; }
    }
    return 0;
}

fn atoi_after_colon(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        if c == 58 { i = i + 1; break; }
        i = i + 1;
        c = load8(s + i);
    }
    while load8(s + i) == 32 { i = i + 1; }
    let v: i64 = 0;
    c = load8(s + i);
    while c != 0 {
        if is_dig(c) == 0 { break; }
        v = v * 10 + (c - 48);
        i = i + 1;
        c = load8(s + i);
    }
    return v;
}
