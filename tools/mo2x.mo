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
var LWSEQ: i64 = 0;        # v1.1195: 可写字面量副本计数
var BOL: i64 = 1;          # 行首标记（全局变量必须先声明）



var OBF: i64 = 0;
# v1.1201: 全量输出缓冲 —— err() 失败退出时半截产物不进 stdout（自评测缺陷③）。
# 成功路径由 main 末尾 out_flush() 一次性 write。8MB 上限（实测 C 产物 6.4MB），满则中途 flush。
var OBUF: [8388608] byte = 0;
var OPO: i64 = 0;
fn out_flush() -> i64 {
    if OPO > 0 { syscall(1, 1, &OBUF, OPO, 0, 0, 0); }
    OPO = 0;
    return 0;
}
fn raw(s: i64) -> i64 {
    if OBF == 1 {
        let n: i64 = strlen(s);
        if OPO + n > 8388000 { out_flush(); }   # 防御：接近 16MB 边界先 flush
        let q: i64 = 0;
        while q < n { store8(&OBUF + OPO, load8(s + q)); OPO = OPO + 1; q = q + 1; }
        return 0;
    }
    let n2: i64 = strlen(s);
    if n2 > 0 { syscall(1, 1, s, n2, 0, 0, 0); }
    return 0;
}
fn rawc(c: i64) -> i64 {
    if OBF == 1 {
        if OPO + 1 > 8388000 { out_flush(); }
        store8(&OBUF + OPO, c);
        OPO = OPO + 1;
        return 0;
    }
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

# v1.1193: 稳定字符串池 —— 各名字表存的名字一律拷贝到此。
# POOL 每个文件重新 tokenize 时 PP=0 整体重写，表里的裸指针会悬空，
# 之后 streq 撞上重写后的无关内容（126_fmath 里 fm_trunc 撞进 PTRV 的根因）。
var STP: [1048576] byte = 0;
var NSTP: i64 = 0;
fn stp_copy(s: i64) -> i64 {
    let p: i64 = &STP + NSTP;
    let q: i64 = 0;
    while load8(s + q) != 0 {
        if NSTP + q >= 1048570 { break; }
        store8(p + q, load8(s + q));
        q = q + 1;
    }
    store8(p + q, 0);
    NSTP = NSTP + q + 1;
    return p;
}
var PP: i64 = 0;

var TK: [200000] i64 = 0;
var TS: [200000] i64 = 0;
var NT: i64 = 0;
var TI: i64 = 0;

# v1.1162: 顶层 const 表（mo2x 此前**完全忽略** const 声明 —— token 兜底跳过，
# 于是 `var A: [N] i64` 里的 N 在 C 里未定义，编译报 use of undeclared identifier）。
# 🔴 必须定义在**所有使用者之前**（Mo 无前向声明；前向调用会被当成外部符号，
#    链接到 0 地址，运行时段错误 —— 表现为"输出到一半突然 SIGSEGV"）。
var CNSN: [256] i64 = 0;    # 名字在 CNSP 池里的偏移（不用 POOL —— 它每轮重写）
var CNSV: [256] i64 = 0;
var NCNS: i64 = 0;
var CNSP: [4096] byte = 0;
var GDIM: [2048] byte = 0;   # 数组维度表达式缓存（全局，勿用局部——返回后栈帧失效）
var GDIMD: i64 = 0;
var ADIM: i64 = 0;   # v1.1193: 最近解析的数组维度数值（标量填充用）          # 当前嵌套深度（多维数组各占 512 字节）
var CNSPP: i64 = 0;

# v1.1163: const fn 求值器（C 后端数组长度 / const 声明用）
# 独立 token 流，不动主解析上下文。
var CFSRC: [16384] byte = 0;   # 函数体源码（拼接）
var CFBO: [512] i64 = 0;       # 函数体在 CFSRC 的起始
var CFBL: [512] i64 = 0;       # 函数体长度
var CFN:  [512] i64 = 0;       # 函数名（CNSP 偏移）
var CFNP: [512] i64 = 0;       # 参数个数
var CFPA: [4096] i64 = 0;      # 参数名（CNSP 偏移）
var NCF:  i64 = 0;             # const fn 个数
var CFARGS: [8] i64 = 0;       # 当前调用实参
var CFTK: [4096] i64 = 0;      # 体 tokens（kind）
var CFTS: [4096] i64 = 0;      # 体 tokens（CFSRC 偏移）
var NCFT: i64 = 0;             # 体 token 数
var CFI:  i64 = 0;             # 体解释指针
var CFTI: i64 = 0;             # 主 token 流恢复点（调用后应位于 ')' 之后）
var CFMODE: i64 = 0;           # 1=正在解释 const fn（嵌套调用时保护）
var CFBOFF: i64 = 0;             # CFSRC 写入游标
var CFFI2: [128] i64 = 0;        # 每帧正在执行的 const fn 索引
var CFTK0: [8192] i64 = 0;      # 所有 const fn 体的 token kind 静态区
var CFTS0: [8192] i64 = 0;      # 所有 const fn 体的 token 文本偏移（相对 CFSRC）
var CFBO0: [512] i64 = 0;       # 函数体在 CFTK0 的起始索引
var CFBL0: [512] i64 = 0;       # 函数体 token 数
var CFTKP: [8192] i64 = 0;      # 帧 token 池（按深度 512 分段）
var CFTSP: [8192] i64 = 0;      # 帧 token 池偏移
var CFBASE: [128] i64 = 0;      # 每帧在 token 池的起点
var CFNF: [128] i64 = 0;        # 每帧 token 数
var CFTOK: i64 = 0;             # CFTK0 写入游标

# 解释器帧栈（递归调用）
var CFNAME: [4096] i64 = 0;   # 参数名（CNSP 偏移），栈式（每帧 512 槽）
var CFVAL:  [4096] i64 = 0;   # 参数值，栈式（每帧 512 槽）
var CFFSTART: [128] i64 = 0;  # 每帧在 CFNAME/CFVAL 的起点
var CFNDEP: i64 = 0;          # 当前帧深度
var CFSP: [128] i64 = 0;      # 保存主 TI（调用返回点）
var CFRET: [128] i64 = 0;     # 保存主 CFI（体解释指针）
var CFNT: [128] i64 = 0;      # 保存主 NCFT
var CFFID: [128] i64 = 0;     # 保存主 CFFSTART 当前帧起点
var CFLN: [128] i64 = 0;      # 每帧局部变量数（局部区在参数区之后）
var CFWEND: [32] i64 = 0;     # while 循环体结束 token index 栈
var CFWP: i64 = 0;            # while 栈顶
var CFLM_B: i64 = 0;  # break 魔数返回值（0-999999001，惰性初始化）
var CFLM_C: i64 = 0;  # continue 魔数（0-999999002）
var CFLM_R: i64 = 0;  # return 魔数（0-999999003）
var CFMAG: i64 = 0;   # 魔数初始化标志
var CFRET_V: i64 = 0;             # return 表达式值

fn cf_init_magics() -> i64 {
    if CFMAG == 1 { return 0; }
    CFLM_B = 0 - 999999001;
    CFLM_C = 0 - 999999002;
    CFLM_R = 0 - 999999003;
    CFMAG = 1;
    return 0;
}
fn cns_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NCNS {
        if streq(&CNSP + CNSN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

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
    OPS[0] = "<<="; OPS[1] = ">>="; OPS[2] = "=>"; OPS[3] = "=="; OPS[4] = "!="; OPS[5] = "<="; OPS[6] = ">=";
    OPS[7] = "&&"; OPS[8] = "||"; OPS[9] = "<<"; OPS[10] = ">>";
    OPS[11] = "+="; OPS[12] = "-="; OPS[13] = "*="; OPS[14] = "/=";
    OPS[15] = "%="; OPS[16] = "&="; OPS[17] = "|="; OPS[18] = "^=";
    OPS[19] = "+"; OPS[20] = "-"; OPS[21] = "*"; OPS[22] = "/";
    OPS[23] = "%"; OPS[24] = "&"; OPS[25] = "|"; OPS[26] = "^";
    OPS[27] = "="; OPS[28] = "<"; OPS[29] = ">"; OPS[30] = "!";
    NOPS = 31;
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
                        if c == 46 && load8(&SRC + SLEN + 1) == 46 {
                            # v1.1203: '..' range/切片单 token（319；moc 同款）
                            store8(&LEXB, 46); store8(&LEXB + 1, 46); store8(&LEXB + 2, 0);
                            SLEN = SLEN + 2;
                            add_tok(5, &LEXB);
                        } else {
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
                        }   # v1.1203: '..' 分支的 else 闭合
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
# FSGR[i]=返回 kind。CURRTK=当前函数返回 kind。
var FSGH: [512] i64 = 0;
var FSGC: [256] i64 = 0;
var FSGK: [4096] i64 = 0;
var FSGR: [256] i64 = 0;
var FSGD: [2048] i64 = 0;   # v1.1199: 形参默认值 FSGD[reg*8+idx]
var FSGDH: [256] i64 = 0;   # v1.1199: reg 从该实参索引起有默认（0=无）
var FSGN: [2048] i64 = 0;   # v1.1199: 形参名（具名实参）
var NAPOS: [8] i64 = 0;   # v1.1206: named args 槽提供标记（1=提供）
var NAST: [8] i64 = 0;    # 实参 token 起点
var NAEN: [8] i64 = 0;    # 实参 token 终点
var FldPTR: [128] i64 = 0;   # v1.1199: ptr 类型字段名（链式访问 -> ）
var FldE: [128] i64 = 0;   # v1.1199: ptr 字段元素类型
var NFldPTR: i64 = 0;
fn fldptr_elm(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NFldPTR {
        if streq(FldPTR[i], nm) == 1 { return FldE[i]; }
        i = i + 1;
    }
    return 0;
}
# v1.1199: 链式 ptr 字段访问重建：L_i = ((T*)(L_{i-1}))->f_i 或 L_{i-1}.f_i
fn chain_rec(base: i64, f0: i64, f1: i64, f2: i64, f3: i64, nf: i64, i: i64) -> i64 {
    if i == 0 { outs(base); return 0; }
    # f_{i-1}（0 索引）是左层字段
    let prev: i64 = 0;
    if i == 1 { prev = 0; } else { if i == 2 { prev = f0; } else { if i == 3 { prev = f1; } else { prev = f2; } } }
    let cur: i64 = 0;
    if i == 1 { cur = f0; } else { if i == 2 { cur = f1; } else { if i == 3 { cur = f2; } else { cur = f3; } } }
    if i > 1 && prev != 0 {
        let fe: i64 = fldptr_elm(prev);
        if fe != 0 {
            if streq(fe, "i64") == 1 { outs("((long long*)("); } else { outs("((struct "); outs(fe); outs("_t*)("); }
            chain_rec(base, f0, f1, f2, f3, nf, i - 1);
            outs("))");
            outs("->");
            outs(cur);
            return 0;
        }
    }
    chain_rec(base, f0, f1, f2, f3, nf, i - 1);
    outs(".");
    outs(cur);
    return 0;
}
fn fldptr_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NFldPTR {
        if streq(FldPTR[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}
var NFSG: i64 = 0;

fn try_strcmp() -> i64 {
    if cur_k() == 3 {
        # v1.1193: 字面量 CMPOP 字面量/str 变量 —— "ab" < "abc" 按内容比
        let save6: i64 = TI;
        TI = TI + 1;
        if cur_k() != 5 { TI = save6; return 0; }
        let op6: i64 = &POOL + TS[TI];
        let ic6: i64 = 0;
        if streq(op6, "==") == 1 { ic6 = 1; }
        if streq(op6, "!=") == 1 { ic6 = 1; }
        if streq(op6, "<") == 1 { ic6 = 1; }
        if streq(op6, ">") == 1 { ic6 = 1; }
        if streq(op6, "<=") == 1 { ic6 = 1; }
        if streq(op6, ">=") == 1 { ic6 = 1; }
        if ic6 == 0 { TI = save6; return 0; }
        TI = TI + 1;
        if cur_k() == 3 || (cur_k() == 1 && strv_find(cur_s()) == 1) {
            outs("strcmp((unsigned char*)");
            out_cstr(&POOL + TS[save6]);
            outs(", (unsigned char*)");
            if cur_k() == 3 { out_cstr(cur_s()); } else { outs(cur_s()); }
            outs(") ");
            outs(op6);
            outs(" 0");
            TI = TI + 1;
            return 1;
        }
        TI = save6;
        return 0;
    }
    if cur_k() != 1 { return 0; }
    let a: i64 = cur_s();
    let isa: i64 = strv_find(a);
    if isa == 0 {
        # v1.1193: 左是返回 str/ptr 的函数调用 ident(...) —— 扩展 strcmp 改写。
        # 先保存，配平实参括号，看后面是不是比较符。
        let sv5: i64 = TI;
        if fsg_find(a) < 0 { return 0; }
        if FSGR[fsg_find(a)] != 1 { return 0; }
        TI = TI + 1;
        if is_op("(") == 0 { TI = sv5; return 0; }
        TI = TI + 1;
        let dep5: i64 = 1;
        while dep5 > 0 && TI < NT {
            if TK[TI] == 5 {
                let s5: i64 = &POOL + TS[TI];
                if streq(s5, "(") == 1 { dep5 = dep5 + 1; }
                if streq(s5, ")") == 1 { dep5 = dep5 - 1; }
            }
            TI = TI + 1;
        }
        if dep5 != 0 { TI = sv5; return 0; }
        if cur_k() != 5 { TI = sv5; return 0; }
        let opidx: i64 = TI;
        let opb: [16] byte = 0;
        let op5: i64 = &opb;
        {
            let c5: i64 = 0;
            let s5b: i64 = &POOL + TS[TI];
            while load8(s5b + c5) != 0 && c5 < 14 { store8(&opb + c5, load8(s5b + c5)); c5 = c5 + 1; }
            store8(&opb + c5, 0);
        }
        let ic5: i64 = 0;
        if streq(op5, "==") == 1 { ic5 = 1; }
        if streq(op5, "!=") == 1 { ic5 = 1; }
        if streq(op5, "<") == 1 { ic5 = 1; }
        if streq(op5, ">") == 1 { ic5 = 1; }
        if streq(op5, "<=") == 1 { ic5 = 1; }
        if streq(op5, ">=") == 1 { ic5 = 1; }
        if ic5 == 0 { TI = sv5; return 0; }
        TI = TI + 1;
        if cur_k() == 3 || (cur_k() == 1 && strv_find(cur_s()) == 1) {
            # 重放调用：emit 到 ')'（emit_primary 一次搞定整个调用）
            TI = sv5;
            outs("strcmp((unsigned char*)");
            emit_primary();
            outs(", (unsigned char*)");
            TI = opidx + 1;
            if cur_k() == 3 { out_cstr(cur_s()); } else { outs(cur_s()); }
            outs(") ");
            outs(op5);
            outs(" 0");
            TI = opidx + 2;
            return 1;
        }
        TI = sv5;
        return 0;
    }
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



var ARRDIM: [2048] i64 = 0;
# v1.1202: 解构行绑定 —— 二维数组声明时的内层维 + 绑定名标记
var ARRDIM2: [2048] i64 = 0;
var ARRW: [2048] i64 = 0;   # v1.1196: 各数组最外维（OOB 运行时检查用）
var EMITFH: [256] i64 = 0;   # v1.1198: 已发函数名 hash（跨文件重复定义去重）
var ENMH: [64] i64 = 0;      # v1.1200: 已发射 enum 名 hash（成员是 C 全局标识符，重发=重定义）
# v1.1206: enum 带数据变体（tagged union）
var EVN: [64] i64 = 0;       # enum 名（stp_copy）
var EVNH: [64] i64 = 0;      # 名 hash
var NEVN: i64 = 0;
var EVCN: [64] i64 = 0;      # 每 enum 变体数
var EVTN: [64*8] i64 = 0;    # 变体名（stp_copy）[enum*8+v]
var EVFC: [64*8] i64 = 0;    # 变体字段数 [enum*8+v]
var EVFK: [64*8*4] i64 = 0;  # 字段 kind [enum*8+v*4+f]  0=i64,1=ptr,3=f64,2=byte
var EVIN: [64] i64 = 0;      # 含带参变体旗标（is_struct_ty 放行）
var EVEM: [64] i64 = 0;
var NMDBG: i64 = 0;      # tagged struct 已发射旗标
var NENMH: i64 = 0;
var ENUMN: [64] i64 = 0;
var NENUMN: i64 = 0;
var NEMITF: i64 = 0;
var CAST_OPEN: i64 = 0;
var PCAST_OPEN: i64 = 0;   # v1.1198: int-ptr 混合 cast 闭括号旗标    # emit_primary 已发 "(long long)("，postfix ']' 后闭合
# v1.1164: 函数签名注册表 —— 调用点按形参类型发隐式 cast（ptr↔i64 互传在 C 里报错）。
# 🔴 键是函数名哈希（FNV-1a 数值），不存名字指针：POOL 在跨文件 tokenize 时 PP=0 重置，
#    绝对地址/偏移都会失效 —— 名字内容被覆盖导致 fsg_find 误命中（io.mo print_f64 的 f64 调用
#    命中 atoi 槽位就是这个坑）。哈希数值跨文件稳定。
# FSGH[i]=名哈希, FSGC[i]=参数个数, FSGK[i*8+j]=参数 j kind（0=i64,1=ptr,2=byte,3=f64,4=其他）,
var CURRTK: i64 = 4;
var CURRTS: i64 = 0;   # v1.1199: 当前函数 struct 返回类型名（CURRTK==4 时）

fn nm_hash(nm: i64) -> i64 {
    let h: i64 = 2166136261;
    let q: i64 = 0;
    while load8(nm + q) != 0 {
        h = (h ^ load8(nm + q)) * 16777619;
        h = h & 268435455;
        q = q + 1;
    }
    return h;
}

fn emit_primary() -> i64 {
    if cur_k() == 2 {
        # v1.1196: 移位左操作数字面量加 LL —— C 里 `1 << 63` 是 int 移位 UB，
        # mo 语义是 i64 wrap（lib/cms.mo cm_shr 的 (1 << (64-n))-1 实测坑：147_cbfcu）
        if peek_op("<<") == 1 { outs(cur_s()); outs("LL"); }
        else { outs(cur_s()); }
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 3 {
        if is_c_like() == 1 {
            # v1.1198: 字面量下标 "…"[N] 包 (unsigned char) —— C 串下标 char 有符号，
            # "\xe4"[0] 得 -28（129_escx）；mo 语义 unsigned。
            if peek_op("[") == 1 {
                outs("((unsigned char*)");
                out_cstr(cur_s());
                outs(")");
            } else {
                outs("(unsigned char*)");
                out_cstr(cur_s());
            }
        } else {
            out_cstr(cur_s());
        }
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
        # v1.1206: enum 带数据变体构造 Enum.Variant(args) → tagged struct 字面量
        if is_op(".") == 1 && TK[TI + 1] == 1 {
            let evn: i64 = nm_hash(nm);
            let evi: i64 = 0 - 1;
            let evq: i64 = 0;
            while evq < NEVN { if EVNH[evq] == evn { evi = evq; } evq = evq + 1; }
            if evi >= 0 && EVIN[evi] == 1 {

                let vq: i64 = TI + 1;   # 指向变体名
                let vpn: i64 = 0;
                let vvi: i64 = 0 - 1;
                let vq2: i64 = 0;
                while vq2 < EVCN[evi] {
                    if streq(EVTN[evi * 8 + vq2], &POOL + TS[vq]) == 1 { vvi = vq2; }
                    vq2 = vq2 + 1;
                }
                if vvi >= 0 && TK[vq + 1] == 5 && streq(&POOL + TS[vq + 1], "(") == 1 {
                    vpn = 1;
                    TI = vq + 2;   # 进入实参
                    outs("(");
                    outs(EVN[evi]);
                    outs("_t){.tag="); outi(vvi); outs(", ");
                    let fa6: i64 = 0;
                    while fa6 < EVFC[evi * 8 + vvi] {
                        outs("._"); outi(fa6); outs("=");
                        if EVFK[evi * 32 + vvi * 4 + fa6] == 3 { outs("(double)("); }
                        else { if EVFK[evi * 32 + vvi * 4 + fa6] == 1 { outs("(unsigned char*)("); } else { outs("(long long)("); } }
                        emit_expr();
                        outs(")");
                        if is_op(",") == 1 { TI = TI + 1; outs(", "); }
                        fa6 = fa6 + 1;
                    }
                    expect_op(")");
                    outs("}");
                    return 0;
                }
            }
        }
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
            # v1.1191: len() 内建 —— 数组外层元素个数。C 系发 sizeof 比值
            # （C 编译期常量；数组实参传参退化为指针的场景不受支持，与 moc 编译期语义一致——moc 也只在同作用域算）。
            if streq(nm, "len") == 1 {
                TI = TI + 1;
                if cur_k() != 1 { return err("len() 实参必须是数组名"); }
                let an: i64 = cur_s();
                TI = TI + 1;
                expect_op(")");
                if strv_find(an) == 1 {
                    # v1.1196: len(str) = 运行时 strlen（v1.1080 语义；str 变量不是数组）
                    outs("((long long)strlen_((unsigned char*)");
                    outs(an);
                    outs("))");
                    return 0;
                }
                outs("((long long)(sizeof(");
                outs(an);
                outs(")/sizeof(");
                outs(an);
                outs("[0])))");
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
                    outs("MF_P=(long long)");
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
            # v1.1190: 内建 load/store 系走直发（宏）—— 不进 fnptr cast（宏名不可 cast）
            if streq(nm, "store64") == 1 || streq(nm, "load64") == 1 || streq(nm, "store8") == 1 || streq(nm, "load8") == 1 || streq(nm, "store16") == 1 || streq(nm, "load16") == 1 || streq(nm, "store32") == 1 || streq(nm, "load32") == 1 {
                outs(nm); outs("(");
                if is_op(")") == 0 { emit_expr(); while accept_op(",") == 1 { outs(","); emit_expr(); } }
                expect_op(")"); outs(")");
                return 0;
            }
            if ptrv_find(nm) == 1 {
                # v1.1166: ptr 变量调用 f(args) —— fnptr cast 调用。
                # 按**顶层**实参个数发对应函数指针原型（0..6 覆盖常用）。
                # '(' 已由上方统一吃掉 —— TI 直接指第一个实参
                # 数顶层实参个数（扫描配平）
                let sv_t: i64 = TI;
                let dep_t: i64 = 1;
                let na_t: i64 = 0;
                let seen: i64 = 0;
                while dep_t > 0 && TI < NT {
                    if TK[TI] == 5 {
                        let s_t: i64 = &POOL + TS[TI];
                        if streq(s_t, "(") == 1 || streq(s_t, "[") == 1 || streq(s_t, "{") == 1 { dep_t = dep_t + 1; }
                        else {
                            if streq(s_t, ")") == 1 || streq(s_t, "]") == 1 || streq(s_t, "}") == 1 {
                                dep_t = dep_t - 1;
                                if dep_t == 0 { break; }
                            }
                            else {
                                if streq(s_t, ",") == 1 && dep_t == 1 { na_t = na_t + 1; }
                            }
                        }
                    }
                    if TK[TI] != 0 { seen = 1; }
                    TI = TI + 1;
                }
                if seen == 1 { na_t = na_t + 1; }   # 逗号数+1（无逗号单实参）
                TI = sv_t;
                outs("((long long(*)(");
                if na_t == 0 { outs("void"); }
                else {
                    let pi: i64 = 0;
                    while pi < na_t {
                        if pi > 0 { outs(","); }
                        outs("long long");
                        pi = pi + 1;
                    }
                }
                outs("))");
                outs(nm);
                outs(")(");
                let ai4: i64 = 0;
                if is_op(")") == 0 {
                    emit_expr();
                    ai4 = 1;
                    while accept_op(",") == 1 { outs(","); emit_expr(); ai4 = ai4 + 1; }
                }
                expect_op(")");
                outs(")");
                return 0;
            }
            # v1.1171: freestanding 前导自带 static strlen/atoi/memset/memcpy ——
            # 调用直发原名（v1.1164 起 mo_ 前缀让 kern64sys 这类"无 import 直用
            # 前导函数"的 freestanding 程序报 undeclared mo_strlen 回归）。
            # 非 freestanding C 目标维持 mo_ 前缀（CRT 头签名冲突）。
            let skip_clash: i64 = 0;
            if TGT == T_FS {
                if streq(nm, "strlen") == 1 { skip_clash = 1; }
                if streq(nm, "atoi") == 1 { skip_clash = 1; }
                if streq(nm, "memset") == 1 { skip_clash = 1; }
                if streq(nm, "memcpy") == 1 { skip_clash = 1; }
                if streq(nm, "strcpy") == 1 { skip_clash = 1; }
                if streq(nm, "strcat") == 1 { skip_clash = 1; }
            }
            if TGT == T_KERN {
                if streq(nm, "strlen") == 1 { skip_clash = 1; }
                if streq(nm, "strcpy") == 1 { skip_clash = 1; }
                if streq(nm, "strcat") == 1 { skip_clash = 1; }
            }
            # v1.1191: const fn 调用编译期折叠 —— 实参全常量时用 cns_expr 求值发数字
            # （此前 const fn 调用当普通函数发射 → undefined reference，295/335-339 全炸）
            if cf_find_fn(nm) >= 0 && is_c_like() == 1 {
                let sv_cf: i64 = TI;
                # v1.1191: dispatch 进入时 '(' 已被上游吃掉（TI 指第一个实参）
                let cfv: i64 = cf_call_fn(cf_find_fn(nm), 1);
                outi(cfv);
                return 0;
            }
            if skip_clash == 0 {
                if is_libc_clash(nm) == 1 { outs("mo_"); }
            }
            # v1.1177: assert(cond, "msg") → 前导 assert_ helper
            if streq(nm, "assert") == 1 { outs("assert_"); } else { outs(nm); }
            outs("(");
            # v1.1164: 查签名表，按形参类型给实参发隐式 cast（ptr↔i64 互传）
            let fi3: i64 = fsg_find(nm);
            let ai3: i64 = 0;
            # v1.1206: named args——预扫实参 token 范围并映射槽位（name: expr 按 FSGN 匹配），发射按槽序
            let hasnamed: i64 = 0;
            if is_op(")") == 0 {
                let sv6: i64 = TI;
                let q6: i64 = 0;
                while q6 < 8 { NAPOS[q6] = 0; NAST[q6] = 0; NAEN[q6] = 0; q6 = q6 + 1; }
                let nxt6: i64 = 0;
                let det6: i64 = 0;
                while det6 == 0 && is_op(")") == 0 {
                    let st6: i64 = TI;
                    let slot6: i64 = 0 - 1;
                    if cur_k() == 1 && peek_op(":") == 1 && fi3 >= 0 {
                        let an6: i64 = cur_s();
                        let hit6: i64 = 0 - 1;
                        let j6: i64 = 0;
                        while j6 < FSGC[fi3] {
                            if streq(FSGN[fi3 * 8 + j6], an6) == 1 { hit6 = j6; }
                            j6 = j6 + 1;
                        }
                        if hit6 >= 0 { slot6 = hit6; TI = TI + 2; hasnamed = 1; st6 = TI; }
                    } else {
                        if fi3 >= 0 && nxt6 < FSGC[fi3] { slot6 = nxt6; nxt6 = nxt6 + 1; }
                    }
                    if slot6 < 0 { det6 = 1; break; }
                    # 平衡扫描表达式 tokens（到 depth0 ',' 或 ')'）
                    let dp6: i64 = 0;
                    while TI < NT {
                        if TK[TI] == 5 {
                            let c6: i64 = &POOL + TS[TI];
                            if dp6 == 0 && (streq(c6, ",") == 1 || streq(c6, ")") == 1) { break; }
                            if streq(c6, "(") == 1 || streq(c6, "[") == 1 || streq(c6, "{") == 1 { dp6 = dp6 + 1; }
                            if streq(c6, ")") == 1 || streq(c6, "]") == 1 || streq(c6, "}") == 1 { dp6 = dp6 - 1; }
                        }
                        TI = TI + 1;
                    }
                    NAPOS[slot6] = 1;
                    NAST[slot6] = st6;
                    NAEN[slot6] = TI;
                    if is_op(",") == 1 { TI = TI + 1; } else { det6 = 1; }
                }
                TI = sv6;
            }
            if hasnamed == 1 && fi3 >= 0 {
                # 按槽序发射（named 语义：未提供的槽用默认值）
                let ai6: i64 = 0;
                while ai6 < FSGC[fi3] {
                    if ai6 > 0 { outs(","); }
                    if NAPOS[ai6] == 1 {
                        TI = NAST[ai6];
                        if FSGK[fi3 * 8 + ai6] == 1 { outs("(unsigned char*)"); }
                        if FSGK[fi3 * 8 + ai6] == 0 { outs("(long long)("); }
                        if FSGK[fi3 * 8 + ai6] == 5 { outs("&("); }
                        emit_expr();
                        if FSGK[fi3 * 8 + ai6] == 0 { outs(")"); }
                        if FSGK[fi3 * 8 + ai6] == 5 { outs(")"); }
                        TI = NAEN[ai6];
                    } else {
                        # 默认值（FSGD）—— 若该槽无默认则发 0
                        if FSGK[fi3 * 8 + ai6] == 1 { outs("(unsigned char*)0"); }
                        else {
                            if FSGK[fi3 * 8 + ai6] == 5 { outs("(long long)0"); }
                            else { outi(FSGD[fi3 * 8 + ai6]); }
                        }
                    }
                    ai6 = ai6 + 1;
                }
                while is_op(")") == 0 && TI < NT { TI = TI + 1; }
                expect_op(")");
                outs(")");
                return 0;
            }
            if is_op(")") == 0 {
                if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 1 { outs("(unsigned char*)"); }
                if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 0 { outs("(long long)("); }
                if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 5 { outs("&("); }
                emit_expr();
                if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 0 { outs(")"); }
                if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 5 { outs(")"); }
                ai3 = 1;
                while accept_op(",") == 1 {
                    outs(",");
                    if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 1 { outs("(unsigned char*)"); }
                    if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 0 { outs("(long long)("); }
                    if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 5 { outs("&("); }
                    emit_expr();
                    if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 0 { outs(")"); }
                    if fi3 >= 0 && FSGK[fi3 * 8 + ai3] == 5 { outs(")"); }
                    ai3 = ai3 + 1;
                }
            }

            # v1.1199: 缺省实参补默认（FSGDH[fi3]=首个有默认的实参索引）
            if fi3 >= 0 && FSGDH[fi3] > 0 {
                while ai3 < FSGC[fi3] {
                    if ai3 > 0 { outs(","); }
                    if FSGK[fi3 * 8 + ai3] == 1 { outs("(unsigned char*)"); }
                    if FSGK[fi3 * 8 + ai3] == 5 { outs("(long long)"); }
                    outi(FSGD[fi3 * 8 + ai3]);
                    ai3 = ai3 + 1;
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
    # v1.1203: 切片预扫 IDENT '[' a '..' b ']' —— 必须在 primary 发出基名之前拦截
    if is_c_like() == 1 && cur_k() == 1 && peek_op("[") == 1 {
        let sb0: i64 = cur_s();
        let j0: i64 = TI + 2;
        let dep0: i64 = 1;
        let hasdd: i64 = 0;
        while j0 < NT {
            if TK[j0] == 5 && streq(&POOL + TS[j0], "[") == 1 { dep0 = dep0 + 1; }
            else {
                if TK[j0] == 5 && streq(&POOL + TS[j0], "]") == 1 {
                    dep0 = dep0 - 1;
                    if dep0 == 0 { break; }
                }
                else {
                    if dep0 == 1 && TK[j0] == 5 && streq(&POOL + TS[j0], "..") == 1 { hasdd = 1; }
                }
            }
            j0 = j0 + 1;
        }
        if hasdd == 1 && TK[j0] == 5 && streq(&POOL + TS[j0], "]") == 1 {
            TI = TI + 2;   # 吃 '[' → 指向 a
            outs("mo_slice((unsigned char*)");
            outs(sb0);
            outs(",");
            let sv_co4: i64 = CAST_OPEN;
            CAST_OPEN = 0;
            emit_expr();
            outs(",");
            expect_op("..");
            emit_expr();
            CAST_OPEN = sv_co4;
            expect_op("]");
            outs(")");
            return 0;
        }
    }
    # v1.1199: 链式 ptr 字段访问预扫：base .f1 .f2 ...（纯 '.' 链，含 fldptr）→ chain_rec 重建
    if is_c_like() == 1 && cur_k() == 1 && peek_op(".") == 1 {
        let cb: i64 = cur_s();
        let cj: i64 = TI + 2;
        let cf0: i64 = 0;
        let cf1: i64 = 0;
        let cf2: i64 = 0;
        let cf3: i64 = 0;
        let cn: i64 = 0;
        let hasptr: i64 = 0;
        while cj + 1 < NT && TK[cj] == 1 && TK[cj - 1] == 5 && streq(&POOL + TS[cj - 1], ".") == 1 && cn < 4 {
            if cn == 0 { cf0 = &POOL + TS[cj]; } else { if cn == 1 { cf1 = &POOL + TS[cj]; } else { if cn == 2 { cf2 = &POOL + TS[cj]; } else { cf3 = &POOL + TS[cj]; } } }
            if fldptr_find(&POOL + TS[cj]) == 1 { hasptr = 1; }
            cn = cn + 1;
            cj = cj + 2;
        }
        if hasptr == 1 && cn > 0 && ptrv_find(cb) == 0 {
            TI = TI + 1 + cn * 2;   # 吃 base .f1 .f2 ...
            chain_rec(cb, cf0, cf1, cf2, cf3, cn, cn);
            return 0;
        }
    }
    # v1.1199: C 系方法调用 IDENT.method(args) → Type_method(&IDENT, args)。
    # obj 为 struct 值变量 → &obj；PTRS/PTRV 成员（指针槽）→ 原样。
    if is_c_like() == 1 && cur_k() == 1 && peek_op(".") == 1 && TK[TI + 2] == 1 && TK[TI + 3] == 5 && streq(&POOL + TS[TI + 3], "(") == 1 {
        let onm2: i64 = cur_s();
        let mth2: i64 = &POOL + TS[TI + 2];
        let ty2: i64 = clsv_ty(onm2);
        # v1.1199: str 变量方法 s.mth(args) —— contains→strstr 内建；starts_with/ends_with→str_*
        if ty2 == 0 && strv_find(onm2) == 1 {
            let m2: i64 = &POOL + TS[TI + 2];
            if streq(m2, "contains") == 1 {
                TI = TI + 4;
                outs("((long long)(strstr((char*)");
                outs(onm2);
                outs(",(char*)");
                emit_expr();
                outs(")!=0))");
                TI = TI + 1;
                return 0;
            }
            let buf3: [128] byte = 0;
            strcat(&buf3, "str_");
            strcat(&buf3, m2);
            if fsg_find(&buf3) >= 0 {
                TI = TI + 4;
                outs(&buf3);
                outs("(");
                outs("(unsigned char*)");
                outs(onm2);
                if is_op(")") == 0 {
                    outs(",");
                    emit_expr();
                    while accept_op(",") == 1 { outs(","); emit_expr(); }
                }
                TI = TI + 1;
                outs(")");
                return 0;
            }
        }
        if ty2 != 0 {
            let buf2: [128] byte = 0;
            strcat(&buf2, ty2);
            strcat(&buf2, "_");
            strcat(&buf2, mth2);
            if fsg_find(&buf2) >= 0 {
                TI = TI + 4;   # 吃 obj . method (
                let empty4: i64 = is_op(")") == 1;   # 扫描前：TI 指首实参或 ')'
                let open4: i64 = TI - 1;   # '(' 的 token 索引
                outs(&buf2);
                outs("(");
                if ptrv_find(onm2) == 1 {
                    outs("(unsigned char*)");
                    outs(onm2);
                } else {
                    outs("(unsigned char*)&");
                    outs(onm2);
                }
                # v1.1199: 具名实参 `name: expr`（值=单 token 数字/ident/负号数字）→ 按形参槽重排
                if empty4 == 0 && cur_k() == 1 && TK[TI + 1] == 5 && streq(&POOL + TS[TI + 1], ":") == 1 {
                    let sv4: [8] i64 = 0;
                    let hv4: [8] i64 = 0;
                    let fi5: i64 = fsg_find(&buf2);
                    while is_op(")") == 0 {
                        let an4: i64 = cur_s();
                        TI = TI + 1;
                        expect_op(":");
                        let ai5: i64 = -1;
                        if fi5 >= 0 {
                            let qq4: i64 = 0;
                            while qq4 < FSGC[fi5] {
                                if streq(FSGN[fi5 * 8 + qq4], an4) == 1 { ai5 = qq4; }
                                qq4 = qq4 + 1;
                            }
                        }
                        let neg4: i64 = 1;
                        if cur_k() == 5 && tok_c(TI) == 45 { neg4 = 0 - 1; TI = TI + 1; }
                        let v4: i64 = atoi(cur_s());
                        TI = TI + 1;
                        if ai5 >= 0 { sv4[ai5] = neg4 * v4; hv4[ai5] = 1; }
                        if is_op(",") == 1 { TI = TI + 1; }
                    }
                    TI = TI + 1;   # 吃 ')'
                    if fi5 >= 0 {
                        let qq4: i64 = 1;
                        while qq4 < FSGC[fi5] {
                            outs(",");
                            if hv4[qq4] == 1 { outi(sv4[qq4]); }
                            else { outi(FSGD[fi5 * 8 + qq4]); }
                            qq4 = qq4 + 1;
                        }
                    }
                    outs(")");
                    return 0;
                }
                if is_op(")") == 0 {
                    outs(",");
                    emit_expr();
                    while accept_op(",") == 1 { outs(","); emit_expr(); }
                }
                # v1.1199: 缺省实参补默认
                let fi4: i64 = fsg_find(&buf2);
                if fi4 >= 0 && FSGDH[fi4] > 0 {
                    let cnt4: i64 = 0;
                    let dep4: i64 = 0 - 1;   # 调用 '(' 本身不算嵌套
                    let k4: i64 = open4;
                    while k4 < TI {
                        if TK[k4] == 5 && streq(&POOL + TS[k4], ",") == 1 && dep4 == 0 { cnt4 = cnt4 + 1; }
                        if TK[k4] == 5 && streq(&POOL + TS[k4], "(") == 1 { dep4 = dep4 + 1; }
                        if TK[k4] == 5 && streq(&POOL + TS[k4], ")") == 1 { dep4 = dep4 - 1; }
                        k4 = k4 + 1;
                    }
                    let have4: i64 = cnt4 + 1;   # 显式实参数（self 之外）
                    if empty4 == 1 { have4 = 0; }
                    let slot4: i64 = have4 + 1;   # 槽 0 = self，已被 &obj 占
                    while slot4 < FSGC[fi4] {
                        outs(",");
                        if FSGK[fi4 * 8 + slot4] == 5 { outs("(long long)"); }
                        outi(FSGD[fi4 * 8 + slot4]);
                        slot4 = slot4 + 1;
                    }
                }
                TI = TI + 1;   # 吃 ')'
                outs(")");
                return 0;
            }
        }
    }
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
    # v1.1199: typed ptr（ptr T）字段访问 p.f → ((struct T_t*)p)->f。
    # 必须在 emit_primary 输出前识别（输出流无法截回）。
    if is_c_like() == 1 && cur_k() == 1 && ptrv_find(cur_s()) == 1 && peek_op(".") == 1 {
        let et: i64 = ptelm_get(cur_s());
        if et != 0 && clsv_isstruct(et) == 1 {
            let pnm: i64 = cur_s();
            TI = TI + 2;   # 吃 '.' 与字段名
            let fld: i64 = cur_s();
            outs("((struct ");
            outs(et);
            outs("_t*)");
            outs(pnm);
            outs(")->");
            outs(fld);
            TI = TI + 1;
            # v1.1199: 链式 p.i.v —— ((T*)p)->i 之后的 .v / [i] 继续走 postfix 循环
            while 1 {
                if accept_op(".") == 1 { outs("."); outs(ident()); }
                else {
                    if accept_op("[") == 1 {
                        outs("[");
                        let sv_co3: i64 = CAST_OPEN; CAST_OPEN = 0;
                        emit_expr();
                        CAST_OPEN = sv_co3;
                        expect_op("]");
                        outs("]");
                    } else { return 0; }
                }
            }
        }
    }
    # v1.1199: typed ptr i64 下标 p[i] → ((long long*)p)[i]（元素步）。
    # emit_primary 之前探测（输出流无法截回）。
    if is_c_like() == 1 && cur_k() == 1 && ptrv_find(cur_s()) == 1 && peek_op("[") == 1 {
        let et2: i64 = ptelm_get(cur_s());
        if et2 != 0 && streq(et2, "i64") == 1 {
            outs("((long long*)");
            outs(cur_s());
            outs(")[");
            TI = TI + 2;
            let sv_co4: i64 = CAST_OPEN; CAST_OPEN = 0;
            emit_expr();
            CAST_OPEN = sv_co4;
            expect_op("]");
            outs("]");
            if CAST_OPEN == 1 { outs(")"); CAST_OPEN = 0; }
            return 0;
        }
    }
    emit_primary();
    while 1 {
        if accept_op("[") == 1 {
            # v1.1199: typed ptr i64 下标 p[i] → ((long long*)p)[i]（元素步）
            if TI >= 2 && TK[TI - 2] == 1 {
                let tpi: i64 = ptelm_get(&POOL + TS[TI - 2]);
                if tpi != 0 && streq(tpi, "i64") == 1 && ptrv_find(&POOL + TS[TI - 2]) == 1 {
                    outs("((long long*)");
                    outs(&POOL + TS[TI - 2]);
                    outs(")[");
                    let sv_co4: i64 = CAST_OPEN; CAST_OPEN = 0;
                    emit_expr();
                    CAST_OPEN = sv_co4;
                    expect_op("]");
                    outs("]");
                    if CAST_OPEN == 1 { outs(")"); CAST_OPEN = 0; }
                    continue;
                }
            }
            # v1.1196: str 负下标 s[-N] → s[strlen_(s)-N]（v1.1140 语义）
            let negi: i64 = 0;
            let negv: i64 = 0;
            let lnm: i64 = 0;
            let lisv: i64 = 0;
            if TI >= 2 && TK[TI - 2] == 1 {
                lnm = TS[TI - 2];
                lisv = strv_find(&POOL + lnm);
            }
            if lisv == 1 && cur_k() == 5 && load8(&POOL + TS[TI]) == 45 {
                negi = 1;
                if TI + 1 < NT && TK[TI + 1] == 2 {
                    let pv: i64 = 0;
                    let q2: i64 = TS[TI + 1];
                    while load8(&POOL + q2) != 0 {
                        pv = pv * 10 + (load8(&POOL + q2) - 48);
                        q2 = q2 + 1;
                    }
                    negv = pv;
                } else { negi = 0; }
            }
            if negi == 1 {
                outs("[strlen_((unsigned char*)");
                outs(&POOL + lnm);
                outs(")-");
                let nb: [24] byte = 0;
                utoa(negv, &nb, 10);
                outs(&nb);
                outs("]");
                TI = TI + 2;   # 吃掉 - N
                expect_op("]");
                if CAST_OPEN == 1 {
                    outs(")");
                    CAST_OPEN = 0;
                }
                continue;
            }
            # v1.1196: 数组变量 OOB 运行时检查（v1.1080 语义：exit 1）
            let oi: i64 = 0 - 1;
            if TI >= 2 && TK[TI - 2] == 1 { oi = arr_find(&POOL + TS[TI - 2]); }
            let idxk: i64 = cur_k();
            if oi >= 0 && ARRDIM[oi] > 0 && idxk != 2 && idxk != 4 {
                let db: [24] byte = 0;
                utoa(ARRDIM[oi], &db, 10);
                outs("[mo_oob(");
                let sv_co2: i64 = CAST_OPEN;
                CAST_OPEN = 0;
                emit_expr();
                CAST_OPEN = sv_co2;
                expect_op("]");
                outs(",");
                outs(&db);
                outs(")]");
                if CAST_OPEN == 1 {
                    outs(")");
                    CAST_OPEN = 0;
                }
                continue;
            }
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
                    if cur_k() == 1 && (ptr_find(cur_s()) == 1 || fldptr_find(cur_s()) == 1) { isptr = 1; }
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
    if is_kw("fn") == 1 {
        # v1.1166: lambda 表达式（C 系后端）—— 收集 token 文本，
        # 值 = mo_lambda_N 函数地址；resolve_lambdas 在 footer 前重
        # tokenize 发声明+定义。非 C 系后端不支持。
        if is_c_like() == 0 { return err("lambda 仅在 C 系后端支持"); }
        return collect_lambda();
    }
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
var CLSFD: [250] i64 = 0;   # v1.1199: 字段默认值（-999999=无）
# v1.1199: struct 值 word 数（嵌套展开）
fn stw(si: i64) -> i64 {
    let tot: i64 = 0;
    let j: i64 = 0;
    while j < STFN[si] {
        let fi: i64 = STF[si] + j * 2;
        let fty: i64 = CLSF[fi + 1];
        if streq(fty, "ptr") == 1 || streq(fty, "str") == 1 { tot = tot + 1; }
        else { if streq(fty, "i64") == 1 || streq(fty, "byte") == 1 || streq(fty, "i32") == 1 || streq(fty, "f64") == 1 { tot = tot + 1; } else {
            let bi: i64 = st_find(fty);
            if bi >= 0 { tot = tot + stw(bi); } else { tot = tot + 1; }
        } }
        j = j + 1;
    }
    return tot;
}
# v1.1199: struct 值 ==/!= → memcmp(&a,&b,n)==0/!=0
fn try_streq() -> i64 {
    if is_c_like() == 0 { return 0; }
    if cur_k() != 1 { return 0; }
    let lty: i64 = clsv_ty(cur_s());
    if lty == 0 { return 0; }
    let li: i64 = st_find(lty);
    if li < 0 { return 0; }
    let nm: i64 = cur_s();
    let save7: i64 = TI;
    TI = TI + 1;
    if cur_k() != 5 { TI = save7; return 0; }
    let op7: i64 = &POOL + TS[TI];
    let iseq: i64 = 0;
    if streq(op7, "==") == 1 { iseq = 1; }
    if streq(op7, "!=") == 1 { iseq = 2; }
    if iseq == 0 { TI = save7; return 0; }
    TI = TI + 1;
    if cur_k() != 1 { TI = save7; return 0; }
    let rty: i64 = clsv_ty(cur_s());
    if streq(rty, lty) != 1 { TI = save7; return 0; }
    let rn: i64 = cur_s();
    TI = TI + 1;
    let w: i64 = stw(li) * 8;
    let wb: [24] byte = 0;
    utoa(w, &wb, 10);
    outs("mo_arrcmp3((void*)&");
    outs(nm);
    outs(",(void*)&");
    outs(rn);
    outs(",");
    outs(&wb);
    outs(")");
    if iseq == 1 { outs(" == 0"); } else { outs(" != 0"); }
    return 1;
}


fn emit_expr() -> i64 {
    if try_streq() == 1 { return 0; }
    if try_strcmp() == 1 { return 0; }
    return emit_prec(1);
}

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
fn clsv_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NCLSV {
        if streq(CLSV[i], nm) == 1 { return CLST[i]; }
        i = i + 1;
    }
    return 0;
}
fn clsv_add(nm: i64, ty: i64) -> i64 {
    let i: i64 = 0;
    while i < NCLSV {
        if streq(CLSV[i], nm) == 1 { CLST[i] = ty; return 0; }
        i = i + 1;
    }
    if NCLSV >= 64 { return 0; }
    CLSV[NCLSV] = stp_copy(nm);
    CLST[NCLSV] = stp_copy(ty);
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
# v1.1166: ptr 变量名表（局部 ptr + ptr 形参）—— 调用点 f(x) 走 fnptr cast
var PTRV: [2048] i64 = 0;
var NPTRV: i64 = 0;
fn ptrv_add(nm: i64) -> i64 {
    if NPTRV >= 2048 { return 0; }
    PTRV[NPTRV] = stp_copy(nm);
    NPTRV = NPTRV + 1;
    return 0;
}
fn ptrv_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NPTRV {
        if streq(PTRV[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

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
    BYTEV[NBYTEV] = stp_copy(nm);
    NBYTEV = NBYTEV + 1;
    return 0;
}

var STRV: [2048] i64 = 0;   # 已知 str 类型局部变量名（指针数组）
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
    if NSTRV >= 2048 { return 0; }
    STRV[NSTRV] = stp_copy(nm);
    NSTRV = NSTRV + 1;
    return 0;
}

fn peek_op2(s: i64, off: i64) -> i64 {
    if TI + off >= NT { return 0; }
    if TK[TI + off] != 5 { return 0; }
    if streq(&POOL + TS[TI + off], s) == 1 { return 1; }
    return 0;
}
var ARRVS: [2048] i64 = 0;
var NARRV: i64 = 0;

# v1.1199: typed ptr 元素类型表（ptr T / ptr i64）
var PTKN: [2048] i64 = 0;   # 变量名（stp_copy）
var PTELM: [2048] i64 = 0;  # 元素类型名（stp_copy）
var NPTELM: i64 = 0;
fn ptelm_set(nm: i64, ty: i64) -> i64 {
    let i: i64 = 0;
    while i < NPTELM {
        if streq(PTKN[i], nm) == 1 { PTELM[i] = stp_copy(ty); return 0; }
        i = i + 1;
    }
    if NPTELM >= 2048 { return 0; }
    PTKN[NPTELM] = stp_copy(nm);
    PTELM[NPTELM] = stp_copy(ty);
    NPTELM = NPTELM + 1;
    return 0;
}
fn ptelm_get(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NPTELM {
        if streq(PTKN[i], nm) == 1 { return PTELM[i]; }
        i = i + 1;
    }
    return 0;
}
# 名字是否为 struct 类型名（供 typed ptr 字段访问判断）
fn clsv_isstruct(t: i64) -> i64 {
    if streq(t, "i64") == 1 { return 0; }
    if streq(t, "byte") == 1 { return 0; }
    if streq(t, "f64") == 1 { return 0; }
    if streq(t, "i32") == 1 { return 0; }
    if streq(t, "bool") == 1 { return 0; }
    if streq(t, "str") == 1 { return 0; }
    return 1;
}
fn peek_op(s: i64) -> i64 {
    if TI + 1 >= NT { return 0; }
    if TK[TI + 1] != 5 { return 0; }
    if streq(&POOL + TS[TI + 1], s) == 1 { return 1; }
    return 0;
}
fn emit_prec(minp: i64) -> i64 {
    let mdone: i64 = 0;
    # v1.1205: match 表达式（语句位置外任意位置）—— 发左值后继续 prec 循环（支持 match ... + 1）
    if is_kw("match") == 1 {
        # v1.1205: 关键字门控——后继须是主体起点（数字/字符串/标识符/'('），排除 uic.mo 等把 match 用作形参名/数组名
        let nk: i64 = TK[TI + 1];
        let ismx: i64 = 0;
        if nk == 2 || nk == 3 { ismx = 1; }
        if nk == 1 { ismx = 1; }
        if nk == 5 && TK[TI + 1] >= 0 && load8(&POOL + TS[TI + 1]) == 40 { ismx = 1; }   # '('
        if ismx == 1 { emit_match(1); mdone = 1; }
    }
    # v1.1199: struct 字面量 P { x: 7; y: 2+3; } → C 复合字面量（指定初始化器）。
    # 必须在 emit_unary 前识别（IDENT '{' 模式）。
    let is_c3: i64 = is_c_like();
    if is_c3 == 1 && cur_k() == 1 && st_find(cur_s()) >= 0 && peek_op("{") == 1 {
        let sty: i64 = cur_s();
        TI = TI + 2;   # 吃 T 与 '{'
        outs("(struct ");
        outs(sty);
        outs("_t){ ");
        # v1.1199: 已列字段标记（供默认值补齐）
        let si233: i64 = st_find(sty);
        let fbase: i64 = 0 - 1;
        let fcnt: i64 = 0;
        if si233 >= 0 && si233 < 32 { fbase = STF[si233]; fcnt = STFN[si233]; }
        let seen: [16] i64 = 0;
        let sawany: i64 = 0;
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct literal"); }
            let fld: i64 = ident();
            outs(".");
            outs(fld);
            expect_op(":");
            outs(" = ");
            emit_expr();
            outs(", ");
            if fbase >= 0 {
                let fj: i64 = 0;
                while fj < fcnt && fj < 16 {
                    if streq(CLSF[fbase + fj * 2], fld) == 1 { seen[fj] = 1; sawany = 1; }
                    fj = fj + 1;
                }
            }
            if is_op(";") == 1 { TI = TI + 1; } else { break; }
        }
        expect_op("}");
        # 未列字段补默认值
        if fbase >= 0 && sawany == 1 {
            let fj2: i64 = 0;
            while fj2 < fcnt && fj2 < 16 {
                if seen[fj2] == 0 && CLSFD[fbase + fj2 * 2] != 0 - 999999 {
                    outs(".");
                    outs(CLSF[fbase + fj2 * 2]);
                    outs(" = ");
                    let nb2: [24] byte = 0;
                    utoa(CLSFD[fbase + fj2 * 2], &nb2, 10);
                    outs(&nb2);
                    outs(", ");
                }
                fj2 = fj2 + 1;
            }
        }
        outs("}");
        return 0;
    }
    if is_c3 == 1 && cur_k() == 1 {
        let onm: i64 = 0;
        if peek_op("+") == 1 { onm = "add"; }
        if peek_op("-") == 1 { onm = "sub"; }
        if peek_op("*") == 1 { onm = "mul"; }
        if peek_op("/") == 1 { onm = "div"; }
        if peek_op("==") == 1 { onm = "eq"; }
        if peek_op("!=") == 1 { onm = "ne"; }
        if peek_op("<") == 1 { onm = "lt"; }
        if peek_op(">") == 1 { onm = "gt"; }
        if peek_op("<=") == 1 { onm = "le"; }
        if peek_op(">=") == 1 { onm = "ge"; }
        if onm != 0 {
            let ty: i64 = clsv_find(cur_s());
            if ty != 0 {
                let buf: [128] byte = 0;
                strcat(&buf, ty);
                strcat(&buf, "_");
                strcat(&buf, onm);
                if fsg_find(&buf) >= 0 {
                    outs(&buf);
                    outs("(&");
                    outs(cur_s());
                    TI = TI + 2;
                    outs(", &");
                    emit_prec(20);
                    outs(")");
                    return 0;
                }
                # 无重载的 struct 比较：native 端按"未定义 → 假"处理（346 语义对齐）。
                # 跳过左 ident 与 op，右表达式用平衡跳过（不发射）。
                if peek_op("==") == 1 || peek_op("!=") == 1 || peek_op("<") == 1 || peek_op(">") == 1 || peek_op("<=") == 1 || peek_op(">=") == 1 {
                    outs("0");
                    TI = TI + 2;
                    let depth: i64 = 0;
                    while TI < NT {
                        if TK[TI] == 5 {
                            if streq(&POOL + TS[TI], "(") == 1 || streq(&POOL + TS[TI], "[") == 1 { depth = depth + 1; }
                            if streq(&POOL + TS[TI], ")") == 1 || streq(&POOL + TS[TI], "]") == 1 {
                                if depth == 0 { break; }
                                depth = depth - 1;
                            }
                            if depth == 0 && (streq(&POOL + TS[TI], ";") == 1 || streq(&POOL + TS[TI], "}") == 1 || streq(&POOL + TS[TI], "{") == 1) { break; }
                        }
                        TI = TI + 1;
                    }
                    return 0;
                }
            }
        }
    }
    # v1.1194: 数组值比较 a == b / a != b → memcmp 语义（native 逐 word 比较）
    if is_c3 == 1 && cur_k() == 1 && arr_find(cur_s()) >= 0 {
        if peek_op("==") == 1 || peek_op("!=") == 1 {
            let anm: i64 = cur_s();
            if TK[TI + 2] == 1 {
                let bnm: i64 = &POOL + TS[TI + 2];
                if arr_find(bnm) >= 0 {
                    let neq: i64 = 0;
                    if peek_op("!=") == 1 { neq = 1; }
                    TI = TI + 2;
                    outs("(mo_arrcmp(");
                    outs(anm);
                    outs(", ");
                    outs(bnm);
                    outs(")");
                    if neq == 1 { outs(" != 0)"); } else { outs(" == 0)"); }
                    TI = TI + 1;
                    return 0;
                }
            }
        }
    }
    # v1.1199: str + str → 拼接（native 走 scat_cat，C 后端此前缺 concat 发射，
    # 131_regex `s = s + "a"` gcc 硬错 ptr+ptr）。探测（左原子 + '+' + 右原子）后重放：
    # scat_cat(l, r)。仅当源码 import 了 scat.mo（fsg 有 scat_cat）时改写，
    # 与 native 一致——native 无 scat import 时同样 die。
    if is_c3 == 1 && fsg_find("scat_cat") >= 0 {
        let lstr: i64 = 0;
        if cur_k() == 3 { lstr = 1; }
        if cur_k() == 1 && strv_find(cur_s()) == 1 { lstr = 1; }
        if cur_k() == 1 && fsg_find(cur_s()) >= 0 && FSGR[fsg_find(cur_s())] == 1 { lstr = 1; }
        let nx131: i64 = TI + 1;
        if cur_k() == 1 && fsg_find(cur_s()) >= 0 && FSGR[fsg_find(cur_s())] == 1 && nx131 < NT && TK[nx131] == 5 && streq(&POOL + TS[nx131], "(") == 1 {
            # 左是函数调用：配平实参括号，取 ')' 后的 '+'
            let d131: i64 = 0;
            let j131: i64 = nx131;
            while j131 < NT {
                if TK[j131] == 5 && streq(&POOL + TS[j131], "(") == 1 { d131 = d131 + 1; }
                if TK[j131] == 5 && streq(&POOL + TS[j131], ")") == 1 {
                    d131 = d131 - 1;
                    if d131 == 0 { break; }
                }
                j131 = j131 + 1;
            }
            nx131 = j131 + 1;
        }
        if nx131 < NT && TK[nx131] == 5 && streq(&POOL + TS[nx131], "+") == 1 {
            let sv131: i64 = nx131 + 1;
            if sv131 < NT {
                let rstr: i64 = 0;
                if TK[sv131] == 3 { rstr = 1; }
                if TK[sv131] == 1 && strv_find(&POOL + TS[sv131]) == 1 { rstr = 1; }
                if rstr == 1 {
                    outs("scat_cat(");
                    emit_unary();
                    outs(", ");
                    TI = sv131;
                    emit_unary();
                    outs(")");
                    TI = sv131 + 1;
                    return 0;
                }
            }
        }
    }
    if mdone == 0 { emit_unary(); }
    while 1 {
        let p: i64 = binprec();
        # v1.1199: 三元 cond ? a : b（C 原生；右结合=右侧走完整 emit_prec(1)）
        if p == 0 && is_c_like() == 1 && is_op("?") == 1 && minp <= 1 {
            TI = TI + 1;
            outs(" ? ");
            emit_prec(1);
            outs(" : ");
            expect_op(":");
            emit_prec(1);
            return 0;
        }
        # v1.1206: as cast `expr as T` → 直通（数值语义由比较/算术 cast 兜住）
        if p == 0 && is_c_like() == 1 && cur_k() == 1 && is_kw("as") == 1 && TK[TI + 1] == 1 {
            TI = TI + 2;   # 吃 'as' 与类型名
            continue;
        }
        if p == 0 { return 0; }
        if p < minp { return 0; }
        # v1.1206: as cast `expr as T` → 直通（数值语义由比较/算术 cast 兜住）
        if is_c_like() == 1 && cur_k() == 1 && is_kw("as") == 1 && TK[TI + 1] == 1 {
            TI = TI + 2;   # 吃 'as' 与类型名
            continue;
        }
        let op: i64 = cur_s();
        TI = TI + 1;
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
        # v1.1198: `int -/+ ptr` 混合算术 → 右侧 ptr 加 (long long) 单目 cast
        if (streq(op, "-") == 1 || streq(op, "+") == 1) && cur_k() == 1 && ptrv_find(cur_s()) == 1 {
            outs("(long long)");
        }
        # v1.1198: `<<` 移位数包 & 63 —— C 移位 >=64 是 UB 且 static+O2 常量折叠
        # 会暴露 poison（147_cbfcu：1LL << (64-n) 在 n=0 时）；native x86 shl 用 cl&63，
        # 语义一致。
        if streq(op, "<<") == 1 { outs("(("); }
        emit_prec(p + 1);
        if streq(op, "<<") == 1 { outs(") & 63)"); }
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
    if streq(nm, "eprint") == 1 { r = 1; }
    if streq(nm, "eprint_i64") == 1 { r = 1; }
    if streq(nm, "eprint_nl") == 1 { r = 1; }
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
    # v1.1206: tagged enum 类型 → Shape_t（typedef 名）
    if is_c_like() == 1 && ev_struct_ty(t) == 0 && NMDBG == 42 { err("evmiss"); }
    if is_c_like() == 1 && ev_struct_ty(t) == 1 {
        outs(t);
        outs("_t");
        return 0;
    }
    # v1.1200: enum 类型名 → 标量 long long（236 enum 变量）
    if is_c_like() == 1 {
        let eth: i64 = nm_hash(t);
        let etf: i64 = 0;
        let eti: i64 = 0;
        while eti < NENMH { if ENMH[eti] == eth { etf = 1; } eti = eti + 1; }
        if etf == 1 { outs("long long"); return 0; }
        outs("struct "); outs(t); outs("_t");
    } else { outs(t); }
    return 0;
}

# C 用：输出完整声明（含数组维度与变量名）
# v1.1162: 数组长度支持任意常量表达式（[2+3]、[fact(5)]、[1<<4]…）。
# C 系后端把长度表达式**原样 emit 进 C 源**，由 C 编译器做常量折叠 ——
# 不在 mo2x 里求值（mo2x 没有常量求值器，硬造一个必然又窄又错）。
# emit_dim_to_cache：从当前 token 走到 ']'（吃掉 ']'），把中间 token 原样
# 拼进 CACHE 缓冲并返回缓存地址。**只走 token，不输出** —— 输出顺序由调用方控制
# （C 声明是 `T name[dim];`，dim 在名字后面）。
# v1.1191: 维度字符串直接写入调用者给的缓冲（避免 GDIM 全局槽覆盖问题）
fn emit_dim_to_buf(db: i64) -> i64 {
    let buf: i64 = db;
    let ci: i64 = 0;
    let save: i64 = TI;
    let has_cf: i64 = 0;
    while TI < NT {
        if is_op("]") == 1 { break; }
        if cur_k() == 1 {
            if cns_find(cur_s()) < 0 && cf_find_fn(cur_s()) >= 0 { has_cf = 1; }
        }
        TI = TI + 1;
    }
    TI = save;
    if has_cf == 1 {
        let v: i64 = cns_expr();
        ADIM = v;
        expect_op("]");
        let nb: [24] byte = 0;
        utoa(v, &nb, 10);
        let q: i64 = 0;
        while load8(&nb + q) != 0 { store8(buf + q, load8(&nb + q)); q = q + 1; }
        store8(buf + q, 0);
        return 0;
    }
    # v1.1193: 记录维度数值（若长度是常量表达式）供标量填充用
    {
        let sv2: i64 = TI;
        let dv: i64 = cns_expr();
        ADIM = dv;
        TI = sv2;
    }
    let first: i64 = 1;
    while TI < NT {
        if is_op("]") == 1 { break; }
        if cur_k() == 1 {
            if cns_find(cur_s()) < 0 {
                return err("mo2x: 数组长度表达式引用了未定义的 const 名");
            }
        }
        if first == 0 {
            store8(buf + ci, 32); ci = ci + 1;
        }
        let t: i64 = cur_s();
        let j: i64 = 0;
        while load8(t + j) != 0 { store8(buf + ci, load8(t + j)); ci = ci + 1; j = j + 1; }
        first = 0;
        TI = TI + 1;
    }
    store8(buf + ci, 0);
    expect_op("]");
    return 0;
}

fn emit_dim_to_cache() -> i64 {
    let base: i64 = &GDIM + GDIMD * 512;
    GDIMD = GDIMD + 1;
    let buf: i64 = base;
    let ci: i64 = 0;
    # 预扫描：长度表达式是否含 const fn 调用？含则整体求值输出数字。
    let save: i64 = TI;
    let has_cf: i64 = 0;
    while TI < NT {
        if is_op("]") == 1 { break; }
        if cur_k() == 1 {
            if cns_find(cur_s()) < 0 && cf_find_fn(cur_s()) >= 0 { has_cf = 1; }
        }
        TI = TI + 1;
    }
    TI = save;
    if has_cf == 1 {
        # 用 cns_expr 求整个长度表达式（支持 const fn 调用），输出十进制数字
        let v: i64 = cns_expr();
        expect_op("]");
        let nb: [24] byte = 0;
        utoa(v, &nb, 10);
        let q: i64 = 0;
        while load8(&nb + q) != 0 { store8(buf + q, load8(&nb + q)); q = q + 1; }
        store8(buf + q, 0);
        # v1.1191: 不在此处减 GDIMD —— 调用者统一配对减回（多层维度需各自占槽）
        return base;
    }
    let first: i64 = 1;
    while TI < NT {
        if is_op("]") == 1 { break; }
        if cur_k() == 1 {
            if cns_find(cur_s()) < 0 {
                return err("mo2x: 数组长度表达式引用了未定义的 const 名");
            }
        }
        if first == 0 {
            store8(buf + ci, 32); ci = ci + 1;
        }
        let t: i64 = cur_s();
        let j: i64 = 0;
        while load8(t + j) != 0 { store8(buf + ci, load8(t + j)); ci = ci + 1; j = j + 1; }
        first = 0;
        TI = TI + 1;
    }
    store8(buf + ci, 0);
    expect_op("]");
    return base;
}

fn emit_scalar_or_arr(nm: i64, isarr: i64) -> i64 {
    if isarr == 1 { arr_add(nm);
        if is_op("[") == 1 {
            # v1.1191: 先收集全部维度再输出 —— 此前递归导致维度顺序反转
            # （[2][3] 发成 [3][2]，sizeof(m) 取错外层，len() 对不上）。
            # v1.1191: 循环收集全部维度的字符串到局部表，再按序输出
            # （此前递归立即输出导致维度反转 [2][3]→[3][2]）。
            let dims: [8][64] byte = 0;
            let nd: i64 = 0;
            let q2: i64 = 0;
            while q2 < 8 {
                if is_op("[") == 0 { break; }
                TI = TI + 1;
                let db: i64 = &dims + q2 * 64;
                emit_dim_to_buf(db);
                nd = nd + 1;
                q2 = q2 + 1;
            }
            emit_scalar_or_arr(nm, 0);
            q2 = 0;
            while q2 < nd {
                outs("[");
                outs(&dims + q2 * 64);
                outs("]");
                q2 = q2 + 1;
            }
            # v1.1196: 记录最外维（OOB 运行时检查用）—— dims[0] 是数字文本
            let ai2: i64 = arr_find(nm);
            if ai2 >= 0 {
                let dv2: i64 = 0;
                let dq2: i64 = 0;
                while load8(&dims + dq2) != 0 {
                    dv2 = dv2 * 10 + (load8(&dims + dq2) - 48);
                    dq2 = dq2 + 1;
                }
                ARRDIM[ai2] = dv2;
                # v1.1202: nd>1 时记录内层维（解构行绑定 stride 用）
                if nd > 1 {
                    let dv3: i64 = 0;
                    let dq3: i64 = 0;
                    let db3: i64 = &dims + 64;
                    while load8(db3 + dq3) != 0 {
                        dv3 = dv3 * 10 + (load8(db3 + dq3) - 48);
                        dq3 = dq3 + 1;
                    }
                    ARRDIM2[ai2] = dv3;
                }
            }
            return 0;
        }
    }
    let t: i64 = ident();
    LASTTY = t;    # v1.1164: 记录基类型 —— emit_local/emit_global 的隐式 cast 依据
    emit_scalar(t);
    outs(" ");
    outs(nm);
    # v1.1199: `let a: T;`（T=struct 有默认字段）→ 默认值初始化
    if is_struct_ty(t) == 1 {
        let dsi: i64 = st_find(t);
        if dsi >= 0 && dsi < 32 {
            let dfb: i64 = STF[dsi];
            let dfn: i64 = STFN[dsi];
            let dany: i64 = 0;
            let dj: i64 = 0;
            while dj < dfn && dj < 16 {
                if CLSFD[dfb + dj * 2] != 0 - 999999 { dany = 1; }
                dj = dj + 1;
            }
            if dany == 1 {
                outs(" = (struct ");
                outs(t);
                outs("_t){ ");
                dj = 0;
                while dj < dfn && dj < 16 {
                    if CLSFD[dfb + dj * 2] != 0 - 999999 {
                        outs(".");
                        outs(CLSF[dfb + dj * 2]);
                        outs(" = ");
                        let nb3: [24] byte = 0;
                        utoa(CLSFD[dfb + dj * 2], &nb3, 10);
                        outs(&nb3);
                        outs(", ");
                    }
                    dj = dj + 1;
                }
                outs("}");
            }
        }
    }
    if streq(t, "byte") == 1 { bytev_add(nm); }
    if streq(t, "ptr") == 1 { bytev_add(nm); ptrv_add(nm);
        # v1.1199: `let p: ptr T`（typed ptr）—— 消费元素类型名并记录
        if cur_k() == 1 { consume_type(); ptelm_set(nm, LASTTY); } }
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
        # v1.1162: 长度位支持任意常量表达式。C 系直接原样 emit；
        # JS/PY 需要数值 —— 纯数字仍走 atoi，表达式情形记 0
        # （JS/PY 后端暂不支持常量表达式长度，见 docs/constexpr-arraylen.md）。
        let d: i64 = 0;
        let onlynum: i64 = 1;
        let save: i64 = TI;
        while TI < NT {
            if is_op("]") == 1 { break; }
            if cur_k() != 2 { onlynum = 0; }
            TI = TI + 1;
        }
        TI = save;
        if onlynum == 1 { d = atoi(cur_s()); TI = TI + 1; expect_op("]"); }
        else {
            # 表达式长度：token 全部跳过（C 系不经此处；JS/PY 暂不支持，d=0）
            while TI < NT { if is_op("]") == 1 { break; } TI = TI + 1; }
            expect_op("]");
        }
        let inner: i64 = consume_type();
        return d;
    }
    if cur_k() == 1 { LASTTY = cur_s(); TI = TI + 1; }
    return 0;
}

# 是否结构体类型（JS 要 new，Python 要实例化）
# v1.1206: enum 名是否为 tagged struct（EVIN 命中）
fn ev_struct_ty(t: i64) -> i64 {
    let eqi: i64 = 0;
    while eqi < NEVN { if EVIN[eqi] == 1 && streq(t, EVN[eqi]) == 1 { return 1; } eqi = eqi + 1; }
    return 0;
}

fn is_struct_ty(t: i64) -> i64 {
    if ev_struct_ty(t) == 1 { return 1; }
    if streq(t, "i64") == 1 { return 0; }
    if streq(t, "byte") == 1 { return 0; }
    if streq(t, "ptr") == 1 { return 0; }
    if streq(t, "f64") == 1 { return 0; }
    # v1.1200: enum 类型名不是 struct
    let eqi: i64 = 0;
    while eqi < NENUMN { if streq(t, ENUMN[eqi]) == 1 { return 0; } eqi = eqi + 1; }
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
    # v1.1202: `let [x, y] = a;` 以标识符开头 + 后跟 [...] = —— 会被误判成
    # 数组元素赋值。语句头是关键字（let/const/return/…）时绝不当赋值。
    if is_kw("let") == 1 || is_kw("const") == 1 || is_kw("return") == 1 || is_kw("if") == 1 || is_kw("while") == 1 || is_kw("for") == 1 || is_kw("match") == 1 || is_kw("fn") == 1 { return 0; }
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
    # v1.1199: typed ptr struct 左值 p.f = ... → ((struct T_t*)p)->f
    let lvtp: i64 = 0;
    if is_c_like() == 1 && cur_k() == 1 && ptrv_find(cur_s()) == 1 && peek_op(".") == 1 {
        lvtp = ptelm_get(cur_s());
        if lvtp != 0 && clsv_isstruct(lvtp) == 1 {
            outs("((struct ");
            outs(lvtp);
            outs("_t*)");
            outs(cur_s());
            outs(")");
            TI = TI + 1;
            expect_op(".");
            outs("->");
            outs(ident());
            while 1 {
                if accept_op(".") == 1 { outs("."); outs(ident()); }
                else { if accept_op("[") == 1 { outs("["); emit_expr(); expect_op("]"); outs("]"); } else { return 0; } }
            }
        }
    }
    outs(ident());
    while 1 {
        if accept_op("[") == 1 {
            # v1.1196: 数组变量 OOB 运行时检查（写路径；ident 已在 TS[TI-2]）
            let oi5: i64 = 0 - 1;
            if TI >= 2 && TK[TI - 2] == 1 { oi5 = arr_find(&POOL + TS[TI - 2]); }
            let idxk5: i64 = cur_k();
            if oi5 >= 0 && ARRDIM[oi5] > 0 && idxk5 != 2 && idxk5 != 4 {
                let db5: [24] byte = 0;
                utoa(ARRDIM[oi5], &db5, 10);
                outs("[mo_oob(");
                emit_expr();
                expect_op("]");
                outs(",");
                outs(&db5);
                outs(")]");
                continue;
            }
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
                    if cur_k() == 1 && (ptr_find(cur_s()) == 1 || fldptr_find(cur_s()) == 1) { isptr = 1; }
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
fn arr_add(nm: i64) -> i64 {
    if NARRV >= 2048 { return 0; }
    if arr_find(nm) >= 0 { return 0; }
    ARRVS[NARRV] = stp_copy(nm);
    NARRV = NARRV + 1;
    return 0;
}
fn arr_find(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NARRV {
        if streq(ARRVS[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}
fn emit_stmt() -> i64 {
    if try_incdec() == 1 { return 0; }
    if is_assign_start() == 1 {
        # v1.1193: 数组整体赋值 q = p; → memcpy(q, p, sizeof(q))
        let sv3: i64 = TI;
        let ln3: i64 = cur_s();
        if cur_k() == 1 && arr_find(ln3) >= 0 && peek_op("=") == 1 && TK[TI + 2] == 1 && arr_find(&POOL + TS[TI + 2]) >= 0 && peek_op2(";", 3) == 1 {
            TI = TI + 2;
            outs("memcpy(");
            outs(ln3);
            outs(", ");
            outs(&POOL + TS[TI]);
            outs(", sizeof(");
            outs(ln3);
            outs("))");
            TI = TI + 1;
            expect_op(";");
            semi();
            return 0;
        }
        TI = sv3;
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
        # v1.1199: struct 返回类型（值语义）—— 形参是指针槽，解引用一层；局部变量是值，原样
    if cur_k() == 1 && streq(cur_s(), "let") == 1 { err("probe: q0"); }
        if is_c_like() == 1 && CURRTK == 4 {
            if cur_k() == 1 && ptr_find(cur_s()) == 1 {
                outs("(*");
                outs(cur_s());
                outs(")");
                TI = TI + 1;
            } else {
                emit_expr();
            }
            expect_op(";");
            semi();
            return 0;
        }
        if is_c_like() == 1 && CURRTK == 5 {
            # v1.1203: 数组返回 —— 局部数组名退化为指针原样返回
            emit_expr();
            expect_op(";");
            semi();
            return 0;
        }
        if is_c_like() == 1 { outs("("); }
        # v1.1164: i64 返回类型的函数，return 表达式包 (long long) —— 兼容 ptr→i64 隐式返回
        if is_c_like() == 1 && CURRTK == 0 { outs("(long long)("); }
        emit_expr();
        if is_c_like() == 1 && CURRTK == 0 { outs(")"); }
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
        # v1.1194: str 判别 → strcmp 比较链（判别表达式首 token 为字面量或 str 变量）
        let swsv: i64 = TI;
        let swstr: i64 = 0;
        if TK[TI] == 3 { swstr = 1; }
        else {
            if TK[TI] == 1 && strv_find(&POOL + TS[TI]) == 1 { swstr = 1; }
        }

        if swstr == 1 { outs("{ unsigned char* switch__val = ("); }
        else { outs("{ long long switch__val = ("); }
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
                    let sv: i64 = TI;
                    if swstr == 1 {
                        outs("mo_swstrcmp(switch__val, ");
                    }
                    else {
                        outs("switch__val == (");
                    }
                    TI = lc0[k];
                    while TI < lc1[k] {
                        if TK[TI] == 3 { out_cstr(&POOL + TS[TI]); }
                        else { tok_c(TI); }
                        TI = TI + 1;
                    }
                    TI = sv;
                    if swstr == 1 { outs(") == 0"); }
                    else { outs(")"); }
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
    # v1.1199: do { ... } while (cond); —— C 原生 do-while（continue→cond 与 mo 语义一致）
    if accept_kw("do") == 1 {
        if TGT == T_PY { return err("do-while 仅 C 系后端支持"); }
        outs("do");
        blk_open();
        expect_op("{");
        emit_stmts();
        IND = IND - 1;
        outs("} while (");
        if is_kw("while") == 1 { TI = TI + 1; } else { return err("DW NEED WHILE"); }
        if is_op("(") == 1 { TI = TI + 1; } else { return err("DW NEED LP"); }
        emit_expr();
        if is_op(")") == 1 { TI = TI + 1; } else { return err("DW NEED RP"); }
        outs(")");
        if is_op(";") == 0 {
            let pb: [32] byte = 0;
            strcat(&pb, "DW k=");
            let eb: [8] byte = 0;
            utoa(cur_k(), &eb, 10);
            strcat(&pb, &eb);
            strcat(&pb, " t=");
            let nb: [32] byte = 0;
            if cur_k() == 5 { strcat(&pb, &POOL + TS[TI]); }
            strcat(&pb, "|");
            utoa(TI, &nb, 10);
            strcat(&pb, &nb);
            strcat(&pb, "/");
            utoa(NT, &nb, 10);
            strcat(&pb, &nb);
            return err(&pb);
        }
        expect_op(";");
        semi();
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
    if is_kw("match") == 1 {
        # v1.1205: match 语句统一走 emit_match(0)（数字/const/字符串模式 + 守卫 if + 语句/值臂）
        return emit_match(0);
    }

    if is_kw("let") == 1 {
        let okc: i64 = 0;
        if TK[TI + 2] == 5 && streq(&POOL + TS[TI + 2], "=") == 1 {
            let rk: i64 = TK[TI + 3];
            if rk == 2 || rk == 3 { okc = 1; }
            if rk == 1 && cf_find_fn(&POOL + TS[TI + 3]) < 0 { okc = 1; }
        }
        if okc == 1 {
        # v1.1206: RHS = Enum.Variant(...) 构造 → 推断为 tagged struct 值类型
        let evlet: i64 = 0 - 1;
        if TK[TI + 3] == 1 && TK[TI + 4] == 5 && TK[TI + 5] == 1 && TK[TI + 6] == 5 && streq(&POOL + TS[TI + 4], ".") == 1 && streq(&POOL + TS[TI + 6], "(") == 1 {
            let eh8: i64 = nm_hash(&POOL + TS[TI + 3]);
            let dq8: i64 = 0;
            while dq8 < NEVN { if EVNH[dq8] == eh8 { evlet = dq8; } dq8 = dq8 + 1; }
            if evlet >= 0 && EVIN[evlet] == 0 { evlet = 0 - 1; }
        }
        if evlet >= 0 {
            let nm8: i64 = stp_copy(&POOL + TS[TI + 1]);
            TI = TI + 3;
            outs(EVN[evlet]);
            outs("_t ");
            outs(nm8);
            outs(" = ");
            emit_expr();
            expect_op(";");
            semi();
            return 0;
        }
        # v1.1205: let 推断 let a = expr;（265）—— 无 ':' 类型。TI 在 let，TI+1=NAME，TI+2='='
        let nm: i64 = stp_copy(&POOL + TS[TI + 1]);
        TI = TI + 3;   # 吃 let、NAME、'='——TI 到 RHS（nm 取 TI+1 的名字）
        ptrv_add(nm);   # fn 值调用 f(args) 走 fnptr cast（265 f=add; f(1,x)）
        outs("long long ");
        outs(nm);
        outs(" = (");
        emit_expr();
        outs(")");
        expect_op(";");
        semi();
        return 0;
        }
    }
    if accept_kw("let") == 1 {
        # v1.1202: 数组解构 let [x, y, z] = arr;（255_destructure）
        # 也支持嵌套 [[x, y], [z, w]]（平铺索引）与 RHS 函数调用（只调用一次）。
        if is_op("[") == 1 {
            TI = TI + 1;
            # 收集名字（平铺；嵌套层只是语法糖，名字按出现顺序对应线性索引）
            let dnames: [32][64] byte = 0;
            # v1.1202: 每名字元数据 —— DN_NEST（0=标量）/ DN_G 组号 / DN_J 组内子号
            let DN_NEST: [32] i64 = 0;
            let DN_G: [32] i64 = 0;
            let DN_J: [32] i64 = 0;
            let dn: i64 = 0;
            let dg: i64 = 0;    # 当前嵌套组号
            while is_op("]") == 0 {
                if is_op("[") == 1 {
                    TI = TI + 1;
                    let dj: i64 = 0;
                    while is_op("]") == 0 {
                        if cur_k() != 1 { return err("destructure: expected identifier"); }
                        let dn2: i64 = dn;
                        if dn2 >= 32 { return err("destructure: too many names"); }
                        let sb: i64 = &dnames + dn2 * 64;
                        let sq: i64 = 0;
                        while load8(cur_s() + sq) != 0 { store8(sb + sq, load8(cur_s() + sq)); sq = sq + 1; }
                        store8(sb + sq, 0);
                        DN_NEST[dn2] = 1; DN_G[dn2] = dg; DN_J[dn2] = dj;
                        dn = dn + 1;
                        dj = dj + 1;
                        TI = TI + 1;
                        if is_op(",") == 1 { TI = TI + 1; } else { break; }
                    }
                    if is_op("]") == 1 { TI = TI + 1; }
                    dg = dg + 1;
                    if is_op(",") == 1 { TI = TI + 1; } else { break; }
                    continue;
                }
                if cur_k() != 1 { return err("destructure: expected identifier"); }
                let dn2: i64 = dn;
                if dn2 >= 32 { return err("destructure: too many names"); }
                let sb: i64 = &dnames + dn2 * 64;
                let sq: i64 = 0;
                while load8(cur_s() + sq) != 0 { store8(sb + sq, load8(cur_s() + sq)); sq = sq + 1; }
                store8(sb + sq, 0);
                DN_NEST[dn2] = 0;
                dn = dn + 1;
                TI = TI + 1;
                if is_op("]") == 1 { TI = TI + 1; }
                if is_op(",") == 1 { TI = TI + 1; } else { break; }
            }
            if is_op("]") == 1 { TI = TI + 1; }
            expect_op("=");
            # RHS：函数调用 → 存临时；数组变量 → 直接用
            let tmp: i64 = 0;
            if cur_k() == 1 && TK[TI + 1] == 5 && load8(&POOL + TS[TI + 1]) == 40 {
                LWSEQ = LWSEQ + 1;
                outs("long long* __ds");
                outi(LWSEQ);
                outs(" = (long long*)");
                emit_expr();
                outs(";");
                nl();
                tmp = LWSEQ;
            } else {
                if cur_k() != 1 { return err("destructure: right side must be an array"); }
            }
            # v1.1202: RHS 二维数组 → 行绑定（v1.1076）：long long* nm = RHS[i];
            let rowb: i64 = 0;
            let anynest: i64 = 0;
            let dchk: i64 = 0;
            while dchk < dn { if DN_NEST[dchk] == 1 { anynest = 1; } dchk = dchk + 1; }
            if tmp == 0 && anynest == 0 {
                let ri: i64 = arr_find(&POOL + TS[TI]);
                if ri >= 0 && ARRDIM2[ri] > 0 { rowb = 1; }
            }
            let di: i64 = 0;
            while di < dn {
                let sb2: i64 = &dnames + di * 64;
                # 解构名字一律 i64 标量（数组元素），不能走 emit_scalar_or_arr
                # ——它会从 token 流消费 `: T`，解构声明里没有类型。
                if rowb == 1 {
                    if is_c_like() == 1 { outs("long long *"); }
                    let wi: i64 = arr_find(sb2);
                    if wi < 0 { wi = arr_add(sb2); }
                    ARRW[wi] = 1;
                } else {
                    if is_c_like() == 1 { outs("long long "); }
                }
                outs(sb2);
                outs(" = ");
                if DN_NEST[di] == 1 {
                    # 嵌套：RHS[组][子]（二维 RHS 逐元素）
                    if is_c_like() == 1 { outs("(long long)"); }
                    outs(&POOL + TS[TI]);
                    outs("[");
                    outi(DN_G[di]);
                    outs("][");
                    outi(DN_J[di]);
                    outs("]");
                } else {
                    if tmp > 0 {
                        outs("((long long*)__ds");
                        outi(tmp);
                        outs(")[");
                        outi(di);
                        outs("]");
                    } else {
                        outs(&POOL + TS[TI]);
                        outs("[");
                        outi(di);
                        outs("]");
                    }
                }
                outs(";");
                nl();
                di = di + 1;
            }
            if tmp == 0 { TI = TI + 1; }   # 吃掉 RHS 数组名
            expect_op(";");
            semi();
            return 0;
        }
        emit_local();
        return 0;
    }
    if accept_kw("const") == 1 {
        # v1.1200: 局部 const NAME: T = expr; —— mo2x 求值（cns_expr）后发
        # C `const long long NAME = <值>;`（引用其它 const 名时直接折叠成数字，
        # 避免 C enum 声明顺序问题）。151_local_const。
        let lnm: i64 = ident();
        expect_op(":");
        ident();
        expect_op("=");
        let lv: i64 = cns_expr();
        expect_op(";");
        # 注册（后续语句引用可见）
        if NCNS < 256 {
            let dupc: i64 = cns_find(lnm);
            if dupc < 0 {
                CNSN[NCNS] = CNSPP;
                let q8: i64 = 0;
                while load8(lnm + q8) != 0 { store8(&CNSP + CNSPP, load8(lnm + q8)); CNSPP = CNSPP + 1; q8 = q8 + 1; }
                store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
                CNSV[NCNS] = lv;
                NCNS = NCNS + 1;
            }
        }
        if is_c_like() == 1 {
            outs("const long long ");
            outs(lnm);
            outs(" = ");
            outi(lv);
            outs(";");
            nl();
        }
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
    # v1.1205: 无 ':' 类型（let a = expr;）→ 按 long long 推断（265/270 简单形态）
    if is_op(":") == 0 {
        expect_op("=");
        if is_c_like() == 1 {
            outs("long long ");
            outs(nm);
            outs(" = (");
            emit_expr();
            outs(")");
        } else {
            outs("long long ");
            outs(nm);
            outs(" = (");
            emit_expr();
            outs(")");
        }
        expect_op(";");
        semi();
        return 0;
    }
    expect_op(":");
    let PTY: i64 = 0;
    if cur_k() == 1 && streq(cur_s(), "ptr") == 1 { PTY = 1; }
    if is_c_like() == 1 {
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        if isarr == 0 && is_c_like() == 1 && TK[TI] == 1 && TK[TI + 1] == 5 && TK[TI + 2] == 3 {
            # v1.1195: 局部 str 字面量 init → 可写 static 副本（07_memory：store64 进字面量）
            LWSEQ = LWSEQ + 1;
            outs("static unsigned char __mlit_");
            outi(LWSEQ);
            outs("[] = ");
            out_cstr(&POOL + TS[TI + 2]);
            outs(";");
            nl();
            TI = TI + 3;
            emit_scalar(&POOL + TS[TI - 3]);
            outs(" ");
            outs(nm);
            if streq(&POOL + TS[TI - 3], "str") == 1 { strv_add(nm); }
            if LASTTY == 0 || streq(LASTTY, "i64") == 1 { outs(" = (long long)(unsigned char*)__mlit_"); }
            else { outs(" = (unsigned char*)__mlit_"); }
            outi(LWSEQ);
            outs(";");
            nl();
            expect_op(";");
            return 0;
        }
        # v1.1203: 数组返回函数内的局部数组 → static（返回指针不悬垂，317_multi_ret）
        if is_c_like() == 1 && CURRTK == 5 && isarr == 1 {
            outs("static ");
            emit_scalar_or_arr(nm, isarr);
            outs(" = {0}");
            outs(";");
            nl();
            if accept_op("=") == 1 {
                outs("memcpy(");
                outs(nm);
                outs(", ");
                if cur_k() == 5 && streq(cur_s(), "[") == 1 {
                    outs("(long long[])");
                    outs("{");
                    emit_arrflat();
                    outs("}");
                }
                else { emit_expr(); }
                outs(", sizeof(");
                outs(nm);
                outs("))");
                expect_op(";");
                semi();
                return 0;
            }
            expect_op(";");
            semi();
            return 0;
        }
        emit_scalar_or_arr(nm, isarr);
        if isarr == 0 && PTY == 0 && LASTTY != 0 && is_struct_ty(LASTTY) == 1 { clsv_add(nm, LASTTY); }   # v1.1205-fix: 值语义 struct 才登记（ptr 声明不登记）
        if accept_op("=") == 1 {
            if isarr == 1 {
                # v1.1196: 记录最外维（OOB 运行时检查用）
                let ai4: i64 = arr_find(nm);
                if ai4 >= 0 { ARRDIM[ai4] = ADIM; }
                # v1.1203: 数组 = 函数调用（返回数组）→ 声明后 memcpy（317_multi_ret）
                if cur_k() == 1 && TK[TI + 1] == 5 && load8(&POOL + TS[TI + 1]) == 40 {
                    outs(";");
                    nl();
                    outs("memcpy(");
                    outs(nm);
                    outs(", ");
                    emit_expr();
                    outs(", sizeof(");
                    outs(nm);
                    outs("))");
                    expect_op(";");
                    semi();
                    return 0;
                }
                outs(" = {");
                if cur_k() == 2 && ADIM > 0 {
                    # v1.1193: `let a: [N] T = v;` 标量填充 —— native 语义是全部元素 = v
                    let fill: i64 = cur_s();
                    let fi: i64 = 0;
                    while fi < ADIM {
                        if fi > 0 { outs(", "); }
                        outs(fill);
                        fi = fi + 1;
                    }
                    TI = TI + 1;
                }
                else {
                if cur_k() == 3 { emit_strbytes(cur_s(), 0); TI = TI + 1; }
                else { if is_op("[") == 1 { emit_arrlit(); } else { emit_expr(); } }
                }
                outs("}");
            }
            else {
                outs(" = (");
                # v1.1164: 按声明类型补隐式 cast（ptr↔i64 互通）：
                # `let p: i64 = s+i`（右值 ptr）与 `let buf: ptr = alloc(...)`
                # （右值 i64）在 C 里都是硬错误 —— 统一补显式转换。
                # 🔴 LASTTY==0 必须跳过（streq(0,..) 解引用空指针段错误；数组声明路径不设 LASTTY）
                if LASTTY != 0 {
                    if streq(LASTTY, "ptr") == 1 || streq(LASTTY, "str") == 1 { outs("(unsigned char*)"); }
                    else {
                        if streq(LASTTY, "i64") == 1 { outs("(long long)"); }
                    }
                }          # `let p: i64 = &arr;` 在 C 系后端原本是**硬错误**：
                # 用 unsigned char* 初始化 long long 属指针→整数转换。
                # 而"这块缓冲在哪"恰恰只能通过取地址表达（virtio 描述符
                # 就要填缓冲的物理地址）。取地址赋给 i64 是正当用法，
                # 所以这里补一个显式转换，而不是让调用方去改编译选项。
                if is_op("&") == 1 { outs("(long long)"); }
                # v1.1199: `let p: T = 0;`（T=struct）→ 零初始化 {0}
                if LASTTY != 0 && is_struct_ty(LASTTY) == 1 && cur_k() == 2 && atoi(cur_s()) == 0 {
                    outs("(struct ");
                    outs(LASTTY);
                    outs("_t){0})");
                    TI = TI + 1;
                    expect_op(";");
                    semi();
                    return 0;
                }
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
        # v1.1201: 数组显式 `= v` → fill(实际值)（原 bug：fill(0) 后又 emit_expr
        # 追加 "0" → `new Array(32).fill(0)0`，自评测报告缺陷③）
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill("); if accept_op("=") == 1 { emit_expr(); } else { outs("0"); } outs(")"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if dim == 0 && accept_op("=") == 1 { outs(" = "); emit_expr(); }
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
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); clsv_add(nm, LASTTY); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
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

# v1.1203: 扁平化数组字面量（memcpy 源用 1D 复合字面量，嵌套 {} 不合法）
fn emit_arrflat() -> i64 {
    expect_op("[");
    let first: i64 = 1;
    while is_op("]") == 0 {
        if first == 0 { outs(", "); }
        first = 0;
        if is_op("[") == 1 {
            emit_arrflat();
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
        if isarr == 0 && cur_k() == 3 && is_c_like() == 1 {
            # v1.1195: 全局 str 字面量 init → 可写副本（native 字面量在 .data 可写，
            # C rodata 上 store64 会 SIGSEGV —— 07_memory）
            LWSEQ = LWSEQ + 1;
            outs("static unsigned char __mlit_");
            outi(LWSEQ);
            outs("[] = ");
            out_cstr(cur_s());
            outs(";");
            nl();
            TI = TI + 3;
            emit_scalar(&POOL + TS[TI - 3]);
            outs(" ");
            outs(nm);
            if streq(&POOL + TS[TI - 3], "str") == 1 { strv_add(nm); }
            if LASTTY == 0 || streq(LASTTY, "i64") == 1 { outs(" = (long long)(unsigned char*)__mlit_"); }
            else { outs(" = (unsigned char*)__mlit_"); }
            outi(LWSEQ);
            outs(";");
            nl();
            expect_op(";");
            return 0;
        }
        emit_scalar_or_arr(nm, isarr);
        if accept_op("=") == 1 {
            if isarr == 1 {
                # v1.1196: 记录最外维（OOB 运行时检查用）
                let ai4: i64 = arr_find(nm);
                if ai4 >= 0 { ARRDIM[ai4] = ADIM; }
                # v1.1203: 数组 = 函数调用（返回数组）→ 声明后 memcpy（317_multi_ret）
                if cur_k() == 1 && TK[TI + 1] == 5 && load8(&POOL + TS[TI + 1]) == 40 {
                    outs(";");
                    nl();
                    outs("memcpy(");
                    outs(nm);
                    outs(", ");
                    emit_expr();
                    outs(", sizeof(");
                    outs(nm);
                    outs("))");
                    expect_op(";");
                    semi();
                    return 0;
                }
                outs(" = {");
                if cur_k() == 2 && ADIM > 0 {
                    # v1.1193: `let a: [N] T = v;` 标量填充 —— native 语义是全部元素 = v
                    let fill: i64 = cur_s();
                    let fi: i64 = 0;
                    while fi < ADIM {
                        if fi > 0 { outs(", "); }
                        outs(fill);
                        fi = fi + 1;
                    }
                    TI = TI + 1;
                }
                else {
                if cur_k() == 3 { emit_strbytes(cur_s(), 0); TI = TI + 1; }
                else { if is_op("[") == 1 { emit_arrlit(); } else { emit_expr(); } }
                }
                outs("}");
            }
            else {
                outs(" = (");
                # v1.1164: 按声明类型补隐式 cast（ptr↔i64 互通）：
                # `let p: i64 = s+i`（右值 ptr）与 `let buf: ptr = alloc(...)`
                # （右值 i64）在 C 里都是硬错误 —— 统一补显式转换。
                # 🔴 LASTTY==0 必须跳过（streq(0,..) 解引用空指针段错误；数组声明路径不设 LASTTY）
                if LASTTY != 0 {
                    if streq(LASTTY, "ptr") == 1 || streq(LASTTY, "str") == 1 { outs("(unsigned char*)"); }
                    else {
                        if streq(LASTTY, "i64") == 1 { outs("(long long)"); }
                    }
                }          # `let p: i64 = &arr;` 在 C 系后端原本是**硬错误**：
                # 用 unsigned char* 初始化 long long 属指针→整数转换。
                # 而"这块缓冲在哪"恰恰只能通过取地址表达（virtio 描述符
                # 就要填缓冲的物理地址）。取地址赋给 i64 是正当用法，
                # 所以这里补一个显式转换，而不是让调用方去改编译选项。
                if is_op("&") == 1 { outs("(long long)"); }
                # v1.1199: `let p: T = 0;`（T=struct）→ 零初始化 {0}
                if LASTTY != 0 && is_struct_ty(LASTTY) == 1 && cur_k() == 2 && atoi(cur_s()) == 0 {
                    outs("(struct ");
                    outs(LASTTY);
                    outs("_t){0})");
                    TI = TI + 1;
                    expect_op(";");
                    semi();
                    return 0;
                }
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
        # v1.1201: 数组显式 `= v` → fill(实际值)（原 bug：fill(0) 后又 emit_expr
        # 追加 "0" → `new Array(32).fill(0)0`，自评测报告缺陷③）
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill("); if accept_op("=") == 1 { emit_expr(); } else { outs("0"); } outs(")"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if dim == 0 && accept_op("=") == 1 { outs(" = "); emit_expr(); }
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
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); clsv_add(nm, LASTTY); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
    }
    nl();
    expect_op(";");
    return 0;
}

var STH: [256] i64 = 0;
var NSTH: i64 = 0;
# 结构体
fn emit_struct() -> i64 {
    let nm: i64 = ident();
    if is_c_like() == 1 {
        # v1.1206: 防重发（pass0 预收集双跑）
        let shh: i64 = nm_hash(nm);
        let shq: i64 = 0;
        let shdup: i64 = 0;
        while shq < NSTH { if STH[shq] == shh { shdup = 1; } shq = shq + 1; }
        if shdup == 1 {
            # 已发过：只吃 body，不发
            skip_balanced();
            return 0;
        }
        if NSTH < 256 { STH[NSTH] = shh; NSTH = NSTH + 1; }
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
                # v1.1199: ptr 字段名入 FldPTR（链式 a.next.next → "->"）
                if streq(fty, "ptr") == 1 && NFldPTR < 128 { FldPTR[NFldPTR] = stp_copy(fn2); FldE[NFldPTR] = stp_copy(&POOL + TS[TI + 1]); NFldPTR = NFldPTR + 1; }
            }
            # v1.1199: ptr 字段声明 struct X_t*（链式 a.next->next 合法）
            if streq(fty, "ptr") == 1 && cur_k() == 1 {
                let pelm: i64 = &POOL + TS[TI + 1];
                TI = TI + 2;
                outs("struct ");
                outs(pelm);
                outs("_t* ");
                outs(fn2);
                # 数组/默认值后缀仍走原逻辑但跳过类型——直接处理 ';' 
                let fdv5: i64 = 0 - 999999;
                if accept_op("=") == 1 {
                    if cur_k() == 2 { fdv5 = atoi(cur_s()); TI = TI + 1; }
                    else { if cur_k() == 5 && tok_c(TI) == 45 { TI = TI + 1; fdv5 = 0 - atoi(cur_s()); TI = TI + 1; } }
                    if NCLSF >= 2 { CLSFD[NCLSF - 2] = fdv5; }
                    outs(" = ");
                    outi(fdv5);
                }
                outs(";");
                nl();
                expect_op(";");
                continue;
            }
            emit_scalar_or_arr(fn2, 0);
            # v1.1199: 字段默认值 x: i64 = 10;
            let fdv: i64 = 0 - 999999;
            if accept_op("=") == 1 {
                if cur_k() == 2 { fdv = atoi(cur_s()); TI = TI + 1; }
                else { return err("字段默认值仅支持数字字面量（C 后端）"); }
            }
            CLSFD[NCLSF - 2] = fdv;   # 刚记录的字段（名索引处）
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

# v1.1164: 与 libc 同名的 mo 函数 → 发射为 mo_<名>（定义与调用点一致）
fn is_libc_clash(nm: i64) -> i64 {
    if streq(nm, "strlen") == 1 { return 1; }
    if streq(nm, "strcmp") == 1 { return 1; }
    if streq(nm, "strcpy") == 1 { return 1; }
    if streq(nm, "strcat") == 1 { return 1; }
    if streq(nm, "strchr") == 1 { return 1; }
    if streq(nm, "strstr") == 1 { return 1; }
    if streq(nm, "memset") == 1 { return 1; }
    if streq(nm, "memcpy") == 1 { return 1; }
    if streq(nm, "memcmp") == 1 { return 1; }
    if streq(nm, "atoi") == 1 { return 1; }
    if streq(nm, "atol") == 1 { return 1; }
    if streq(nm, "strtol") == 1 { return 1; }
    if streq(nm, "atol") == 1 { return 1; }
    if streq(nm, "fopen") == 1 { return 1; }
    if streq(nm, "fclose") == 1 { return 1; }
    if streq(nm, "fread") == 1 { return 1; }
    if streq(nm, "fwrite") == 1 { return 1; }
    if streq(nm, "fputs") == 1 { return 1; }
    if streq(nm, "fork") == 1 { return 1; }
    if streq(nm, "raise") == 1 { return 1; }
    if streq(nm, "signal") == 1 { return 1; }
    if streq(nm, "abs") == 1 { return 1; }
    if streq(nm, "labs") == 1 { return 1; }
    if streq(nm, "memchr") == 1 { return 1; }
    if streq(nm, "memmove") == 1 { return 1; }
    # v1.1190: 补全 libc 撞名表 —— puts 撞 glibc（签名不兼容 → 链接期未定义行为/静默错码）
    if streq(nm, "puts") == 1 { return 1; }
    if streq(nm, "printf") == 1 { return 1; }
    if streq(nm, "putchar") == 1 { return 1; }
    if streq(nm, "malloc") == 1 { return 1; }
    if streq(nm, "free") == 1 { return 1; }
    if streq(nm, "calloc") == 1 { return 1; }
    if streq(nm, "realloc") == 1 { return 1; }
    if streq(nm, "exit") == 1 { return 1; }
    if streq(nm, "abort") == 1 { return 1; }
    if streq(nm, "open") == 1 { return 1; }
    if streq(nm, "read") == 1 { return 1; }
    if streq(nm, "write") == 1 { return 1; }
    if streq(nm, "close") == 1 { return 1; }
    if streq(nm, "unlink") == 1 { return 1; }
    # v1.1198: fs.mo 系撞名补全（116_mopkg rename 撞 libc）
    if streq(nm, "rename") == 1 { return 1; }
    if streq(nm, "mkdir") == 1 { return 1; }
    if streq(nm, "rmdir") == 1 { return 1; }
    if streq(nm, "chmod") == 1 { return 1; }
    if streq(nm, "remove") == 1 { return 1; }
    if streq(nm, "usleep") == 1 { return 1; }
    if streq(nm, "strlen_") == 1 { return 0; }
    return 0;
}

# v1.1164: 签名表查找（-1=未注册）
fn fsg_find(nm: i64) -> i64 {
    let hh: i64 = nm_hash(nm);
    let q: i64 = 0;
    while q < NFSG {
        if FSGH[q] == hh { return q; }
        q = q + 1;
    }
    return 0 - 1;
}

# 函数签名
fn emit_sig() -> i64 {
    NTRS = 0;   # v1.1199: 每函数清 PTRS（跨函数残留误判）
    # v1.1164: 签名表查找（0=未注册）—— 先行定义供调用点用
    let nm: i64 = ident();
    expect_op("(");
    # v1.1164: 注册签名（C 系后端），调用点据此发隐式 cast
    let reg: i64 = -1;
    if is_c_like() == 1 {
        reg = fsg_find(nm);   # v1.1199: 重复签名（声明+定义两 pass）复用同一槽
        if reg < 0 && NFSG < 256 {
            reg = NFSG;
            FSGH[reg] = nm_hash(nm);
            NFSG = NFSG + 1;
        }
        if reg >= 0 {
            FSGC[reg] = 0;
            let q: i64 = 0;
            while q < 8 { FSGK[reg * 8 + q] = 4; q = q + 1; }
        }
    }
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
            let tk: i64 = 4;
            if streq(t, "i64") == 1 { if isarr == 1 { strcat(&ps, "long long*"); } else { strcat(&ps, "long long"); } tk = 0; }
            else {
                if streq(t, "i32") == 1 { strcat(&ps, "int"); }
                else {
                if streq(t, "byte") == 1 { strcat(&ps, "unsigned char"); tk = 2; }
                else {
                    if streq(t, "ptr") == 1 { strcat(&ps, "unsigned char*"); tk = 1; ptrv_add(pn);
                        # v1.1199: `ptr T`（T=类型名）→ 消费 T（unsigned char* 槽）并记录元素类型
                        if cur_k() == 1 && is_op(",") == 0 && is_op(")") == 0 { consume_type(); ptelm_set(pn, LASTTY); } }
                    else {
                        if streq(t, "f64") == 1 { strcat(&ps, "double"); tk = 3; }
                        else {
                            # v1.1190: str 形参 = unsigned char*（值语义 8 字节槽，与 moc 一致）
                            if streq(t, "str") == 1 { strcat(&ps, "unsigned char*"); tk = 1; }
                            else {
                            # struct 形参：moc 语义是引用（self.x=… 对调用方可见）。
                            # v1.1206: tagged enum 形参 → Shape_t*（typedef，非 struct tag）
                            if ev_struct_ty(t) == 1 { strcat(&ps, t); strcat(&ps, "_t*"); }
                            else { strcat(&ps, "struct "); strcat(&ps, t); strcat(&ps, "_t*"); }
                            if NTRS < 64 { PTRS[NTRS] = stp_copy(pn); NTRS = NTRS + 1; }
                            clsv_add(pn, t);   # 方法接收者也可 .method()
                            tk = 5;   # v1.1199: struct 形参 → 调用点取址
                            }
                        }
                    }
                }
                }
            }
            if reg >= 0 && FSGC[reg] < 8 {
                FSGK[reg * 8 + FSGC[reg]] = tk;
                FSGN[reg * 8 + FSGC[reg]] = stp_copy(pn);   # v1.1199: 具名实参
                FSGC[reg] = FSGC[reg] + 1;
            }
            strcat(&ps, " ");
            strcat(&ps, pn);
            # v1.1199: 形参默认值 `= 数字` → FSGD 表，调用点缺实参补默认
            if reg >= 0 && is_op("=") == 1 {
                TI = TI + 1;
                # v1.1206: 默认值支持常量表达式（0 - 5 等）——cns_expr 求值
                let dv: i64 = cns_expr();
                FSGD[reg * 8 + FSGC[reg] - 1] = dv;
                FSGDH[reg] = FSGC[reg];   # 从该索引起全部有默认
            }
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
    let rtarr: i64 = 0;   # v1.1203: 返回数组 -> [N][M] T（退化指针语义）
    if is_op("[") == 1 {
        rtarr = 1;
        while is_op("[") == 1 { skip_brackets(); }
        if cur_k() == 1 { rt = cur_s(); TI = TI + 1; }
    } else {
    if cur_k() == 1 { rt = cur_s(); TI = TI + 1; }
    }
    if rtarr == 1 { CURRTK = 5; }
    let ismain: i64 = 0;
    if streq(nm, "main") == 1 { ismain = 1; }
    # v1.1164: 返回类型 kind —— emit return 处按需 cast
    CURRTK = 0;
    if rtarr == 1 { CURRTK = 5; }   # v1.1203: 数组返回 → 指针，return 不 cast
    else if rt != 0 {
        if streq(rt, "ptr") == 1 || streq(rt, "str") == 1 {
            CURRTK = 1;
            # v1.1199: `-> ptr T` 返回类型 —— 消费元素类型名
            if streq(rt, "ptr") == 1 && cur_k() == 1 { TI = TI + 1; }
        }
        else {
            if streq(rt, "f64") == 1 { CURRTK = 3; }
            else {
                if streq(rt, "i64") == 1 { CURRTK = 0; }
                else { CURRTK = 4; CURRTS = rt; }
            }
        }
    }
    if reg >= 0 { FSGR[reg] = CURRTK; }

    if is_c_like() == 1 {
        if rtarr == 1 { outs("long long* "); }
        else if rt != 0 {
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
                            else {
                                # v1.1206: tagged enum 返回 → Sh_t（无 struct tag）
                                if ev_struct_ty(rt) == 1 { outs(rt); outs("_t "); }
                                else { outs("struct "); outs(rt); outs("_t "); }
                            }
                        }
                    }
                }
                }
            }
        } else { outs("long long "); }
        if ismain == 1 { outs("mo_main"); }
        else {
            # v1.1164: mo 定义的 libc 同名函数改 mo_ 前缀 —— strlen 与前导宏冲突；
            # strcmp 等 windows CRT 头签名冲突（unsigned char* vs char*）。
            if is_libc_clash(nm) == 1 { outs("mo_"); }
            outs(nm);
        }
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

# v1.1163: const fn 体独立 lexer（支持标识符/数字/运算符/注释/括号/分号）
fn mini_lex(buf: i64, len: i64) -> i64 {
    let p: i64 = 0;
    let n: i64 = 0;
    NCFT = 0;
    while p < len {
        let c: i64 = load8(buf + p);
        if c == 32 || c == 9 || c == 10 || c == 13 { p = p + 1; continue; }
        if c == 35 {   # '#'
            while p < len && load8(buf + p) != 10 { p = p + 1; }
            continue;
        }
        if is_alpha(c) == 1 {
            let q: i64 = 0;
            while p < len && (is_alpha(load8(buf+p)) == 1 || is_digit_ch(load8(buf+p)) == 1) {
                store8(&LEXB + q, load8(buf + p)); p = p + 1; q = q + 1;
            }
            store8(&LEXB + q, 0);
            if n < 4096 { CFTK[n] = 1; CFTS[n] = p - q; n = n + 1; }
            continue;
        }
        if is_digit_ch(c) == 1 {
            let q: i64 = 0;
            let ishex: i64 = 0;
            if c == 48 && p + 1 < len && (load8(buf+p+1) == 120 || load8(buf+p+1) == 88) {
                ishex = 1; p = p + 2;
            }
            while p < len {
                let d: i64 = load8(buf + p);
                if ishex == 1 { if is_digit_ch(d) == 1 || (d >= 97 && d <= 102) || (d >= 65 && d <= 70) { store8(&LEXB+q, d); q = q + 1; p = p + 1; } else { break; } }
                else { if is_digit_ch(d) == 1 { store8(&LEXB+q, d); q = q + 1; p = p + 1; } else { break; } }
            }
            store8(&LEXB + q, 0);
            if n < 4096 { CFTK[n] = 2; CFTS[n] = p - q; n = n + 1; }
            continue;
        }
        if c == 34 {   # 字符串字面量（const fn 一般不用，仍支持）
            let q: i64 = 0;
            p = p + 1;
            while p < len && load8(buf+p) != 34 {
                if load8(buf+p) == 92 && p+1 < len { store8(&LEXB+q, load8(buf+p+1)); q = q + 1; p = p + 2; }
                else { store8(&LEXB+q, load8(buf+p)); q = q + 1; p = p + 1; }
            }
            p = p + 1;
            store8(&LEXB + q, 0);
            if n < 4096 { CFTK[n] = 3; CFTS[n] = p - q - 2; n = n + 1; }
            continue;
        }
        # 运算符：长优先
        let matched: i64 = 0;
        let k: i64 = 0;
        while k < NOPS {
            let oplen: i64 = strlen(OPS[k]);
            let same: i64 = 1;
            let t: i64 = 0;
            while t < oplen {
                if p + t >= len { same = 0; break; }
                if load8(buf + p + t) != load8(OPS[k] + t) { same = 0; break; }
                t = t + 1;
            }
            if same == 1 { matched = 1; break; }
            k = k + 1;
        }
        if matched == 1 {
            if n < 4096 { CFTK[n] = 5; CFTS[n] = p; n = n + 1; }
            p = p + strlen(OPS[k]);
            continue;
        }
        # 单字符运算符 / 括号 / 分号
        if n < 4096 { CFTK[n] = 5; CFTS[n] = p; n = n + 1; }
        p = p + 1;
    }
    NCFT = n;
    return n;
}

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

# v1.1162: 顶层 const 表（mo2x 此前**完全忽略** const 声明 —— token 兜底跳过，
# 于是 `var A: [N] i64` 里的 N 在 C 里未定义，编译报 use of undeclared identifier）。
# kind==1 轮收集 const 名与值；发射时 const 用 enum（真常量表达式，可用于数组长度），
# 数组长度里的 const 名替换成名字本身（enum 成员是常量表达式）。

# 编译期 const 求值（mo2x 侧）：+ - * / % << >> & | ^ 比较，const 名引用。
# 与 moc 的 const_expr 语义对齐（两级优先级 + 位运算 + 比较）。
fn cns_name_or_err(nm: i64) -> i64 {
    let i: i64 = cns_find(nm);
    if i < 0 {
        return err("mo2x: 常量表达式引用了未定义的 const 名");
    }
    return nm;
}



fn cf_cur_k() -> i64 {
    let base: i64 = CFBASE[CFNDEP - 1];
    if CFI >= CFNF[CFNDEP - 1] { return 0; }
    return CFTKP[base + CFI];
}
fn cf_cur_s() -> i64 {
    let base: i64 = CFBASE[CFNDEP - 1];
    if CFI >= CFNF[CFNDEP - 1] { return 0; }
    return &CFSRC + CFTSP[base + CFI];
}
fn cf_is_op(s: i64) -> i64 {
    if CFNDEP == 0 { return 0; }
    if cf_cur_k() != 5 { return 0; }
    return streq(cf_cur_s(), s);
}
fn cf_is_kw(s: i64) -> i64 {
    if CFNDEP == 0 { return 0; }
    return streq(cf_cur_s(), s);
}
fn cf_expect_op(s: i64) -> i64 {
    if cf_is_op(s) == 1 { CFI = CFI + 1; return 0; }
    return err("mo2x: const fn 体语法错误");
}
fn cf_ident() -> i64 {
    let s: i64 = cf_cur_s();
    CFI = CFI + 1;
    return s;
}

# 参数查找：当前帧的 CFNAME/CFVAL（帧起点 base）
fn cf_find_slot(nm: i64) -> i64 {
    let base: i64 = CFBASE[CFNDEP - 1];
    let np: i64 = CFNP[CFFI2[CFNDEP - 1]];
    let ne: i64 = base + np + CFLN[CFNDEP - 1];
    let i: i64 = base;
    while i < ne {
        if streq(CFNAME[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 999999;
}

fn cf_find_arg(nm: i64) -> i64 {
    let s: i64 = cf_find_slot(nm);
    if s >= 0 { return CFVAL[s]; }
    return 0 - 999999;
}

fn cf_call_fn(fi: i64, from_main: i64) -> i64 {
    cf_init_magics();
    let na: i64 = CFNP[fi];
    let vals: [8] i64 = 0;
    let vi: i64 = 0;
    while vi < na {
        if vi > 0 {
            if from_main == 1 { expect_op(","); } else { cf_expect_op(","); }
        }
        if from_main == 1 { vals[vi] = cns_expr(); }
        else { vals[vi] = cf_lor(); }
        vi = vi + 1;
    }
    if from_main == 1 { expect_op(")"); } else { cf_expect_op(")"); }
    if CFNDEP >= 128 { return err("mo2x: const fn 嵌套过深"); }
    let save_i: i64 = CFI;
    let save_n: i64 = NCFT;
    let base: i64 = CFNDEP * 512;
    let k: i64 = 0;
    while k < CFBL0[fi] && base + k < 8192 {
        CFTKP[base + k] = CFTK0[CFBO0[fi] + k];
        CFTSP[base + k] = CFTS0[CFBO0[fi] + k];
        k = k + 1;
    }
    CFBASE[CFNDEP] = base;
    CFNF[CFNDEP] = CFBL0[fi];
    CFFI2[CFNDEP] = fi;
    let pi: i64 = 0;
    while pi < na {
        CFNAME[base + pi] = &CNSP + CFPA[fi * 8 + pi];
        CFVAL[base + pi] = vals[pi];
        pi = pi + 1;
    }
    CFFSTART[CFNDEP] = base;
    CFLN[CFNDEP] = 0;
    CFNDEP = CFNDEP + 1;
    CFI = 0;
    NCFT = CFNF[CFNDEP - 1];
    let rv: i64 = cf_run_body();
    CFNDEP = CFNDEP - 1;
    CFI = save_i;
    NCFT = save_n;
    if rv == CFLM_R { return CFRET_V; }
    return rv;
}

fn cf_atom() -> i64 {
    if cf_is_op("(") == 1 {
        CFI = CFI + 1;
        let v: i64 = cf_lor();
        cf_expect_op(")");
        return v;
    }
    if cf_is_op("-") == 1 { CFI = CFI + 1; return 0 - cf_atom(); }
    if cf_is_op("+") == 1 { CFI = CFI + 1; return cf_atom(); }
    if cf_cur_k() == 2 {
        let v: i64 = atoi(cf_cur_s());
        CFI = CFI + 1;
        return v;
    }
    if cf_cur_k() == 1 {
        let nm: i64 = cf_cur_s();
        let av: i64 = cf_find_arg(nm);
        if av != 0 - 999999 { CFI = CFI + 1; return av; }
        let ci: i64 = cns_find(nm);
        if ci >= 0 { CFI = CFI + 1; return CNSV[ci]; }
        let fi: i64 = cf_find_fn(nm);
        if fi >= 0 {
            CFI = CFI + 1;
            cf_expect_op("(");
            return cf_call_fn(fi, 0);
        }
        return err("mo2x: const fn 表达式里引用了未知标识符");
    }
    return err("mo2x: const fn 表达式里有意外 token");
}

fn cf_term() -> i64 {
    let v: i64 = cf_atom();
    while cf_is_op("*") == 1 || cf_is_op("/") == 1 || cf_is_op("%") == 1 {
        let op: i64 = 1;
        if cf_is_op("/") == 1 { op = 2; }
        if cf_is_op("%") == 1 { op = 3; }
        CFI = CFI + 1;
        let r: i64 = cf_atom();
        if op == 1 { v = v * r; } else { if op == 2 { v = v / r; } else { v = v % r; } }
    }
    return v;
}

fn cf_expr() -> i64 {
    let v: i64 = cf_term();
    while cf_is_op("+") == 1 || cf_is_op("-") == 1 {
        let op: i64 = 1;
        if cf_is_op("-") == 1 { op = 2; }
        CFI = CFI + 1;
        let r: i64 = cf_term();
        if op == 1 { v = v + r; } else { v = v - r; }
    }
    while cf_is_op("<<") == 1 || cf_is_op(">>") == 1 {
        let op: i64 = 3;
        if cf_is_op(">>") == 1 { op = 2; }
        CFI = CFI + 1;
        let r: i64 = cf_term();
        if op == 3 { v = v << r; } else { v = v >> r; }
    }
    while cf_is_op("&") == 1 || cf_is_op("|") == 1 || cf_is_op("^") == 1 {
        let op: i64 = 1;
        if cf_is_op("|") == 1 { op = 2; }
        if cf_is_op("^") == 1 { op = 3; }
        CFI = CFI + 1;
        let r: i64 = cf_term();
        if op == 1 { v = v & r; } else { if op == 2 { v = v | r; } else { v = v ^ r; } }
    }
    while cf_is_op("==") == 1 || cf_is_op("!=") == 1 || cf_is_op("<") == 1 || cf_is_op("<=") == 1 || cf_is_op(">") == 1 || cf_is_op(">=") == 1 {
        let cop: i64 = 1;
        if cf_is_op("!=") == 1 { cop = 2; }
        if cf_is_op("<") == 1 { cop = 3; }
        if cf_is_op("<=") == 1 { cop = 4; }
        if cf_is_op(">") == 1 { cop = 5; }
        if cf_is_op(">=") == 1 { cop = 6; }
        CFI = CFI + 1;
        let r: i64 = cf_expr();
        let b: i64 = 0;
        if cop == 1 { if v == r { b = 1; } }
        if cop == 2 { if v != r { b = 1; } }
        if cop == 3 { if v < r { b = 1; } }
        if cop == 4 { if v <= r { b = 1; } }
        if cop == 5 { if v > r { b = 1; } }
        if cop == 6 { if v >= r { b = 1; } }
        v = b;
    }
    return v;
}

fn cf_lor() -> i64 {
    let v: i64 = cf_expr();
    while cf_is_op("&&") == 1 || cf_is_op("||") == 1 {
        let land: i64 = 1;
        if cf_is_op("||") == 1 { land = 2; }
        CFI = CFI + 1;
        if land == 1 {
            if v == 0 { cf_skip_and(); v = 0; }
            else { let r: i64 = cf_lor(); if r != 0 { v = 1; } else { v = 0; } }
        } else {
            if v != 0 { cf_skip_or(); v = 1; }
            else { let r: i64 = cf_lor(); if r != 0 { v = 1; } else { v = 0; } }
        }
    }
    return v;
}

fn cf_skip_expr() -> i64 {
    cf_skip_or();
    return 0;
}

fn cf_skip_or() -> i64 {
    cf_skip_and();
    while cf_is_op("||") == 1 { CFI = CFI + 1; cf_skip_and(); }
    return 0;
}

fn cf_skip_and() -> i64 {
    cf_skip_cmp();
    while cf_is_op("&&") == 1 { CFI = CFI + 1; cf_skip_cmp(); }
    return 0;
}

fn cf_skip_cmp() -> i64 {
    cf_skip_add();
    while cf_is_op("==") == 1 || cf_is_op("!=") == 1 || cf_is_op("<") == 1 || cf_is_op("<=") == 1 || cf_is_op(">") == 1 || cf_is_op(">=") == 1 {
        CFI = CFI + 1;
        cf_skip_add();
    }
    return 0;
}

fn cf_skip_add() -> i64 {
    cf_skip_mul();
    while cf_is_op("+") == 1 || cf_is_op("-") == 1 || cf_is_op("&") == 1 || cf_is_op("|") == 1 || cf_is_op("^") == 1 || cf_is_op("<<") == 1 || cf_is_op(">>") == 1 {
        CFI = CFI + 1;
        cf_skip_mul();
    }
    return 0;
}

fn cf_skip_mul() -> i64 {
    cf_skip_atom();
    while cf_is_op("*") == 1 || cf_is_op("/") == 1 || cf_is_op("%") == 1 {
        CFI = CFI + 1;
        cf_skip_atom();
    }
    return 0;
}

fn cf_skip_atom() -> i64 {
    if cf_is_op("(") == 1 {
        CFI = CFI + 1;
        cf_skip_or();
        if cf_is_op(")") == 1 { CFI = CFI + 1; }
        return 0;
    }
    if cf_is_op("-") == 1 || cf_is_op("+") == 1 { CFI = CFI + 1; cf_skip_atom(); return 0; }
    if cf_cur_k() == 1 {
        CFI = CFI + 1;
        if cf_is_op("(") == 1 {
            let dd: i64 = 1;
            CFI = CFI + 1;
            while CFI < NCFT && dd > 0 {
                if cf_is_op("(") == 1 { dd = dd + 1; }
                if cf_is_op(")") == 1 { dd = dd - 1; }
                CFI = CFI + 1;
            }
        }
        return 0;
    }
    if cf_cur_k() == 2 || cf_cur_k() == 5 { CFI = CFI + 1; return 0; }
    return 0;
}

fn cf_find_fn(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NCF {
        if streq(&CNSP + CFN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn cf_stmt() -> i64 {
    # 返回：0=无语句匹配；1=普通语句已执行；2=体结束'}'；CFLM_B/CFLM_C=break/continue
    cf_init_magics();
    if cf_is_op("}") == 1 { return 2; }
    if cf_is_kw("let") == 1 {
        CFI = CFI + 1;
        if cf_cur_k() != 1 { return err("mo2x: const fn let 语法错误"); }
        let nm: i64 = cf_cur_s();
        CFI = CFI + 1;
        cf_expect_op(":");
        if cf_cur_k() != 1 { return err("mo2x: const fn let 类型语法错误"); }
        CFI = CFI + 1;
        cf_expect_op("=");
        let v: i64 = cf_lor();
        cf_expect_op(";");
        let es: i64 = cf_find_slot(nm);
        if es >= 0 {
            CFVAL[es] = v;
            return 1;
        }
        let base: i64 = CFBASE[CFNDEP - 1];
        let np: i64 = CFNP[CFFI2[CFNDEP - 1]];
        let slot: i64 = base + np + CFLN[CFNDEP - 1];
        if slot >= 4096 { return err("mo2x: const fn 局部变量过多"); }
        CFNAME[slot] = nm;
        CFVAL[slot] = v;
        CFLN[CFNDEP - 1] = CFLN[CFNDEP - 1] + 1;
        return 1;
    }
    if cf_is_kw("while") == 1 {
        CFI = CFI + 1;
        let condstart: i64 = CFI;
        cf_lor();
        cf_expect_op("{");
        let start: i64 = CFI;
        let dd: i64 = 1;
        let wend: i64 = CFI;
        while CFI < NCFT && dd > 0 {
            if cf_is_op("{") == 1 { dd = dd + 1; }
            if cf_is_op("}") == 1 { dd = dd - 1; }
            if dd == 0 { wend = CFI; }
            if dd > 0 { CFI = CFI + 1; }
        }
        if CFWP >= 32 { return err("mo2x: const fn while 嵌套过深"); }
        CFWEND[CFWP] = wend;
        CFWP = CFWP + 1;
        let rv: i64 = 0;
        while 1 == 1 {
            CFI = condstart;
            let cond: i64 = cf_lor();
            if cond == 0 { rv = 0; break; }
            CFI = start;
            rv = cf_run_body_until(wend);
            if rv == CFLM_R { break; }
            if rv == CFLM_B { rv = 0; break; }
            if rv == CFLM_C { rv = 0; continue; }
            rv = 0;
            if CFI <= wend { CFI = wend; }
        }
        CFWP = CFWP - 1;
        CFI = wend + 1;
        if rv == CFLM_R { return CFLM_R; }
        return 1;
    }
    if cf_is_kw("break") == 1 {
        CFI = CFI + 1;
        cf_expect_op(";");
        if CFWP > 0 { CFI = CFWEND[CFWP - 1]; return CFLM_B; }
        return err("mo2x: const fn break 在循环外");
    }
    if cf_is_kw("continue") == 1 {
        CFI = CFI + 1;
        cf_expect_op(";");
        if CFWP > 0 { CFI = CFWEND[CFWP - 1]; return CFLM_C; }
        return err("mo2x: const fn continue 在循环外");
    }
    # 赋值 / 复合赋值：ident 后跟 = += -= *= /= %=
    if cf_cur_k() == 1 {
        let nm: i64 = cf_cur_s();
        if cf_find_slot(nm) >= 0 {
            CFI = CFI + 1;
            let aop: i64 = 0;
            if cf_is_op("=") == 1 { aop = 1; }
            if cf_is_op("+=") == 1 { aop = 2; }
            if cf_is_op("-=") == 1 { aop = 3; }
            if cf_is_op("*=") == 1 { aop = 4; }
            if cf_is_op("/=") == 1 { aop = 5; }
            if cf_is_op("%=") == 1 { aop = 6; }
            if aop == 0 { return err("mo2x: const fn 赋值语法错误"); }
            CFI = CFI + 1;
            let r: i64 = cf_expr();
            cf_expect_op(";");
            let slot: i64 = cf_find_slot(nm);
            if aop == 1 { CFVAL[slot] = r; }
            if aop == 2 { CFVAL[slot] = CFVAL[slot] + r; }
            if aop == 3 { CFVAL[slot] = CFVAL[slot] - r; }
            if aop == 4 { CFVAL[slot] = CFVAL[slot] * r; }
            if aop == 5 { CFVAL[slot] = CFVAL[slot] / r; }
            if aop == 6 { CFVAL[slot] = CFVAL[slot] % r; }
            return 1;
        }
    }
    return 0;
}

fn cf_run_body() -> i64 {

    let guard: i64 = 0;
    while CFI < NCFT {
        guard = guard + 1;
        if guard > 100000 { return err("mo2x: const fn 执行步数超限"); }
            if cf_is_kw("return") == 1 {
            CFI = CFI + 1;
            CFRET_V = cf_lor();
            return CFLM_R;
        }
        if cf_is_kw("if") == 1 {
            CFI = CFI + 1;
            let cond: i64 = cf_lor();
            cf_expect_op("{");
            let start: i64 = CFI;
            let dd: i64 = 1;
            let endif: i64 = CFI;
            while CFI < NCFT && dd > 0 {
                if cf_is_op("{") == 1 { dd = dd + 1; }
                if cf_is_op("}") == 1 { dd = dd - 1; }
                if dd == 0 { endif = CFI; }
                if dd > 0 { CFI = CFI + 1; }
            }
            if cond != 0 {
                CFI = start;
                let rv: i64 = cf_run_body_until(endif);
                if rv == 0 || rv == 1 || rv == 2 {
                    CFI = endif + 1;
                    if cf_is_kw("else") == 1 {
                        CFI = CFI + 1;
                        cf_expect_op("{");
                        let d3: i64 = 1;
                        while CFI < NCFT && d3 > 0 {
                            if cf_is_op("{") == 1 { d3 = d3 + 1; }
                            if cf_is_op("}") == 1 { d3 = d3 - 1; }
                            CFI = CFI + 1;
                        }
                    }
                    continue;
                }
                return rv;
            } else {
                CFI = endif + 1;
                if cf_is_kw("else") == 1 {
                    CFI = CFI + 1;
                    cf_expect_op("{");
                    let s2: i64 = CFI;
                    let d2: i64 = 1;
                    let e2: i64 = CFI;
                    while CFI < NCFT && d2 > 0 {
                        if cf_is_op("{") == 1 { d2 = d2 + 1; }
                        if cf_is_op("}") == 1 { d2 = d2 - 1; }
                        if d2 == 0 { e2 = CFI; }
                        if d2 > 0 { CFI = CFI + 1; }
                    }
                    CFI = s2;
                    let rv: i64 = cf_run_body_until(e2);
                    if rv == 0 || rv == 1 || rv == 2 { CFI = e2 + 1; continue; }
                    return rv;
                }
                continue;   # if 处理完不再走"跳到;"兜底
            }
        }
        let sr: i64 = cf_stmt();
        if sr == 1 { continue; }
        if sr == 2 { CFI = CFI + 1; break; }
        if sr != 0 { return sr; }
        while CFI < NCFT && cf_is_op(";") == 0 { CFI = CFI + 1; }
        if CFI < NCFT { CFI = CFI + 1; }
    }
    return 0;
}

fn cf_run_body_until(limit: i64) -> i64 {
    let guard: i64 = 0;
    while CFI < NCFT && CFI <= limit {
        guard = guard + 1;
        if guard > 100000 { return err("mo2x: const fn 执行步数超限"); }
        if cf_is_kw("return") == 1 {
            CFI = CFI + 1;
            CFRET_V = cf_lor();
            return CFLM_R;
        }
        if cf_is_kw("if") == 1 {
            CFI = CFI + 1;
            let cond: i64 = cf_lor();
            cf_expect_op("{");
            let start: i64 = CFI;
            let dd: i64 = 1;
            let endif: i64 = CFI;
            while CFI < NCFT && dd > 0 {
                if cf_is_op("{") == 1 { dd = dd + 1; }
                if cf_is_op("}") == 1 { dd = dd - 1; }
                if dd == 0 { endif = CFI; }
                if dd > 0 { CFI = CFI + 1; }
            }
            if cond != 0 {
                CFI = start;
                let rv: i64 = cf_run_body_until(endif);
                if rv == 0 || rv == 1 || rv == 2 {
                    CFI = endif + 1;
                    if cf_is_kw("else") == 1 {
                        CFI = CFI + 1;
                        cf_expect_op("{");
                        let d3: i64 = 1;
                        while CFI < NCFT && d3 > 0 {
                            if cf_is_op("{") == 1 { d3 = d3 + 1; }
                            if cf_is_op("}") == 1 { d3 = d3 - 1; }
                            CFI = CFI + 1;
                        }
                    }
                    continue;
                }
                return rv;
            } else {
                CFI = endif + 1;
                if cf_is_kw("else") == 1 {
                    CFI = CFI + 1;
                    cf_expect_op("{");
                    let s2: i64 = CFI;
                    let d2: i64 = 1;
                    let e2: i64 = CFI;
                    while CFI < NCFT && d2 > 0 {
                        if cf_is_op("{") == 1 { d2 = d2 + 1; }
                        if cf_is_op("}") == 1 { d2 = d2 - 1; }
                        if d2 == 0 { e2 = CFI; }
                        if d2 > 0 { CFI = CFI + 1; }
                    }
                    CFI = s2;
                    let rv: i64 = cf_run_body_until(e2);
                    if rv == 0 || rv == 1 || rv == 2 { CFI = e2 + 1; continue; }
                    return rv;
                }
                continue;
            }
        }
        let sr: i64 = cf_stmt();
        if sr == 1 { continue; }
        if sr == 2 { CFI = CFI + 1; break; }
        if sr != 0 { return sr; }
        while CFI < NCFT && cf_is_op(";") == 0 { CFI = CFI + 1; }
        if CFI < NCFT { CFI = CFI + 1; }
    }
    return 0;
}

fn collect_const_fn() -> i64 {
    TI = TI + 1;
    let nm: i64 = ident();
    expect_op("(");
    let na: i64 = 0;
    while is_op(")") == 0 {
        let pn: i64 = ident();
        if NCF < 512 && na < 8 {
            CFPA[NCF * 8 + na] = CNSPP;
            let q: i64 = 0;
            while load8(pn + q) != 0 { store8(&CNSP + CNSPP, load8(pn + q)); CNSPP = CNSPP + 1; q = q + 1; }
            store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
        }
        na = na + 1;
        expect_op(":");
        ident();
        if is_op(",") == 1 { TI = TI + 1; }
    }
    expect_op(")");
    while is_op("{") == 0 && cur_k() != 0 { TI = TI + 1; }
    expect_op("{");
    let body_start: i64 = CFTOK;
    let dd: i64 = 1;
    while dd > 0 && cur_k() != 0 {
        if is_op("{") == 1 { dd = dd + 1; }
        if is_op("}") == 1 { dd = dd - 1; }
        if dd > 0 {
            let t: i64 = cur_s();
            let q: i64 = 0;
            while load8(t + q) != 0 { store8(&CFSRC + CFBOFF, load8(t + q)); CFBOFF = CFBOFF + 1; q = q + 1; }
            store8(&CFSRC + CFBOFF, 0); CFBOFF = CFBOFF + 1;
            if CFTOK < 8192 {
                CFTK0[CFTOK] = TK[TI];
                CFTS0[CFTOK] = CFBOFF - q - 1;
                CFTOK = CFTOK + 1;
            }
        }
        if dd > 0 { TI = TI + 1; }
    }
    if NCF < 512 {
        CFN[NCF] = CNSPP;
        let q: i64 = 0;
        while load8(nm + q) != 0 { store8(&CNSP + CNSPP, load8(nm + q)); CNSPP = CNSPP + 1; q = q + 1; }
        store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
        CFNP[NCF] = na;
        CFBO0[NCF] = body_start;
        CFBL0[NCF] = CFTOK - body_start;
        NCF = NCF + 1;
    }
    if is_op("}") == 1 { TI = TI + 1; }
    return 0;
}

fn cns_atom() -> i64 {
    if is_op("(") == 1 {
        TI = TI + 1;
        let v: i64 = cns_expr();
        expect_op(")");
        return v;
    }
    if is_op("-") == 1 { TI = TI + 1; return 0 - cns_atom(); }
    if is_op("+") == 1 { TI = TI + 1; return cns_atom(); }
    # v1.1200: sizeof([N] T)/alignof([N] T) —— i64 系宽度 8
    if cur_k() == 1 && (streq(cur_s(), "sizeof") == 1 || streq(cur_s(), "alignof") == 1) {
        let isal: i64 = streq(cur_s(), "alignof");
        TI = TI + 1;
        expect_op("(");
        expect_op("[");
        let dim: i64 = atoi(cur_s());
        TI = TI + 1;
        expect_op("]");
        ident();   # 元素类型 i64/byte/...（统一按 8 字节宽；byte 数组会有偏差，暂同 moc 对齐语义）
        expect_op(")");
        if isal == 1 { return 8; }
        return dim * 8;
    }
    if cur_k() == 2 { let v: i64 = atoi(cur_s()); TI = TI + 1; return v; }
    if cur_k() == 1 {
        # v1.1200: 限定名 E.B（enum 点访问）—— 记 "E.B" 全名查表；命中吃 3 token
        if peek_op(".") == 1 {
            let ebase: i64 = cur_s();
            let sv9: i64 = TI;
            TI = TI + 2;
            if cur_k() == 1 {
                # 拼 "E.B" 到栈缓冲
                let nb9: [128] byte = 0;
                let q9: i64 = 0;
                while load8(ebase + q9) != 0 { store8(&nb9 + q9, load8(ebase + q9)); q9 = q9 + 1; }
                store8(&nb9 + q9, 46); q9 = q9 + 1;
                let mem9: i64 = cur_s();
                let q10: i64 = 0;
                while load8(mem9 + q10) != 0 { store8(&nb9 + q9, load8(mem9 + q10)); q9 = q9 + 1; q10 = q10 + 1; }
                store8(&nb9 + q9, 0);
                let i9: i64 = cns_find(&nb9);
                if i9 >= 0 { TI = TI + 1; return CNSV[i9]; }
            }
            TI = sv9;
        }
        let i: i64 = cns_find(cur_s());
        if i >= 0 { TI = TI + 1; return CNSV[i]; }
        # const fn 调用：当前 token 是函数名，后面跟 '(' —— 用解释器
        let fi: i64 = cf_find_fn(cur_s());
        if fi >= 0 {
            TI = TI + 1;
            expect_op("(");
            return cf_call_fn(fi, 1);
        }
        return err("mo2x: const 表达式引用了未定义/不可求值的标识符");
    }
    return err("mo2x: const 表达式里有意外的 token");
}

fn cns_term() -> i64 {
    let v: i64 = cns_atom();
    while is_op("*") == 1 || is_op("/") == 1 || is_op("%") == 1 {
        let op: i64 = 1;
        if is_op("/") == 1 { op = 2; }
        if is_op("%") == 1 { op = 3; }
        TI = TI + 1;
        let r: i64 = cns_atom();
        if op == 1 { v = v * r; } else { if op == 3 { v = v % r; } else { v = v / r; } }
        # % 与 / 同号语义 —— moc 的 % 是 C 语义，对齐
    }
    return v;
}

# v1.1204: uic component 展开（C 等价于 moc parse_component 展开文本）
fn emit_component(cnm: i64, nrows: i64, csep: i64, CFN: ptr, CFK: ptr, CFW: ptr, CFH: ptr, CFM: ptr, CFX: ptr, CNF: i64) -> i64 {
    # 全局存储：每字段 + buf
    let fi: i64 = 0;
    while fi < CNF {
        let fk: i64 = load64(CFK + fi * 8);
        if fk == 0 {
            outs("unsigned char ");
            outs(cnm); outs("_"); outs(load64(CFN + fi * 8)); outs("[32] = {0};"); nl();
        } else {
            outs("long long ");
            outs(cnm); outs("_"); outs(load64(CFN + fi * 8)); outs(" = 0;"); nl();
        }
        if fk == 7 {
            # spark: hist 数组 + n
            outs("long long ");
            outs(cnm); outs("_"); outs(load64(CFN + fi * 8)); outs("_hist[");
            outi(load64(CFH + fi * 8)); outs("] = {0};"); nl();
            outs("long long ");
            outs(cnm); outs("_"); outs(load64(CFN + fi * 8)); outs("_n = 0;"); nl();
        }
        fi = fi + 1;
    }
    outs("unsigned char "); outs(cnm); outs("_buf[64] = {0};"); nl();
    outs("long long "); outs(cnm); outs("_auto = 0;"); nl();
    outs("static long long "); outs(cnm); outs("_init(void);"); nl();
    # set 函数
    fi = 0;
    while fi < CNF {
        let fk: i64 = load64(CFK + fi * 8);
        let fl: i64 = load64(CFN + fi * 8);
        outs("long long "); outs(cnm); outs("_set_"); outs(fl); outs("(long long v) {"); nl();
        if fk == 0 {
            outs("long long n = strlen_(v); long long i = 0;"); nl();
            outs("while (i < n) { "); outs(cnm); outs("_"); outs(fl); outs("[i] = ((unsigned char*)v)[i]; i++; }"); nl();
            outs(cnm); outs("_"); outs(fl); outs("[n] = 0;"); nl();
        } else {
        if fk == 7 {
            # spark: 环形 hist 推进
            let hn: i64 = load64(CFH + fi * 8);
            outs("if ("); outs(cnm); outs("_"); outs(fl); outs("_n >= "); outi(hn); outs(") {"); nl();
            outs("long long k = 1;"); nl();
            outs("while (k < "); outi(hn); outs(") { "); outs(cnm); outs("_"); outs(fl); outs("_hist[k-1] = "); outs(cnm); outs("_"); outs(fl); outs("_hist[k]; k++; }"); nl();
            outs("} else {"); nl();
            outs(cnm); outs("_"); outs(fl); outs("_n++;"); nl(); outs("}"); nl();
            outs(cnm); outs("_"); outs(fl); outs("_hist["); outs(cnm); outs("_"); outs(fl); outs("_n - 1] = v;"); nl();
        } else {
        if fk == 4 {
            outs("if (v < 0) { v = 0; }"); nl();
            if load64(CFX + fi * 8) > 0 { outs("if (v > "); outi(load64(CFX + fi * 8)); outs(") { v = "); outi(load64(CFX + fi * 8)); outs("; }"); nl(); }
        }
        outs(cnm); outs("_"); outs(fl); outs(" = v;"); nl();
        }
        }
        outs("return 0; }"); nl();
        fi = fi + 1;
    }
    # row 函数
    outs("long long "); outs(cnm); outs("_row(long long x, long long y, long long fg, long long bg) {"); nl();
    outs("long long cx = x;"); nl();
    outs("if ("); outs(cnm); outs("_auto == 0) { "); outs(cnm); outs("_init(); "); outs(cnm); outs("_auto = 1; }"); nl();
    fi = 0;
    while fi < CNF {
        let fk: i64 = load64(CFK + fi * 8);
        let fl: i64 = load64(CFN + fi * 8);
        let fw: i64 = load64(CFW + fi * 8);
        outs("uc_text(cx, y, \""); outs(fl); outs("\", UC_WHITE, bg);"); nl();
        outs("cx += strlen_(\""); outs(fl); outs("\") + 1;"); nl();
        if fk == 0 {
            outs("{ long long tv = strlen_("); outs(cnm); outs("_"); outs(fl); outs(");"); nl();
            outs("if (tv > "); outi(fw); outs(") {"); nl();
            outs("{ long long tz = 0; while (tz < "); outi(fw); outs(") { "); outs(cnm); outs("_buf[tz] = "); outs(cnm); outs("_"); outs(fl); outs("[tz]; tz++; }"); nl();
            outs(cnm); outs("_buf["); outi(fw); outs("] = 0; uc_text(cx, y, "); outs(cnm); outs("_buf, UC_YELLOW, bg); }"); nl();
            outs("} else { uc_text(cx, y, "); outs(cnm); outs("_"); outs(fl); outs(", UC_YELLOW, bg); }"); nl();
            outs("{ long long p = "); outi(fw); outs(" - tv; long long j = 0;"); nl();
            outs("while (j < p) { uc_set(cx + tv + j, y, 32, fg, bg); j++; } } }"); nl();
        } else if fk == 8 {
            outs("{ unsigned char* pb = "); outs(cnm); outs("_buf; long long pz = 0;"); nl();
            outs("while (pz < 64) { "); outs(cnm); outs("_buf[pz] = 0; pz++; }"); nl();
            outs("str_itoa_base(pb, "); outs(cnm); outs("_"); outs(fl); outs(", 10);"); nl();
            outs("if (strlen_(pb) > "); outi(fw); outs(") "); outs(cnm); outs("_buf["); outi(fw); outs("] = 0;"); nl();
            outs("uc_text(cx, y, pb, UC_CYAN, bg);"); nl();
            outs("uc_set(cx + strlen_(pb), y, 37, UC_GREEN, bg); }"); nl();
        } else if fk == 4 {
            outs("{ unsigned char* gf = "); outs(cnm); outs("_buf; long long gz = 0;"); nl();
            outs("while (gz < 64) { "); outs(cnm); outs("_buf[gz] = 0; gz++; }"); nl();
            outs("str_itoa_base(gf, "); outs(cnm); outs("_"); outs(fl); outs(", 10);"); nl();
            outs("long long gl = strlen_(gf); long long gw = "); outi(fw); outs(" - gl - 1;"); nl();
            outs("long long gq = ("); outs(cnm); outs("_"); outs(fl); outs(" * 8) / 100; long long gi = 0;"); nl();
            outs("while (gi < gw) { uc_set(cx + gi, y, 9608, UC_CYAN, bg); gi++; }"); nl();
            outs("long long gj = 0;"); nl();
            outs("while (gj < gq) { if (gj < gw) uc_set(cx + gj, y, 9619, UC_YELLOW, bg); gj++; }"); nl();
            outs("uc_text(cx + gw + 1, y, gf, UC_WHITE, bg); }"); nl();
        } else if fk == 7 {
            outs("{ long long hh = "); outi(fw); outs(" - 0; long long hj = 0;"); nl();
            outs("while (hj < "); outs(cnm); outs("_"); outs(fl); outs("_n) {"); nl();
            outs("long long hv = "); outs(cnm); outs("_"); outs(fl); outs("_hist[hj];"); nl();
            outs("long long hq = (hv * "); outi(load64(CFH + fi * 8)); outs(") / 100; long long hr = 0;"); nl();
            outs("while (hr < "); outi(load64(CFH + fi * 8)); outs(") { if (hr < hq) uc_set(cx + hj, y - hr, 9608, UC_YELLOW, bg); hr++; }"); nl();
            outs("hj++; } }"); nl();
        }
        outs("cx += "); outi(fw); outs(" + 2;"); nl();
        fi = fi + 1;
    }
    outs("return 0; }"); nl();
    # grid
    outs("long long "); outs(cnm); outs("_grid(long long x, long long y, long long fg, long long bg) {"); nl();
    outs("long long gi = 0;"); nl();
    outs("while (gi < "); outi(nrows); outs(") {"); nl();
    outs(cnm); outs("_row(x, y + gi * 2, fg, bg);"); nl();
    if csep == 1 {
        outs("if (gi < "); outi(nrows - 1); outs(") {"); nl();
        outs("long long sj = 0; while (sj < 40) { uc_set(x + sj, y + gi * 2 + 1, 45, UC_WHITE, bg); sj++; } }"); nl();
    }
    outs("gi++; }"); nl();
    outs("return 0; }"); nl();
    # init
    outs("long long "); outs(cnm); outs("_init(void) { return 0; }"); nl();
    # head
    outs("long long "); outs(cnm); outs("_head(long long x, long long y, long long fg, long long bg) {"); nl();
    outs("long long cx = x;"); nl();
    fi = 0;
    while fi < CNF {
        let fl: i64 = load64(CFN + fi * 8);
        outs("uc_text(cx, y, \""); outs(fl); outs("\", UC_WHITE, bg);"); nl();
        outs("{ long long l = strlen_(\""); outs(fl); outs("\"); long long j = 0;"); nl();
        outs("while (j < 2) { uc_set(cx + l + j, y, 45, UC_WHITE, bg); j++; } }"); nl();
        outs("cx += strlen_(\""); outs(fl); outs("\") + 4;"); nl();
        fi = fi + 1;
    }
    outs("return 0; }"); nl();
    return 0;
}

fn cns_expr() -> i64 {
    let v: i64 = cns_term();
    while is_op("+") == 1 || is_op("-") == 1 {
        let op: i64 = 1;
        if is_op("-") == 1 { op = 2; }
        TI = TI + 1;
        let r: i64 = cns_term();
        if op == 1 { v = v + r; } else { v = v - r; }
    }
    while is_op("<<") == 1 || is_op(">>") == 1 {
        let op: i64 = 3;
        if is_op(">>") == 1 { op = 2; }
        TI = TI + 1;
        let r: i64 = cns_term();
        if op == 3 { v = v << r; } else { v = v >> r; }
    }
    while is_op("&") == 1 || is_op("|") == 1 || is_op("^") == 1 {
        let op: i64 = 1;
        if is_op("|") == 1 { op = 2; }
        if is_op("^") == 1 { op = 3; }
        TI = TI + 1;
        let r: i64 = cns_term();
        if op == 1 { v = v & r; } else { if op == 2 { v = v | r; } else { v = v ^ r; } }
    }
    while is_op("==") == 1 || is_op("!=") == 1 || is_op("<") == 1 || is_op("<=") == 1 || is_op(">") == 1 || is_op(">=") == 1 {
        let cop: i64 = 1;
        if is_op("!=") == 1 { cop = 2; }
        if is_op("<") == 1 { cop = 3; }
        if is_op("<=") == 1 { cop = 4; }
        if is_op(">") == 1 { cop = 5; }
        if is_op(">=") == 1 { cop = 6; }
        TI = TI + 1;
        let r: i64 = cns_expr();
        let b: i64 = 0;
        if cop == 1 { if v == r { b = 1; } }
        if cop == 2 { if v != r { b = 1; } }
        if cop == 3 { if v < r { b = 1; } }
        if cop == 4 { if v <= r { b = 1; } }
        if cop == 5 { if v > r { b = 1; } }
        if cop == 6 { if v >= r { b = 1; } }
        v = b;
    }
    return v;
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
                if accept_kw("const") == 1 {
                    # const fn —— 记录函数体文本到 CFSRC，供数组长度求值
                    if cur_k() == 1 && streq(cur_s(), "fn") == 1 {
                        collect_const_fn();
                        continue;
                    }
                    # const NAME : i64 = <expr> ; —— mo2x 只支持字面量算术（无 const fn 调用）
                    if kind == 1 {
                        let cnm: i64 = ident();
                        expect_op(":");
                        ident();          # i64
                        expect_op("=");
                        # 表达式 token 到 ';'：全数字/运算符 → 原样 emit；
                        # 含标识符（const 名引用）→ 递归暂不支持，报错；
                        # 含函数调用 → 报错（mo2x 无 const fn 求值器）。
                        let sv: i64 = TI;
                        let sv_emit: i64 = TI;
                        TI = sv;
                        let cval: i64 = 0;
                        if NCNS < 256 {
                            CNSN[NCNS] = CNSPP;
                            let snj: i64 = 0;
                            while load8(cnm + snj) != 0 { store8(&CNSP + CNSPP, load8(cnm + snj)); CNSPP = CNSPP + 1; snj = snj + 1; }
                            store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
                            # 求值：数字与 + - * / % << >> & | ^ （从左到右，先乘除后加减的近似不实现 ——
                            # 与 moc 语义差别记录在 docs；实际用 C enum 让编译器算，mo2x 只需要
                            # 知道**数组长度够不够**吗？不需要 —— C enum 直接折叠。但 CNSV
                            # 用于 JS/PY 的 new Array(dim)。所以这里仍要算 —— 实现左到右两级求值。
                            cval = cns_expr();
                            CNSV[NCNS] = cval;
                            NCNS = NCNS + 1;
                        }
                        if is_c_like() == 1 {
                            # v1.1163: 表达式含 const fn 调用时 enum 直接用**求值结果**（C enum
                            # 不允许函数调用）；纯算式仍原样 emit（保留可读性）。
                            let sv2: i64 = sv_emit;
                            TI = sv2;
                            let has_call: i64 = 0;
                            let sc: i64 = TI;
                            while TI < NT {
                                if is_op(";") == 1 { break; }
                                # 任何标识符（const 名/const fn/sizeof 等）都改用折叠值发射，
                                # 避免声明顺序（enum 在 const 之后）与未注册名错误
                                if cur_k() == 1 { has_call = 1; }
                                TI = TI + 1;
                            }
                            TI = sc;
                            outs("enum { ");
                            outs(cnm);
                            outs(" = ");
                            if has_call == 1 {
                                let nb2: [24] byte = 0;
                                utoa(cval, &nb2, 10);
                                outs(&nb2);
                                TI = sv;
                                while TI < NT { if is_op(";") == 1 { break; } TI = TI + 1; }
                            } else {
                                let first: i64 = 1;
                                while TI < NT {
                                    if is_op(";") == 1 { break; }
                                    if first == 0 { outs(" "); }
                                    if cur_k() == 1 { outs(cns_name_or_err(cur_s())); }
                                    else { outs(cur_s()); }
                                    first = 0;
                                    TI = TI + 1;
                                }
                            }
                            outs(" };");
                            nl();
                        }
                        expect_op(";");
                    } else { skip_to_semi(); }
                } else {
                if accept_kw("var") == 1 || accept_kw("let") == 1 {
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
                    if accept_kw("component") == 1 {
                        # v1.1204: uic component DSL 展开（144/145/158/159）
                        # component Name rows N sep? { fld: kind width W ...; }
                        # 只在 kind==3（函数体发射轮）展开；收集/前向轮跳过
                        if kind != 3 { skip_balanced(); continue; }
                        let cnm: i64 = ident();
                        let nrows: i64 = 0;
                        let csep: i64 = 0;
                        if accept_kw("rows") == 1 {
                            if cur_k() == 2 { nrows = atoi(cur_s()); TI = TI + 1; }
                            else { nrows = cns_expr(); }
                        }
                        if accept_kw("sep") == 1 { csep = 1; }
                        if accept_kw("title") == 1 { skip_to_semi(); }
                        expect_op("{");
                        let CFN: [16] i64 = 0;
                        let CFK: [16] i64 = 0;
                        let CFW: [16] i64 = 0;
                        let CFH: [16] i64 = 0;
                        let CFM: [16] i64 = 0;
                        let CFX: [16] i64 = 0;
                        let CNF: i64 = 0;
                        while is_op("}") == 0 {
                            let tfn: i64 = cur_s();
                            TI = TI + 1;
                            expect_op(":");
                            let tfk: i64 = 0 - 1;
                            if accept_kw("text") == 1 { tfk = 0; }
                            if accept_kw("num") == 1 { tfk = 1; }
                            if accept_kw("state") == 1 { tfk = 2; }
                            if accept_kw("bar") == 1 { tfk = 3; }
                            if accept_kw("gauge") == 1 { tfk = 4; }
                            if accept_kw("kv") == 1 { tfk = 5; }
                            if accept_kw("hex") == 1 { tfk = 6; }
                            if accept_kw("spark") == 1 { tfk = 7; }
                            if accept_kw("pct") == 1 { tfk = 8; }
                            if accept_kw("delta") == 1 { tfk = 9; }
                            if tfk == 0 - 1 { return err("component: unknown field kind"); }
                            let tfw: i64 = 10;
                            if accept_kw("width") == 1 {
                                if cur_k() == 2 { tfw = atoi(cur_s()); TI = TI + 1; }
                                else { tfw = cns_expr(); }
                            }
                            let tfh: i64 = 0;
                            if accept_kw("hist") == 1 {
                                if cur_k() == 2 { tfh = atoi(cur_s()); TI = TI + 1; }
                                else { tfh = cns_expr(); }
                            }
                            let tfm: i64 = 0;
                            let tfx: i64 = 0;
                            if accept_kw("min") == 1 {
                                if cur_k() == 2 { tfm = atoi(cur_s()); TI = TI + 1; }
                                else { tfm = cns_expr(); }
                            }
                            if accept_kw("max") == 1 {
                                if cur_k() == 2 { tfx = atoi(cur_s()); TI = TI + 1; }
                                else { tfx = cns_expr(); }
                            }
                            accept_kw("hidden");
                            if accept_kw("align") == 1 {
                                if cur_k() == 1 && (streq(cur_s(), "right") == 1 || streq(cur_s(), "left") == 1) { TI = TI + 1; }
                            }
                            CFN[CNF] = tfn; CFK[CNF] = tfk; CFW[CNF] = tfw; CFH[CNF] = tfh; CFM[CNF] = tfm; CFX[CNF] = tfx;
                            CNF = CNF + 1;
                            expect_op(";");
                        }
                        TI = TI + 1;
                        emit_component(cnm, nrows, csep, &CFN, &CFK, &CFW, &CFH, CFM, CFX, CNF);
                        continue;
                    }
                    if accept_kw("enum") == 1 {
                        # enum Name { A; B; }（或 A = expr;）—— 注册成员常量 CNSV/CNSN
                        # 并发射匿名 C enum，使 const 表达式可引用成员（143/144/145/148…）。
                        let enm: i64 = 0;
                        if cur_k() == 1 { enm = ident(); }
                        expect_op("{");
                        if kind == 9 {
                            # v1.1206: tagged decls pass —— EVIN enum 前置发 typedef
                            let ehh9: i64 = 0;
                            if enm != 0 { ehh9 = nm_hash(enm); } else { ehh9 = nm_hash(cur_s()); }
                            let evx9: i64 = 0 - 1;
                            let dq9b: i64 = 0;
                            while dq9b < NEVN { if EVNH[dq9b] == ehh9 { evx9 = dq9b; } dq9b = dq9b + 1; }
                            if evx9 >= 0 && EVIN[evx9] == 1 && EVEM[evx9] == 0 {
                                outs("typedef struct ");
                                outs(EVN[evx9]);
                                outs(" { long long tag; long long _0; long long _1; long long _2; long long _3; } ");
                                outs(EVN[evx9]);
                                outs("_t;\n");
                                EVEM[evx9] = 1;   # 后续发射轮跳过（防重发）
                            }
                            while is_op("}") == 0 { TI = TI + 1; }
                            expect_op("}");
                            continue;
                        }
                        if kind != 3 {
                            # 收集/前向轮：只注册成员常量；enum 名进 ENMH（is_struct_ty 排除用）
                            if enm != 0 {
                                let enb: [64] byte = 0;
                                let q13: i64 = 0;
                                while load8(enm + q13) != 0 { store8(&enb + q13, load8(enm + q13)); q13 = q13 + 1; }
                                store8(&enb + q13, 0);
                                if NENUMN < 64 { ENUMN[NENUMN] = stp_copy(&enb); NENUMN = NENUMN + 1; }
                            }
                            let ev0: i64 = 0;
                            # v1.1206: enum 名 → EVN/EVIN 登记（带参变体时为 tagged struct）
                            let eidx0: i64 = 0 - 1;
                            if enm != 0 {
                                let eh6: i64 = nm_hash(enm);
                                let dq6: i64 = 0;
                                while dq6 < NEVN { if EVNH[dq6] == eh6 { eidx0 = dq6; } dq6 = dq6 + 1; }
                                if eidx0 < 0 && NEVN < 64 { EVN[NEVN] = stp_copy(enm); EVNH[NEVN] = eh6; EVCN[NEVN] = 0; EVIN[NEVN] = 0; eidx0 = NEVN; NEVN = NEVN + 1; }
                            }
                            while is_op("}") == 0 {
                                let menm0: i64 = cur_s();
                                TI = TI + 1;
                                # v1.1206: 带参变体 Name(T1, T2);
                                if is_op("(") == 1 {
                                    TI = TI + 1;
                                    let fc6: i64 = 0;
                                    let vdup6: i64 = 0 - 1;
                                    if eidx0 >= 0 {
                                        let vq7: i64 = 0;
                                        while vq7 < EVCN[eidx0] { if streq(EVTN[eidx0 * 8 + vq7], menm0) == 1 { vdup6 = vq7; } vq7 = vq7 + 1; }
                                    }
                                    if vdup6 < 0 && eidx0 >= 0 && EVCN[eidx0] < 8 {
                                        let vv6: i64 = EVCN[eidx0];
                                        EVTN[eidx0 * 8 + vv6] = stp_copy(menm0);
                                        while is_op(")") == 0 {
                                            # 字段类型：跳过数组维，取类型名
                                            let fk6: i64 = 0;
                                            while is_op("[") == 1 { skip_brackets(); }
                                            let tn6: i64 = 0;
                                            if cur_k() == 1 {
                                                tn6 = cur_s(); TI = TI + 1;
                                                if streq(tn6, "i64") == 1 || streq(tn6, "i32") == 1 || streq(tn6, "u64") == 1 { fk6 = 0; }
                                                else { if streq(tn6, "f64") == 1 { fk6 = 3; } else { if streq(tn6, "byte") == 1 || streq(tn6, "u8") == 1 { fk6 = 2; } else { fk6 = 1; } } }
                                            }
                                            if eidx0 >= 0 && fc6 < 4 { EVFK[eidx0 * 32 + vv6 * 4 + fc6] = fk6; }
                                            fc6 = fc6 + 1;
                                            if is_op(",") == 1 { TI = TI + 1; }
                                        }
                                        expect_op(")");
                                        EVFC[eidx0 * 8 + vv6] = fc6;
                                        EVIN[eidx0] = 1;
                                        EVCN[eidx0] = vv6 + 1;
                                    } else {
                                        while is_op(")") == 0 { TI = TI + 1; }
                                        expect_op(")");
                                    }
                                    accept_op(";");
                                    continue;
                                }
                                let mev0: i64 = ev0;
                                if accept_op("=") == 1 { mev0 = cns_expr(); }
                                if NCNS < 256 {
                                    CNSN[NCNS] = CNSPP;
                                    let q7: i64 = 0;
                                    while load8(menm0 + q7) != 0 { store8(&CNSP + CNSPP, load8(menm0 + q7)); CNSPP = CNSPP + 1; q7 = q7 + 1; }
                                    store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
                                    CNSV[NCNS] = mev0;
                                    NCNS = NCNS + 1;
                                    # 限定名 "Name.member" 也注册（E.B 点访问）
                                    if enm != 0 && NCNS < 256 {
                                        CNSN[NCNS] = CNSPP;
                                        let q11: i64 = 0;
                                        while load8(enm + q11) != 0 { store8(&CNSP + CNSPP, load8(enm + q11)); CNSPP = CNSPP + 1; q11 = q11 + 1; }
                                        store8(&CNSP + CNSPP, 46); CNSPP = CNSPP + 1;
                                        let q12: i64 = 0;
                                        while load8(menm0 + q12) != 0 { store8(&CNSP + CNSPP, load8(menm0 + q12)); CNSPP = CNSPP + 1; q12 = q12 + 1; }
                                        store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
                                        CNSV[NCNS] = mev0;
                                        NCNS = NCNS + 1;
                                    }
                                }
                                ev0 = mev0 + 1;
                                accept_op(";");
                            }
                            expect_op("}");
                            continue;
                        }
                        # 去 重：枚举成员是 C 全局标识符，多次发射=重定义错
                        let ehh: i64 = 0;
                        if enm != 0 { ehh = nm_hash(enm); } else { ehh = nm_hash(cur_s()); }
                        let edup: i64 = 0;
                        let dq9: i64 = 0;
                        while dq9 < NENMH { if ENMH[dq9] == ehh { edup = 1; } dq9 = dq9 + 1; }
                        if edup == 0 {
                        if NENMH < 64 { ENMH[NENMH] = ehh; NENMH = NENMH + 1; }
                        # v1.1206: 含带参变体 → 发 tagged struct（成员 _0.._3 全变体共享槽）
                        let evx: i64 = 0 - 1;
                        let dqx: i64 = 0;
                        while dqx < NEVN { if EVNH[dqx] == ehh { evx = dqx; } dqx = dqx + 1; }
                        if evx >= 0 && EVIN[evx] == 1 && EVEM[evx] == 0 {
                            # 跳过变体 body（到配平 '}'）
                            while is_op("}") == 0 { TI = TI + 1; }   # 吃掉变体 body（enum body 无嵌套 '{'）
                            expect_op("}");
                            outs("typedef struct ");
                            outs(EVN[evx]);
                            outs(" { long long tag; ");
                            let fkx: i64 = 0;
                            while fkx < 4 {
                                outs("long long _"); outi(fkx); outs("; ");
                                fkx = fkx + 1;
                            }
                            outs("} ");
                            outs(EVN[evx]);
                            outs("_t;\n");
                            EVEM[evx] = 1;   # v1.1206: 防重发
                            continue;
                        }
                        if evx >= 0 && EVIN[evx] == 1 {
                            while is_op("}") == 0 { TI = TI + 1; }
                            expect_op("}");
                            continue;   # 已发 tagged struct（防重发）
                        }
                        outs("enum { ");
                        let ev: i64 = 0;
                        let ef: i64 = 1;
                        while is_op("}") == 0 {
                            if ef == 0 { outs(", "); }
                            ef = 0;
                            let menm: i64 = cur_s();
                            outs(menm);
                            TI = TI + 1;
                            let mev: i64 = ev;
                            if accept_op("=") == 1 { mev = cns_expr(); }
                            outs(" = ");
                            outi(mev);
                            # 注册到 const 表（NCNS>=256 时静默跳过注册，只发射）
                            if NCNS < 256 {
                                CNSN[NCNS] = CNSPP;
                                let q6: i64 = 0;
                                while load8(menm + q6) != 0 { store8(&CNSP + CNSPP, load8(menm + q6)); CNSPP = CNSPP + 1; q6 = q6 + 1; }
                                store8(&CNSP + CNSPP, 0); CNSPP = CNSPP + 1;
                                CNSV[NCNS] = mev;
                                NCNS = NCNS + 1;
                            }
                            ev = mev + 1;
                            accept_op(";");
                        }
                        expect_op("}");
                        outs(" };");
                        nl();
                        }
                        continue;
                    }
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
                                outs("static ");
                                emit_sig();
                                outs(";");
                                nl();
                            } }
                            if is_gen() == 0 { skip_balanced(); }
                        } else {
                            if kind == 3 {
                                if is_gen() == 1 { g_sig(); g_block(); } else {
                                    # v1.1198: 跨文件重复函数定义 → 只发第一个（native 链接器宽容；C 重定义硬错）
                                    let duph: i64 = nm_hash(cur_s());
                                    let dupf: i64 = 0;
                                    let dq3: i64 = 0;
                                    while dq3 < NEMITF { if EMITFH[dq3] == duph { dupf = 1; } dq3 = dq3 + 1; }
                                    if dupf == 0 {
                                        if NEMITF < 256 { EMITFH[NEMITF] = duph; NEMITF = NEMITF + 1; }
                                        # v1.1198: PTRV/ARRV 是作用域表 —— 不清会跨函数/文件误命中
                                        #（str.mo 的 i64 局部 m 命中陈旧 ptr 名 m → 假 cast + 池偏移崩溃）
                                        if is_c_like() == 1 { outs("static "); }
                                        emit_sig(); emit_block_body();
                                    } else { skip_balanced(); }
                                }
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
    # v1.1171: 补 strcpy/strcat 原名符号（同上：宏挡不住 IR 层引用；且
    # skip_clash 让这些调用不再发 mo_ 前缀）
    line("static unsigned char* strcpy(unsigned char* d, unsigned char* s){ long i=0; while(s[i]){ d[i]=s[i]; i++; } d[i]=0; return d; }");
    line("static unsigned char* strcat_(unsigned char* d, unsigned char* s){ long i=0,j=0; while(d[i]) i++; while(s[j]){ d[i+j]=s[j]; j++; } d[i+j]=0; return d; }");
    # v1.1176: panic 内建对齐（moc v1.1175）—— syscall write(2) + exit(1)
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
    # v1.1194: str switch 比较用 mo 前缀，避免与 str.mo 的 strcmp 冲突
    line("static long long mo_swstrcmp(const unsigned char* a, const unsigned char* b){ long long i=0; while(a[i] && a[i]==b[i]) i++; return (long long)(unsigned char)a[i] - (long long)(unsigned char)b[i]; }");
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
        line("static void panic(const unsigned char* m){ long mn=0; while(m[mn]) mn++; mo_syscall(MO_WRITE_, 2, (long)m, mn, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); }");
        line("static long long mo_oob(long long i, long long n){ if(i<0){ i+=n; } if(i<0||i>=n){ mo_syscall(MO_WRITE_, 2, (long)\"index out of bounds\\n\", 19, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); } return i; }");
            line("static void assert_(long c, const unsigned char* m){ if(c) return; long mn=0; while(m[mn]) mn++; mo_syscall(MO_WRITE_, 2, (long)m, mn, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); }");
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
        line("static void assert_(long c, const unsigned char* m){ if(c) return; long mn=0; while(m[mn]) mn++; mo_syscall(MO_WRITE_, 2, (long)m, mn, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); }");
        line("static void panic(const unsigned char* m){ long mn=0; while(m[mn]) mn++; mo_syscall(MO_WRITE_, 2, (long)m, mn, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); }");
        line("static long long mo_oob(long long i, long long n){ if(i<0){ i+=n; } if(i<0||i>=n){ mo_syscall(MO_WRITE_, 2, (long)\"index out of bounds\\n\", 19, 0, 0, 0); mo_syscall(MO_EXIT_, 1, 0, 0, 0, 0, 0); } return i; }");
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
    if TGT == T_C { return n; }            # c 目标：mo_syscall 走 libc，号透传
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
    line("static void eprint(const unsigned char* s){ vga_print((const char*)s); }");
    line("static void eprint_nl(void){ vga_putc('\\n'); }");
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
    line("static unsigned char* mo_slice(unsigned char* p, long long a, long long b){ long long n=b-a; if(n<0) n=0; unsigned char* q=(unsigned char*)malloc((size_t)(n+1)); long long i=0; while(i<n){ q[i]=p[a+i]; i++; } q[n]=0; return q; }");
    line("#define strlen strlen_");
    line("static unsigned char* strcpy_(unsigned char* d, unsigned char* s){ long i=0; while(s[i]){ d[i]=s[i]; i++; } d[i]=0; return d; }");
    line("#define strcpy strcpy_");
    line("static unsigned char* strcat_(unsigned char* d, unsigned char* s){ long i=0,j=0; while(d[i]) i++; while(s[j]){ d[i+j]=s[j]; j++; } d[i+j]=0; return d; }");
    line("#define strcat strcat_");
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
    line("static void eprint(const unsigned char* s){ uart_print((const char*)s); }");
    line("static void eprint_nl(void){ uart_putc('\\n'); }");
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
    # 🔴 v1.1161: 一律用 long long —— Windows x86_64 是 LLP64，long 只有 32 位。
    # 用 long 的 load64/store64 在 Windows 上读写 4 字节（内存踩坏），
    # call0..3 把 64 位函数指针截断成 32 位（直接崩）。
    line("#define load64(p)  (*(long long*)(p))");
    line("#define store8(p,v)  (*(unsigned char*)(p) = (unsigned char)(v))");
    line("#define store64(p,v) (*(long long*)(p) = (long long)(v))");
    line("static long long atomic_cas(long long* p, long long e, long long d){ long long old_=e; long long ok_=__atomic_compare_exchange_n(p,&old_,d,0,5,5); return ok_?1:0; }");
    line("static long long call2(long long f, long long a, long long b){ long long (*g)(long long,long long)=(long long(*)(long long,long long))f; return g(a,b); }");
    line("static long long call0(long long f){ long long (*g)(void)=(long long(*)(void))f; return g(); }");
    line("static long long call1(long long f, long long a){ long long (*g)(long long)=(long long(*)(long long))f; return g(a); }");
    line("static long long call3(long long f, long long a, long long b, long long c){ long long (*g)(long long,long long,long long)=(long long(*)(long long,long long,long long))f; return g(a,b,c); }");
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
    line("static void eprint(const unsigned char* s){ long n=0; while(s[n]) n++; mo_syscall(MO_WRITE_,2,(long)s,n,0,0,0); }");
    line("static void eprint_nl(void){ mo_syscall(MO_WRITE_,2,(long)&MO_NL_,1,0,0,0); }");
    line("static void eprint_i64(long v){");
    line("  unsigned char b[24]; int i=0; unsigned long u; int neg=0;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(unsigned char)('0'+(u%10)); u/=10; }");
    line("  if(neg) b[i++]='-';");
    line("  while(i){ unsigned char c=b[--i]; mo_syscall(MO_WRITE_,2,(long)&c,1,0,0,0); }");
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
    line("static void eprint(const unsigned char* s){ uefi_puts((const char*)s); }");
    line("static void eprint_nl(void){ uefi_puts(\"\\r\\n\"); }");
    line("static void eprint_i64(long v){");
    line("  char b[24]; int i=0; unsigned long u; int neg=0;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(char)('0'+(u%10)); u/=10; }");
    line("  if(neg) b[i++]='-';");
    line("  char o[24]; int j=0; while(i) o[j++]=b[--i]; o[j]=0;");
    line("  uefi_puts(o);");
    line("}");
    line("static void print_i64(long v){");
    line("  char b[24]; int i=0; unsigned long u; int neg=0;");
    line("  if(v<0){ neg=1; u=(unsigned long)(-(long)v); } else u=(unsigned long)v;");
    line("  if(u==0) b[i++]='0';");
    line("  while(u){ b[i++]=(char)('0'+(u%10)); u/=10; }");
    line("  if(neg) b[i++]='-';");
    line("  char o[24]; int j=0; while(i) o[j++]=b[--i]; o[j]=0;");
    line("  uefi_puts(o);");
    line("}");
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
        line("#include <stdlib.h>");
        # syscall 支持按平台条件编译：
        # 无条件 include <sys/syscall.h> 会让 Windows / WASI 直接编译失败
        # （那两个平台根本没有这个头）；而只在 NEED_SYS 时发出又会漏掉
        # —— NEED_SYS 是扫描源码后才置位的，header 写得更早。
        # 所以用预处理器判断，两端都留一份定义。
        line("#if defined(__linux__) && !defined(__wasi__)");
        line("#include <errno.h>");
        # mo 程序全局常量可能撞 errno.h 宏（EAGAIN 等）—— include 后 undef 高频撞名
        line("#undef EAGAIN");
        line("#undef EWOULDBLOCK");
        line("#undef EINTR");
        line("#undef EBADF");
        line("#undef EINVAL");
        line("#undef ENOMEM");
        line("#undef EACCES");
        line("#undef EPIPE");
        line("#undef ECONNRESET");
        line("#undef EPERM");
        line("#undef EEXIST");
        line("#undef ENOENT");
        line("#undef EISDIR");
        line("#undef ENOTDIR");
        line("#undef EMFILE");
        line("#include <sys/syscall.h>");
        line("static long long mo_syscall(long long n,long long a,long long b,long long c,long long d,long long e,long long f){");
        # v1.1200: glibc syscall() 出错返回 -1+errno；mo 原语语义=负 errno（moc 内联汇编版）。
        # 对齐：失败时返回 -errno（118 futex 断言 -EAGAIN=-11 依赖此语义）。
        line("  long long r = syscall(n,a,b,c,d,e,f);");
        line("  if (r == -1 && errno != 0) return -errno;");
        line("  return r;");
        line("}");
        line("#else");
        line("/* 该平台没有 syscall()：WASI / Windows 走这里。");
        line("   返回 -1 而不是静默成功 —— 用了 syscall 的程序应当看得出来。 */");
        line("static long long mo_syscall(long long n,long long a,long long b,long long c,long long d,long long e,long long f){");
        line("  (void)n;(void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return -1; }");
        line("#endif");
        line("static long long strlen_(unsigned char* s){ long long n=0; while(s[n]) n++; return n; }");
        line("static unsigned char* mo_slice(unsigned char* p, long long a, long long b){ long long n=b-a; if(n<0) n=0; unsigned char* q=(unsigned char*)malloc((size_t)(n+1)); long long i=0; while(i<n){ q[i]=p[a+i]; i++; } q[n]=0; return q; }");
        
        # v1.1190: fbits/ffrombits 前导补齐（fs_header 有但普通 C 目标漏 —— 127_str 经 assert.mo 用 fbits 链接失败）
        line("static long long mo_swstrcmp(const unsigned char* a, const unsigned char* b){ long long i=0; while(a[i] && a[i]==b[i]) i++; return (long long)(unsigned char)a[i] - (long long)(unsigned char)b[i]; }");
        line("static long long mo_arrcmp3(const void* a, const void* b, unsigned long n){ const unsigned char* x=a; const unsigned char* y=b; unsigned long i=0; while(i<n){ if(x[i]!=y[i]) return (long long)x[i]-(long long)y[i]; i++; } return 0; }");
        line("#define mo_arrcmp(a,b) mo_arrcmp3(a,b,sizeof(a))");
        line("static long long mo_fbits_impl(double v){ union {double d; long long i;} u; u.d=v; return u.i; }");
        line("#define fbits mo_fbits_impl");
        line("static double mo_ffrombits_impl(long long i){ union {double d; long long i;} u; u.i=i; return u.d; }");
        line("#define ffrombits mo_ffrombits_impl");
        line("struct str_t;");   # v1.1190: str 类型 opaque 前向（str 作形参/返回时 struct 未定义处可用）
        line("#define strlen strlen_");
        # v1.1171: freestanding 前导补 strcpy/strcat（无符号 char* 语义，供
        # "无 import 直用" 的裸机程序；strlen 系列其余函数签名冲突留给 mo_ 前缀）
        line("static unsigned char* strcpy_(unsigned char* d, unsigned char* s){ long long i=0; while(s[i]){ d[i]=s[i]; i++; } d[i]=0; return d; }");
        line("#define strcpy strcpy_");
        line("static unsigned char* strcat_(unsigned char* d, unsigned char* s){ long long i=0,j=0; while(d[i]) i++; while(s[j]){ d[i+j]=s[j]; j++; } d[i+j]=0; return d; }");
        line("#define strcat strcat_");
        emit_mem_macros();
        # 输出函数由后端提供（printf 版）。
        # 不用 syscall 是因为 WASI 没有 syscall() —— 照搬 io.mo 会链接失败。
        line("#include <stdio.h>");
        line("static long long print_(const unsigned char* s){ return (long long)fputs((const char*)s, stdout); }");
        line("static long long print_i64_(long long v){ return (long long)fprintf(stdout, \"%lld\", v); }");
        line("static long long print_nl_(void){ return (long long)fputc('\\n', stdout); }");
        line("static long long print_hex_(long long v){ return (long long)fprintf(stdout, \"%llx\", v); }");
        line("#define print print_");
        line("#define print_i64 print_i64_");
        line("#define print_nl print_nl_");
        line("#define print_hex print_hex_");
        line("static long long eprint_(const unsigned char* s){ return (long long)fputs((const char*)s, stderr); }");
        line("static long long eprint_i64_(long long v){ return (long long)fprintf(stderr, \"%lld\", v); }");
        line("static long long eprint_nl_(void){ return (long long)fputc('\\n', stderr); }");
        line("#define eprint eprint_");
        line("#define eprint_i64 eprint_i64_");
        line("#define eprint_nl eprint_nl_");
        # v1.1164: fint/f64 内建（f64↔i64 转换）。LLP64 规则：一律 long long。
        # (long long)double 向零截断 = cvttsd2si 语义。
        line("static long long fint(double v){ return (long long)v; }");
        line("static double f64(long long v){ return (double)v; }");
        # v1.1176: panic 内建对齐（moc v1.1175）
        line("#include <stdlib.h>");
        line("static void panic(const char* m){ fprintf(stderr, \"%s\", m); exit(1); }");
        line("static long long mo_oob(long long i, long long n){ if(i<0){ i+=n; } if(i<0||i>=n){ fprintf(stderr, \"index out of bounds\\n\"); exit(1);} return i; }");
        line("static void assert_(long c, const char* m){ if(!c){ fprintf(stderr, \"%s\", m); exit(1);} }");
        line("static long long mo_main(void);");
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

# ==========================================================================
#  v1.1166: lambda 表达式（C 系后端）
#
#  emit_unary 遇 "fn"（表达式位置）→ collect_lambda()：
#  把 lambda 的 token 流（'(' 起到配平 '}'）按 token 文本拼接（token 间
#  加空格防标识符粘连；字符串字面量是 kind3 单 token，其内部 {} 不参与
#  配平 —— 比 moc 的字节级朴素配平更准）存入 LAMSRC 队列；表达式值 =
#  "((unsigned char*)mo_lambda_N)"。resolve_lambdas()（emit_footer 前，
#  此时主文件 token 流已消费完，重载 TK/TS 安全）：把队列文本 memcpy 进
#  &SRC → tokenize() → 两遍发射（第一遍 emit_sig+";" 做前向声明，第二遍
#  emit_sig+emit_block_body 做定义）。返回类型统一 long long（ptr/str
#  兼容；f64 返回会被截断 —— 局限记录在 docs）。
# ==========================================================================

var LAMSRC: [524288] byte = 0;   # lambda 文本队列：n*8192
var NLAM: i64 = 0;               # 已收集 lambda 数
var LAMCN: i64 = 0;              # 命名计数

# v1.1166: prescan —— emit_header 前对已加载文件扫描 lambda（fn 后紧跟 '('）并收集文本。
# 正文 collect_lambda 与 prescan 同一 token 流同序，故槽位编号天然一致。
fn prescan_lambdas() -> i64 {
    if is_c_like() == 0 { return 0; }
    let f: i64 = 0;
    while f < NF {
        load_file(f);
        let i: i64 = 0;
        while i < NT - 1 {
            if TK[i] == 1 && streq(&POOL + TS[i], "fn") == 1 {
                if TK[i + 1] == 5 && streq(&POOL + TS[i + 1], "(") == 1 {
                    TI = i + 1;
                    gather_lambda();
                    i = TI;
                    continue;
                }
            }
            i = i + 1;
        }
        f = f + 1;
    }
    return 0;
}

# 收集当前 lambda（TI 指 '('）到 LAMSRC[NLAM]，编号 = NLAM+1
fn gather_lambda() -> i64 {
    if NLAM >= 64 { return err("too many lambdas (limit 64)"); }
    let base: i64 = NLAM * 8192;
    let w: i64 = 0;
    # 前缀 "fn mo_lambda_N"：resolve 时 emit_sig 的 ident() 需要读到名字
    memcpy(&LAMSRC + base, "fn mo_lambda_N", 14);   # "fn mo_lambda_N" = 14 字符，N 在 base+13
    w = 14;
    store8(&LAMSRC + base + w, 32);
    w = w + 1;
    if NLAM + 1 >= 10 {
        # 两位数编号：覆盖占位 'N'（十进制逐位写）
        let v: i64 = NLAM + 1;
        let digs: [8] byte = 0;
        let dn: i64 = 0;
        while v > 0 { store8(&digs + dn, 48 + (v % 10)); v = v / 10; dn = dn + 1; }
        let di: i64 = dn - 1;
        while di >= 0 {
            store8(&LAMSRC + base + w, load8(&digs + di));
            w = w + 1;
            di = di - 1;
        }
    } else {
        store8(&LAMSRC + base + 13, 48 + NLAM + 1);      # 覆盖占位 'N'（base+13）
    }
    let dep: i64 = 0;
    while 1 == 1 {
        if TI >= NT { return err("unterminated lambda body"); }
        let k: i64 = TK[TI];
        let s: i64 = &POOL + TS[TI];
        if w > 0 { store8(&LAMSRC + base + w, 32); w = w + 1; }   # token 间空格
        let q: i64 = 0;
        while load8(s + q) != 0 {
            if w >= 8100 { return err("lambda too large (8KB)"); }
            store8(&LAMSRC + base + w, load8(s + q));
            w = w + 1;
            q = q + 1;
        }
        if k == 5 {
            if streq(s, "{") == 1 { dep = dep + 1; }
            else { if streq(s, "}") == 1 {
                dep = dep - 1;
                if dep == 0 { TI = TI + 1; break; }
            } }
        }
        TI = TI + 1;
    }
    store8(&LAMSRC + base + w, 10);
    store8(&LAMSRC + base + w + 1, 0);
    NLAM = NLAM + 1;
    return 0;
}

# 正文：fn 表达式 → 消费序号 + 发函数地址值
fn collect_lambda() -> i64 {
    TI = TI + 1;                          # 吃 'fn'，当前 = '('（prescan 已收集文本）
    let myn: i64 = LAMCN + 1;
    LAMCN = LAMCN + 1;
    if LAMCN > NLAM { return err("lambda prescan mismatch"); }
    # 跳过 lambda 体 token（配平 {}）
    let dep: i64 = 0;
    while 1 == 1 {
        if TI >= NT { return err("unterminated lambda body"); }
        if TK[TI] == 5 {
            let s: i64 = &POOL + TS[TI];
            if streq(s, "{") == 1 { dep = dep + 1; }
            else { if streq(s, "}") == 1 {
                dep = dep - 1;
                if dep == 0 { TI = TI + 1; break; }
            } }
        }
        TI = TI + 1;
    }
    # 表达式值 = 函数地址（cast 成 unsigned char* 与既有 ptr 语义一致）
    outs("((unsigned char*)mo_lambda_");
    outi(myn);
    outs(")");
    return 0;
}

# v1.1166: lambda 前向声明（使用点在 header 后、定义在文件尾）—— 
# K&R 无原型声明对任意参数表兼容（gnu17 下合法）。
fn emit_lambda_decls() -> i64 {
    if NLAM == 0 { return 0; }
    let n: i64 = 1;
    let tot: i64 = NLAM;
    while n <= tot {
        # 真原型：tokenize 该 lambda 文本，emit_sig 发 "long long mo_lambda_N(...)"
        memcpy(&SRC, &LAMSRC + (n - 1) * 8192, 8192);
        PP = 0;
        tokenize();
        TI = TI + 1;
        outs("static ");
        emit_sig();
        line(";");
        n = n + 1;
    }
    return 0;
}

# footer 前：逐条重 tokenize + 两遍发射（声明 + 定义）
fn resolve_lambdas() -> i64 {
    if NLAM == 0 { return 0; }
    if is_c_like() == 0 { return 0; }
    let n: i64 = 0;
    while n < NLAM {
        memcpy(&SRC, &LAMSRC + n * 8192, 8192);
        PP = 0;
        tokenize();
        TI = TI + 1;                      # 吃 'fn'
        outs("static ");
        emit_sig();
        emit_block_body();
        n = n + 1;
    }
    return 0;
}

fn emit_footer() -> i64 {
    if TGT == T_UEFI {
        nl();
        line("static long long mo_main(void);");
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
        line("static long long mo_main(void);");
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
                if is_c_like() == 1 && TK[TI] == 3 {
                    # v1.1195: 局部 str 字面量 init → 可写 static 副本（07_memory）
                    LWSEQ = LWSEQ + 1;
                    outs("static unsigned char __mlit_");
                    outi(LWSEQ);
                    outs("[] = ");
                    out_cstr(cur_s());
                    outs(";");
                    nl();
                    TI = TI + 1;
                    g_decl(nm, 0);
                    if LASTTY == 0 || streq(LASTTY, "i64") == 1 { outs(" = (long long)(unsigned char*)__mlit_"); }
                    else { outs(" = (unsigned char*)__mlit_"); }
                    outi(LWSEQ);
                    outs(";");
                    return 0;
                }
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
    OBF = 1;
    OPO = 0;
    add_file(argv(1));
    if is_gen() == 0 { prescan_lambdas(); }   # v1.1166: C 系 —— emit_header 前收集 lambda
    # v1.1206: 预收集轮（EVIN/EVTN 登记）+ tagged typedef 前置（全局 var 用）
    let ip0: i64 = 0;
    while ip0 < NF { pass_file(ip0, 0); ip0 = ip0 + 1; }
    let ip9: i64 = 0;
    while ip9 < NF { pass_file(ip9, 9); ip9 = ip9 + 1; }
    if is_gen() == 1 { g_header(); } else { emit_header(); }
    if is_gen() == 0 { emit_lambda_decls(); } # 前向声明（K&R 兼容原型）紧跟 header
    let i: i64 = 0;
    while i < NF { pass_file(i, 0); i = i + 1; }
    let j: i64 = 0;
    while j < NF { pass_file(j, 1); j = j + 1; }
    # v1.1206: tagged enum typedef 前置（收集轮之后、发射轮之前，EVIN 已登记）
    let i9: i64 = 0;
    while i9 < NF { pass_file(i9, 9); i9 = i9 + 1; }
    let k: i64 = 0;
    while k < NF { pass_file(k, 2); k = k + 1; }
    let m: i64 = 0;
    while m < NF { pass_file(m, 3); m = m + 1; }
    resolve_lambdas();
    if is_gen() == 1 { g_footer(); } else { emit_footer(); }
    # v1.1201: 全部 pass 成功结束才 flush 缓冲 —— 编译失败（err→exit）时
    # 缓冲整块丢弃，stdout 无半截产物
    out_flush();
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

# v1.1205: 臂首 token 是否语句关键字（语句形态臂）还是值表达式（match 表达式臂）
fn arm_is_stmt() -> i64 {
    if cur_k() != 1 { return 0; }
    if streq(cur_s(), "return") == 1 { return 1; }
    if streq(cur_s(), "let") == 1 { return 1; }
    if streq(cur_s(), "const") == 1 { return 1; }
    if streq(cur_s(), "if") == 1 { return 1; }
    if streq(cur_s(), "while") == 1 { return 1; }
    if streq(cur_s(), "for") == 1 { return 1; }
    if streq(cur_s(), "match") == 1 { return 1; }
    return 0;
}

var MPB: [4096] byte = 0;   # v1.1205: match 模式路径缓冲
var MLPT: i64 = 0;           # 当前路径长度（NUL 位置）
var MBN: [64] i64 = 0;      # 绑定名表（match 模式绑定，臂内可见）
var NMBN: i64 = 0;
# v1.1205: 统一 match 发射（isexpr=1 值形态 statement-expression；0 语句形态）
# 调用时 TI 停在 "match" 上（本函数 TI+1 吃掉它）。

fn mbn_add(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NMBN {
        if streq(MBN[i], nm) == 1 { return 0; }
        i = i + 1;
    }
    if NMBN < 64 { MBN[NMBN] = stp_copy(nm); NMBN = NMBN + 1; }
    return 0;
}
fn mp_init() -> i64 {
    store8(&MPB + 0, 95);   # _
    store8(&MPB + 1, 95);   # _
    store8(&MPB + 2, 109);  # m
    store8(&MPB + 3, 118);  # v
    store8(&MPB + 4, 0);
    MLPT = 4;
    return 0;
}
fn mp_push(f: i64) -> i64 {
    # 追加 '.' + 字段名，返回旧 MLPT（供弹出恢复）
    let old: i64 = MLPT;
    let q: i64 = old;
    store8(&MPB + q, 46);   # '.'
    q = q + 1;
    let w: i64 = 0;
    while load8(f + w) != 0 {
        store8(&MPB + q + w, load8(f + w));
        w = w + 1;
    }
    store8(&MPB + q + w, 0);
    MLPT = q + w;
    return old;
}
fn mp_pop(o: i64) -> i64 {
    store8(&MPB + o, 0);
    MLPT = o;
    return 0;
}
fn emit_mpat_leaf() -> i64 {
    # v1.1205: 模式字段叶子 —— 路径前缀由调用方顺序 outs（无指针拼接，规避 native 拼接异常）
    # 当前 token = 字段值（数字 / 绑定名 / 嵌套 struct 模式）
    if cur_k() == 1 && st_find(cur_s()) >= 0 && peek_op("{") == 1 {
        TI = TI + 2;   # 吃 Name '{'
        while is_op("}") == 0 {
            if is_op(";") == 1 { TI = TI + 1; continue; }
            let oldp: i64 = mp_push(&POOL + TS[TI]);   # 路径追加 .字段
            TI = TI + 2;   # 吃 字段名 与 ':'
            emit_mpat_leaf();
            mp_pop(oldp);
            if is_op(";") == 1 || is_op(",") == 1 { TI = TI + 1; }
            if is_op("}") == 0 { outs(" && "); }
        }
        expect_op("}");
        return 0;
    }
    if cur_k() == 2 {
        outs(&MPB);
        outs(" == (");
        outs(cur_s());
        outs(")");
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 1 {
        # 绑定：v 声明提升到 match 块头（臂内可见）——条件处只赋值
        mbn_add(&POOL + TS[TI]);
        outs("(({ ");
        outs(&POOL + TS[TI]);
        outs(" = ");
        outs(&MPB);
        outs("; 1; }))");
        TI = TI + 1;
        return 0;
    }
    return err("match: 不支持的字段模式值");
}
fn emit_match(isexpr: i64) -> i64 {
    NMBN = 0;
    TI = TI + 1;
    if isexpr == 1 { outs("({ "); }
    else { outs("{ "); }
    # v1.1205: struct 主体 → struct X_t __mv = (expr);（模式访问字段）；标量主体 → long long
    let msv: i64 = 0;
    if cur_k() == 1 && clsv_find(cur_s()) != 0 {
        msv = 1;
        # v1.1206: tagged enum 主体 → Shape_t __mv（无 struct tag）
        if ev_struct_ty(clsv_find(cur_s())) == 1 {
            outs(clsv_find(cur_s()));
            outs("_t __mv = (");
        } else {
        outs("struct ");
        outs(clsv_find(cur_s()));
        outs("_t __mv = (");
        }
        # struct 指针形参（FSGK tk=5）→ 解引用
        if ptr_find(cur_s()) == 1 { outs("*"); }
        emit_expr();
        outs("); long long __mr = 0; long long __mf = 0;");
    } else {
        outs("long long __mv = (long long)(");
        emit_expr();
        outs("); long long __mr = 0; long long __mf = 0;");
    }
    nl();
    expect_op("{");
    # v1.1205: 预扫模式绑定名（`字段: 名` 且非 struct 名/非 _）→ 臂内可见声明
    NMBN = 0;
    {
        let svb: i64 = TI;
        let depb: i64 = 1;
        while depb > 0 && TI < NT {
            if TK[TI] == 5 {
                let sb: i64 = &POOL + TS[TI];
                if streq(sb, "{") == 1 { depb = depb + 1; }
                if streq(sb, "}") == 1 { depb = depb - 1; }
                if streq(sb, ":") == 1 && TK[TI + 1] == 1 {
                    let nb: i64 = &POOL + TS[TI + 1];
                    if streq(nb, "_") == 0 && st_find(nb) < 0 { mbn_add(nb); }
                }
            }
            if TK[TI] == 1 && TK[TI + 1] == 1 && TI + 1 < NT && streq(&POOL + TS[TI + 1], "if") == 1 {
                let nb2: i64 = &POOL + TS[TI];
                if streq(nb2, "_") == 0 { mbn_add(nb2); }
            }
            # v1.1206: 变体模式 `Variant(b1, b2)` 预扫绑定
            if TK[TI] == 1 && TK[TI + 1] == 5 && TI + 1 < NT && streq(&POOL + TS[TI + 1], "(") == 1 {
                let pv: i64 = TI + 2;
                let dpv: i64 = 0;
                while pv < NT {
                    if TK[pv] == 5 {
                        let spv: i64 = &POOL + TS[pv];
                        if dpv == 0 && streq(spv, ")") == 1 { break; }
                        if streq(spv, "(") == 1 { dpv = dpv + 1; }
                        if streq(spv, ")") == 1 { dpv = dpv - 1; }
                    }
                    if TK[pv] == 1 && dpv >= 0 && streq(&POOL + TS[pv], "_") == 0 { mbn_add(&POOL + TS[pv]); }
                    pv = pv + 1;
                }
            }
            TI = TI + 1;
        }
        TI = svb;
    }
    mp_init();
    # v1.1205: 模式绑定声明（臂内可见）—— 预扫后
    {
        let bi: i64 = 0;
        while bi < NMBN {
            outs(" long long ");
            outs(MBN[bi]);
            outs(" = 0;");
            bi = bi + 1;
        }
    }
    # v1.1205: strex 判定在 '{' 之后（看第一个模式是否字符串字面量）
    let strex: i64 = 0;
    if cur_k() == 3 { strex = 1; }
    let mfirst: i64 = 1;
    while is_op("}") == 0 {
        let bindg: i64 = 0;
        let isdef: i64 = 0;
        if cur_k() == 1 && streq(cur_s(), "_") == 1 { isdef = 1; TI = TI + 1; }
        if mfirst == 0 { outs(" else "); }
        if isdef == 0 {
            outs("if (");
            # v1.1205: struct 模式 P { x: 5; y: 2; } → __mv.x==5 && __mv.y==2（仅列出字段；支持嵌套+绑定）
            if cur_k() == 1 && st_find(cur_s()) >= 0 && peek_op("{") == 1 {
                TI = TI + 2;   # 吃 'P' 与 '{'
                outs("(");
                while is_op("}") == 0 {
                    if is_op(";") == 1 { TI = TI + 1; continue; }
                    let oldp: i64 = mp_push(&POOL + TS[TI]);   # 路径追加 .字段
                    TI = TI + 2;   # 吃 字段名 与 ':'
                    emit_mpat_leaf();
                    mp_pop(oldp);
                    if is_op(";") == 1 || is_op(",") == 1 { TI = TI + 1; }
                    if is_op("}") == 0 { outs(" && "); }
                }
                expect_op("}");
                outs(") && 1");
            } else {
            if strex == 1 {
                outs("mo_swstrcmp((unsigned char*)__mv, \"");
                outs(cur_s());
                outs("\") == 0");
                TI = TI + 1;
            } else {
                if cur_k() == 2 { outs("__mv == "); outs(cur_s()); TI = TI + 1; }
                else {
                    # v1.1206: 变体模式 `Variant(b1, b2)` → __mv.tag==v && 绑定=__mv._N
                    if cur_k() == 1 && TK[TI + 1] == 5 && streq(&POOL + TS[TI + 1], "(") == 1 {
                        let vmn: i64 = 0 - 1;
                        let vmv: i64 = 0 - 1;
                        let vme: i64 = 0;
                        while vme < NEVN {
                            let vq3: i64 = 0;
                            while vq3 < EVCN[vme] {
                                if streq(EVTN[vme * 8 + vq3], cur_s()) == 1 { vmn = vme; vmv = vq3; }
                                vq3 = vq3 + 1;
                            }
                            vme = vme + 1;
                        }
                        if vmn >= 0 {
                            TI = TI + 2;   # 吃 变体名 与 '('
                            outs("( __mv.tag == ");
                            outi(vmv);
                            let fb6: i64 = 0;
                            while fb6 < EVFC[vmn * 8 + vmv] && is_op(")") == 0 {
                                if TK[TI] == 1 && streq(&POOL + TS[TI], "_") == 0 {
                                    mbn_add(cur_s());
                                    outs(" && ((");
                                    outs(cur_s());
                                    outs(" = __mv._");
                                    outi(fb6);
                                    outs(", 1))");
                                }
                                TI = TI + 1;
                                if is_op(",") == 1 { TI = TI + 1; }
                                fb6 = fb6 + 1;
                            }
                            expect_op(")");
                            outs(") ");
                        } else { outi(cns_expr()); }
                    } else {
                    if cur_k() == 1 && TK[TI + 1] >= 0 && TK[TI + 1] < NT && TK[TI + 1] == 1 && streq(&POOL + TS[TI + 1], "if") == 1 {
                        # v1.1206: 绑定模式 `y if cond` —— y 已在 match 顶部声明（NMBN），此处赋值+守卫
                        bindg = 1;
                        mbn_add(cur_s());
                        outs("(({ ");
                        outs(cur_s());
                        outs(" = __mv; 1; }))");
                        TI = TI + 1;   # 只吃 名字；'if' 交守卫分支
                    }
                    else { outi(cns_expr()); }
                    }
                }
            }
            }
            # 守卫 if cond（281）；v1.1206: 绑定模式 bindg=1 时条件恒真，守卫照常发射
            if accept_kw("if") == 1 {
                outs(" && (");
                emit_expr();
                outs(")");
            }
            outs(")");
        }
        expect_op("=>");
        outs(" { __mf = 1;");
        if is_op("{") == 1 {
            TI = TI + 1;
            if isexpr == 1 && arm_is_stmt() == 0 {
                outs(" __mr = (");
                emit_expr();
                outs(");");
                expect_op("}");
            } else {
                emit_stmts();
            }
        } else {
            outs(" __mr = (");
            emit_expr();
            outs(");");
            if is_op("}") == 0 && is_op(",") == 0 { err("match: expected } or , after bare arm"); }
        }
        outs(" }");
        if isdef == 1 { mfirst = 2; }
        else { mfirst = 0; }
        if is_op(",") == 1 { TI = TI + 1; }
    }
    expect_op("}");
    if isexpr == 1 { outs(" __mr; })"); }
    else { outs(" }"); semi(); }
    return 0;
}
