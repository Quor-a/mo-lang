# mo2x —— 墨语言多后端翻译器（用墨语言自己写的）
#
#   ./mo2x prog.mo c   > prog.c      gcc -O2 prog.c -o prog
#   ./mo2x prog.mo js  > prog.js     node prog.js
#   ./mo2x prog.mo py  > prog.py     python3 prog.py
#
# 为什么是这个形态：
#   一个前端（分词 + 解析）产出同一套结构，交给不同的「发射器」。
#   三个后端共用解析器，所以它们的行为天然一致 ——
#   这正是「多后端对齐」的关键：差异只应该出现在发射层。
#
# 后端 1 = C      ：交给 gcc/clang，白嫖所有架构
# 后端 2 = JS     ：交给 node / 浏览器
# 后端 3 = Python ：交给 python3
#
# 已知差异（写清楚，不藏着）：
#   * C 后端数组不做越界检查
#   * JS 后端整数是浮点，超过 2^53 会失精（与普通 JS 一致）
#   * Python 后端整数任意精度，与 i64 的溢出行为不同

import "io.mo";
import "str.mo";
import "fs.mo";
import "dir.mo";

# ---------- 目标 ----------
var T_C: i64 = 1;
var T_JS: i64 = 2;
var T_PY: i64 = 3;
var T_FS: i64 = 4;          # freestanding C：无 libc，内联汇编 syscall
var T_KERN: i64 = 5;
var KERN_ARCH: i64 = 1;      # 内核目标架构：1=x86(VGA+端口)  2=aarch64(UART MMIO)        # 内核目标：无 libc，VGA + 端口 I/O（无系统调用）
var T_UEFI: i64 = 6;        # UEFI 目标：固件环境，输出走 ConOut 协议
var FS_ARCH: i64 = 0;      # 1=x86_64  2=aarch64  3=riscv64
# *at 版本适配：aarch64/riscv64 只有 openat/mkdirat/unlinkat/newfstatat/faccessat，
# 比 x86-64 的 open/mkdir/unlink/stat/access 多一个 dfd 首参（部分还多一个 flags 尾参）。
# FS_ATINS  = 0 或 AT_FDCWD(-100)：在调用号之后**插入**第一个实参
# FS_ATTAIL = 1：在实参表末尾**追加** flags=0
# 二者都是每次 syscall 发射前重置的专用全局，绝不复用共享临时变量。
var FS_ATINS: i64 = 0;
var FS_ATVAL: i64 = 0;
var FMODE: i64 = 0;    # f-string 状态：1 = {expr} 之后还有片段
var FSTOP: i64 = 0;    # lex_fstr_frag 的停止原因：123 = 遇到 {，34 = 收尾引号   # *at 插入的 dfd 值；fork→clone 时插 SIGCHLD(17)，epoll_wait→pwait 插 sigmask=NULL(0)   # *at 插入的 dfd 值；fork→clone 时插 SIGCHLD(17)，epoll_wait→pwait 插 sigmask=NULL(0)
var FS_ATTAIL: i64 = 0;
var TGT: i64 = 1;
var T_JAVA: i64 = 10;
var T_GO:   i64 = 11;
var T_RUST: i64 = 12;
var T_CS:   i64 = 13;
var T_SWIFT:i64 = 14;
var T_RUBY: i64 = 15;
var T_LUA:  i64 = 16;
var T_PHP:  i64 = 17;
var T_PERL: i64 = 18;

# profile —— 全部在 set_profile 里按目标填好
var G_FN: i64 = 0;          # 函数关键字（含尾空格）
var G_ENDFN: i64 = 0;       # 函数体结束符（"}" / "end"）
var G_VAR: i64 = 0;         # 变量前缀（"let " / "var " / "my $" / "local " / "$" / ""）
var G_TYI64: i64 = 0;       # i64 的类型名（动态语言为空串）
var G_TYPED: i64 = 0;       # 1 = 声明时写类型（java/go/rust/cs/swift）
var G_SEMI: i64 = 1;        # 语句结尾分号
var G_ARRPRE: i64 = 0;      # 数组初始化前缀（含数量占位用 # ）
var G_ARRPOST: i64 = 0;
var G_CLASS: i64 = 0;       # 结构体关键字（"class " / "type " / "struct "）
var G_NEW: i64 = 0;         # 结构体实例化（"new T()" / "T{}"）
var G_DIV: i64 = 0;         # 整数除写法：0=直接用 /  1=//  2=intdiv(a,b)  3=int(a/b)
var G_AND: i64 = 0;         # && 的写法
var G_OR: i64 = 0;
var G_NOT: i64 = 0;         # 一元 ! 的写法
var G_ELIF: i64 = 0;        # else-if 关键字
var G_CMT: i64 = 0;         # 注释前缀
var G_REF: i64 = 0;
var G_BOPEN: i64 = 0;
var G_FNBOPEN: i64 = 0;
var G_BREAK: i64 = 0;      # break 关键字（perl=last）
var G_CONT: i64 = 0;      # continue 关键字（perl/ruby=next）    # 函数体开始符（perl/lua/ruby 为空：函数头已自带）      # 块开始符（默认 "{"，lua 为空）         # 变量引用前缀（perl/php 用 $）
var G_ISMAIN: i64 = 0;      # 目标是否属于通用后端
var G_DIV_STR: i64 = 0;     # 整数除的写法
var TGNAME: i64 = 0;
var FSNAME: i64 = 0;        # 目标名（注释里用）
var G_ENDCLASS: i64 = 0;    # 结构体定义结束符



# ---------- 输出 ----------
var CHB: [2] byte = 0;
var IND: i64 = 0;          # 当前缩进层级（Python 用）
var LASTDIM: i64 = 0;      # 最近一次数组维度
var LASTTY: i64 = 0;       # 最近一次基类型名
var BOL: i64 = 1;          # 行首标记（全局变量必须先声明）

fn raw(s: i64) -> i64 {
    let n: i64 = strlen(s);
    if n > 0 { syscall(1, 1, s, n, 0, 0, 0); }
    return 0;
}
fn rawc(c: i64) -> i64 {
    store8(&CHB, c);
    syscall(1, 1, &CHB, 1, 0, 0, 0);
    return 0;
}
fn ind() -> i64 {
    if TGT == T_PY {
        let i: i64 = 0;
        while i < IND { raw("    "); i = i + 1; }
    }
    return 0;
}
fn outs(s: i64) -> i64 {
    if BOL == 1 { ind(); BOL = 0; }
    return raw(s);
}
fn nl() -> i64 {
    rawc(10);
    BOL = 1;
    return 0;
}
fn line(s: i64) -> i64 {
    outs(s);
    nl();
    return 0;
}

# ---------- 源码 / 分词 ----------

# 🔴 SRC 上限直接决定了 mo2x 能翻译多大的源文件，而原来的 131072 是**静默**的：
# read_file(..., 131071) 在文件更大时截断返回，parser 在半截文件上撞到 EOF，
# 报 "<file>:3618: unexpected eof in block at '<eof>'" —— 3618 是缓冲边界
# 对应的行，与真因（文件超过 128KB）毫无关系。
# 实测：src/compiler.mo 是 346889 字节，正好撞在这上面（v1.179）。
# 于是 "把墨语言编译器本身交叉编译成 ARM64" 这条路上，第一道关就是它。
#
# 两件事一起做：把上限抬到 524288，并且**超限要响亮报错**（见 load_file）。
var SRC: [524288] byte = 0;
var SLEN: i64 = 0;

var POOL: [1048576] byte = 0;
var PP: i64 = 0;

var TK: [200000] i64 = 0;
var TS: [200000] i64 = 0;
var NT: i64 = 0;
var TI: i64 = 0;
var LN: i64 = 1;

var OPS: [32] i64 = 0;
var NOPS: i64 = 0;

var LEXB: [4096] byte = 0;

# POOL 上限。PP 是**只增不减**的：每个文件都要 load_file → tokenize 一次，
# 而 pass_file 对每个文件跑 4 个 kind，于是同一个文件的 token 字符串被反复
# 追加 4 次。a64as.mo 这类上千行的程序两轮就撑爆 180000，越界写会改坏
# 别的全局数组 —— 症状是 "expected operator at '<eof>'"，报的位置还在
# 另一个文件里（文件名是 CURF，与真正溢出的文件不是同一个）。
# 越界写必须响亮失败，静默写坏内存的话根因无从查起。
fn pool_add(s: i64) -> i64 {
    let o: i64 = PP;
    let i: i64 = 0;
    if PP > 1000000 {
        err("token 池溢出（源码过大）");
        return 0;
    }
    while load8(s + i) != 0 {
        store8(&POOL + PP, load8(s + i));
        PP = PP + 1;
        i = i + 1;
    }
    store8(&POOL + PP, 0);
    PP = PP + 1;
    return o;
}

fn cur_k() -> i64 { return TK[TI]; }
fn cur_s() -> i64 { return &POOL + TS[TI]; }

fn is_op(s: i64) -> i64 {
    if cur_k() != 5 { return 0; }
    if streq(cur_s(), s) == 1 { return 1; }
    return 0;
}
fn accept_op(s: i64) -> i64 {
    if is_op(s) == 1 { TI = TI + 1; return 1; }
    return 0;
}
fn is_kw(s: i64) -> i64 {
    if cur_k() != 1 { return 0; }
    if streq(cur_s(), s) == 1 { return 1; }
    return 0;
}
fn accept_kw(s: i64) -> i64 {
    if is_kw(s) == 1 { TI = TI + 1; return 1; }
    return 0;
}
fn ident() -> i64 {
    if cur_k() != 1 { return err("expected identifier"); }
    let s: i64 = cur_s();
    TI = TI + 1;
    return s;
}

# instantiate 别名表：名字 + 参数是否 class（调用点需 &）
var IAN: [32] i64 = 0;
var IPARM: [256] i64 = 0;
var NIAC: i64 = 0;
fn ia_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NIAC {
        if streq(IAN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

var FP: [24576] byte = 0;
var FPP: i64 = 0;
var FILES: [64] i64 = 0;
var NEED_SYS: i64 = 0;
var NEED_CALL2: i64 = 0;       # 用到 syscall / 裸内存 → 需要 <sys/syscall.h>
var NF: i64 = 0;
var CURF: i64 = 0;

fn err(msg: i64) -> i64 {
    syscall(1, 2, "mo2x: ", 6, 0, 0, 0);
    syscall(1, 2, &FP + FILES[CURF], strlen(&FP + FILES[CURF]), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    let lb: [24] byte = 0;
    utoa(LN, &lb, 10);
    syscall(1, 2, &lb, strlen(&lb), 0, 0, 0);
    syscall(1, 2, ": ", 2, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, " at '", 5, 0, 0, 0);
    if TI >= NT { syscall(1, 2, "<eof>", 5, 0, 0, 0); }
    else {
        if cur_k() == 0 { syscall(1, 2, "<eof>", 5, 0, 0, 0); }
        else { syscall(1, 2, cur_s(), strlen(cur_s()), 0, 0, 0); }
    }
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn expect_op(s: i64) -> i64 {
    if accept_op(s) == 0 { return err("expected operator"); }
    return 0;
}

fn is_alpha(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c == 95 { return 1; }
    return 0;
}
fn is_digit_ch(c: i64) -> i64 {
    if c >= 48 { if c <= 57 { return 1; } }
    return 0;
}
# 十六进制字面量 0x.. ：moc 支持，而 mo2x 此前**不支持** ——
# 于是 0xD2800000 被切成 token "0" 加标识符 "xD2800000"，
# 报 "expected operator at 'xD2800000'"，且位置指向文件末尾（最后一个 token
# 之后），看起来像文件结尾有语法错。a64as/a64ld 大量用 0x 表示机器码，
# 因此在 cfs-* 后端下根本编不过。
fn hexval(c: i64) -> i64 {
    if c >= 48 { if c <= 57 { return c - 48; } }
    if c >= 97 { if c <= 102 { return c - 87; } }
    if c >= 65 { if c <= 70 { return c - 55; } }
    return -1;
}
fn is_ws(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    if c == 10 { return 1; }
    if c == 13 { return 1; }
    return 0;
}

fn ops_init() -> i64 {
    if NOPS > 0 { return 0; }
    # 长的必须在前，否则 "==" 会被拆成两个 "="
    OPS[0] = "<<="; OPS[1] = ">>="; OPS[2] = "=="; OPS[3] = "!="; OPS[4] = "<="; OPS[5] = ">=";
    OPS[6] = "&&"; OPS[7] = "||"; OPS[8] = "<<"; OPS[9] = ">>";
    OPS[10] = "+="; OPS[11] = "-="; OPS[12] = "*="; OPS[13] = "/=";
    OPS[14] = "%="; OPS[15] = "&="; OPS[16] = "|="; OPS[17] = "^=";
    OPS[18] = "+"; OPS[19] = "-"; OPS[20] = "*"; OPS[21] = "/";
    OPS[22] = "%"; OPS[23] = "&"; OPS[24] = "|"; OPS[25] = "^";
    OPS[26] = "="; OPS[27] = "<"; OPS[28] = ">"; OPS[29] = "!";
    NOPS = 30;
    return 0;
}

# f-string 片段：从 SLEN 读到未转义的 '{' 或收尾 '"'。
# 转义处理与 lex_str 一致。停止原因记 FSTOP（123 = '{'，34 = '"'）。
fn lex_fstr_frag(dst: i64) -> i64 {
    let n: i64 = 0;
    FSTOP = 0;
    while 1 {
        let c: i64 = load8(&SRC + SLEN);
        if c == 0 { FSTOP = 34; break; }
        if c == 34 { SLEN = SLEN + 1; FSTOP = 34; break; }
        if c == 123 { FSTOP = 123; break; }
        if c == 92 {
            SLEN = SLEN + 1;
            let e: i64 = load8(&SRC + SLEN);
            if e == 120 {
                # \xHH —— 两位十六进制（129_escx）
                SLEN = SLEN + 1;
                let h1: i64 = load8(&SRC + SLEN);
                SLEN = SLEN + 1;
                let h2: i64 = load8(&SRC + SLEN);
                let v1: i64 = 0;
                if h1 >= 48 && h1 <= 57 { v1 = h1 - 48; }
                else { if h1 >= 97 && h1 <= 102 { v1 = h1 - 97 + 10; } else { if h1 >= 65 && h1 <= 70 { v1 = h1 - 65 + 10; } else { v1 = 0; } } }
                let v2: i64 = 0;
                if h2 >= 48 && h2 <= 57 { v2 = h2 - 48; }
                else { if h2 >= 97 && h2 <= 102 { v2 = h2 - 97 + 10; } else { if h2 >= 65 && h2 <= 70 { v2 = h2 - 65 + 10; } else { v2 = 0; } } }
                store8(dst + n, v1 * 16 + v2);
            }
            else {
            if e == 110 { store8(dst + n, 10); }
            else {
                if e == 116 { store8(dst + n, 9); }
                else {
                    if e == 114 { store8(dst + n, 13); }
                    else {
                        if e == 48 { store8(dst + n, 0); }
                        else {
                            if e == 92 { store8(dst + n, 92); }
                            else {
                                if e == 34 { store8(dst + n, 34); }
                                else {
                                    if e == 39 { store8(dst + n, 39); }
                                    else { store8(dst + n, e); }
                                }
                            }
                        }
                    }
                }
            }
            }
            SLEN = SLEN + 1;
            n = n + 1;
        } else {
            store8(dst + n, c);
            SLEN = SLEN + 1;
            n = n + 1;
        }
    }
    store8(dst + n, 0);
    return 0;
}

fn lex_str(dst: i64) -> i64 {
    let n: i64 = 0;
    while load8(&SRC + SLEN) != 34 {
        let c: i64 = load8(&SRC + SLEN);
        if c == 0 { return n; }
        if c == 92 {
            SLEN = SLEN + 1;
            let e: i64 = load8(&SRC + SLEN);
            if e == 120 {
                # \xHH —— 两位十六进制（129_escx）
                SLEN = SLEN + 1;
                let h1: i64 = load8(&SRC + SLEN);
                SLEN = SLEN + 1;
                let h2: i64 = load8(&SRC + SLEN);
                let v1: i64 = 0;
                if h1 >= 48 && h1 <= 57 { v1 = h1 - 48; }
                else { if h1 >= 97 && h1 <= 102 { v1 = h1 - 97 + 10; } else { if h1 >= 65 && h1 <= 70 { v1 = h1 - 65 + 10; } else { v1 = 0; } } }
                let v2: i64 = 0;
                if h2 >= 48 && h2 <= 57 { v2 = h2 - 48; }
                else { if h2 >= 97 && h2 <= 102 { v2 = h2 - 97 + 10; } else { if h2 >= 65 && h2 <= 70 { v2 = h2 - 65 + 10; } else { v2 = 0; } } }
                store8(dst + n, v1 * 16 + v2);
            }
            else {
            if e == 110 { store8(dst + n, 10); }
            else {
                if e == 116 { store8(dst + n, 9); }
                else {
                    if e == 114 { store8(dst + n, 13); }
                    else {
                        if e == 48 { store8(dst + n, 0); }
                        else {
                            if e == 92 { store8(dst + n, 92); }
                            else {
                                if e == 34 { store8(dst + n, 34); }
                                else {
                                    if e == 39 { store8(dst + n, 39); }
                                    else { store8(dst + n, e); }
                                }
                            }
                        }
                    }
                }
            }
            }
            SLEN = SLEN + 1;
            n = n + 1;
        } else {
            store8(dst + n, c);
            SLEN = SLEN + 1;
            n = n + 1;
        }
    }
    SLEN = SLEN + 1;
    store8(dst + n, 0);
    return n;
}

fn add_tok(k: i64, s: i64) -> i64 {
    # token 上限。原来是 6000 —— 而 import 进来的库是**全部拼在一起**
    # 词法化的，str.mo + mem.mo 就超了，于是后面的 token 被静默丢弃，
    # 表现为 "expected operator at '<eof>'"（报在最末尾那个文件上）。
    # 症状离根因很远：看起来像语法不支持，其实是缓冲满了。
    if NT >= 200000 {
        err("token 数超过 200000（源码过大）");
        return 0;
    }
    TK[NT] = k;
    TS[NT] = pool_add(s);
    NT = NT + 1;
    return 0;
}

# token 流终止符。
# 🔴 此前完全没有：tokenize 只重置 NT/TI，不写 TK[NT]=0。于是当后一个文件的
# token 数**少于**前一个时，TK/TS 里前一个文件的残留仍在，被当成当前文件的
# 内容继续解析 —— 症状是 "expected operator at '<eof>'"，报的位置还是前一个
# 文件的末尾附近（LN 已在 eof 停下），看起来像那个文件有语法错。
# 触发条件是"后文件比前文件短"，所以小程序（t.mo + io.mo）从不出事，
# 一到 a64as.mo（1547 行）接着处理 io.mo（114 行）就必然发作。
fn tk_end() -> i64 {
    TK[NT] = 0;
    TS[NT] = 0;
    return 0;
}

fn tokenize() -> i64 {
    NT = 0;
    FMODE = 0;
    TI = 0;
    SLEN = 0;
    LN = 1;
    # 每个文件重新 tokenize，旧 token 全部作废 —— 池从头复用。
    # 不重置的话 PP 单调增长，大文件两轮 pass 就越界（见 pool_add 注释）。
    PP = 0;
    ops_init();
    while 1 {
        while 1 {
            let c: i64 = load8(&SRC + SLEN);
            if c == 0 { tk_end(); return 0; }
            if is_ws(c) == 1 {
                if c == 10 { LN = LN + 1; }
                SLEN = SLEN + 1;
            } else {
                if c == 35 {
                    while load8(&SRC + SLEN) != 10 {
                        if load8(&SRC + SLEN) == 0 { tk_end(); return 0; }
                        SLEN = SLEN + 1;
                    }
                } else {
                    break;
                }
            }
        }
        let c: i64 = load8(&SRC + SLEN);
        if is_alpha(c) == 1 {
            let n: i64 = 0;
            while is_alpha(load8(&SRC + SLEN)) == 1 || is_digit_ch(load8(&SRC + SLEN)) == 1 {
                store8(&LEXB + n, load8(&SRC + SLEN));
                SLEN = SLEN + 1;
                n = n + 1;
            }
            store8(&LEXB + n, 0);
            # f-string：标识符 f 紧跟 '"'。切出第一个片段（到 '{' 或收尾 '"'），
            # '{' 之后回到主循环按普通 token 走 —— 表达式 token 自然产出。
            if streq(&LEXB, "f") == 1 && load8(&SRC + SLEN) == 34 {
                SLEN = SLEN + 1;
                lex_fstr_frag(&LEXB);
                add_tok(6, &LEXB);
                if FSTOP == 123 { SLEN = SLEN + 1; add_tok(5, "{"); FMODE = 1; } else { FMODE = 0; }
            } else {
                add_tok(1, &LEXB);
            }
        } else {
            if is_digit_ch(c) == 1 {
                if c == 48 && (load8(&SRC + SLEN + 1) == 120 || load8(&SRC + SLEN + 1) == 88) {
                    # 按 i64 补码累积，溢出自然回绕 —— 与 moc 一致：
                    # 0xFFFFFFFFFFFFFFFF 得到 -1（实测 moc 也是 -1）。
                    let v: i64 = 0;
                    let nd: i64 = 0;
                    SLEN = SLEN + 2;
                    while hexval(load8(&SRC + SLEN)) >= 0 {
                        v = v * 16 + hexval(load8(&SRC + SLEN));
                        SLEN = SLEN + 1;
                        nd = nd + 1;
                    }
                    if nd == 0 { return err("0x 后缺少十六进制数字"); }
                    utoa(v, &LEXB, 10);
                    add_tok(2, &LEXB);
                } else {
                let n: i64 = 0;
                while is_digit_ch(load8(&SRC + SLEN)) == 1 {
                    store8(&LEXB + n, load8(&SRC + SLEN));
                    SLEN = SLEN + 1;
                    n = n + 1;
                }
                # 浮点字面量 10.0：'.' 在分隔符表里，此前被单独切出来，
                # 于是 "10" "." "0"，报 "expected identifier at '0'" ——
                # 报错位置还落在 import 进来的库里（lib/io.mo 的 print_f64），
                # 看着像库有语法错。只在 '.' 后紧跟数字时才合并。
                if load8(&SRC + SLEN) == 46 {
                    if is_digit_ch(load8(&SRC + SLEN + 1)) == 1 {
                        store8(&LEXB + n, 46);
                        n = n + 1;
                        SLEN = SLEN + 1;
                        while is_digit_ch(load8(&SRC + SLEN)) == 1 {
                            store8(&LEXB + n, load8(&SRC + SLEN));
                            SLEN = SLEN + 1;
                            n = n + 1;
                        }
                    }
                }
                    store8(&LEXB + n, 0);
                    add_tok(2, &LEXB);
                }
            } else {
                if c == 34 {
                    SLEN = SLEN + 1;
                    lex_str(&LEXB);
                    add_tok(3, &LEXB);
                } else {
                    if c == 39 {
                        SLEN = SLEN + 1;
                        let v: i64 = 0;
                        if load8(&SRC + SLEN) == 92 {
                            SLEN = SLEN + 1;
                            let e: i64 = load8(&SRC + SLEN);
                            if e == 120 {
                                # \xHH 字符字面量（129_escx）
                                SLEN = SLEN + 1;
                                let h1: i64 = load8(&SRC + SLEN);
                                SLEN = SLEN + 1;
                                let h2: i64 = load8(&SRC + SLEN);
                                let v1: i64 = 0;
                                if h1 >= 48 && h1 <= 57 { v1 = h1 - 48; }
                                else { if h1 >= 97 && h1 <= 102 { v1 = h1 - 97 + 10; } else { if h1 >= 65 && h1 <= 70 { v1 = h1 - 65 + 10; } else { v1 = 0; } } }
                                let v2: i64 = 0;
                                if h2 >= 48 && h2 <= 57 { v2 = h2 - 48; }
                                else { if h2 >= 97 && h2 <= 102 { v2 = h2 - 97 + 10; } else { if h2 >= 65 && h2 <= 70 { v2 = h2 - 65 + 10; } else { v2 = 0; } } }
                                v = v1 * 16 + v2;
                            }
                            else {
                                if e == 110 { v = 10; }
                                else {
                                    if e == 116 { v = 9; }
                                    else {
                                        if e == 48 { v = 0; }
                                        else { v = e; }
                                    }
                                }
                            }
                            SLEN = SLEN + 1;
                        } else {
                            v = load8(&SRC + SLEN);
                            SLEN = SLEN + 1;
                        }
                        if load8(&SRC + SLEN) == 39 { SLEN = SLEN + 1; }
                        store8(&LEXB, v);
                        store8(&LEXB + 1, 0);
                        add_tok(4, &LEXB);
                    } else {
                        # 单字符分隔符。注意：不能包含 < > = ! ，
                        # 否则 "==" / "!=" / "<=" / ">=" 会被拆开
                        if c == 40 || c == 41 || c == 123 || c == 125 || c == 91 || c == 93
                           || c == 59 || c == 44 || c == 58 || c == 46 {
                            # f-string：'}' 是插值表达式结束 —— 后面紧跟下一个
                            # 片段（片段之间没有引号），不能当普通代码块结尾。
                            if c == 125 && FMODE == 1 {
                                store8(&LEXB, 125);
                                store8(&LEXB + 1, 0);
                                SLEN = SLEN + 1;
                                add_tok(5, &LEXB);
                                lex_fstr_frag(&LEXB);
                                add_tok(6, &LEXB);
                                if FSTOP == 34 { FMODE = 0; }   # '{' 由主循环自然切出
                            } else {
                            store8(&LEXB, c);
                            store8(&LEXB + 1, 0);
                            SLEN = SLEN + 1;
                            add_tok(5, &LEXB);
                            }
                        } else {
                            let k: i64 = 0;
                            let found: i64 = -1;
                            while k < NOPS {
                                let op: i64 = OPS[k];
                                let j: i64 = 0;
                                let ok: i64 = 1;
                                while load8(op + j) != 0 {
                                    if load8(&SRC + SLEN + j) != load8(op + j) { ok = 0; }
                                    j = j + 1;
                                }
                                if ok == 1 { found = k; break; }
                                k = k + 1;
                            }
                            if found < 0 {
                                SLEN = SLEN + 1;
                            } else {
                                let op: i64 = OPS[found];
                                SLEN = SLEN + strlen(op);
                                add_tok(5, op);
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# ---------- 表达式 ----------
#
# 用「优先级递归」而不是手写 8 个层级函数：
#   emit_prec(minp)：先输出一元项，再看当前运算符优先级是否 >= minp，
#   是就输出运算符并递归 emit_prec(p+1)。
# 这样既保证结合性，又不产生多余括号 —— 手写层级时括号数对不上，
# 会生成错的表达式，而这类错误极难发现。

fn binprec() -> i64 {
    if cur_k() != 5 { return 0; }
    let s: i64 = cur_s();
    if streq(s, "||") == 1 { return 1; }
    if streq(s, "&&") == 1 { return 2; }
    if streq(s, "|") == 1 { return 3; }
    if streq(s, "^") == 1 { return 4; }
    if streq(s, "&") == 1 { return 5; }
    if streq(s, "==") == 1 { return 6; }
    if streq(s, "!=") == 1 { return 6; }
    if streq(s, "<") == 1 { return 7; }
    if streq(s, ">") == 1 { return 7; }
    if streq(s, "<=") == 1 { return 7; }
    if streq(s, ">=") == 1 { return 7; }
    if streq(s, "<<") == 1 { return 8; }
    if streq(s, ">>") == 1 { return 8; }
    if streq(s, "+") == 1 { return 9; }
    if streq(s, "-") == 1 { return 9; }
    if streq(s, "*") == 1 { return 10; }
    if streq(s, "/") == 1 { return 10; }
    if streq(s, "%") == 1 { return 10; }
    return 0;
}

fn emit_binop(s: i64) -> i64 {
    if TGT == T_PY {
        if streq(s, "&&") == 1 { outs(" and "); return 0; }
        if streq(s, "||") == 1 { outs(" or "); return 0; }
        # 墨语言 / 是整数除，Python 的 / 会得到浮点
        if streq(s, "/") == 1 { outs(" // "); return 0; }
    }
    if TGT == T_JS {
        if streq(s, "/") == 1 {
            return err("JS 后端不支持整数除法 / （JS 的 / 是浮点除）。请改写或改用 c / py");
        }
    }
    if is_gen() == 1 {
        if streq(s, "&&") == 1 { outs(G_AND); return 0; }
        if streq(s, "||") == 1 { outs(G_OR); return 0; }
        if streq(s, "/") == 1 {
            # Lua 用 //，PHP 用 intdiv，Perl 要 int(a/b)
            outs(G_DIV_STR);
            return 0;
        }
    }
    outs(" ");
    outs(s);
    outs(" ");
    return 0;
}

# 字符串比较特判：IDENT(∈STRV) CMPOP STRING/IDENT(∈STRV) —— Mo 语义按内容比较。
# 只覆盖常见模式；复杂表达式回退指针比较（预存限制）。
fn try_strcmp() -> i64 {
    if cur_k() != 1 { return 0; }
    let a: i64 = cur_s();
    let isa: i64 = strv_find(a);
    if isa == 0 { return 0; }
    let save: i64 = TI;
    TI = TI + 1;
    if cur_k() != 5 { TI = save; return 0; }
    let op: i64 = cur_s();
    let iscmp: i64 = 0;
    if streq(op, "==") == 1 { iscmp = 1; }
    if streq(op, "!=") == 1 { iscmp = 1; }
    if streq(op, "<") == 1 { iscmp = 1; }
    if streq(op, ">") == 1 { iscmp = 1; }
    if streq(op, "<=") == 1 { iscmp = 1; }
    if streq(op, ">=") == 1 { iscmp = 1; }
    if iscmp == 0 { TI = save; return 0; }
    TI = TI + 1;
    if cur_k() == 3 || (cur_k() == 1 && strv_find(cur_s()) == 1) {
        outs("strcmp((unsigned char*)");
        outs(a);
        outs(", (unsigned char*)");
        if cur_k() == 3 { out_cstr(cur_s()); } else { outs(cur_s()); }
        outs(") ");
        outs(op);
        outs(" 0");
        TI = TI + 1;
        return 1;
    }
    TI = save;
    return 0;
}

fn emit_expr() -> i64 {
    if try_strcmp() == 1 { return 0; }
    return emit_prec(1);
}

var CAST_OPEN: i64 = 0;    # emit_primary 已发 "(long long)("，postfix ']' 后闭合

fn emit_primary() -> i64 {
    if cur_k() == 2 {
        outs(cur_s());
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 3 {
        if is_c_like() == 1 { outs("(unsigned char*)"); }
        out_cstr(cur_s());
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 4 {
        let v: i64 = load8(cur_s());
        let b: [24] byte = 0;
        utoa(v, &b, 10);
        outs(&b);
        TI = TI + 1;
        return 0;
    }
    if accept_op("(") == 1 {
        outs("(");
        emit_expr();
        expect_op(")");
        outs(")");
        return 0;
    }
    if cur_k() == 1 {
        let nm: i64 = cur_s();
        TI = TI + 1;
        # byte/ptr 基下标读提升（v1.194.0）：name[...] 整体包 (long long)(...)
        # 流式输出无法回包 —— 必须在 name 输出前决定。lookahead：下一个是 '['
        # 且变量是 byte 基 → 先输出 cast 开括号，CAST_OPEN 交 postfix 闭合。
        CAST_OPEN = 0;
        if TGT == T_FS {
            if is_op("[") == 1 {
                if bytev_find(nm) == 1 || ptr_find(nm) == 1 {
                    # 多维 a[i][j]：向后配平看 ']' 后是否又是 '['，是则不 cast
                    let sv3: i64 = TI;   # TI 指向 '['
                    let depth: i64 = 0;
                    let stop: i64 = 0;
                    while TI < NT && stop == 0 {
                        if is_op("[") == 1 { depth = depth + 1; }
                        else {
                            if is_op("]") == 1 {
                                depth = depth - 1;
                                if depth == 0 { stop = 1; }
                            }
                        }
                        TI = TI + 1;
                    }
                    # TI 停在配平 ']' 的下一个
                    if is_op("[") != 1 {
                        CAST_OPEN = 1;
                        outs("(long long)(");
                    }
                    TI = sv3;
                }
            }
        }
        if is_op("(") == 1 {
            # 内存原语只在有线性内存语义的后端（C 系）可用。
            # C 系下它们就是普通调用 —— 实现由前导里的宏给出。
            if is_c_like() == 0 {
                if streq(nm, "load8") == 1 { return err("load8 仅在 C 系后端支持"); }
                if streq(nm, "load64") == 1 { return err("load64 仅在 C 系后端支持"); }
                if streq(nm, "store8") == 1 { return err("store8 仅在 C 系后端支持"); }
                if streq(nm, "store64") == 1 { return err("store64 仅在 C 系后端支持"); }
            }
            if streq(nm, "syscall") == 1 {
                if is_c_like() == 0 { return err("syscall 仅在 C / freestanding 后端支持"); }
                TI = TI + 1;                 # 吃掉 '('，否则实参解析会把它当分组
                # 每次发射都从干净状态开始：非字面量调用号那条路径不会设置
                # FS_ATINS/FS_ATTAIL，若不在开头清零，上一次 syscall 的设置会残留
                # 到这一次 —— 于是普通调用被静默塞进一个 dfd 参数。
                FS_ATINS = 0;
                FS_ATTAIL = 0;
                FS_ATVAL = 0 - 100;
                outs("mo_syscall");          # header 里定义的就是这个名字
                outs("(");
                let na: i64 = 0;             # 用户实参个数（不含调用号），用于上限校验
                if is_op(")") == 0 {
                    # 第一个参数是**调用号**。整数字面量必须按目标架构翻译：
                    # 源码里写的是 x86-64 号表，原样透传到 aarch64 会发错调用。
                    if cur_k() == 2 {
                        if is_num_tok(cur_s()) == 1 {
                            let no: i64 = atoi(cur_s());
                            let tn: i64 = fs_sysno(no);
                            if tn == -1 {
                                return err("syscall 号不能只靠换号翻译：rename 等调用在目标架构参数形态不同（需要多个 dfd），请改用 *at 号显式书写");
                            }
                            if tn == -2 {
                                return err("该目标架构暂无 syscall 号表");
                            }
                            TI = TI + 1;
                            outs("(long)");
                            let nb: [24] byte = 0;
                            utoa(tn, &nb, 10);
                            outs(&nb);
                            # *at 版本：在调用号之后插入 dfd（renameat 要插两个）
                            if FS_ATINS == 1 { outs(",(long)"); let av: [24] byte = 0; utoa(FS_ATVAL, &av, 10); outs(&av); }
                            if FS_ATINS == 2 { outs(",(long)"); let av: [24] byte = 0; utoa(FS_ATVAL, &av, 10); outs(&av); }
                        } else {
                            outs("(long)");
                            emit_expr();
                        }
                    } else {
                        # 实参显式转 long：指针传给 long 形参在 clang/zig 下是硬错误，
                        # 而 syscall 的语义本来就是把地址当整数传
                        outs("(long)");
                        emit_expr();
                    }
                    # *at/变体适配会追加实参（dfd / flags / sigsetsize），
                    # 源码又习惯把实参补满 0 —— 两头相加会超 mo_syscall 的 6 个实参位。
                    # 允许的用户实参数 = 6 - 追加个数；超出的**尾部字面量 0** 是
                    # mo_syscall 本来就会补的占位，直接跳过不发射。
                    let extra: i64 = 0;
                    extra = extra + FS_ATINS;
                    if FS_ATTAIL == 1 { extra = extra + 1; }
                    if FS_ATTAIL == 2 { extra = extra + 2; }
                    let allowed: i64 = 6 - extra;
                    while accept_op(",") == 1 {
                        # 尾部占位 0：超配额且当前 token 就是字面量 0 → 吞掉不发射
                        if na >= allowed && cur_k() == 2 && streq(cur_s(), "0") == 1 {
                            TI = TI + 1;
                            continue;
                        }
                        na = na + 1;
                        outs(",");
                        if FS_ATINS == 2 && na == 2 {
                            outs("(long)");
                            let av2: [24] byte = 0;
                            utoa(FS_ATVAL, &av2, 10);
                            outs(&av2);
                            outs(",");
                        }
                        outs("(long)");
                        emit_expr();
                    }
                }
                # newfstatat / faccessat 比 x86 的 stat / access 多一个尾部 flags
                if FS_ATTAIL == 1 { outs(",(long)0"); }
                if FS_ATTAIL == 2 { outs(",(long)0,(long)8"); }   # epoll_pwait 的 sigsetsize=8
                # mo_syscall 固定 7 个形参（n,a,b,c,d,e,f）⟹ 实参位只有 6 个。
                # C 要求实参给满，缺的必须补 0 —— 否则 zigcc 直接报
                # "too few arguments to function call"，构建失败。
                # 顺带解决了"每次都得手写满 7 个参数"这个可用性问题。
                let tot: i64 = na + FS_ATINS + FS_ATTAIL;
                if tot > 6 {
                    return err("syscall 实参过多：适配 *at 版本后超出 mo_syscall 的 7 个形参");
                }
                while tot < 6 {
                    outs(",(long)0");
                    tot = tot + 1;
                }
                expect_op(")");
                outs(")");
                return 0;
            }
            if is_c_like() == 0 {
                if streq(nm, "argc") == 1 { return err("argc 仅在 C 系后端支持"); }
                if streq(nm, "argv") == 1 { return err("argv 仅在 C 系后端支持"); }
            }
            TI = TI + 1;          # 吃掉 '(' —— 必须先消耗再输出
            # f-string 实参：print(f"A{e}B") / sfmt(dst, f"A{e}B")。
            # mo2x 没有类型推断，{表达式} 的分派按形状启发：
            #   字符串字面量 / ptr(...) 开头 → strcat（当字符串拼）
            #   其余                          → strcat_i64 / print_i64
            # print 用逗号表达式串多条语句；sfmt 用全局游标 MF_P 级联 strcat。
            let hasf: i64 = 0;
            if streq(nm, "sfmt") == 1 || streq(nm, "print") == 1 {
                let sv: i64 = TI;
                let dep: i64 = 0;
                while dep == 0 && cur_k() != 0 {
                    if cur_k() == 6 { hasf = 1; }
                    if is_op("(") == 1 || is_op("{") == 1 { dep = dep + 1; }
                    if is_op(")") == 1 { if dep == 0 { break; } dep = dep - 1; }
                    TI = TI + 1;
                }
                TI = sv;
            }
            if hasf == 1 && (cur_k() == 6 || streq(nm, "sfmt") == 1) {
                outs("(");
                let firstp: i64 = 1;
                if streq(nm, "sfmt") == 1 {
                    outs("MF_P=(long)");
                    emit_expr();               # dst 只求值一次
                    accept_op(",");            # 吃掉 dst 与 f-string 之间的逗号
                    firstp = 0;
                }
                while cur_k() == 6 {
                    if streq(nm, "sfmt") == 1 { outs(","); }
                    else { if firstp == 0 { outs(","); } }
                    firstp = 0;
                    if streq(nm, "print") == 1 {
                        outs("print(");
                        out_cstr(cur_s());
                        outs(")");
                    } else {
                        outs("strcat(MF_P,");
                        out_cstr(cur_s());
                        outs(")");
                    }
                    TI = TI + 1;
                    if is_op("{") == 1 {
                        TI = TI + 1;
                        # 分派：字符串字面量或 ptr( 开头 → 字符串拼接
                        let isstr: i64 = 0;
                        if cur_k() == 3 { isstr = 1; }
                        let isptrcast: i64 = 0;
                        if cur_k() == 1 && streq(cur_s(), "ptr") == 1 { isstr = 1; isptrcast = 1; }
                        if isptrcast == 1 {
                            TI = TI + 1;           # 吃掉 ptr
                            expect_op("(");
                            if streq(nm, "print") == 1 { outs(",print((unsigned char*)("); }
                            else { outs(",strcat(MF_P,(unsigned char*)("); }
                            emit_expr();
                            expect_op(")");
                            outs(")");
                        } else {
                        if streq(nm, "print") == 1 {
                            if isstr == 1 { outs(",print("); } else { outs(",print_i64("); }
                        } else {
                            if isstr == 1 { outs(",strcat(MF_P,"); } else { outs(",strcat_i64(MF_P,"); }
                        }
                        emit_expr();
                        }
                        outs(")");
                        if is_op("}") == 0 { return err("f-string: 缺少 '}'"); }
                        TI = TI + 1;
                    }
                }
                if streq(nm, "sfmt") == 1 { outs(",MF_P"); }
                outs(")");
                expect_op(")");
                return 0;
            }
            if streq(nm, "exit") == 1 {
                # freestanding: exit(n) → mo_exit(n)（前导提供，exit_group）
                outs("mo_exit(");
                if is_op(")") == 0 { emit_expr(); }
                expect_op(")");
                outs(")");
                return 0;
            }
            let iai: i64 = ia_find(nm);
            if iai >= 0 {
                # instantiate 别名调用：class 实参需取地址（引用语义）
                outs(nm);
                outs("(");
                let na2: i64 = 0;
                if is_op(")") == 0 {
                    if IPARM[iai * 8 + 0] == 1 { outs("(unsigned char*)&"); }
                    emit_expr();
                    na2 = 1;
                    while accept_op(",") == 1 {
                        outs(",");
                        if IPARM[iai * 8 + na2] == 1 { outs("(unsigned char*)&"); }
                        emit_expr();
                        na2 = na2 + 1;
                    }
                }
                expect_op(")");
                outs(")");
                return 0;
            }
            outs(nm);
            outs("(");
            if is_op(")") == 0 {
                emit_expr();
                while accept_op(",") == 1 {
                    outs(",");
                    emit_expr();
                }
            }
            expect_op(")");
            outs(")");
            return 0;
        }
        if is_gen() == 1 { outs(G_REF); }
        outs(nm);
        return 0;
    }
    return err("bad primary");
}

fn emit_postfix() -> i64 {
    # 方法调用探测：IDENT . IDENT ( args ) → Type_method(IDENT, args)。
    # 必须在 emit_primary 输出 IDENT 之前识别（输出流无法截回）。
    if cur_k() == 1 && TGT == T_FS {
        let save: i64 = TI;
        let onm: i64 = cur_s();
        TI = TI + 1;
        if is_op(".") == 1 {
            TI = TI + 1;
            if cur_k() == 1 {
                let mth: i64 = cur_s();
                TI = TI + 1;
                if is_op("(") == 1 {
                    let ty: i64 = clsv_ty(onm);
                    let fi2: i64 = iface_find(ty);
                    if fi2 >= 0 {
                        # 接口方法调用：a.area() → ((long long(*)(void*))((void**)a.vt)[IDX])(a.obj, args...)
                        TI = TI + 1;   # '('
                        let mid: i64 = iface_mid(fi2, mth);
                        if mid < 0 { return err("接口方法不在接口声明中"); }
                        outs("((long long(*)(void*,...))((void**)");
                        outs(onm);
                        outs(".vt)[");
                        outi(mid);
                        outs("])((void*)");
                        outs(onm);
                        outs(".obj");
                        if is_op(")") == 0 {
                            outs(",");
                            emit_expr();
                            while accept_op(",") == 1 { outs(","); emit_expr(); }
                        }
                        expect_op(")");
                        outs(")");
                        return 0;
                    }
                    if ty != 0 {
                        TI = TI + 1;   # 吃掉 '(' —— 否则它会混进第一个实参
                        # Type_method(obj, args)；obj 若已是 struct 指针（泛型实例化体的形参）→ 不加 &
                        outs(ty);
                        outs("_");
                        outs(mth);
                        outs("(");
                        if ptr_find(onm) == 1 { outs("(unsigned char*)"); } else { outs("(unsigned char*)&"); }
                        outs(onm);
                        if is_op(")") == 0 {
                            outs(",");
                            emit_expr();
                            while accept_op(",") == 1 { outs(","); emit_expr(); }
                        }
                        expect_op(")");
                        outs(")");
                        return 0;
                    }
                }
            }
        }
        TI = save;
    }
    emit_primary();
    while 1 {
        if accept_op("[") == 1 {
            outs("[");
            let sv_co: i64 = CAST_OPEN;   # 下标表达式内的 emit_primary 会重置 CAST_OPEN，先保存
            CAST_OPEN = 0;
            emit_expr();
            CAST_OPEN = sv_co;
            expect_op("]");
            outs("]");
            if CAST_OPEN == 1 {
                outs(")");
                CAST_OPEN = 0;
            }
        } else {
            if accept_op(".") == 1 {
                # 字段访问。左侧 ident 若是 struct 指针（方法形参 self）→ "->"。
                let isptr: i64 = 0;
                if TI >= 2 {
                    let sv: i64 = TI;
                    TI = TI - 2;
                    if cur_k() == 1 && ptr_find(cur_s()) == 1 { isptr = 1; }
                    TI = sv;
                }
                if isptr == 1 { outs("->"); } else { outs("."); }
                outs(ident());
            } else {
                return 0;
            }
        }
    }
    return 0;
}

# 内核目标：print / print_i64 / print_nl 重定向到 VGA
fn kern_print_redirect() -> i64 {
    return 0;
}

fn emit_unary() -> i64 {
    if accept_op("-") == 1 {
        outs("-");
        return emit_unary();
    }
    if accept_op("!") == 1 {
        if TGT == T_PY { outs("not "); }
        else {
            if is_gen() == 1 { outs(G_NOT); } else { outs("!"); }
        }
        return emit_unary();
    }
    if accept_op("&") == 1 {
        # 只有 C 系后端（c / cfs / kern）有地址概念；
        # JS/Python/Perl 等没有线性内存语义，取地址无从表达。
        if is_c_like() == 0 { return err("取地址 & 仅在 C 系后端支持"); }
        # 统一转成 unsigned char*：
        # 对数组变量，`&arr` 在 C 里是 "指向整个数组的指针"（unsigned char(*)[N]），
        # 传给期待 unsigned char* 的函数是硬错误。加显式转换后，
        # 数组与标量的取地址语义就一致了 —— 都是"首字节地址"。
        outs("(unsigned char*)&");
        return emit_unary();
    }
    if accept_op("*") == 1 {
        if is_c_like() == 0 { return err("解引用 * 仅在 C 系后端支持"); }
        outs("*");
        return emit_unary();
    }
    return emit_postfix();
}

var STN: [32] i64 = 0;    # 已发射 class/struct 名
var STF: [32] i64 = 0;    # 各类型字段在 CLSF 的起始 slot（每字段 2 slot：名,类型）
var STFN: [32] i64 = 0;   # 字段数
var NST: i64 = 0;
var CLSF: [256] i64 = 0;  # 字段 (名,类型) 对池
var PTRS: [64] i64 = 0;   # struct 指针形参名（emit_sig 时记录）
var NTRS: i64 = 0;
fn ptr_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NTRS {
        if streq(PTRS[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}
var NCLSF: i64 = 0;
fn st_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NST {
        if streq(STN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

var CLSV: [64] i64 = 0;   # struct 类型局部变量名
var CLST: [64] i64 = 0;   # 对应类型名
var NCLSV: i64 = 0;
fn clsv_add(nm: i64, ty: i64) -> i64 {
    let i: i64 = 0;
    while i < NCLSV {
        if streq(CLSV[i], nm) == 1 { CLST[i] = ty; return 0; }
        i = i + 1;
    }
    if NCLSV >= 64 { return 0; }
    CLSV[NCLSV] = nm;
    CLST[NCLSV] = ty;
    NCLSV = NCLSV + 1;
    return 0;
}
fn clsv_ty(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NCLSV {
        if streq(CLSV[i], nm) == 1 { return CLST[i]; }
        i = i + 1;
    }
    return 0;
}

var BYTEV: [256] i64 = 0;  # byte 基类型变量名（数组/指针）—— 读值需提升 long long
var NBYTEV: i64 = 0;

fn bytev_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NBYTEV {
        if streq(BYTEV[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

fn bytev_add(nm: i64) -> i64 {
    if NBYTEV >= 256 { return 0; }
    BYTEV[NBYTEV] = nm;
    NBYTEV = NBYTEV + 1;
    return 0;
}

var STRV: [64] i64 = 0;   # 已知 str 类型局部变量名（指针数组）
var NSTRV: i64 = 0;
var EXSTR: i64 = 0;        # 上一个 primary 是否字符串值

fn strv_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NSTRV {
        if streq(STRV[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

fn strv_add(nm: i64) -> i64 {
    if NSTRV >= 64 { return 0; }
    STRV[NSTRV] = nm;
    NSTRV = NSTRV + 1;
    return 0;
}

fn emit_prec(minp: i64) -> i64 {
    emit_unary();
    while 1 {
        let p: i64 = binprec();
        if p == 0 { return 0; }
        if p < minp { return 0; }
        let op: i64 = cur_s();
        TI = TI + 1;
        # 字符串比较：Mo 语义是按内容比较（strcmp），C 的指针比较是比地址。
        # 左操作数是字符串（字面量或已知 str 变量）且 op 是比较符 →
        # 改写为 strcmp(l, r) OP 0。
        let iscmp: i64 = 0;
        if streq(op, "==") == 1 { iscmp = 1; }
        if streq(op, "!=") == 1 { iscmp = 1; }
        if streq(op, "<") == 1 { iscmp = 1; }
        if streq(op, ">") == 1 { iscmp = 1; }
        if streq(op, "<=") == 1 { iscmp = 1; }
        if streq(op, ">=") == 1 { iscmp = 1; }
        emit_binop(op);
        emit_prec(p + 1);
    }
    return 0;
}

fn out_cstr(s: i64) -> i64 {
    outs("\"");
    let i: i64 = 0;
    while load8(s + i) != 0 {
        let c: i64 = load8(s + i);
        if c == 34 { outs("\\\""); }
        else {
            if c == 92 { outs("\\\\"); }
            else {
                if c == 10 { outs("\\n"); }
                else {
                    if c == 9 { outs("\\t"); }
                    else {
                        if c == 13 { outs("\\r"); }
                        else {
                            if c < 32 { outs(" "); }
                            else { rawc(c); }
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    outs("\"");
    return 0;
}

# 这些名字由后端自己提供，不照搬 Mo 源码里的实现
fn peek_builtin_fn() -> i64 {
    let save: i64 = TI;
    if cur_k() != 1 { return 0; }
    let nm: i64 = cur_s();
    let r: i64 = 0;
    if streq(nm, "print") == 1 { r = 1; }
    if streq(nm, "print_i64") == 1 { r = 1; }
    if streq(nm, "print_nl") == 1 { r = 1; }
    if streq(nm, "print_hex") == 1 { r = 1; }
    if streq(nm, "exit") == 1 { r = 1; }
    if streq(nm, "argc") == 1 { r = 1; }
    if streq(nm, "argv") == 1 { r = 1; }
    # freestanding（cfs-*）：前导已给出 static strlen/atoi/memset/memcpy。
    # 再输出 str.mo 里的同名实现就是 "conflicting types for 'strlen'" ——
    # 报的位置在生成的 C 里，离"前导和库撞名"这个真因很远。
    if TGT == T_FS {
        if streq(nm, "strlen") == 1 { r = 1; }
        if streq(nm, "atoi") == 1 { r = 1; }
        if streq(nm, "memset") == 1 { r = 1; }
        if streq(nm, "memcpy") == 1 { r = 1; }
    }
    TI = save;
    return r;
}

# ---------- 类型名映射 ----------

fn emit_scalar(t: i64) -> i64 {
    if streq(t, "i64") == 1 {
        if is_c_like() == 1 { outs("long long"); } else { outs("0"); }
        return 0;
    }
    if streq(t, "byte") == 1 {
        if is_c_like() == 1 { outs("unsigned char"); } else { outs("0"); }
        return 0;
    }
    if streq(t, "ptr") == 1 {
        if is_c_like() == 1 { outs("unsigned char*"); return 0; }
        return err("ptr 只在 C / freestanding 后端支持（JS/Python 等无指针语义）");
    }
    # f64：此前不认识，于是 `fn print_f64(v: f64)` 让参数解析一路吃到 eof，
    # 报 "expected operator at '<eof>'"，位置还在被 import 的库里。
    if streq(t, "f64") == 1 {
        if is_c_like() == 1 { outs("double"); } else { outs("0"); }
        return 0;
    }
    if streq(t, "i32") == 1 {
        if is_c_like() == 1 { outs("int"); return 0; }
    }
    # str：Mo 的字符串类型（moc 内建）—— C 系即 unsigned char*。
    # 此前不认识 → `let zh: str = "..."` 发射 `struct str_t` → 编译失败。
    if streq(t, "str") == 1 {
        if is_c_like() == 1 { outs("unsigned char*"); return 0; }
        return err("str 类型仅在 C 系后端支持");
    }
    if is_c_like() == 1 { outs("struct "); outs(t); outs("_t"); } else { outs(t); }
    return 0;
}

# C 用：输出完整声明（含数组维度与变量名）
fn emit_scalar_or_arr(nm: i64, isarr: i64) -> i64 {
    if isarr == 1 {
        if is_op("[") == 1 {
            TI = TI + 1;
            let n: i64 = cur_s();
            TI = TI + 1;
            expect_op("]");
            emit_scalar_or_arr(nm, 1);
            outs("[");
            outs(n);
            outs("]");
            return 0;
        }
    }
    let t: i64 = ident();
    emit_scalar(t);
    outs(" ");
    outs(nm);
    if streq(t, "byte") == 1 { bytev_add(nm); }
    if streq(t, "ptr") == 1 { bytev_add(nm); }
    if streq(t, "str") == 1 { strv_add(nm); }
    else {
        if streq(t, "i64") == 0 && streq(t, "byte") == 0 && streq(t, "ptr") == 0 && streq(t, "f64") == 0 && streq(t, "i32") == 0 && streq(t, "bool") == 0 {
            clsv_add(nm, t);
        }
    }
    return 0;
}

# 消耗一个类型，返回数组维度（0 表示标量）。
# JS / Python 不需要类型名，但**必须把它消耗掉** ——
# 早先只在数组分支消耗，标量时类型名残留在流里，
# 后面的 '=' 就匹配不上（现象：只生成 "let s;" 就崩了）。
fn consume_type() -> i64 {
    if is_op("[") == 1 {
        TI = TI + 1;
        let d: i64 = atoi(cur_s());
        TI = TI + 1;
        expect_op("]");
        let inner: i64 = consume_type();
        return d;
    }
    if cur_k() == 1 { LASTTY = cur_s(); TI = TI + 1; }
    return 0;
}

# 是否结构体类型（JS 要 new，Python 要实例化）
fn is_struct_ty(t: i64) -> i64 {
    if streq(t, "i64") == 1 { return 0; }
    if streq(t, "byte") == 1 { return 0; }
    if streq(t, "ptr") == 1 { return 0; }
    if streq(t, "f64") == 1 { return 0; }
    return 1;
}

fn outi(v: i64) -> i64 {
    let b: [24] byte = 0;
    utoa(v, &b, 10);
    return outs(&b);
}

# ---------- 块与语句 ----------

fn blk_open() -> i64 {
    if TGT == T_PY {
        outs(":");
        nl();
        IND = IND + 1;
        return 0;
    }
    outs(" {");
    nl();
    return 0;
}

fn blk_close() -> i64 {
    if TGT == T_PY {
        IND = IND - 1;
        return 0;
    }
    outs("}");
    nl();
    return 0;
}

# 关闭一个块并紧接着开另一个（else / else if）
fn blk_join(kw: i64) -> i64 {
    if TGT == T_PY {
        IND = IND - 1;
        outs(kw);
        outs(":");
        nl();
        IND = IND + 1;
        return 0;
    }
    outs("} ");
    outs(kw);
    outs(" {");
    nl();
    return 0;
}

fn semi() -> i64 {
    if TGT == T_PY { nl(); return 0; }
    outs(";");
    nl();
    return 0;
}

# 判断当前语句是不是赋值（只扫 token，不产生输出）
fn is_assign_start() -> i64 {
    let save: i64 = TI;
    let r: i64 = 0;
    if cur_k() == 1 {
        TI = TI + 1;
        let ok: i64 = 1;
        while ok == 1 {
            if is_op("[") == 1 {
                let d: i64 = 0;
                let done: i64 = 0;
                while TI < NT {
                    if is_op("[") == 1 { d = d + 1; }
                    else {
                        if is_op("]") == 1 {
                            d = d - 1;
                            if d == 0 { TI = TI + 1; done = 1; break; }
                        }
                    }
                    TI = TI + 1;
                }
                if done == 0 { ok = 0; }
            } else {
                if is_op(".") == 1 {
                    TI = TI + 1;
                    if cur_k() == 1 { TI = TI + 1; } else { ok = 0; }
                } else {
                    break;
                }
            }
        }
        if ok == 1 {
            if is_op("=") == 1 { r = 1; }
            else { if is_op("+=") == 1 { r = 1; }
            else { if is_op("-=") == 1 { r = 1; }
            else { if is_op("*=") == 1 { r = 1; }
            else { if is_op("/=") == 1 { r = 1; }
            else { if is_op("%=") == 1 { r = 1; }
            else { if is_op("&=") == 1 { r = 1; }
            else { if is_op("|=") == 1 { r = 1; }
            else { if is_op("^=") == 1 { r = 1; }
            else { if is_op("<<=") == 1 { r = 1; }
            else { if is_op(">>=") == 1 { r = 1; } } } } } } } } } } }
        }
    }
    TI = save;
    return r;
}

fn emit_lvalue() -> i64 {
    if is_gen() == 1 { outs(G_REF); }
    outs(ident());
    while 1 {
        if accept_op("[") == 1 {
            outs("[");
            emit_expr();
            expect_op("]");
            outs("]");
        } else {
            if accept_op(".") == 1 {
                # 同 emit_postfix：struct 指针（self）字段 → ->
                let isptr: i64 = 0;
                if TI >= 2 {
                    let sv: i64 = TI;
                    TI = TI - 2;
                    if cur_k() == 1 && ptr_find(cur_s()) == 1 { isptr = 1; }
                    TI = sv;
                }
                if isptr == 1 { outs("->"); } else { outs("."); }
                outs(ident());
            } else {
                return 0;
            }
        }
    }
    return 0;
}


# for 的 step 段：i = expr / i++ / i-- / i += expr 等（不加尾分号）。
fn emit_step() -> i64 {
    let nm: i64 = cur_s();
    TI = TI + 1;
    outs(nm);
    # ++ / --：分词器把两个 '+' 切成两个单字符 op
    if is_op("+") == 1 {
        TI = TI + 1;
        if is_op("+") == 1 { TI = TI + 1; outs("++"); return 0; }
        outs("+");
        emit_expr();
        return 0;
    }
    if is_op("-") == 1 {
        TI = TI + 1;
        if is_op("-") == 1 { TI = TI + 1; outs("--"); return 0; }
        outs("-");
        emit_expr();
        return 0;
    }
    # 其余：= += -= *= /= %= &= |= ^= <<= >>=
    outs(" ");
    outs(cur_s());
    outs(" ");
    TI = TI + 1;
    emit_expr();
    return 0;
}

# 自增/自减语句：IDENT[++|--] / IDENT[].[f]++ / IDENT[[i]]++。
# 返回 1 已发射；0 非此形态。
fn try_incdec() -> i64 {
    if cur_k() != 1 { return 0; }
    let save: i64 = TI;
    TI = TI + 1;
    # 走 lvalue 后缀链（[...]/.f）
    let ok: i64 = 1;
    while ok == 1 {
        if is_op("[") == 1 {
            let d: i64 = 0;
            let done: i64 = 0;
            while TI < NT {
                if is_op("[") == 1 { d = d + 1; }
                else {
                    if is_op("]") == 1 {
                        d = d - 1;
                        if d == 0 { TI = TI + 1; done = 1; break; }
                    }
                }
                TI = TI + 1;
            }
            if done == 0 { ok = 0; }
        } else {
            if is_op(".") == 1 {
                TI = TI + 1;
                if cur_k() == 1 { TI = TI + 1; } else { ok = 0; }
            } else {
                break;
            }
        }
    }
    if ok == 1 && is_op("+") == 1 {
        TI = TI + 1;
        if is_op("+") == 1 {
            TI = save;
            emit_lvalue();
            TI = TI + 2;   # 越过 '+' '+'
            outs("++");
            expect_op(";");
            semi();
            return 1;
        }
        TI = save; return 0;
    }
    if ok == 1 && is_op("-") == 1 {
        TI = TI + 1;
        if is_op("-") == 1 {
            TI = save;
            emit_lvalue();
            TI = TI + 2;
            outs("--");
            expect_op(";");
            semi();
            return 1;
        }
    }
    TI = save;
    return 0;
}


var SWN: i64 = 0;         # switch 唯一编号（goto break 目标）

# 接口表：接口名 → 方法名列表（按声明顺序 = vt 索引）
var IFN: [32] i64 = 0;
var IFM: [512] i64 = 0;   # 方法名池：接口 i 的方法 j = IFM[i*16+j]
var IFMC: [32] i64 = 0;
var NIF: i64 = 0;
fn iface_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NIF {
        if streq(IFN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}
# 泛型记录
var GNM: [16] i64 = 0;     # 函数名
var GPAR: [128] i64 = 0;   # 类型参数名（池 i*8+j）
var GPC: [16] i64 = 0;     # 参数个数
var G0: [16] i64 = 0;
var G1: [16] i64 = 0;
var NG: i64 = 0;
fn gen_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NG {
        if streq(GNM[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

fn iface_mid(fi: i64, mth: i64) -> i64 {
    let j: i64 = 0;
    while j < IFMC[fi] {
        if streq(IFM[fi * 16 + j], mth) == 1 { return j; }
        j = j + 1;
    }
    return -1;
}

# token 的 C 文本形态（switch 条件重放用）
fn tok_c(ti: i64) -> i64 {
    outs(&POOL + TS[ti]);
    return 0;
}
fn emit_stmt() -> i64 {
    if try_incdec() == 1 { return 0; }
    if is_assign_start() == 1 {
        emit_lvalue();
        let t: i64 = cur_s();
        TI = TI + 1;
        if TGT == T_PY {
            if streq(t, "/=") == 1 { outs(" //= "); } else { outs(" "); outs(t); outs(" "); }
        } else {
            outs(" ");
            outs(t);
            outs(" ");
        }
        emit_expr();
        expect_op(";");
        semi();
        return 0;
    }
    if accept_kw("return") == 1 {
        if is_op(";") == 1 {
            TI = TI + 1;
            outs("return");
            semi();
            return 0;
        }
        outs("return ");
        if is_c_like() == 1 { outs("("); }
        emit_expr();
        if is_c_like() == 1 { outs(")"); }
        expect_op(";");
        semi();
        return 0;
    }
    if accept_kw("break") == 1 {
        expect_op(";");
        if TGT == T_PY { line("break"); } else { line("break;"); }
        return 0;
    }
    if accept_kw("continue") == 1 {
        expect_op(";");
        if TGT == T_PY { line("continue"); } else { line("continue;"); }
        return 0;
    }
    # for (init; cond; step) { body } —— C 系直译；测试基线 132 覆盖
    # 空段（for(;;)）、++/-- 步进、+= 步进、表达式步进、嵌套。
    # 其他后端展开为 init; while (cond) { body; step; }（与 moc 一致）。
    # switch：不穿透（空 case 例外）+ fallthrough 显式 —— 与 moc 语义一致。
    # C 落地为比较链 if/else。两遍法：先扫出标签（条件 token 区间）与 body 区间，
    # 再对每组重放输出；空 case 标签并入下一组条件；fallthrough 使 body 延续到下一组。
    if accept_kw("switch") == 1 {
        expect_op("(");
        outs("{ long long switch__val = (");
        emit_expr();
        outs(");");
        expect_op(")");
        expect_op("{");
        IND = IND + 1;
        # 扫描：收集标签。SLB[i]: 标签类型(1=case 2=default)，SLC[i]/SLE[i]: 条件
        # token 区间 [C,E)，SBI[i]/SBE[i]: body 区间 [B,E)。
        let start: i64 = TI;
        let d: i64 = 0;
        let nlab: i64 = 0;
        let ltyp: [64] i64 = 0;
        let lc0: [64] i64 = 0;
        let lc1: [64] i64 = 0;
        let lb0: [64] i64 = 0;
        let idep: i64 = 0;   # 嵌套块深度（内层 switch 的 {} 与语句 {}）
        # 第一遍：定位标签
        while 1 {
            if cur_k() == 0 { return err("unexpected eof in switch"); }
            if is_op("{") == 1 { idep = idep + 1; TI = TI + 1; continue; }
            if is_op("}") == 1 {
                if idep > 0 { idep = idep - 1; TI = TI + 1; continue; }
                break;
            }
            if idep == 0 && is_kw("case") == 1 {
                lb0[nlab] = TI;        # 标签 token 起点（'case' 本身）
                TI = TI + 1;
                ltyp[nlab] = 1;
                lc0[nlab] = TI;
                let dep: i64 = 0;
                while 1 {
                    if is_op("(") == 1 { dep = dep + 1; }
                    if is_op(")") == 1 { if dep == 0 { break; } dep = dep - 1; }
                    if is_op(":") == 1 && dep == 0 { break; }
                    TI = TI + 1;
                }
                lc1[nlab] = TI;
                TI = TI + 1;   # ':'
                nlab = nlab + 1;
                if nlab >= 64 { return err("switch: case 标签过多（mo2x 上限 64）"); }
                continue;
            }
            if idep == 0 && is_kw("default") == 1 {
                lb0[nlab] = TI;
                TI = TI + 1;
                expect_op(":");
                ltyp[nlab] = 2;
                lc0[nlab] = TI;
                lc1[nlab] = TI;
                nlab = nlab + 1;
                if nlab >= 64 { return err("switch: 标签过多"); }
                continue;
            }
            TI = TI + 1;
        }
        let end: i64 = TI;   # 指向 '}'
        # body 区间：标签 i 的 body = lc1[i]+1（或 default ':' 后）到下一标签起点
        # 第二遍输出
        let i: i64 = 0;
        let nout: i64 = 0;
        while i < nlab {
            # 跳过空标签（其 body 区间为空）——并到下一组
            # 组 = 标签 i..j，j 是第一个有 body 的标签
            let j: i64 = i;
            let bend: i64 = 0;
            let b0: i64 = 0;
            while j < nlab {
                if ltyp[j] == 2 { b0 = lc1[j]; } else { b0 = lc1[j] + 1; }   # default 的 lc1 即 body 首
                if j + 1 < nlab { bend = lb0[j + 1]; }
                else { bend = end; }
                if b0 < bend { break; }
                j = j + 1;
            }
            if j >= nlab { break; }
            let onlydef: i64 = 1;
            let k0: i64 = i;
            while k0 <= j {
                if ltyp[k0] == 1 { onlydef = 0; }
                k0 = k0 + 1;
            }
            if nout == 0 {
                if onlydef == 1 { outs("if (1)"); } else { outs("if ("); }
            }
            else {
                if onlydef == 1 { outs(" else"); } else { outs(" else if ("); }
            }
            nout = nout + 1;
            # 条件列表 i..j
            let k: i64 = i;
            let cf: i64 = 1;
            while k <= j {
                if ltyp[k] == 1 {
                    if cf == 0 { outs(" || "); }
                    cf = 0;
                    outs("switch__val == (");
                    let sv: i64 = TI;
                    TI = lc0[k];
                    while TI < lc1[k] {
                        tok_c(TI);
                        TI = TI + 1;
                    }
                    TI = sv;
                    outs(")");
                }
                k = k + 1;
            }
            if onlydef == 0 { outs(")"); }
            outs(" {");
            nl();
            IND = IND + 1;

            # 重放 body
            let svb: i64 = TI;
            let swid: i64 = SWN;
            SWN = SWN + 1;
            TI = b0;
            while TI < bend {
                if is_kw("fallthrough") == 1 {
                    TI = TI + 1;
                    if is_op(";") == 1 { TI = TI + 1; }
                    # 穿透：迭代附加后续各组 body，直到无 fallthrough
                    let nx: i64 = j + 1;
                    while nx < nlab {
                        let nb0: i64 = 0;
                        let nbe: i64 = 0;
                        if ltyp[nx] == 2 { nb0 = lc1[nx]; } else { nb0 = lc1[nx] + 1; }
                        if nx + 1 < nlab { nbe = lb0[nx + 1]; } else { nbe = end; }
                        let nf: i64 = 0;   # 该组末尾是否有 fallthrough
                        if nb0 < nbe {
                            let save2: i64 = TI;
                            TI = nb0;
                            while TI < nbe {
                                if is_kw("fallthrough") == 1 {
                                    TI = TI + 1;
                                    if is_op(";") == 1 { TI = TI + 1; }
                                    nf = 1;
                                    continue;
                                }
                                if is_kw("break") == 1 {
                                    outs("goto __sw");
                                    outi(swid);
                                    outs("_end;");
                                    TI = TI + 1;
                                    if is_op(";") == 1 { TI = TI + 1; }
                                    continue;
                                }
                                emit_stmt();
                            }
                            TI = save2;
                        }
                        if nf == 0 { break; }
                        nx = nx + 1;
                    }
                    continue;
                }
                if is_kw("break") == 1 {
                    outs("goto __sw");
                    outi(swid);
                    outs("_end;");
                    TI = TI + 1;      # 越 break
                    if is_op(";") == 1 { TI = TI + 1; }   # 越 ';'
                    continue;
                }
                emit_stmt();
            }
            TI = svb;
            outs("__sw");
            outi(swid);
            outs("_end: ;");
            nl();
            IND = IND - 1;
            blk_close();
            i = j + 1;
        }
        # default 若未被合并（无 body 组）—— 检查
        let di: i64 = 0;
        let hasdef: i64 = 0;
        while di < nlab {
            if ltyp[di] == 2 { hasdef = 1; }
            di = di + 1;
        }
        if hasdef == 1 && nout > 0 {
            # default 是否已输出？若 default 是最后标签且其组已含 —— 上循环处理。
            # 兜底：若无任何组包含 default（全空），跳过。
        }
        TI = end;
        expect_op("}");
        outs("}");
        semi();
        return 0;
    }
    # 嵌套函数（闭包）：就地发射为 GNU C 嵌套函数 —— gcc 词法作用域自动
    # 捕获外层局部变量（与 moc 的静态链语义一致，一层嵌套）。
    # 仅 C 系后端支持；注意嵌套函数的 self/struct 捕获不在此列。
    if accept_kw("fn") == 1 {
        if is_c_like() == 0 {
            return err("嵌套函数仅在 C 系后端支持");
        }
        emit_sig();
        emit_block_body();
        return 0;
    }
    if accept_kw("for") == 1 {
        expect_op("(");
        if is_c_like() == 1 {
            outs("for (");
            if is_op(";") == 0 { emit_stmt(); if is_op(";") == 1 { TI = TI + 1; } }
            else { TI = TI + 1; outs(";"); }
            outs(" ");
            if is_op(";") == 0 { emit_expr(); }
            outs(";");
            if is_op(";") == 1 { TI = TI + 1; }
            if is_op(")") == 0 { outs(" "); emit_step(); }
            outs(")");
            expect_op(")");
        } else {
            return err("for 仅在 C 系后端支持（其余后端待实现展开）");
        }
        expect_op("{");
        blk_open();
        emit_stmts();
        blk_close();
        return 0;
    }
    if accept_kw("while") == 1 {
        if TGT == T_PY { outs("while "); } else { outs("while ("); }
        emit_expr();
        if TGT != T_PY { outs(")"); }
        expect_op("{");
        blk_open();
        emit_stmts();
        blk_close();
        return 0;
    }
    if accept_kw("if") == 1 {
        if TGT == T_PY { outs("if "); } else { outs("if ("); }
        emit_expr();
        if TGT != T_PY { outs(")"); }
        expect_op("{");
        blk_open();
        emit_stmts();
        while is_kw("else") == 1 {
            TI = TI + 1;
            if is_kw("if") == 1 {
                TI = TI + 1;
                if TGT == T_PY {
                    IND = IND - 1;
                    outs("elif ");
                    emit_expr();
                    outs(":");
                    nl();
                    IND = IND + 1;
                } else {
                    outs("} else if (");
                    emit_expr();
                    outs(") {");
                    nl();
                }
                expect_op("{");
                emit_stmts();
            } else {
                blk_join("else");
                expect_op("{");
                emit_stmts();
            }
        }
        blk_close();
        return 0;
    }
    if accept_kw("let") == 1 {
        emit_local();
        return 0;
    }
    if accept_op("{") == 1 {
        blk_open();
        emit_stmts();
        blk_close();
        return 0;
    }
    emit_expr();
    expect_op(";");
    semi();
    return 0;
}

fn emit_stmts() -> i64 {
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in block"); }
        emit_stmt();
    }
    TI = TI + 1;
    return 0;
}

fn emit_block_body() -> i64 {
    expect_op("{");
    if TGT == T_PY {
        IND = 0;
        outs(":");
        nl();
        IND = 1;
    } else {
        outs(" {");
        nl();
    }
    emit_stmts();
    if TGT == T_PY { IND = 0; } else { line("}"); }
    return 0;
}

# ---------- 声明 ----------

# 局部：let name: T [= expr];
fn emit_local() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    if is_c_like() == 1 {
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        emit_scalar_or_arr(nm, isarr);
        if accept_op("=") == 1 {
            if isarr == 1 {
                outs(" = {");
                if cur_k() == 3 { emit_strbytes(cur_s(), 0); TI = TI + 1; }
                else { if is_op("[") == 1 { emit_arrlit(); } else { emit_expr(); } }
                outs("}");
            }
            else {
                outs(" = (");
                # `let p: i64 = &arr;` 在 C 系后端原本是**硬错误**：
                # 用 unsigned char* 初始化 long long 属指针→整数转换。
                # 而"这块缓冲在哪"恰恰只能通过取地址表达（virtio 描述符
                # 就要填缓冲的物理地址）。取地址赋给 i64 是正当用法，
                # 所以这里补一个显式转换，而不是让调用方去改编译选项。
                if is_op("&") == 1 { outs("(long long)"); }
                emit_expr();
                outs(")");
            }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    let dim: i64 = consume_type();
    if TGT == T_JS {
        outs("let ");
        outs(nm);
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if accept_op("=") == 1 {
            if dim > 0 { emit_expr(); } else { outs(" = "); emit_expr(); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if streq(LASTTY, "str") == 1 && dim == 0 { strv_add(nm); }
    outs(nm);
    if dim > 0 {
        outs(" = [0] * ");
        outi(dim);
        if accept_op("=") == 1 { emit_expr(); }
    } else {
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
    }
    nl();
    expect_op(";");
    return 0;
}

# 全局：var name: T = expr;
# 数组字面量：[e1, e2, ...] → 逐元素裸输出（调用方已包 { }）。
# 元素可为负数字面量；元素少于数组长度时 C 的初始化列表自动补 0 —— 语义一致。
# byte 数组的字符串初始化：var b: [8] byte = "hi" → {104,105,33,0,...}。
# C 里 (unsigned char*)"hi" 不是静态初始化器，必须展开成字节列表。
fn emit_strbytes(strp: i64, cap: i64) -> i64 {
    let n: i64 = 0;
    while load8(strp + n) != 0 {
        let b: [24] byte = 0;
        utoa(load8(strp + n), &b, 10);
        if n > 0 { outs(", "); }
        outs(&b);
        n = n + 1;
    }
    # C 语义：显式初始化器之后自动补 0 —— 与 Mo 的"不足补 0"一致
    return 0;
}

fn emit_arrlit() -> i64 {
    expect_op("[");
    let first: i64 = 1;
    while is_op("]") == 0 {
        if first == 0 { outs(", "); }
        first = 0;
        if is_op("[") == 1 {
            outs("{");
            emit_arrlit();
            outs("}");
            if is_op(",") == 1 { TI = TI + 1; }
            continue;
        }
        emit_expr();
        if is_op(",") == 1 { TI = TI + 1; } else { break; }
    }
    expect_op("]");
    return 0;
}

fn emit_global() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    if is_c_like() == 1 {
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        emit_scalar_or_arr(nm, isarr);
        if accept_op("=") == 1 {
            if isarr == 1 {
                outs(" = {");
                if cur_k() == 3 { emit_strbytes(cur_s(), 0); TI = TI + 1; }
                else { if is_op("[") == 1 { emit_arrlit(); } else { emit_expr(); } }
                outs("}");
            }
            else {
                outs(" = (");
                # `let p: i64 = &arr;` 在 C 系后端原本是**硬错误**：
                # 用 unsigned char* 初始化 long long 属指针→整数转换。
                # 而"这块缓冲在哪"恰恰只能通过取地址表达（virtio 描述符
                # 就要填缓冲的物理地址）。取地址赋给 i64 是正当用法，
                # 所以这里补一个显式转换，而不是让调用方去改编译选项。
                if is_op("&") == 1 { outs("(long long)"); }
                emit_expr();
                outs(")");
            }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    let dim: i64 = consume_type();
    if TGT == T_JS {
        outs("let ");
        outs(nm);
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if accept_op("=") == 1 {
            if dim > 0 { emit_expr(); } else { outs(" = "); emit_expr(); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if streq(LASTTY, "str") == 1 && dim == 0 { strv_add(nm); }
    outs(nm);
    if dim > 0 {
        outs(" = [0] * ");
        outi(dim);
        if accept_op("=") == 1 { emit_expr(); }
    } else {
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
    }
    nl();
    expect_op(";");
    return 0;
}

# 结构体
fn emit_struct() -> i64 {
    let nm: i64 = ident();
    if is_c_like() == 1 {
        outs("typedef struct ");
        outs(nm);
        outs("_t {\n");
        let myi: i64 = NST;
        if NST < 32 {
            STN[NST] = nm;
            STF[NST] = NCLSF;
            STFN[NST] = 0;
            NST = NST + 1;
        }
        # 继承：class A : B —— 基类字段**扁平展开**（与 moc 的内存布局一致）。
        if accept_op(":") == 1 {
            let base: i64 = ident();
            let bi: i64 = st_find(base);
            if bi < 0 { return err("class 继承的基类未在此前定义（mo2x 需先基类后派生）"); }
            let j: i64 = 0;
            while j < STFN[bi] {
                let fi: i64 = STF[bi] + j * 2;
                outs("  ");
                emit_scalar(CLSF[fi + 1]);   # 类型（映射 i64→long long 等）
                outs(" ");
                outs(CLSF[fi]);       # 名
                outs(";\n");
                j = j + 1;
            }
        }
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let fn2: i64 = ident();
            expect_op(":");
            # 记录 (名, 类型) 供派生类展开。类型名在 emit_scalar_or_arr 内被消耗 ——
            # 先偷看：cur 是类型 ident。
            let fty: i64 = cur_s();
            if myi < 32 && NCLSF < 250 {
                CLSF[NCLSF] = fn2;
                CLSF[NCLSF + 1] = fty;
                NCLSF = NCLSF + 2;
                STFN[myi] = STFN[myi] + 1;
            }
            emit_scalar_or_arr(fn2, 0);
            outs(";");
            nl();
            expect_op(";");
        }
        TI = TI + 1;
        outs("} ");
        outs(nm);
        outs("_t;\n");
        return 0;
    }
    if TGT == T_JS {
        outs("function ");
        outs(nm);
        outs("() {\n");
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let fn2: i64 = ident();
            expect_op(":");
            let dim: i64 = consume_type();
            outs("  this.");
            outs(fn2);
            if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); } else { outs(" = 0"); }
            outs(";");
            nl();
            expect_op(";");
        }
        TI = TI + 1;
        outs("}\n");
        return 0;
    }
    outs("class ");
    outs(nm);
    outs(":\n");
    outs("    def __init__(self):\n");
    expect_op("{");
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in struct"); }
        let fn2: i64 = ident();
        expect_op(":");
        let dim: i64 = consume_type();
        outs("        self.");
        outs(fn2);
        if dim > 0 { outs(" = [0] * "); outi(dim); } else { outs(" = 0"); }
        nl();
        expect_op(";");
    }
    TI = TI + 1;
    return 0;
}

# 函数签名
fn emit_sig() -> i64 {
    let nm: i64 = ident();
    expect_op("(");
    let first: i64 = 1;
    let ps: [512] byte = 0;
    while is_op(")") == 0 {
        # 可变参数：extern 声明里的 `...`（printf 等 libc 函数）。
        # 分词器把三个 '.' 切成三个独立 token —— 这里合并识别。
        if is_op(".") == 1 {
            TI = TI + 1;
            expect_op(".");
            expect_op(".");
            strcat(&ps, ", ...");
            first = 0;
            if is_op(",") == 1 { TI = TI + 1; }
            continue;
        }
        if first == 0 { strcat(&ps, ", "); }
        first = 0;
        let pn: i64 = ident();
        expect_op(":");
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        if is_c_like() == 1 {
            if isarr == 1 { skip_brackets(); }
            let t: i64 = ident();
            if streq(t, "i64") == 1 { strcat(&ps, "long long"); }
            else {
                if streq(t, "i32") == 1 { strcat(&ps, "int"); }
                else {
                if streq(t, "byte") == 1 { strcat(&ps, "unsigned char"); }
                else {
                    if streq(t, "ptr") == 1 { strcat(&ps, "unsigned char*"); }
                    else {
                        if streq(t, "f64") == 1 { strcat(&ps, "double"); }
                        else {
                            # struct 形参：moc 语义是引用（self.x=… 对调用方可见）。
                            strcat(&ps, "struct "); strcat(&ps, t); strcat(&ps, "_t*");
                            if NTRS < 64 { PTRS[NTRS] = pn; NTRS = NTRS + 1; }
                            clsv_add(pn, t);   # 方法接收者也可 .method()
                        }
                    }
                }
                }
            }
            strcat(&ps, " ");
            strcat(&ps, pn);
        } else {
            strcat(&ps, pn);
            let d: i64 = consume_type();
        }
        if is_op(",") == 1 { TI = TI + 1; } else { break; }
    }
    expect_op(")");
    accept_op("-");
    accept_op(">");
    let rt: i64 = 0;
    if cur_k() == 1 { rt = cur_s(); TI = TI + 1; }
    let ismain: i64 = 0;
    if streq(nm, "main") == 1 { ismain = 1; }

    if is_c_like() == 1 {
        if rt != 0 {
            if streq(rt, "i64") == 1 { outs("long long "); }
            else {
                if streq(rt, "i32") == 1 { outs("int "); }
                else {
                if streq(rt, "byte") == 1 { outs("unsigned char "); }
                else {
                    if streq(rt, "f64") == 1 { outs("double "); }
                    else {
                        # 🔴 ptr/str 返回值：此前漏判 → `struct ptr_t` 未定义类型
                        #    （examples/arenademo.mo 的 Arena_alloc 返回 ptr 时炸出
                        #     invalid use of undefined type 'struct ptr_t'）。
                        if streq(rt, "ptr") == 1 { outs("unsigned char* "); }
                        else {
                            if streq(rt, "str") == 1 { outs("unsigned char* "); }
                            else { outs("struct "); outs(rt); outs("_t "); }
                        }
                    }
                }
                }
            }
        } else { outs("long long "); }
        if ismain == 1 { outs("mo_main"); } else { outs(nm); }
        outs("(");
        outs(&ps);
        outs(")");
        return 0;
    }
    if TGT == T_JS {
        outs("function ");
        outs(nm);
        outs("(");
        outs(&ps);
        outs(")");
        return 0;
    }
    outs("def ");
    outs(nm);
    outs("(");
    outs(&ps);
    outs(")");
    return 0;
}

fn skip_brackets() -> i64 {
    while is_op("[") == 1 {
        TI = TI + 1;
        TI = TI + 1;
        expect_op("]");
    }
    return 0;
}

# ---------- 跳过 ----------

fn skip_balanced() -> i64 {
    while is_op("{") == 0 {
        if cur_k() == 0 { return 0; }
        TI = TI + 1;
    }
    let d: i64 = 0;
    while 1 {
        if cur_k() == 0 { return 0; }
        if is_op("{") == 1 { d = d + 1; }
        else {
            if is_op("}") == 1 {
                d = d - 1;
                TI = TI + 1;
                if d == 0 { return 0; }
                continue;
            }
        }
        TI = TI + 1;
    }
    return 0;
}

fn skip_to_semi() -> i64 {
    while is_op(";") == 0 {
        if cur_k() == 0 { return 0; }
        TI = TI + 1;
    }
    TI = TI + 1;
    return 0;
}

# ---------- 文件表 ----------

var PBUF: [4096] byte = 0;

fn add_file(path: i64) -> i64 {
    let i: i64 = 0;
    while i < NF {
        if streq(&FP + FILES[i], path) == 1 { return 0; }
        i = i + 1;
    }
    if NF >= 64 { return -1; }
    let o: i64 = FPP;
    let k: i64 = 0;
    while load8(path + k) != 0 {
        store8(&FP + FPP, load8(path + k));
        FPP = FPP + 1;
        k = k + 1;
    }
    store8(&FP + FPP, 0);
    FPP = FPP + 1;
    FILES[NF] = o;
    NF = NF + 1;
    return 0;
}

fn resolve(path: i64, dst: i64) -> i64 {
    if exists(path) == 1 {
        strcpy(dst, path);
        return 0;
    }
    let bi: i64 = 0;
    let i: i64 = 0;
    while load8(path + i) != 0 {
        if load8(path + i) == 47 { bi = i + 1; }
        i = i + 1;
    }
    strcpy(dst, "lib/");
    strcat(dst, path + bi);
    if exists(dst) == 1 { return 0; }
    strcpy(dst, "../lib/");
    strcat(dst, path + bi);
    if exists(dst) == 1 { return 0; }
    return -1;
}

# 扫描 token，记录是否需要 Linux 特定能力。
# C 后端原先无条件输出 <sys/syscall.h>，于是 Windows / macOS 直接编译失败
# （那两个平台根本没有这个头）。应该按需输出。
fn scan_needs() -> i64 {
    let k: i64 = 0;
    while k < NT {
        if TK[k] == 1 {
            let nm: i64 = &POOL + TS[k];
            if streq(nm, "syscall") == 1 { NEED_SYS = 1; }
            if streq(nm, "load8") == 1 { NEED_SYS = 1; }
            if streq(nm, "load64") == 1 { NEED_SYS = 1; }
            if streq(nm, "store8") == 1 { NEED_SYS = 1; }
            if streq(nm, "store64") == 1 { NEED_SYS = 1; }
            if streq(nm, "atomic_cas") == 1 { NEED_SYS = 1; }
            if streq(nm, "call2") == 1 { NEED_CALL2 = 1; }
            if streq(nm, "argc") == 1 { NEED_SYS = 1; }
            if streq(nm, "argv") == 1 { NEED_SYS = 1; }
        }
        k = k + 1;
    }
    return 0;
}

# 文件真实大小（open + lseek(SEEK_END) + close）。
#
# 为什么必须知道它：read_file(buf, cap) 在文件超过 cap 时**静默截断**，
# 返回 cap-1，调用方看不出"读完了"和"被截断了"的区别。截断后的半截文件
# 在 parser 手里只会撞到一个莫名其妙的 EOF，报错位置是缓冲边界对应的行。
#
# 实测（v1.179）：src/compiler.mo 346889 字节，VSRC 上限 131072 时
#   mo2x: src/compiler.mo:3618: unexpected eof in block at '<eof>'
# 而 `head -c 131071 src/compiler.mo` 报的是**同一行同一个错** ——
# 说明与 compiler.mo 的语法毫无关系，纯粹是缓冲边界。
fn file_size(path: i64) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0);
    if fd < 0 { return -1; }
    let sz: i64 = syscall(8, fd, 0, 2, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    return sz;
}

var NTOT: [64] i64 = 0;
fn load_file(i: i64) -> i64 {
    let n: i64 = read_file(&FP + FILES[i], &SRC, 524287);
    if n < 0 {
        syscall(1, 2, "mo2x: cannot open ", 19, 0, 0, 0);
        syscall(1, 2, &FP + FILES[i], strlen(&FP + FILES[i]), 0, 0, 0);
        syscall(1, 2, "\n", 1, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    # 截断检查：读满了上限就**必须**去问真实大小。
    # 不检查的话，超限文件表现为一个指向随机行的语法错 ——
    # 那是本项目反复出现的形状：**缓冲满了却报成语法错**。
    if n >= 524287 {
        let sz: i64 = file_size(&FP + FILES[i]);
        let lb: [24] byte = 0;
        if sz > 0 { utoa(sz, &lb, 10); } else { utoa(n, &lb, 10); }
        err("源文件超过 524287 字节上限（实际 ");
        syscall(1, 2, &lb, strlen(&lb), 0, 0, 0);
        syscall(1, 2, " 字节）—— 请拆分或抬高 SRC 上限\n", 36, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    store8(&SRC + n, 0);
    PP = 0;
    tokenize();
    scan_needs();
    NTOT[i] = NT;
    return 0;
}

# kind: 0=收集 import + struct  1=var  2=函数签名  3=函数体
var INS_DONE: i64 = 0;
fn pass_file(i: i64, kind: i64) -> i64 {
    CURF = i;
    INS_DONE = 0;
    load_file(i);
    if kind == 3 {
        nl();
        if is_gen() == 1 { raw(G_CMT); raw(" ---- "); raw(&FP + FILES[i]); raw(" ----\n"); }
        else {
            if TGT == T_PY { raw("# ---- "); raw(&FP + FILES[i]); raw(" ----\n"); }
            else { raw("/* ---- "); raw(&FP + FILES[i]); raw(" ---- */\n"); }
        }
    }
    while cur_k() != 0 {
        if INS_DONE == 1 && TI >= NTOT[CURF] { break; }
        if accept_kw("import") == 1 {
            if cur_k() == 3 {
                let p: i64 = cur_s();
                TI = TI + 1;
                if kind == 0 {
                    if resolve(p, &PBUF) == 0 { add_file(&PBUF); }
                }
            }
            accept_op(";");
        } else {
            if accept_kw("struct") == 1 {
                if kind == 0 {
                    if is_gen() == 1 { g_struct(); } else { emit_struct(); }
                } else { skip_balanced(); }
            } else {
                # class Name [: Base] { field: T; ... } —— 与 struct 同义。
                if accept_kw("class") == 1 {
                    if kind == 0 {
                        if is_gen() == 1 { g_struct(); } else { emit_struct(); }
                    } else { skip_balanced(); }
                } else {
                    # interface Name { fn m(self: ptr, ...); ... }
                    # → typedef struct { void* obj; void* vt; } Name_t;
                    # generic fn name<T,U>(...)：记录 token 区间，不发射
                    if accept_kw("generic") == 1 {
                        if kind != 0 { skip_balanced(); continue; }
                        accept_kw("fn");
                        let gn: i64 = ident();
                        let gi: i64 = NG;
                        if NG < 16 {
                            GNM[NG] = gn;
                            G0[NG] = TI - 1;   # 指向函数名（emit_sig 从名开始）
                            GPC[NG] = 0;
                            NG = NG + 1;
                        }
                        expect_op("<");
                        while is_op(">") == 0 {
                            if cur_k() == 1 {
                                if gi < 16 && GPC[gi] < 8 {
                                    GPAR[gi * 8 + GPC[gi]] = cur_s();
                                    GPC[gi] = GPC[gi] + 1;
                                }
                                TI = TI + 1;
                            } else { TI = TI + 1; }
                            # 跳过 bound：': Type + Type2'（到 ',' 或 '>' 为止）
                            if is_op(":") == 1 {
                                TI = TI + 1;
                                while is_op(",") == 0 && is_op(">") == 0 { TI = TI + 1; }
                            }
                            if is_op(",") == 1 { TI = TI + 1; }
                        }
                        expect_op(">");
                        # 推进到函数体结束 '}'（签名 + 块，用括号深度）
                        let dep2: i64 = 0;
                        let started: i64 = 0;
                        while 1 {
                            if cur_k() == 0 { return err("unexpected eof in generic"); }
                            if is_op("{") == 1 { dep2 = dep2 + 1; started = 1; }
                            if is_op("}") == 1 {
                                dep2 = dep2 - 1;
                                if dep2 == 0 && started == 1 { TI = TI + 1; break; }
                            }
                            TI = TI + 1;
                        }
                        if gi < 16 { G1[gi] = TI; }
                        continue;
                    }
                    # instantiate name(T1,T2) as alias; —— 单态化发射
                    if accept_kw("instantiate") == 1 {
                        if kind != 3 { skip_to_semi(); continue; }
                        let gn2: i64 = ident();
                        expect_op("(");
                        let a0: [8] i64 = 0;
                        let na: i64 = 0;
                        while is_op(")") == 0 {
                            if cur_k() == 1 {
                                if na < 8 { a0[na] = cur_s(); na = na + 1; }
                                TI = TI + 1;
                            } else { TI = TI + 1; }
                            if is_op(",") == 1 { TI = TI + 1; }
                        }
                        expect_op(")");
                        accept_kw("as");
                        let alias: i64 = ident();
                        expect_op(";");
                        let gi2: i64 = gen_find(gn2);
                        if gi2 < 0 { return err("instantiate: 泛型函数未定义"); }
                        # 追加替换后的 token 拷贝到流尾，然后发射
                        let base: i64 = NT;
                        let ti2: i64 = G0[gi2];
                        let inskip: i64 = 0;
                        while ti2 < G1[gi2] {
                            # 跳过签名里的 <T,U> 泛型参数段
                            if inskip == 0 && TK[ti2] == 5 && streq("<", &POOL + TS[ti2]) == 1 && ti2 < G0[gi2] + 4 {
                                inskip = 1; ti2 = ti2 + 1; continue;
                            }
                            if inskip == 1 {
                                if TK[ti2] == 5 && streq(">", &POOL + TS[ti2]) == 1 { inskip = 0; }
                                ti2 = ti2 + 1; continue;
                            }
                            let replaced: i64 = 0;
                            if TK[ti2] == 1 {
                                let p2: i64 = 0;
                                while p2 < GPC[gi2] {
                                    if streq(GPAR[gi2 * 8 + p2], &POOL + TS[ti2]) == 1 {
                                        # 类型参数 → 实参类型 token（原类型名，emit_scalar 会映射）
                                        add_tok(1, a0[p2]);
                                        replaced = 1;
                                        break;
                                    }
                                    p2 = p2 + 1;
                                }
                                if replaced == 0 && streq(GNM[gi2], &POOL + TS[ti2]) == 1 {
                                    add_tok(1, alias);
                                    replaced = 1;
                                }
                            }
                            if replaced == 0 {
                                add_tok(TK[ti2], &POOL + TS[ti2]);
                            }
                            ti2 = ti2 + 1;
                        }
                        let iai: i64 = NIAC;
                        if NIAC < 32 {
                            IAN[NIAC] = alias;
                            let pz: i64 = 0;
                            while pz < 8 { IPARM[NIAC * 8 + pz] = 0; pz = pz + 1; }
                            NIAC = NIAC + 1;
                        }
                        # 由拷贝流推导原型：alias( a: T, ... ) -> RT
                        # 返回类型：扫到 [)][-][>] 取其后类型
                        let rq: i64 = base;
                        let rty: i64 = 0;
                        while rq < NT {
                            if TK[rq] == 5 && streq(">", &POOL + TS[rq]) == 1 && rq > base && TK[rq - 1] == 5 && streq("-", &POOL + TS[rq - 1]) == 1 && TK[rq + 1] == 1 {
                                rty = rq + 1; 
                                break;
                            }
                            rq = rq + 1;
                        }
                        if rty != 0 { emit_scalar(&POOL + TS[rty]); } else { outs("long long"); }
                        outs(" ");
                        outs(alias);
                        let fp: i64 = base + 1;
                        while !(TK[fp] == 5 && streq("(", &POOL + TS[fp]) == 1) { fp = fp + 1; }
                        if TK[fp] == 5 && streq("(", &POOL + TS[fp]) == 1 {
                            outs("(");
                            fp = fp + 1;
                            let fst: i64 = 1;
                            while TK[fp] != 0 && !(TK[fp] == 5 && streq(")", &POOL + TS[fp]) == 1) {
                                # 形如 [名][:][类型] [,]
                                if TK[fp] == 1 && TK[fp + 1] == 5 && streq(":", &POOL + TS[fp + 1]) == 1 {
                                    if fst == 0 { outs(","); outs(" "); }
                                    fst = 0;
                                    let pty: i64 = &POOL + TS[fp + 2];
                                    let isbi: i64 = 0;
                                    if streq("i64", pty) == 1 { isbi = 1; }
                                    if streq("f64", pty) == 1 { isbi = 1; }
                                    if streq("i32", pty) == 1 { isbi = 1; }
                                    if streq("byte", pty) == 1 { isbi = 1; }
                                    if streq("ptr", pty) == 1 { isbi = 1; }
                                    if streq("str", pty) == 1 { isbi = 1; }
                                    if streq("i8", pty) == 1 { isbi = 1; }
                                    if streq("i16", pty) == 1 { isbi = 1; }
                                    if streq("u64", pty) == 1 { isbi = 1; }
                                    emit_scalar(pty);
                                    if isbi == 0 { outs("*"); if iai < 32 && (fp - 2 - base) / 3 < 8 { IPARM[iai * 8 + (fp - 2 - base) / 3] = 1; } }
                                    outs(" ");
                                    outs(&POOL + TS[fp]);
                                    fp = fp + 3;
                                } else { fp = fp + 1; }
                            }
                            outs(");");
                            nl();
                        }
                        # 生成体内被调用的函数 → 旧式前向声明（防 implicit 冲突）
                        let cq: i64 = base;
                        let kwok: i64 = 1;
                        while cq < NT - 1 {
                            if TK[cq] == 1 && TK[cq + 1] == 5 && streq("(", &POOL + TS[cq + 1]) == 1 {
                                kwok = 1;
                                if streq("if", &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq("while", &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq("for", &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq("return", &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq("sizeof", &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq(alias, &POOL + TS[cq]) == 1 { kwok = 0; }
                                if streq(gn2, &POOL + TS[cq]) == 1 { kwok = 0; }
                                if kwok == 1 {
                                    outs("long long ");
                                    outs(&POOL + TS[cq]);
                                    outs("();");
                                    nl();
                                }
                                cq = cq + 2;
                            } else { cq = cq + 1; }
                        }
                        # 形参登记到 CLSV（体里 obj.method() 需要）
                        let pq: i64 = base + 1;
                        let pn: i64 = 0;
                        while TK[pq] != 0 && !(TK[pq] == 5 && streq(")", &POOL + TS[pq]) == 1) {
                            if TK[pq] == 1 && TK[pq + 1] == 5 && streq(":", &POOL + TS[pq + 1]) == 1 {
                                let pnm: i64 = &POOL + TS[pq];
                                let pty: i64 = &POOL + TS[pq + 2];
                                let isbi2: i64 = 0;
                                if streq("i64", pty) == 1 { isbi2 = 1; }
                                if streq("f64", pty) == 1 { isbi2 = 1; }
                                if streq("i32", pty) == 1 { isbi2 = 1; }
                                if streq("byte", pty) == 1 { isbi2 = 1; }
                                if streq("ptr", pty) == 1 { isbi2 = 1; }
                                if streq("str", pty) == 1 { isbi2 = 1; }
                                if isbi2 == 0 { clsv_add(pnm, pty); }
                                pn = pn + 1;
                                pq = pq + 3;
                            } else { pq = pq + 1; }
                        }
                        let sv3: i64 = TI;
                        TI = base;
                        emit_sig();
                        emit_block_body();
                        TI = sv3;
                        # 标记：本 pass 发射过拷贝，主循环爬到 NTOT[CURF] 即文件尾
                        INS_DONE = 1;
                        TI = sv3;
                        continue;
                    }
                    if accept_kw("interface") == 1 {
                        if kind != 0 { skip_balanced(); continue; }
                        let inm: i64 = ident();
                        if NIF < 32 {
                            IFN[NIF] = inm;
                            IFMC[NIF] = 0;
                            NIF = NIF + 1;
                        }
                        let fi: i64 = iface_find(inm);
                        if is_c_like() == 1 {
                            outs("typedef struct ");
                            outs(inm);
                            outs("_t { void* obj; void* vt; } ");
                            outs(inm);
                            outs("_t;");
                            nl();
                        }
                        expect_op("{");
                        while is_op("}") == 0 {
                            if accept_kw("fn") == 1 {
                                let fm: i64 = ident();
                                if fi >= 0 && IFMC[fi] < 16 {
                                    IFM[fi * 16 + IFMC[fi]] = fm;
                                    IFMC[fi] = IFMC[fi] + 1;
                                }
                                skip_to_semi();
                            } else { TI = TI + 1; }
                        }
                        TI = TI + 1;   # '}'
                        continue;
                    }
                    # impl IFACE for TYPE { m1; m2; }
                    # → void* IFACE_TYPE_vt[] = { [0]=(void*)TYPE_m1, ... };
                    if accept_kw("impl") == 1 {
                        if kind != 3 { skip_balanced(); continue; }
                        let ifn: i64 = ident();
                        accept_kw("for");
                        let tn: i64 = ident();
                        let fi: i64 = iface_find(ifn);
                        if is_c_like() == 1 {
                            # 旧式无原型声明：vt 初始化器引用的函数此时还没定义
                            if fi >= 0 {
                                let j3: i64 = 0;
                                while j3 < IFMC[fi] {
                                    outs("long long ");
                                    outs(tn);
                                    outs("_");
                                    outs(IFM[fi * 16 + j3]);
                                    outs("();");
                                    nl();
                                    j3 = j3 + 1;
                                }
                            }
                            outs("void* ");
                            outs(ifn);
                            outs("_");
                            outs(tn);
                            outs("_vt[");
                            if fi >= 0 { outi(IFMC[fi]); } else { outs("0"); }
                            outs("] = {");
                            if fi >= 0 {
                                let j2: i64 = 0;
                                let cf2: i64 = 1;
                                while j2 < IFMC[fi] {
                                    if cf2 == 0 { outs(", "); }
                                    cf2 = 0;
                                    outs("[");
                                    outi(j2);
                                    outs("]=(void*)");
                                    outs(tn);
                                    outs("_");
                                    outs(IFM[fi * 16 + j2]);
                                    j2 = j2 + 1;
                                }
                            }
                            outs("};");
                            nl();
                        }
                        expect_op("{");
                        while is_op("}") == 0 { TI = TI + 1; }
                        TI = TI + 1;
                        continue;
                    }
                if accept_kw("var") == 1 {
                    if kind == 1 {
                        if is_gen() == 1 { g_global(); } else { emit_global(); }
                    } else { skip_to_semi(); }
                } else {
                    if accept_kw("extern") == 1 {
                        # extern 声明：`extern fn g(...) -> i32;`（无函数体）。
                        # 此前 'extern' 落进兜底的 TI+1 分支，'fn' 被当普通声明，
                        # kind==2 时 emit_sig 之后调的是 skip_balanced ——
                        # 它找 '{' 找不到，把声明后面的**所有内容**一路吞到文件尾，
                        # 报 "expected operator at ';'"，且报错行号指向下一个文件/EOF。
                        # 症状：lib/csp.mo、lib/lf.mo、lib/thread.mo、examples/ffi.mo
                        # 等 4+ 文件在全部 C 系后端（含 cfs-aarch64 安卓）编译失败。
                        # 修法：extern 分支显式处理 —— 声明输出后用 skip_to_semi。
                        if cur_k() == 1 && streq(cur_s(), "fn") == 1 {
                            TI = TI + 1;
                            if kind == 2 {
                                if is_gen() == 0 && is_c_like() == 1 {
                                    emit_sig();
                                    outs(";");
                                    nl();
                                }
                                skip_to_semi();
                            } else {
                                skip_to_semi();
                            }
                        } else {
                            skip_to_semi();
                        }
                    } else {
                    if accept_kw("fn") == 1 {
                        # 输出函数是"后端提供"的：C 系目标用 printf 实现，
                        # 而不是照搬 io.mo 里基于 syscall 的写法 ——
                        # WASI 根本没有 syscall()，照搬会链接失败。
                        # 所以这里同时跳过前向声明与函数体。
                        if peek_builtin_fn() == 1 {
                            skip_balanced();
                        } else {
                        if kind == 2 {
                            if is_gen() == 1 { skip_balanced(); } else { if is_c_like() == 1 {
                                emit_sig();
                                outs(";");
                                nl();
                            } }
                            if is_gen() == 0 { skip_balanced(); }
                        } else {
                            if kind == 3 {
                                if is_gen() == 1 { g_sig(); g_block(); } else { emit_sig(); emit_block_body(); }
                            } else {
                                skip_balanced();
                            }
                        }
                        }
                    } else {
                        # 🔴 顶层加固（v1.190.0）：kind==3 发射轮里，顶层出现裸 '{' 或 '}'
                        # 一律是括号不平衡的泄漏 —— kvserver 事故（else 链少 1 个 } +
                        # fn 尾多 1 个 } 恰好抵消）里，多出的 } 就是从这里被静默吞掉，
                        # 解析树错位导致运行时段错。现在响亮报错，带 fn 名与行号。
                        if kind == 3 {
                            if is_op("}") == 1 {
                                return err("顶层出现多余的 '}'：某函数/块的括号不平衡（检查最近编辑的 fn 的 else 链与结尾）");
                            }
                            if is_op("{") == 1 {
                                return err("顶层出现多余的 '{'：某函数/块的括号不平衡");
                            }
                        }
                        TI = TI + 1;
                    }
                    }
                }
            }
            }
        }
    }
    return 0;
}

# ---------- 前后缀 ----------

fn fs_header() -> i64 {
    line("/* generated by mo2x -- 墨语言 freestanding 后端 */");

    # 内存原语（load8/store8/load64/store64）—— 此前**只有 kern 后端**输出它们，
    # cfs 后端不输出，于是在 freestanding 程序里写 load8 会得到
    #   error: call to undeclared function 'load8'
    # 这让 cfs 上的包管理器读不了目录项（getdents64 的 buffer 必须逐字节解），
    # 也解析不了清单文件。C 系后端指针语义本来就一致，这里补齐。
    emit_mem_macros();

    line("/* 完全不依赖 libc：系统调用用内联汇编直接陷入内核 */");
    raw("/* 目标架构: ");
    raw(FSNAME);
    raw(" */\n");
    # freestanding（不链 libc）下，C 编译器会把"手写循环"**识别成库函数调用**：
    #   slen 里的 while (s[i]) 循环  →  strlen(s)
    #   大数组 = 0 的清零            →  memset(...)
    # 于是链接时报 `undefined symbol: strlen` / `memset`（v1.154 记过后者）。
    #
    # 关键：**别名宏挡不住**。`#define strlen strlen_` 是预处理阶段的事，
    # 而编译器是在 IR 层插入对**原名 `strlen`** 的引用 —— 那时预处理早已结束。
    # 所以这里必须提供原名符号本身，而不是只给带下划线的别名。
    #
    # v1.154 当时的绕法是"数组不写 = 0"，那治的是症状；这里修的是根因。
    line("static long strlen(const unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
    # strcmp：try_strcmp 改写需要。-nostdlib 无 libc，但 lib/str.mo 会带实现；
    # 为不重复定义，前导不提供 strcmp —— 依赖 str.mo 的程序已覆盖，未引 str.mo
    # 而用字符串比较的程序需 import str.mo（响亮报错：undefined reference）。
    # fbits：f64 位模式 → i64（moc 内建，lib/assert.mo、fmath.mo 依赖）
    line("static long long fbits(double v){ union {double d; long long i;} u; u.d=v; return u.i; }");
    line("static double ffrombits(long long i){ union {double d; long long i;} u; u.i=i; return u.d; }");
    # 🔴 memset/memcpy 不能是 static：GCC/Clang 在 O2 下会把大数组初始化
    #    （如 local 的 `unsigned char part[512] = {0}`）**降级成对 memset 的调用**，
    #    这一步连 -fno-builtin 都拦不住（它是初始化器 lowering，不是 builtin 替换）。
    #    static 定义挡不住这个调用（声明与定义同文件反而让它"理直气壮"），链接必炸
    #    undefined reference to `memset'，且只在 O2 出现、O0 正常 —— 极具迷惑性。
    #    改成非 static 全局定义：调用方（含编译器自动生成的）都能解析到。
    #    实测：wc.mo 的 str_split 在 O2 必现（2026-10-25，安卓 ARM64 实战）。
    line("void* memset(unsigned char* d, int c, unsigned long n){ unsigned long i=0; while(i<n){ d[i]=(unsigned char)c; i++; } return (void*)d; }");
    line("void* memcpy(unsigned char* d, const unsigned char* s, unsigned long n){ unsigned long i=0; while(i<n){ d[i]=s[i]; i++; } return (void*)d; }");
    # atoi：freestanding 没有 libc，字符串转数字要自己有。
    # 放在这里是因为 andromo.mo 这类程序要用命令行参数指定规模。
    line("static long atoi(const unsigned char* s){");
    line("  long v=0; int neg=0; int i=0;");
    line("  if(s[0]=='-'){ neg=1; i=1; }");
    line("  while(s[i]){ if(s[i]<'0'||s[i]>'9') break; v=v*10+(s[i]-'0'); i++; }");
    line("  return neg? -v : v; }");
    # fint / f64：墨语言里 f64 <-> i64 是**内建**（编译器直接发 cvttsd2si /
    # cvtsi2sd），C 后端此前没有对应物，于是原样输出 fint(v) —— 编译期报
    # "implicit declaration of function 'fint'"（v1.177 在把 a64as.mo 交叉编译
    # 到 aarch64 时撞上：只有用到 print_f64 的程序才会触发）。
    #
    # 语义对齐：C 的 (long)double 是**向零截断**，与 cvttsd2si 一致；
    # 不能用 lrint（那是按当前舍入模式，可能是就近取整）。
    line("static long fint(double v){ return (long)v; }");
    line("static double f64(long v){ return (double)v; }");
    # 前置声明：真正的定义在文件末尾（紧邻 _start，因为它要读初始栈）。
    # 少了这两行，源码里用 argc() 会触发隐式声明 int argc()，
    # 于是后面 static 定义时报
    # "static declaration of 'argc' follows non-static declaration"。
    line("static long argc(void);");
    line("static unsigned char* argv(long i);");
    if FS_ARCH == 1 {
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  register long r0 asm(\"rax\") = n;");
        line("  register long r1 asm(\"rdi\") = a; register long r2 asm(\"rsi\") = b;");
        line("  register long r3 asm(\"rdx\") = c; register long r4 asm(\"r10\") = d;");
        line("  register long r5 asm(\"r8\")  = e; register long r6 asm(\"r9\")  = f;");
        line("  asm volatile(\"syscall\" : \"+r\"(r0)");
        line("    : \"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5),\"r\"(r6)");
        line("    : \"rcx\",\"r11\",\"memory\");");
        line("  return r0;");
        line("}");
        line("#define MO_WRITE_ 1");
        line("#define MO_EXIT_  60");
        emit_fs_print();
        return 0;
    }
    if FS_ARCH == 2 {
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  register long r8 asm(\"x8\") = n; register long r0 asm(\"x0\") = a;");
        line("  register long r1 asm(\"x1\") = b; register long r2 asm(\"x2\") = c;");
        line("  register long r3 asm(\"x3\") = d; register long r4 asm(\"x4\") = e;");
        line("  register long r5 asm(\"x5\") = f;");
        line("  asm volatile(\"svc #0\" : \"+r\"(r0)");
        line("    : \"r\"(r8),\"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5)");
        line("    : \"memory\");");
        line("  return r0;");
        line("}");
        line("#define MO_WRITE_ 64");
        line("#define MO_EXIT_  93");
        # exit：libc 风格程序直接调 exit(code) —— freestanding 无 libc。
        # 必须在 mo_syscall 定义之后（否则隐式声明冲突）。
        line("static void __attribute__((noreturn)) mo_exit(long c){ mo_syscall(94,c,0,0,0,0,0); for(;;){} }");
        emit_fs_print();
        return 0;
    }
    if FS_ARCH == 4 { return fs_s390x_syscall(); }
    if FS_ARCH == 5 { return fs_ppc64le_syscall(); }
    if FS_ARCH == 6 { return fs_ppc64le_syscall(); }
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  register long r7 asm(\"a7\") = n; register long r0 asm(\"a0\") = a;");
    line("  register long r1 asm(\"a1\") = b; register long r2 asm(\"a2\") = c;");
    line("  register long r3 asm(\"a3\") = d; register long r4 asm(\"a4\") = e;");
    line("  register long r5 asm(\"a5\") = f;");
    line("  asm volatile(\"ecall\" : \"+r\"(r0)");
    line("    : \"r\"(r7),\"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5)");
    line("    : \"memory\");");
    line("  return r0;");
    line("}");
    line("#define MO_WRITE_ 64");
    line("#define MO_EXIT_  93");
        emit_fs_print();
    return 0;
}

# s390x：Linux ABI 是 调用号 r1、参数 r2-r7、返回 r2，陷入用 `svc 0`。
# 注意它是**大端**（与 aarch64/riscv64 都不同）。
# ---------------------------------------------------------------------------
# syscall 号翻译
#
# 墨语言源码里 syscall(2,...) 用的是 **x86-64 号表**（2=open）。
# 此前 mo2x 把它原样透传给所有 freestanding 后端 ——
# 于是 aarch64 上 x8=2 是 io_submit，riscv64 上 a7=2 同样是 io_submit。
# 不报错、不崩溃，只是发了一个完全不相干的系统调用。
#
# 现有测试从未抓到，是因为 print() 走 emit_fs_print() 里的 MO_WRITE_ 宏
# （那个是架构正确的），绕开了这条路径；而 freestanding 的示例只打印
# 不读写文件，从未触及 syscall()。
#
# 参数形态不同的调用（open / stat / mkdir / unlink —— aarch64 只有 *at
# 版本，参数个数与含义都不同）不做号映射：那会静默给出错误语义。
# 这里返回负数，由发射处报错。
# ---------------------------------------------------------------------------
fn fs_sysno(n: i64) -> i64 {
    FS_ATINS = 0;
    FS_ATTAIL = 0;
    FS_ATVAL = 0 - 100;
    if FS_ARCH == 1 { return n; }          # x86-64：源码写的就是它
    if FS_ARCH == 2 { return fs_sysno_generic(n); }
    if FS_ARCH == 3 { return fs_sysno_generic(n); }   # riscv64 同为 asm-generic 表
    return -2;                              # -2 = 该架构暂无号表
}

# asm-generic（aarch64 / riscv64 共用）
#
# 返回 -1 表示"该调用不能靠换号完成"。其中 open/mkdir/unlink/stat/access
# 现在靠**实参重排**适配（FS_ATINS / FS_ATTAIL），不再一律报错 ——
# 包管理器要读写文件，没有 open 在 ARM64 上寸步难行。
fn fs_sysno_generic(n: i64) -> i64 {
    if n == 0   { return 63;  }   # read
    if n == 1   { return 64;  }   # write
    if n == 3   { return 57;  }   # close
    if n == 8   { return 62;  }   # lseek
    if n == 12  { return 214; }   # brk
    if n == 59  { return 221; }   # execve
    if n == 60  { return 93;  }   # exit
    if n == 61  { return 260; }   # wait4
    # getdents64 —— **此前写的是 217→217，是错的**。
    # 217 是 x86-64 的号；ARM64 走 asm-generic 表，getdents64 = 61，
    # 而 ARM64 的 217 是 **add_key**（keyring）。也就是说这一条会把
    # "列目录"发成"往内核密钥环里加密钥" —— 不报错、不崩溃，只返回
    # -ENOSYS/-EPERM，于是包管理器的 list 永远得到空列表。
    # 这正是本项目反复出现的形状：**号表本身静默发错号**。
    # 该表已用 /usr/include/asm-generic/unistd.h 逐条核对（tools/sysnocheck.sh）。
    if n == 217 { return 61;  }   # getdents64
    if n == 134 { return 134; }   # rt_sigaction（形态一致，sigaction 结构含 sa_mask 尺寸尾参）
    if n == 231 { return 94;  }   # exit_group
    # ---- *at 版本：多一个 dfd 首参（AT_FDCWD = -100）----
    if n == 2   { FS_ATINS = 1; return 56;  }   # open   → openat
    if n == 83  { FS_ATINS = 1; return 34;  }   # mkdir  → mkdirat
    if n == 87  { FS_ATINS = 1; return 35;  }   # unlink → unlinkat
    # rmdir —— x86-64 有独立的 rmdir(84)，asm-generic **没有**（新架构只有
    # unlinkat + AT_REMOVEDIR）。所以这一条是"换号 + 插 dfd"，
    # 而 AT_REMOVEDIR(512) 必须由**源码自己写在第二实参**：
    #   syscall(84, path, 512, 0, 0, 0)
    # x86 透传 → rmdir(path)（第二实参被忽略，rmdir 只要一个参数）
    # ARM64    → unlinkat(-100, path, 512)（插 dfd 后 512 正好落在 flags）
    # 两端因此得到同一个语义，源码里不需要知道目标架构。
    if n == 84  { FS_ATINS = 1; return 35;  }   # rmdir  → unlinkat
    # ---- *at 版本：多一个 dfd 首参 + 一个 flags 尾参 ----
    if n == 4   { FS_ATINS = 1; FS_ATTAIL = 1; return 79; }  # stat   → newfstatat
    if n == 21  { FS_ATINS = 1; FS_ATTAIL = 1; return 48; }  # access → faccessat
    # x86-64 号 → asm-generic(ARM64/RISC-V 通用) 号完整对照表。
    # 逐条用 /usr/aarch64-linux-gnu/include/asm-generic/unistd.h 核对过。
    # 只收"参数形态完全一致"的调用 —— 形态不同的（open→openat、
    # stat→fstatat、dup2→dup3、accept→accept4、pipe→pipe2、chmod→fchmodat、
    # rename→renameat 等）仍走各自的 *at/变体适配或响亮报错。
    if n == 0   { return 63;  }   # read
    if n == 1   { return 64;  }   # write
    if n == 3   { return 57;  }   # close
    if n == 9   { return 222; }   # mmap
    if n == 10  { return 226; }   # mprotect
    if n == 11  { return 215; }   # munmap
    if n == 12  { return 214; }   # brk
    if n == 13  { return 134; }   # rt_sigaction
    if n == 14  { return 135; }   # rt_sigprocmask
    if n == 16  { return 29;  }   # ioctl
    if n == 26  { return 227; }   # msync（x86 26=msync；ptrace 是 101/117 的事，勿混）
    if n == 34  { return 23;  }   # dup
    if n == 35  { return 101; }   # nanosleep
    if n == 39  { return 172; }   # getpid
    if n == 41  { return 198; }   # socket
    if n == 42  { return 203; }   # connect
    if n == 44  { return 206; }   # sendto
    if n == 45  { return 207; }   # recvfrom
    if n == 49  { return 200; }   # bind
    if n == 51  { return 204; }   # getsockname（x86 51；50=listen 已占用）
    if n == 52  { return 205; }   # getpeername
    if n == 48  { return 210; }   # shutdown
    if n == 50  { return 201; }   # listen
    if n == 54  { return 208; }   # setsockopt
    if n == 55  { return 209; }   # getsockopt
    if n == 62  { return 129; }   # kill
    if n == 59  { return 221; }   # execve
    if n == 60  { return 93;  }   # exit
    if n == 61  { return 260; }   # wait4
    if n == 8   { return 62;  }   # lseek
    if n == 63  { return 160; }   # uname
    if n == 72  { return 25;  }   # fcntl
    if n == 74  { return 82;  }   # fsync
    if n == 77  { return 46;  }   # ftruncate
    if n == 79  { return 17;  }   # getcwd
    if n == 80  { return 49;  }   # chdir
    if n == 78  { return 61;  }   # getdents（x86 78 老 getdents；库多写 217）
    if n == 89  { return 96;  }   # set_tid_address
    if n == 96  { return 169; }   # gettimeofday
    if n == 82  { FS_ATINS = 2; return 38;  }   # rename → renameat(-100,old,-100,new)
    if n == 90  { FS_ATINS = 1; return 53;  }   # chmod → fchmodat(AT_FDCWD,...)
    if n == 22  { FS_ATTAIL = 1; return 59;  }   # pipe → pipe2（多 flags=0）
    if n == 33  { FS_ATTAIL = 1; return 24;  }   # dup2 → dup3（多 flags=0）
    if n == 43  { FS_ATTAIL = 1; return 242; }   # accept → accept4（多 flags=0）
    if n == 57  { FS_ATINS = 1; FS_ATVAL = 17; return 220; }   # fork → clone(SIGCHLD)
    if n == 232 { FS_ATTAIL = 2; return 22;   }   # epoll_wait → epoll_pwait(NULL,8)
    if n == 98  { return 165; }   # getrusage
    if n == 99  { return 179; }   # sysinfo

        if n == 109 { return 154; }   # setpgid
    if n == 110 { return 173; }   # getppid
    if n == 112 { return 157; }   # setsid
    if n == 121 { return 155; }   # getpgid
    if n == 137 { return 43;  }   # statfs（3264 表，形态一致）
    if n == 140 { return 141; }   # getpriority
    if n == 141 { return 140; }   # setpriority
    if n == 160 { return 164; }   # setrlimit（prlimit64 形态不同，x86 160 是 setrlimit）
    if n == 186 { return 178; }   # gettid
    if n == 202 { return 98;  }   # futex（x86 号 202 → asm-generic 98）
    if n == 217 { return 61;  }   # getdents64（有的库直接写 217=老的 x86 号）
    if n == 228 { return 113; }   # clock_gettime
    if n == 46  { return 211; }   # sendmsg
    if n == 47  { return 212; }   # recvmsg
    if n == 233 { return 21;  }   # epoll_ctl
    if n == 234 { return 20;  }   # epoll_create1（x86 291 误写为 234 时的兜底）
    if n == 291 { return 20;  }   # epoll_create1
    return -1;                     # -1 = 该调用不能靠换号完成return -1;                     # -1 = 该调用不能靠换号完成
}

# 整数字面量判断：kind 2 同时表示标识符和数字，只能看内容
fn is_num_tok(s: i64) -> i64 {
    let i: i64 = 0;
    if load8(s) == 0 { return 0; }
    while load8(s + i) != 0 {
        if is_digit_ch(load8(s + i)) == 0 { return 0; }
        i = i + 1;
    }
    return 1;
}

fn fs_s390x_syscall() -> i64 {
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  register long r1 asm(\"r1\") = n; register long r2 asm(\"r2\") = a;");
    line("  register long r3 asm(\"r3\") = b; register long r4 asm(\"r4\") = c;");
    line("  register long r5 asm(\"r5\") = d; register long r6 asm(\"r6\") = e;");
    line("  register long r7 asm(\"r7\") = f;");
    line("  asm volatile(\"svc 0\" : \"+r\"(r2)");
    line("    : \"r\"(r1),\"r\"(r3),\"r\"(r4),\"r\"(r5),\"r\"(r6),\"r\"(r7)");
    line("    : \"memory\");");
    line("  return r2;");
    line("}");
    line("#define MO_WRITE_ 4");
    line("#define MO_EXIT_  1");
    emit_fs_print();
    return 0;
}

# ppc64le (ELFv2)：调用号 r0、参数 r3-r8、返回 r3，陷入用 `sc`。
fn fs_ppc64le_syscall() -> i64 {
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  register long r0 asm(\"r0\") = n; register long r3 asm(\"r3\") = a;");
    line("  register long r4 asm(\"r4\") = b; register long r5 asm(\"r5\") = c;");
    line("  register long r6 asm(\"r6\") = d; register long r7 asm(\"r7\") = e;");
    line("  register long r8 asm(\"r8\") = f;");
    line("  asm volatile(\"sc\" : \"+r\"(r3)");
    line("    : \"r\"(r0),\"r\"(r4),\"r\"(r5),\"r\"(r6),\"r\"(r7),\"r\"(r8)");
    line("    : \"memory\");");
    line("  return r3;");
    line("}");
    line("#define MO_WRITE_ 4");
    line("#define MO_EXIT_  1");
    emit_fs_print();
    return 0;
}

fn is_c_like() -> i64 {
    if TGT == T_KERN { return 1; }
    if TGT == T_UEFI { return 1; }
    if TGT == T_C { return 1; }
    if TGT == T_FS { return 1; }
    return 0;
}

# --------------------------------------------------------------------------
#  内核目标的前导
#
#  与 cfs（freestanding + 内联汇编 syscall）的关键差别：
#    - 内核**不能**用系统调用（它自己就是提供系统调用的那一层）
#    - 输出走 VGA 文本缓冲 0xB8000
#    - 提供 inb / outb 端口 I/O（内联汇编）
#    - 提供 hlt / cli / sti
#
#  于是同一份墨语言源码，既能编成用户态程序（cfs），也能编成内核（kern）。
# --------------------------------------------------------------------------
fn kern_header() -> i64 {
    line("/* generated by mo2x -- 墨语言 内核后端 */");
    line("/* 无 libc、无系统调用：直接写 VGA 缓冲与端口 */");
    line("typedef unsigned char u8; typedef unsigned short u16;");
    line("typedef unsigned int u32; typedef unsigned long long u64;");
    line("static volatile u16* const VGA = (volatile u16*)0xB8000u;");
    line("static int KROW = 0, KCOL = 0;");
    line("static void vga_clear(void){ int i; for(i=0;i<80*25;i++) VGA[i]=0x0720u; KROW=0; KCOL=0; }");
    line("static void vga_putc(char c){");
    line("  if(c=='\\n'){ KROW++; KCOL=0; }");
    line("  else if(c=='\\r'){ KCOL=0; }");
    line("  else { VGA[KROW*80+KCOL] = (u16)(0x0700u | (u16)c); KCOL++; }");
    line("  if(KCOL>=80){ KCOL=0; KROW++; }");
    line("  if(KROW>=25){ /* 简单上滚：整屏上移一行 */");
    line("    int i; for(i=0;i<80*24;i++) VGA[i]=VGA[i+80];");
    line("    for(i=80*24;i<80*25;i++) VGA[i]=0x0720u; KROW=24; }");
    line("}");
    line("static void vga_print(const char* s){ int i=0; while(s[i]) vga_putc(s[i++]); }");
    line("static unsigned char inb(unsigned short p){ unsigned char v;");
    line("  __asm__ volatile(\"inb %%dx, %%al\" : \"=a\"(v) : \"d\"(p)); return v; }");
    line("static void outb(unsigned short p, unsigned char v){");
    line("  __asm__ volatile(\"outb %%al, %%dx\" :: \"a\"(v), \"d\"(p)); }");
    line("static void hlt(void){ __asm__ volatile(\"hlt\"); }");
    line("static void cli(void){ __asm__ volatile(\"cli\"); }");
    line("static void sti(void){ __asm__ volatile(\"sti\"); }");
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;");
    line("  outb(0xE9, (unsigned char)(n & 0xFF));  /* QEMU/Bochs 调试端口 */");
    line("  return 0; }");
    line("static long strlen_(unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
    line("#define strlen strlen_");
    # 墨语言源码里的 print / print_i64 / print_nl 是普通函数调用，
    # 在内核目标下必须在这里给出定义，否则链接期找不到符号。
    line("static void print(const unsigned char* s){ vga_print((const char*)s); }");
    line("static void print_nl(void){ vga_putc('\\n'); }");
    line("static void print_i64(long v){");
    line("  char b[24]; int i=0, neg=0; unsigned long u;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(char)('0'+(u%10)); u/=10; }");
    line("  if(neg) vga_putc('-');");
    line("  while(i) vga_putc(b[--i]);");
    line("}");
    line("static void exit(long c){ (void)c; cli(); for(;;) hlt(); }");
    line("static long argc(void){ return 0; }");
    line("static unsigned char* argv(long i){ (void)i; return (unsigned char*)0; }");
    line("static void heap_init(void){ }");
    # 内核里没有标准库，字符串函数得自己给。
    # 只给最小集合 —— 够写一个 shell，不多给。
    line("static long streq(const unsigned char* a, const unsigned char* b){");
    line("  int i=0; while(a[i]&&b[i]){ if(a[i]!=b[i]) return 0; i++; }");
    line("  return a[i]==b[i]; }");
    line("static long str_starts_with(const unsigned char* s, const unsigned char* p){");
    line("  int i=0; while(p[i]){ if(s[i]!=p[i]) return 0; i++; } return 1; }");
    line("static void strcpy_(unsigned char* d, const unsigned char* s){");
    line("  int i=0; while(s[i]){ d[i]=s[i]; i++; } d[i]=0; }");
    line("static void strcat_(unsigned char* d, const unsigned char* s){");
    line("  int i=0,j=0; while(d[i]) i++; while(s[j]){ d[i+j]=s[j]; j++; } d[i+j]=0; }");
    line("static void memset_(unsigned char* d, unsigned char v, long n){ long i; for(i=0;i<n;i++) d[i]=v; }");
    line("static void memcpy_(unsigned char* d, const unsigned char* s, long n){ long i; for(i=0;i<n;i++) d[i]=s[i]; }");
    line("#define strcpy strcpy_");
    line("#define strcat strcat_");
    line("#define memset memset_");
    line("#define memcpy memcpy_");
    line("static void utoa(long v, unsigned char* b, long base){");
    line("  char t[24]; int i=0,j=0; unsigned long u;");
    line("  if(v<0){ b[j++]='-'; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) t[i++]='0';");
    line("  while(u){ t[i++]=(char)('0'+(u%base)); u/=base; }");
    line("  while(i) b[j++]=(unsigned char)t[--i];");
    line("  b[j]=0; }");
    emit_mem_macros();
    return 0;
}

# 内存原语：墨语言的 load8/store8/load64/store64 直接对应指针读写。
# C 系后端（c / cfs / kern）共用同一份宏定义 —— 指针语义一致，
# 内核里也就是读写物理内存。
# --------------------------------------------------------------------------
#  ARM64 裸机内核的前导（QEMU virt / 真实 ARM64 板子的 PL011 UART）
#
#  与 x86 内核后端的差别不是"换个地址"那么简单：
#    - x86 有独立的 I/O 地址空间（in/out 指令），ARM64 **没有** ——
#      所有设备都是 MMIO，统一用普通读写指令访问。
#    - 所以 inb/outb 在 ARM64 上只能退化成 MMIO 字节读写：
#      源码里那些 x86 端口号在 ARM64 上不成立，键盘那类设备要改走 UART。
#    - 关机/停机指令从 hlt 换成 wfi。
#
#  UART 用 PL011（QEMU virt 把它放在 0x09000000）：
#    DR(+0x00) 数据寄存器：写=发送，读=接收
#    FR(+0x18) 标志寄存器：bit4 RXFE=1 表示接收 FIFO 空
# --------------------------------------------------------------------------
fn kern_header_aarch64() -> i64 {
    line("/* generated by mo2x -- 墨语言 ARM64 内核后端 */");
    line("/* 无 libc、无系统调用、无 I/O 端口：一切走 MMIO */");
    line("typedef unsigned char u8; typedef unsigned short u16;");
    line("typedef unsigned int u32; typedef unsigned long long u64;");
    line("#define UART_BASE 0x09000000UL");
    line("static volatile u32* const UART_DR = (volatile u32*)(UART_BASE + 0x00UL);");
    line("static volatile u32* const UART_FR = (volatile u32*)(UART_BASE + 0x18UL);");
    line("static void uart_putc(char c){ *UART_DR = (u32)c; }");
    line("static void uart_print(const char* s){ int i=0; while(s[i]) uart_putc(s[i++]); }");
    line("/* 阻塞读一个字符：PL011 的 RXFE 为 1 时 FIFO 空，轮询等待 */");
    line("static int uart_trygetc(void){ if(*UART_FR & 0x10u) return -1; return (int)(*UART_DR & 0xFFu); }");
    line("static int uart_getc(void){ int c; for(;;){ c = uart_trygetc(); if(c >= 0) return c; } }");
    line("static void wfi_(void){ __asm__ volatile(\"wfi\"); }");
    line("static void hlt(void){ wfi_(); }");
    line("static void cli(void){ __asm__ volatile(\"msr daifset, #2\"); }");
    line("static void sti(void){ __asm__ volatile(\"msr daifclr, #2\"); }");
    # ARM64 没有 I/O 地址空间，inb/outb 只能落到这里。
    # 保留同名函数是为了让**同一份墨语言源码**仍能编出来，
    # 但端口号必须换成 MMIO 物理地址，否则读写的是无关内存。
    line("static unsigned char inb(unsigned long p){ return *(volatile unsigned char*)p; }");
    line("static void outb(unsigned long p, unsigned char v){ *(volatile unsigned char*)p = v; }");
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;");
    line("  uart_putc((char)('0' + (int)(n % 10)));  /* 内核里没有 syscall，响一下 */");
    line("  return 0; }");
    line("static long strlen_(unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
    line("#define strlen strlen_");
    line("static void print(const unsigned char* s){ uart_print((const char*)s); }");
    line("static void print_nl(void){ uart_putc('\\n'); }");
    line("static void print_i64(long v){");
    line("  char b[24]; int i=0, neg=0; unsigned long u;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(char)('0'+(u%10)); u/=10; }");
    line("  if(neg) uart_putc('-');");
    line("  while(i) uart_putc(b[--i]);");
    line("}");
    line("/* 裸机没有退出目标：打印完就停机 */");
    line("static void exit(long c){ (void)c; cli(); for(;;) wfi_(); }");
    line("static long argc(void){ return 0; }");
    line("static unsigned char* argv(long i){ (void)i; return (unsigned char*)0; }");
    line("static void heap_init(void){ }");
    line("static long streq(const unsigned char* a, const unsigned char* b){");
    line("  int i=0; while(a[i]&&b[i]){ if(a[i]!=b[i]) return 0; i++; }");
    line("  return a[i]==b[i]; }");
    line("static long str_starts_with(const unsigned char* s, const unsigned char* p){");
    line("  int i=0; while(p[i]){ if(s[i]!=p[i]) return 0; i++; } return 1; }");
    line("static void strcpy_(unsigned char* d, const unsigned char* s){");
    line("  int i=0; while(s[i]){ d[i]=s[i]; i++; } d[i]=0; }");
    line("static void strcat_(unsigned char* d, const unsigned char* s){");
    line("  int i=0,j=0; while(d[i]) i++; while(s[j]){ d[i+j]=s[j]; j++; } d[i+j]=0; }");
    line("static void memset_(unsigned char* d, unsigned char v, long n){ long i; for(i=0;i<n;i++) d[i]=v; }");
    line("static void memcpy_(unsigned char* d, const unsigned char* s, long n){ long i; for(i=0;i<n;i++) d[i]=s[i]; }");
    line("#define strcpy strcpy_");
    line("#define strcat strcat_");
    line("#define memset memset_");
    line("#define memcpy memcpy_");
    line("static void utoa(long v, unsigned char* b, long base){");
    line("  char t[24]; int i=0,j=0; unsigned long u;");
    line("  if(v<0){ b[j++]='-'; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) t[i++]='0';");
    line("  while(u){ t[i++]=(char)('0'+(u%base)); u/=base; }");
    line("  while(i) b[j++]=(unsigned char)t[--i];");
    line("  b[j]=0; }");
    emit_mem_macros();
    return 0;
}

fn emit_mem_macros() -> i64 {
    line("static unsigned char* MF_P;  /* f-string 拼接游标（sfmt 用） */");
    line("#define load8(p)   (*(unsigned char*)(p))");
    line("#define load64(p)  (*(long*)(p))");
    line("#define store8(p,v)  (*(unsigned char*)(p) = (unsigned char)(v))");
    line("#define store64(p,v) (*(long*)(p) = (long)(v))");
    line("static long atomic_cas(long* p, long e, long d){ long old_=e; long ok_=__atomic_compare_exchange_n(p,&old_,d,0,5,5); return ok_?1:0; }");
    line("static long call2(long f, long a, long b){ long (*g)(long,long)=(long(*)(long,long))f; return g(a,b); }");
    line("static long call0(long f){ long (*g)(void)=(long(*)(void))f; return g(); }");
    line("static long call1(long f, long a){ long (*g)(long)=(long(*)(long))f; return g(a); }");
    line("static long call3(long f, long a, long b, long c){ long (*g)(long,long,long)=(long(*)(long,long,long))f; return g(a,b,c); }");
    return 0;
}

# freestanding 下的 print 家族：直接用 write(1, ...) 系统调用
fn emit_fs_print() -> i64 {
    line("static void print(const unsigned char* s){ long n=0; while(s[n]) n++; mo_syscall(MO_WRITE_,1,(long)s,(long)n,0,0,0); }");
    line("static const unsigned char MO_NL_ = (unsigned char)10;");
    line("static void print_nl(void){ mo_syscall(MO_WRITE_,1,(long)&MO_NL_,1,0,0,0); }");
    line("static void print_i64(long v){");
    line("  unsigned char b[24]; int i=0; unsigned long u; int neg=0;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(unsigned char)('0'+(u%10)); u/=10; }");
    line("  if(neg) b[i++]='-';");
    line("  while(i){ unsigned char c=b[--i]; mo_syscall(MO_WRITE_,1,(long)&c,1,0,0,0); }");
    line("}");
    return 0;
}

# UEFI 前导
#
# 与 cfs / kern 都不同：UEFI 是**固件环境**，既没有 Linux 系统调用，
# 也没有 VGA 缓冲。输出只能走 EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL。
#
# 关键布局（x86-64，指针 8 字节）：
#   EFI_SYSTEM_TABLE:
#     +64  ConOut        (EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL*)
#   EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL:
#     +8   OutputString  (EFI_STATUS (*)(This, CHAR16*))
#     +48  ClearScreen   (EFI_STATUS (*)(This))
#     +56  SetAttribute
#
# CHAR16 是 UTF-16LE，所以 ASCII 要拆成 "低字节, 0" 两字节。
fn uefi_header() -> i64 {
    line("/* generated by mo2x -- 墨语言 UEFI 后端 */");
    line("/* 固件环境：无 libc、无系统调用，输出走 ConOut 协议 */");
    line("typedef unsigned char u8; typedef unsigned short u16;");
    line("typedef unsigned int u32; typedef unsigned long long u64;");
    line("typedef long long i64;");
    line("static void* EFI_ST = 0;          /* EFI_SYSTEM_TABLE* */");
    line("static void* EFI_CO = 0;          /* ConOut* */");
    line("/* 读 EFI_SYSTEM_TABLE+64 得到 ConOut */");
    line("static void uefi_boot(void* imgh, void* st){");
    line("  (void)imgh; EFI_ST = st;");
    line("  if(st) EFI_CO = *(void**)((unsigned char*)st + 64);");
    line("}");
    line("/* OutputString 在 ConOut+8，调用约定是 MS x64 (rcx,rdx) ——");
    line("   而本目标是按 windows-gnu 编译的，编译器会自动用 MS ABI，");
    line("   所以这里直接当普通函数指针调用即可。 */");
    line("static void uefi_puts(const char* s){");
    line("  if(!EFI_CO) return;");
    line("  unsigned short b[512]; int i=0;");
    line("  while(s[i] && i<510){ b[i]=(unsigned short)s[i]; i++; }");
    line("  b[i]=0;");
    line("  long (*os)(void*, unsigned short*) = *(long(**)(void*,unsigned short*))((unsigned char*)EFI_CO + 8);");
    line("  os(EFI_CO, b);");
    line("}");
    line("static void uefi_clear(void){");
    line("  if(!EFI_CO) return;");
    line("  long (*cs)(void*) = *(long(**)(void*))((unsigned char*)EFI_CO + 48);");
    line("  cs(EFI_CO);");
    line("}");
    line("static void print(const unsigned char* s){ uefi_puts((const char*)s); }");
    line("static void print_nl(void){ uefi_puts(\"\\r\\n\"); }");
    line("static void print_i64(long v){");
    line("  char b[24]; int i=0; unsigned long u; int neg=0;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(char)('0'+(u%10)); u/=10; }");
    line("  if(neg) b[i++]='-';");
    line("  char o[24]; int j=0; while(i) o[j++]=b[--i]; o[j]=0;");
    line("  uefi_puts(o);");
    line("}");
    line("static void exit(long c){ (void)c; for(;;){} }");
    line("static long argc(void){ return 0; }");
    line("static unsigned char* argv(long i){ (void)i; return (unsigned char*)0; }");
    line("static void heap_init(void){ }");
    emit_mem_macros();
    return 0;
}

fn emit_header() -> i64 {
    if TGT == T_FS { return fs_header(); }
    if TGT == T_KERN {
        if KERN_ARCH == 2 { return kern_header_aarch64(); }
        return kern_header();
    }
    if TGT == T_UEFI { return uefi_header(); }
    if is_c_like() == 1 {
        line("/* generated by mo2x -- 墨语言 C 后端 */");
        line("#include <unistd.h>");
        # syscall 支持按平台条件编译：
        # 无条件 include <sys/syscall.h> 会让 Windows / WASI 直接编译失败
        # （那两个平台根本没有这个头）；而只在 NEED_SYS 时发出又会漏掉
        # —— NEED_SYS 是扫描源码后才置位的，header 写得更早。
        # 所以用预处理器判断，两端都留一份定义。
        line("#if defined(__linux__) && !defined(__wasi__)");
        line("#include <sys/syscall.h>");
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  return syscall(n,a,b,c,d,e,f);");
        line("}");
        line("#else");
        line("/* 该平台没有 syscall()：WASI / Windows 走这里。");
        line("   返回 -1 而不是静默成功 —— 用了 syscall 的程序应当看得出来。 */");
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  (void)n;(void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return -1; }");
        line("#endif");
        line("static long strlen_(unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
        line("#define strlen strlen_");
        emit_mem_macros();
        # 输出函数由后端提供（printf 版）。
        # 不用 syscall 是因为 WASI 没有 syscall() —— 照搬 io.mo 会链接失败。
        line("#include <stdio.h>");
        line("static long print_(const unsigned char* s){ return (long)fputs((const char*)s, stdout); }");
        line("static long print_i64_(long v){ return (long)fprintf(stdout, \"%ld\", v); }");
        line("static long print_nl_(void){ return (long)fputc('\\n', stdout); }");
        line("static long print_hex_(long v){ return (long)fprintf(stdout, \"%lx\", v); }");
        line("#define print print_");
        line("#define print_i64 print_i64_");
        line("#define print_nl print_nl_");
        line("#define print_hex print_hex_");
        return 0;
    }
    if TGT == T_JS {
        line("// generated by mo2x -- 墨语言 JS 后端");
        line("function strlen(s){ return s.length; }");
        return 0;
    }
    line("# generated by mo2x -- 墨语言 Python 后端");
    line("import sys");
    line("sys.setrecursionlimit(100000)");
    line("def strlen(s): return len(s)");
    return 0;
}

fn tg_name() -> i64 {
    if TGT == T_JAVA { return "Java"; }
    if TGT == T_GO { return "Go"; }
    if TGT == T_RUST { return "Rust"; }
    if TGT == T_CS { return "C#"; }
    if TGT == T_SWIFT { return "Swift"; }
    if TGT == T_RUBY { return "Ruby"; }
    if TGT == T_LUA { return "Lua"; }
    if TGT == T_PHP { return "PHP"; }
    return "Perl";
}

fn g_header() -> i64 {
    outs(G_CMT);
    outs(" generated by mo2x -- 墨语言 ");
    outs(tg_name());
    outs(" 后端\n");
    if TGT == T_GO { line("package main"); line("import \"os\""); return 0; }
    if TGT == T_PERL { line("use strict;"); line("use warnings;"); return 0; }
    if TGT == T_PHP { line("<?php"); return 0; }
    if TGT == T_RUST { return 0; }
    if TGT == T_JAVA { return 0; }
    if TGT == T_CS { return 0; }
    if TGT == T_SWIFT { line("import Foundation"); return 0; }
    if TGT == T_RUBY { return 0; }
    if TGT == T_LUA { return 0; }
    return 0;
}

fn g_footer() -> i64 {
    if TGT == T_GO { line("func main() { os.Exit(int(mo_main_entry())) }"); return 0; }
    if TGT == T_RUST { line("fn main() { std::process::exit(mo_main_entry() as i32) }"); return 0; }
    if TGT == T_JAVA { return 0; }
    if TGT == T_CS { return 0; }
    if TGT == T_SWIFT { line("exit(Int32(mo_main_entry()))"); return 0; }
    if TGT == T_RUBY { line("exit(main())"); return 0; }
    if TGT == T_LUA { line("os.exit(main())"); return 0; }
    if TGT == T_PHP { line("exit(main());"); return 0; }
    line("exit main();");
    return 0;
}

fn emit_footer() -> i64 {
    if TGT == T_UEFI {
        nl();
        line("long long mo_main(void);");
        # lld-link 在 --subsystem,efi_application 下默认找的入口叫 EfiMain
        # （不是 efi_main）—— 用错名字会报 "undefined symbol: EfiMain"。
        line("long long EfiMain(void* imgh, void* st){");
        line("  uefi_boot(imgh, st);");
        line("  long r = mo_main();");
        line("  return r;");
        line("}");
        return 0;
    }
    if TGT == T_FS {
        nl();
        line("long long mo_main(void);");
        # Linux 的初始栈顶布局：[sp] = argc, [sp+8] = argv[0], ...
        # 必须在 _start 最开头读，否则栈会被后续调用弄乱。
        #
        # _start 是 **naked**：否则 C 编译器会先生成函数序言调整 sp，
        # 于是 [sp] 不再是 argc —— 实测 argc() 返回 0，程序以为没参数。
        # 每条 asm 只写**一条**指令：多行 asm 字符串要穿过「墨语言词法」
        # 与「C 词法」两层转义，实测生成的字面量会被真实换行截断，
        # 报 "expected string literal in 'asm'"。单行没有这个麻烦。
        #
        # MO_ARGC / MO_ARGV 必须**非 static**：static 变量被判定"只写不读"
        # 后会被优化掉，于是 naked asm 里引用的名字在链接时报 undefined
        # symbol。同理 -O2 下还要 -fno-lto（见 tools/android_native.sh）：
        # LTO 看不见 naked asm 里的引用，会把这两个变量整段删掉。
        line("long MO_ARGC = 0; unsigned char** MO_ARGV = 0;");
        line("long argc(void){ return MO_ARGC; }");
        line("unsigned char* argv(long i){ return MO_ARGV[i]; }");
        line("__attribute__((noinline)) void mo_start(void){");
        line("  long r = mo_main();");
        line("  mo_syscall(MO_EXIT_, r, 0, 0, 0, 0, 0);");
        line("  while(1){}");
        line("}");
        line("__attribute__((naked,noreturn)) void _start(void){");
        if FS_ARCH == 2 {
            line("  asm volatile(\"ldr x9, [sp]\");");
            line("  asm volatile(\"add x10, sp, 8\");");
            line("  asm volatile(\"adrp x11, MO_ARGC\");");
            line("  asm volatile(\"str x9, [x11, :lo12:MO_ARGC]\");");
            line("  asm volatile(\"adrp x12, MO_ARGV\");");
            line("  asm volatile(\"str x10, [x12, :lo12:MO_ARGV]\");");
            line("  asm volatile(\"b mo_start\");");
        } else {
            if FS_ARCH == 1 {
                line("  asm volatile(\"movq (%rsp), %rax\");");
                line("  asm volatile(\"leaq 8(%rsp), %rdx\");");
                line("  asm volatile(\"movq %rax, MO_ARGC(%rip)\");");
                line("  asm volatile(\"movq %rdx, MO_ARGV(%rip)\");");
                # 栈对齐：jmp 不像 call 那样压入 8 字节返回地址，
                # 于是进 mo_start 时 rsp ≡ 0 (mod 16)，而 C 函数按 ABI
                # 假定 rsp ≡ 8 —— 后续栈帧整体错位 8 字节。
                # 后果：给局部数组初始化生成的 movaps（要求 16 字节对齐）
                # 落到未对齐地址 → SIGSEGV，且崩在任何输出之前。
                line("  asm volatile(\"andq $-16, %rsp\");");
                line("  asm volatile(\"subq $8, %rsp\");");
                line("  asm volatile(\"jmp mo_start\");");
            } else {
                if FS_ARCH == 4 {
                    line("  asm volatile(\"lg %r9, 0(%r15)\");");
                    line("  asm volatile(\"la %r10, 8(%r15)\");");
                    line("  asm volatile(\"larl %r11, MO_ARGC\");");
                    line("  asm volatile(\"stg %r9, 0(%r11)\");");
                    line("  asm volatile(\"larl %r12, MO_ARGV\");");
                    line("  asm volatile(\"stg %r10, 0(%r12)\");");
                    line("  asm volatile(\"jg mo_start\");");
                } else {
                    if FS_ARCH >= 5 {
                        # ppc64 ELFv2：必须先手工建立 TOC 指针 r2
                        # （正常由 crt 做，我们 -nostdlib）。
                        line("  asm volatile(\"addis 2, 12, .TOC.-_start@ha\");");
                        line("  asm volatile(\"addi 2, 2, .TOC.-_start@l\");");
                        line("  asm volatile(\"b mo_start\");");
                    } else {
                        line("  asm volatile(\"ld t0, 0(sp)\");");
                        line("  asm volatile(\"addi t1, sp, 8\");");
                        line("  asm volatile(\"la t2, MO_ARGC\");");
                        line("  asm volatile(\"sd t0, 0(t2)\");");
                        line("  asm volatile(\"la t3, MO_ARGV\");");
                        line("  asm volatile(\"sd t1, 0(t3)\");");
                        line("  asm volatile(\"j mo_start\");");
                    }
                }
            }
        }
        line("}");
        return 0;
    }
    if is_c_like() == 1 {
        line("int main(int argc, char** argv){");
        line("  return (int)mo_main();");
        line("}");
        return 0;
    }
    if TGT == T_JS {
        line("process.exit(main());");
        return 0;
    }
    line("sys.exit(main())");
    return 0;
}

# ==========================================================================
#  通用多语言后端：一套 profile 驱动，覆盖 java / go / rust / cs / swift /
#  ruby / lua / php / perl
#
#  做法：把每门语言的「关键字与模板」抽成一组变量（profile），
#  发射器只写一份。新增一门语言 = 填一张表，而不是复制一套发射器。
# ==========================================================================

fn set_profile(t: i64) -> i64 {
    TGT = t;
    G_ISMAIN = 1;
    G_SEMI = 1;
    G_ENDFN = "}";
    G_ENDCLASS = "}";
    G_DIV = 0;
    G_AND = " && ";
    G_OR = " || ";
    G_NOT = "!";
    G_DIV_STR = " / ";
    G_ELIF = "else if";
    G_VAR = "";
    G_TYPED = 0;
    G_TYI64 = "";
    G_ARRPRE = "";
    G_ARRPOST = "";
    G_NEW = "";
    G_CMT = "//";
    G_REF = "";
    G_BOPEN = "{";
    G_FNBOPEN = "{";
    G_BREAK = "break";
    G_CONT = "continue";

    if t == T_JAVA {
        G_FN = "static long "; G_VAR = ""; G_TYPED = 1; G_TYI64 = "long";
        G_ARRPRE = "new long["; G_ARRPOST = "]"; G_CLASS = "class ";
        G_NEW = "new "; G_CMT = "//"; return 0;
    }
    if t == T_GO {
        G_FN = "func "; G_VAR = "var "; G_TYPED = 1; G_TYI64 = "int64";
        G_ARRPRE = "make([]int64, "; G_ARRPOST = ")"; G_CLASS = "type ";
        G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_RUST {
        G_FN = "fn "; G_VAR = "let mut "; G_TYPED = 1; G_TYI64 = "i64";
        G_ARRPRE = "vec![0i64; "; G_ARRPOST = "]"; G_CLASS = "struct ";
        G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_CS {
        G_FN = "static long "; G_VAR = ""; G_TYPED = 1; G_TYI64 = "long";
        G_ARRPRE = "new long["; G_ARRPOST = "]"; G_CLASS = "class ";
        G_NEW = "new "; G_CMT = "//"; return 0;
    }
    if t == T_SWIFT {
        G_FN = "func "; G_VAR = "var "; G_TYPED = 1; G_TYI64 = "Int64";
        G_ARRPRE = "[Int64](repeating: 0, count: "; G_ARRPOST = ")";
        G_CLASS = "class "; G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_RUBY {
        G_FN = "def "; G_ENDFN = "end"; G_ENDCLASS = "end"; G_SEMI = 0;
        G_ARRPRE = "Array.new("; G_ARRPOST = ", 0)"; G_CLASS = "class ";
        G_NEW = ".new"; G_AND = " and "; G_OR = " or "; G_ELIF = "elsif";
        G_CMT = "#"; return 0;
    }
    if t == T_LUA {
        G_FN = "function "; G_ENDFN = "end"; G_ENDCLASS = "end"; G_SEMI = 0;
        G_VAR = "local "; G_ARRPRE = "{}"; G_CLASS = "";
        G_AND = " and "; G_OR = " or "; G_NOT = "not "; G_ELIF = "elseif"; G_CONT = "goto __cont";
        G_DIV = 1; G_CMT = "--"; G_DIV_STR = " // "; G_REF = ""; G_BOPEN = ""; G_FNBOPEN = ""; return 0;
    }
    if t == T_PHP {
        G_FN = "function "; G_VAR = "$"; G_ARRPRE = "array_fill(0, "; G_ARRPOST = ", 0)";
        G_CLASS = "class "; G_NEW = "new "; G_ELIF = "elseif"; G_DIV = 2;
        G_CMT = "//"; return 0;
    }
    if t == T_PERL {
        G_FN = "sub "; G_ENDFN = "}"; G_ENDCLASS = "}"; G_VAR = "my $";
        G_ARRPRE = "(0) x "; G_ELIF = "elsif"; G_DIV = 3; G_DIV_STR = " / "; G_REF = "$"; G_BREAK = "last"; G_CONT = "next";
        G_AND = " and "; G_OR = " or "; G_CMT = "#"; G_DIV_STR = " / "; G_FNBOPEN = ""; return 0;
    }
    return 0;
}


fn is_gen() -> i64 {
    if TGT >= 10 { return 1; }
    return 0;
}

# ---------- 通用后端的类型与声明 ----------

fn g_decl(nm: i64, dim: i64) -> i64 {
    if dim > 0 {
        if TGT == T_RUST { outs("let mut "); outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_GO { outs("var "); outs(nm); outs(" []int64 = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_SWIFT { outs("var "); outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_JAVA { outs("long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); return 0; }
        if TGT == T_CS { outs("long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); return 0; }
        if TGT == T_LUA { outs("local "); outs(nm); outs(" = {}"); return 0; }
        if TGT == T_PHP { outs(G_REF); outs(nm); outs(" = array_fill(0, "); outi(dim); outs(", 0)"); return 0; }
        if TGT == T_PERL { outs("my @"); outs(nm); outs(" = (0) x "); outi(dim); return 0; }
        outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST);
        return 0;
    }
    if G_TYPED == 1 {
        if TGT == T_GO { outs("var "); outs(nm); outs(" "); outs(G_TYI64); return 0; }
        if TGT == T_RUST { outs("let mut "); outs(nm); outs(": "); outs(G_TYI64); return 0; }
        if TGT == T_SWIFT { outs("var "); outs(nm); outs(": "); outs(G_TYI64); return 0; }
        outs(G_TYI64); outs(" "); outs(nm);
        return 0;
    }
    outs(G_VAR);
    outs(nm);
    return 0;
}

# ---------- 通用后端的语句 ----------

fn g_stmt() -> i64 {
    if is_assign_start() == 1 {
        ind();
        emit_lvalue();
        let t: i64 = cur_s();
        TI = TI + 1;
        outs(" ");
        outs(t);
        outs(" ");
        emit_expr();
        expect_op(";");
        if G_SEMI == 1 { outs(";"); }
        nl();
        return 0;
    }
    if accept_kw("return") == 1 {
        ind();
        outs("return ");
        emit_expr();
        expect_op(";");
        if G_SEMI == 1 { outs(";"); }
        nl();
        return 0;
    }
    if accept_kw("break") == 1 {
        expect_op(";");
        line(G_BREAK);
        return 0;
    }
    if accept_kw("continue") == 1 {
        expect_op(";");
        line(G_CONT);
        return 0;
    }
    if accept_kw("while") == 1 {
        ind();
        if TGT == T_GO { outs("for "); } else { outs("while "); }
        if TGT == T_RUBY { emit_expr(); }
        else {
            if TGT == T_LUA { emit_expr(); outs(" do"); }
            else { outs(" ("); emit_expr(); outs(")"); }
        }
        if TGT == T_GO { nl(); }
        else {
            if TGT == T_RUST { nl(); }
            else { outs(" "); }
        }
        expect_op("{");
        outs(G_BOPEN);
        nl();
        g_stmts();
        ind();
        outs(G_ENDFN);
        nl();
        return 0;
    }
    if accept_kw("if") == 1 {
        ind();
        outs("if ");
        if TGT == T_RUBY { emit_expr(); }
        else {
            if TGT == T_LUA { emit_expr(); outs(" then"); }
            else { outs(" ("); emit_expr(); outs(")"); }
        }
        outs(" ");
        expect_op("{");
        outs(G_BOPEN);
        nl();
        g_stmts();
        while is_kw("else") == 1 {
            TI = TI + 1;
            if is_kw("if") == 1 {
                TI = TI + 1;
                ind();
                outs("} ");
                outs(G_ELIF);
                outs(" ");
                if TGT == T_RUBY { emit_expr(); } else { outs(" ("); emit_expr(); outs(")"); }
                outs(" {");
                nl();
                expect_op("{");
                g_stmts();
            } else {
                ind();
                outs("} else {");
                nl();
                expect_op("{");
                g_stmts();
            }
        }
        ind();
        outs("}");
        nl();
        return 0;
    }
    if accept_kw("let") == 1 {
        let nm: i64 = ident();
        expect_op(":");
        let dim: i64 = consume_type();
        ind();
        if dim > 0 {
            g_decl(nm, dim);
            if accept_op("=") == 1 { emit_expr(); }
        } else {
            if is_struct_ty(LASTTY) == 1 {
                # 结构体实例
                if TGT == T_JAVA { outs(""); outs(LASTTY); outs(" "); outs(nm); outs(" = new "); outs(LASTTY); outs("()"); }
                else {
                    if TGT == T_CS { outs(LASTTY); outs(" "); outs(nm); outs(" = new "); outs(LASTTY); outs("()"); }
                    else {
                        if TGT == T_GO { outs("var "); outs(nm); outs(" "); outs(LASTTY); }
                        else {
                            if TGT == T_RUST { outs("let mut "); outs(nm); outs(" = "); outs(LASTTY); outs(" {}"); }
                            else {
                                if TGT == T_SWIFT { outs("var "); outs(nm); outs(" = "); outs(LASTTY); outs("()"); }
                                else { outs(nm); outs(" = "); outs(LASTTY); outs(".new"); }
                            }
                        }
                    }
                }
                if accept_op("=") == 1 { emit_expr(); }
            } else {
                g_decl(nm, 0);
                if accept_op("=") == 1 { outs(" = "); emit_expr(); }
                else {
                    if TGT == T_RUST { outs(" = 0"); }
                    else {
                        if TGT == T_GO { outs(" = 0"); }
                        else {
                            if TGT == T_JAVA { outs(" = 0"); }
                            else {
                                if TGT == T_CS { outs(" = 0"); }
                                else {
                                    if TGT == T_SWIFT { outs(" = 0"); }
                                    else { outs(" = 0"); }
                                }
                            }
                        }
                    }
                }
            }
        }
        if G_SEMI == 1 { outs(";"); }
        nl();
        expect_op(";");
        return 0;
    }
    ind();
    emit_expr();
    expect_op(";");
    if G_SEMI == 1 { outs(";"); }
    nl();
    return 0;
}

fn g_stmts() -> i64 {
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in block"); }
        g_stmt();
    }
    TI = TI + 1;
    return 0;
}

# ---------- 通用后端的签名与结构体 ----------

fn g_sig() -> i64 {
    let nm: i64 = ident();
    expect_op("(");
    let ps: [512] byte = 0;
    let first: i64 = 1;
    while is_op(")") == 0 {
        if first == 0 { strcat(&ps, ", "); }
        first = 0;
        let pn: i64 = ident();
        expect_op(":");
        let d: i64 = consume_type();
        if G_TYPED == 1 {
            if TGT == T_GO { strcat(&ps, pn); strcat(&ps, " "); strcat(&ps, G_TYI64); }
            else {
                if TGT == T_RUST { strcat(&ps, pn); strcat(&ps, ": "); strcat(&ps, G_TYI64); }
                else {
                    if TGT == T_SWIFT { strcat(&ps, pn); strcat(&ps, ": "); strcat(&ps, G_TYI64); }
                    else { strcat(&ps, G_TYI64); strcat(&ps, " "); strcat(&ps, pn); }
                }
            }
        } else {
            strcat(&ps, G_REF);
            strcat(&ps, pn);
        }
        if is_op(",") == 1 { TI = TI + 1; } else { break; }
    }
    expect_op(")");
    accept_op("-");
    accept_op(">");
    if cur_k() == 1 { TI = TI + 1; }

    if TGT == T_GO { outs("func "); outs(nm); outs("("); outs(&ps); outs(") int64 "); return 0; }
    if TGT == T_RUST { outs("fn "); outs(nm); outs("("); outs(&ps); outs(") -> i64 "); return 0; }
    if TGT == T_SWIFT { outs("func "); outs(nm); outs("("); outs(&ps); outs(") -> Int64 "); return 0; }
    if TGT == T_JAVA { outs("static long "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_CS { outs("static long "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_RUBY { outs("def "); outs(nm); outs("("); outs(&ps); outs(")"); return 0; }
    if TGT == T_PHP { outs("function "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_LUA { outs("function "); outs(nm); outs("("); outs(&ps); outs(")"); return 0; }
    outs("sub ");
    outs(nm);
    outs(" { my (");
    outs(&ps);
    outs(") = @_;");
    return 0;
}

fn g_struct() -> i64 {
    let nm: i64 = ident();
    if TGT == T_PERL { return err("Perl 后端不支持 struct（用 hash 需另设语义）"); }
    if TGT == T_LUA { return err("Lua 后端不支持 struct（用 table 需另设语义）"); }
    if TGT == T_GO {
        outs("type ");
        outs(nm);
        outs(" struct {\n");
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let f: i64 = ident();
            expect_op(":");
            let d: i64 = consume_type();
            outs("    ");
            outs(f);
            outs(" int64\n");
            expect_op(";");
        }
        TI = TI + 1;
        outs("}\n");
        return 0;
    }
    if TGT == T_RUST {
        outs("struct ");
        outs(nm);
        outs(" { ");
        expect_op("{");
        let first: i64 = 1;
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let f: i64 = ident();
            expect_op(":");
            let d: i64 = consume_type();
            if first == 0 { outs(", "); }
            first = 0;
            outs(f);
            outs(": i64");
            expect_op(";");
        }
        TI = TI + 1;
        outs(" }\n");
        return 0;
    }
    # java / cs / swift / ruby / php：class
    outs(G_CLASS);
    outs(nm);
    outs(" {\n");
    expect_op("{");
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in struct"); }
        let f: i64 = ident();
        expect_op(":");
        let d: i64 = consume_type();
        if TGT == T_RUBY { outs("  attr_accessor :"); outs(f); nl(); }
        else {
            if TGT == T_PHP { outs("  public $"); outs(f); outs(" = 0;"); nl(); }
            else {
                if TGT == T_JAVA { outs("  public long "); outs(f); outs(" = 0;"); nl(); }
                else {
                    if TGT == T_CS { outs("  public long "); outs(f); outs(" = 0;"); nl(); }
                    else { outs("  var "); outs(f); outs(": Int64 = 0"); nl(); }
                }
            }
        }
        expect_op(";");
    }
    TI = TI + 1;
    outs(G_ENDCLASS);
    nl();
    return 0;
}

fn g_block() -> i64 {
    expect_op("{");
    outs(" ");
    outs(G_FNBOPEN);
    nl();
    g_stmts();
    ind();
    outs(G_ENDFN);
    nl();
    return 0;
}

# 目标识别：用 if-return 平铺，避免深层 else 链
# （墨语言的 else 必须紧跟 }，深层嵌套极易写错）
fn target_id(t: i64) -> i64 {
    if streq(t, "c") == 1 { TGT = T_C; return 1; }
    if streq(t, "js") == 1 { TGT = T_JS; return 1; }
    if streq(t, "py") == 1 { TGT = T_PY; return 1; }
    if streq(t, "perl") == 1 { set_profile(T_PERL); return 1; }
    if streq(t, "java") == 1 { set_profile(T_JAVA); return 1; }
    if streq(t, "go") == 1 { set_profile(T_GO); return 1; }
    if streq(t, "rust") == 1 { set_profile(T_RUST); return 1; }
    if streq(t, "cs") == 1 { set_profile(T_CS); return 1; }
    if streq(t, "swift") == 1 { set_profile(T_SWIFT); return 1; }
    if streq(t, "ruby") == 1 { set_profile(T_RUBY); return 1; }
    if streq(t, "lua") == 1 { set_profile(T_LUA); return 1; }
    if streq(t, "php") == 1 { set_profile(T_PHP); return 1; }
    if streq(t, "cfs") == 1 { TGT = T_FS; FS_ARCH = 1; FSNAME = "x86_64"; return 1; }
    if streq(t, "cfs-x86_64") == 1 { TGT = T_FS; FS_ARCH = 1; FSNAME = "x86_64"; return 1; }
    if streq(t, "cfs-aarch64") == 1 { TGT = T_FS; FS_ARCH = 2; FSNAME = "aarch64"; return 1; }
    if streq(t, "cfs-arm64") == 1 { TGT = T_FS; FS_ARCH = 2; FSNAME = "aarch64"; return 1; }
    if streq(t, "cfs-riscv64") == 1 { TGT = T_FS; FS_ARCH = 3; FSNAME = "riscv64"; return 1; }
    if streq(t, "cfs-s390x") == 1 { TGT = T_FS; FS_ARCH = 4; FSNAME = "s390x"; return 1; }
    if streq(t, "cfs-ppc64le") == 1 { TGT = T_FS; FS_ARCH = 5; FSNAME = "ppc64le"; return 1; }
    if streq(t, "cfs-ppc64") == 1 { TGT = T_FS; FS_ARCH = 6; FSNAME = "ppc64"; return 1; }
    if streq(t, "kern") == 1 { TGT = T_KERN; return 1; }
    if streq(t, "kern-i386") == 1 { TGT = T_KERN; return 1; }
    if streq(t, "kern-x86_64") == 1 { TGT = T_KERN; return 1; }
    if streq(t, "kern-aarch64") == 1 { TGT = T_KERN; KERN_ARCH = 2; return 1; }
    if streq(t, "kern-arm64") == 1 { TGT = T_KERN; KERN_ARCH = 2; return 1; }
    if streq(t, "uefi") == 1 { TGT = T_UEFI; return 1; }
    return 0;
}


fn main() -> i64 {
    if argc() < 3 {
        print("usage: mo2x <file.mo> <target>\n");
        print("target: c | cfs | cfs-aarch64 | cfs-riscv64 | cfs-s390x | cfs-ppc64le\n");
        print("        kern | uefi | js | py | perl\n");
        print("        java | go | rust | cs | swift | ruby | lua | php\n");
        return 2;
    }
    if target_id(argv(2)) == 0 {
        print("unknown target: ");
        print(argv(2));
        print("\n");
        return 2;
    }
    add_file(argv(1));
    if is_gen() == 1 { g_header(); } else { emit_header(); }
    let i: i64 = 0;
    while i < NF { pass_file(i, 0); i = i + 1; }
    let j: i64 = 0;
    while j < NF { pass_file(j, 1); j = j + 1; }
    let k: i64 = 0;
    while k < NF { pass_file(k, 2); k = k + 1; }
    let m: i64 = 0;
    while m < NF { pass_file(m, 3); m = m + 1; }
    if is_gen() == 1 { g_footer(); } else { emit_footer(); }
    return 0;
}

# 通用后端的全局变量声明
fn g_global() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    let dim: i64 = consume_type();
    if TGT == T_PERL {
        if dim > 0 { outs("my @"); outs(nm); outs(" = (0) x "); outi(dim); }
        else { outs("my $"); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_RUBY {
        outs(nm);
        if dim > 0 { outs(" = Array.new("); outi(dim); outs(", 0)"); } else { outs(" = 0"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_GO {
        outs("var ");
        outs(nm);
        if dim > 0 { outs(" = make([]int64, "); outi(dim); outs(")"); } else { outs(" int64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_RUST {
        outs("static mut ");
        outs(nm);
        if dim > 0 { outs(": Vec<i64> = Vec::new()"); } else { outs(": i64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_JAVA {
        if dim > 0 { outs("static long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); }
        else { outs("static long "); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_CS {
        if dim > 0 { outs("static long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); }
        else { outs("static long "); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_SWIFT {
        outs("var ");
        outs(nm);
        if dim > 0 { outs(" = [Int64](repeating: 0, count: "); outi(dim); outs(")"); }
        else { outs(": Int64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_PHP {
        outs(G_REF);
        outs(nm);
        if dim > 0 { outs(" = array_fill(0, "); outi(dim); outs(", 0)"); } else { outs(" = 0"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    outs("local ");
    outs(nm);
    if dim > 0 { outs(" = {}"); } else { outs(" = 0"); }
    if accept_op("=") == 1 { outs(" = "); emit_expr(); }
    nl();
    expect_op(";");
    return 0;
}
