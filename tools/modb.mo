# dwmo.mo —— 墨语言自己写的 DWARF 调试信息校验器
#
# 为什么要写这个：
#   tools/dwvar.py 干的是同一件事（验证 -g 生成的变量位置真的对得上
#   机器码），但它是 Python，而且要借 readelf / objdump 两个外部工具。
#   也就是说：调试信息是自己生成的，验证器却不是 —— 自包含生态在这一
#   环上是断的。
#
#   本文件直接读 ELF 二进制：
#     1. 自己解析 ELF64 节头表，按名字找 .text/.debug_info/.debug_abbrev
#        /.debug_frame
#     2. 自己解析 .debug_abbrev，再按 form 逐个读 DIE 属性
#     3. 自己写 x86-64 **指令长度解码器**，线性扫描函数体收集 [rbp+off]
#     4. 自己解析 .debug_frame 的 CIE/FDE 与 DW_CFA 指令流
#   全程不调 readelf、不调 objdump、不调 Python。
#
# 🔴 比 Python 版多一条别人做不到的断言：
#    Python 版把字节块交给 objdump 反汇编，objdump 是黑盒 —— 它说有
#    [rbp-8] 就有，没人验证它扫得对不对。
#    这里自己解码，于是可以断言 **线性扫描的指令边界必须精确落在
#    函数末尾**（high_pc）。任何一条指令长度算错，末尾就对不上 ——
#    这是对"扫描本身"的校验，而不是只校验扫描结果。
#
# 用法：dwmo <file.elf>

import "fs.mo";
import "io.mo";
import "str.mo";
import "mem.mo";

var BUFSZ: i64 = 2097152;

# 容量上限。为什么必须显式检查而不是靠数组越界崩溃：
#   扫 bin/moc 这种真实大程序时，DIE 数轻松破千。越界时墨语言只报
#   "index out of bounds" —— 没有上下文，看不出是 DIE 满、FDE 满还是
#   abbrev 满，极易误判成"输入文件坏了"。这里逐个容器显式报错。
var MAXSEC: i64 = 64;
var MAXAB:  i64 = 256;
var MAXD:   i64 = 4096;
var MAXF:   i64 = 4096;
var MAXR:   i64 = 512;

var CAPERR: i64 = 0;       # 1 = 容量不足（调用方必须据此退出，而不是继续）

# ---------- -s 全程序扫描模式（与被测程序无关的通用校验）----------
var SC_NF: i64 = 0;        # 扫过的函数数
var SC_NI: i64 = 0;        # 解出的指令条数
var SC_NB: i64 = 0;        # 覆盖的字节数
var SC_BAD: i64 = 0;       # 边界未落在 high_pc 的函数数
var SC_ERR: i64 = 0;       # 遇到无法解码指令的函数数
var SC_NR: i64 = 0;        # 收集到的 [rbp+off] 偏移总数
var SC_NBR: i64 = 0;       # 检查过的跳转/调用目标数
var SC_NBD: i64 = 0;       # 目标不是合法指令边界的数量
var SC_PERFN: i64 = 0;     # 1 = -S 模式：逐函数打印 lo/hi/指令数
var SC_NI_PREV: i64 = 0;
var BUF: i64 = 0;
var FSZ: i64 = 0;

var PASS: i64 = 0;
var FAIL: i64 = 0;

# ---------- 节 ----------
var NS: i64 = 0;
var S_OFF: [64] i64 = 0;
var S_SIZE: [64] i64 = 0;
var S_ADDR: [64] i64 = 0;
var I_TEXT: i64 = 0;
var I_INFO: i64 = 0;
var I_ABBR: i64 = 0;
var I_FRAME: i64 = 0;
var I_LINE: i64 = 0;

# ---------- uleb / sleb ----------
var ULEB_V: i64 = 0;
var ULEB_P: i64 = 0;
var SLEB_V: i64 = 0;
var SLEB_P: i64 = 0;

# ---------- abbrev ----------
var AB_TAG: [256] i64 = 0;
var AB_CH: [256] i64 = 0;
var AB_NAT: [256] i64 = 0;
var AB_A: [2048] i64 = 0;
var AB_F: [2048] i64 = 0;

# ---------- DIE ----------
var ND: i64 = 0;
var D_OFF: [4096] i64 = 0;
var D_TAG: [4096] i64 = 0;
var D_NM: [4096] i64 = 0;
var D_PAR: [4096] i64 = 0;
var D_LO: [4096] i64 = 0;
var D_HI: [4096] i64 = 0;
var D_FB: [4096] i64 = 0;
var D_HFB: [4096] i64 = 0;
var D_AD: [4096] i64 = 0;
var D_HAD: [4096] i64 = 0;
var D_LINE: [4096] i64 = 0;
var D_TY: [4096] i64 = 0;
var D_MLOC: [4096] i64 = 0;
# 类型尺寸复用 D_LO（subprogram 用它存 low_pc，类型 DIE 不用），
# 元素数复用 D_MLOC（member 用它存偏移，subrange 用它存 count）。
# 为什么不再开三个 [4096] 数组：全局数据区接近上限时编译器会**静默损坏
# 符号表**，报错落在完全无关的行（"undefined symbol 'BUF'"），
# 极易误判成代码写错。
var D_FILE: [4096] i64 = 0;    # DW_AT_decl_file（file_names 编号，从 1 起）
var CU_BASE: i64 = 0;          # DW_AT_type 等 ref4 的基准偏移
var LN_FNBADF: i64 = 0;        # 函数 decl_file 与入口行号记录的文件不一致数
var LN_FNNOF: i64 = 0;         # 完全没读到 decl_file 的函数数
var PSTK: [512] i64 = 0;

# ---------- 反汇编收集到的 rbp 偏移 ----------
var RBP_N: i64 = 0;
var RBP_O: [512] i64 = 0;

# ---------- .debug_line ----------
# 行号表是 DWARF 里**唯一**把机器码地址与源码行号绑在一起的段。
# 1.90 之前 dwmo 完全没解析它 —— 于是"函数定义行能不能下断点"这件
#    事从来没被校验过（后来发现它真的有问题，见 docs/dwmo.md）。
var MAXL: i64 = 8192;
var NL: i64 = 0;
var L_AD: [8192] i64 = 0;
var L_LN: [8192] i64 = 0;
var L_FN: [8192] i64 = 0;     # 每条记录所属的**文件编号**（DWARF 从 1 起）
var SOL: [16] i64 = 0;        # standard_opcode_lengths[]

# ---------- .debug_line 的 file_names 表 ----------
# 一条行号记录只说明"第几行"，不说明"哪个文件"。文件由 DW_LNS_set_file
# 选定，编号指向这张表。表少一个条目 → readelf 报 file number out of range；
# 表有条目却没有记录用到 → 说明那个文件的代码压根没登记行号。
var NFT: i64 = 0;             # 文件表条目数
var FT_NM: [32] i64 = 0;      # 名字在 FNBUF 里的偏移
var FNBUF: [2048] byte = 0;
var FNB: i64 = 0;
var FT_ROWS: [32] i64 = 0;    # 每个文件被多少条记录用到
var LN_BADFILE: i64 = 0;      # 文件编号越界（<1 或 >NFT）的记录数
var LN_NOFILE: i64 = 0;       # 文件表里有、却一条记录都没用到的文件数

var LN_NSEQ: i64 = 0;         # sequence 数（end_sequence 出现次数）
var LN_END: i64 = 0;          # 最后一个 end_sequence 的地址
var LN_MAXL: i64 = 0;         # 出现过的最大行号
var LN_BADTXT: i64 = 0;       # 地址不在 .text 内的记录数
var LN_BADSORT: i64 = 0;      # 地址非递增的记录数
var LN_BADOOB: i64 = 0;       # 地址不在任何函数 [lo,hi) 内的记录数
var LN_COV: i64 = 0;          # 行号表覆盖的 .text 字节数

var NFN: i64 = 0;             # 带代码的 subprogram 数
var FI: [4096] i64 = 0;       # 按 low_pc 升序排列的 DIE 下标
var FN_LO: [4096] i64 = 0;
var FN_HI: [4096] i64 = 0;
var FN_NR: [4096] i64 = 0;    # 落在该函数内的行号记录数
var LN_FNNOROW: i64 = 0;      # 完全没有行号记录的函数数
var LN_FNMISS: i64 = 0;       # decl_line 不在自己行号记录里的函数数
var FN_HIT: [4096] i64 = 0;   # 该函数的定义行是否出现在自己的行号记录里
var FN_ENTF: i64 = 0;         # 堆：函数入口行号记录的**文件编号**

# ---------- .debug_frame ----------
var NFDE: i64 = 0;
var F_LO: [4096] i64 = 0;
var F_HI: [4096] i64 = 0;
var F_CFA: [4096] i64 = 0;

# ---------- 源码交叉校验（-L <source>） ----------
# 行表用堆分配：源文件行数未知，且固定数组会挤占本就接近上限的全局区。
var SRC: i64 = 0;          # 源码缓冲区
var SRC_SZ: i64 = 0;
var SRC_N: i64 = 0;        # 行数（1-based）
var SRC_OFF: i64 = 0;      # 行 -> 起始偏移，[0..SRC_N+1]
var SRC_HIT: i64 = 0;      # 行 -> 是否被行号表覆盖
var SRC_TMP: i64 = 0;      # 取一行出来做匹配用的临时缓冲
var SRCP: [256] i64 = 0;   # -L 后面的路径（argv 指针会失效，必须拷一份）
var S_HAS: i64 = 0;        # 1 = 命令行给了 -L
var S_OOB: i64 = 0;        # 行号越界的记录数
var S_BADKIND: i64 = 0;    # 行号指向空白/注释行的记录数
var S_DECLN: i64 = 0;      # 检查过的定义行数
var S_DECLBAD: i64 = 0;    # 定义行不含 fn 关键字的数量
var S_SHOWN: i64 = 0;      # 已打印的违规示例数（限流）
var S_CODE: i64 = 0;       # 源码中"代码行"总数
var S_MISS: i64 = 0;       # 代码行中从未出现在行号表里的数量
var S_MISSFN: i64 = 0;     # 其中"看起来像函数定义行"的数量（真正可疑的）
var S_SHOW2: i64 = 0;      # 未覆盖示例打印限流
var S_NAMEBAD: i64 = 0;    # 定义行里不包含该函数自身名字的数量
var FN_ENT: i64 = 0;       # 堆：该函数是否有一条"入口地址"行号记录
var FN_ENTLN: i64 = 0;     # 堆：那条记录的行号
var S_ENTN: i64 = 0;       # 有入口记录的函数数
var S_ENTBAD: i64 = 0;     # 入口记录的行号里没有该函数名的数量

# ================= 基础读取 =================
fn gb(i: i64) -> i64 { return load8(BUF + i); }

fn g16(i: i64) -> i64 {
    return gb(i) + (gb(i + 1) * 256);
}

fn g32(i: i64) -> i64 {
    return gb(i) + (gb(i + 1) * 256) + (gb(i + 2) * 65536)
         + (gb(i + 3) * 16777216);
}

fn g64(i: i64) -> i64 {
    let r: i64 = 0;
    let k: i64 = 0;
    while k < 8 {
        r = r + (gb(i + k) << (k * 8));
        k = k + 1;
    }
    return r;
}

fn guleb(p: i64) -> i64 {
    let r: i64 = 0;
    let s: i64 = 0;
    let b: i64 = 0;
    while 1 {
        b = gb(p);
        p = p + 1;
        r = r + ((b & 127) << s);
        s = s + 7;
        if (b & 128) == 0 { break; }
    }
    ULEB_V = r;
    ULEB_P = p;
    return r;
}

fn gsleb(p: i64) -> i64 {
    let r: i64 = 0;
    let s: i64 = 0;
    let b: i64 = 0;
    while 1 {
        b = gb(p);
        p = p + 1;
        r = r + ((b & 127) << s);
        s = s + 7;
        if (b & 128) == 0 { break; }
    }
    if (b & 64) != 0 { r = r - (1 << s); }
    SLEB_V = r;
    SLEB_P = p;
    return r;
}

# ================= ELF =================
fn parse_elf() -> i64 {
    let i: i64 = 0;
    let shoff: i64 = 0;
    let shent: i64 = 0;
    let shnum: i64 = 0;
    let shstr: i64 = 0;
    let stroff: i64 = 0;
    let h: i64 = 0;
    let nm: i64 = 0;
    if g32(0) != 1179403647 { return 0 - 1; }
    if gb(4) != 2 { return 0 - 2; }
    shoff = g64(40);
    shent = g16(58);
    shnum = g16(60);
    shstr = g16(62);
    if shnum > MAXSEC {
        print("dwmo: 容量不足 —— 节数 ");
        print_i64(shnum);
        print(" > 上限 ");
        print_i64(MAXSEC);
        print_nl();
        CAPERR = 1;
        return 0 - 3;
    }
    NS = shnum;
    stroff = g64(shoff + shstr * shent + 24);
    while i < shnum {
        h = shoff + i * shent;
        S_OFF[i] = g64(h + 24);
        S_SIZE[i] = g64(h + 32);
        S_ADDR[i] = g64(h + 16);
        nm = BUF + stroff + g32(h);
        if streq(nm, ".text") == 1 { I_TEXT = i; }
        if streq(nm, ".debug_info") == 1 { I_INFO = i; }
        if streq(nm, ".debug_abbrev") == 1 { I_ABBR = i; }
        if streq(nm, ".debug_frame") == 1 { I_FRAME = i; }
        if streq(nm, ".debug_line") == 1 { I_LINE = i; }
        i = i + 1;
    }
    return 0;
}

# ================= abbrev =================
fn parse_abbrev() -> i64 {
    let p: i64 = S_OFF[I_ABBR];
    let e: i64 = p + S_SIZE[I_ABBR];
    let code: i64 = 0;
    let tag: i64 = 0;
    let ch: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    let f: i64 = 0;
    while p < e {
        guleb(p);
        code = ULEB_V;
        p = ULEB_P;
        if code == 0 { return 0; }
        if code >= MAXAB {
            print("dwmo: 容量不足 —— abbrev code ");
            print_i64(code);
            print(" >= 上限 ");
            print_i64(MAXAB);
            print_nl();
            CAPERR = 1;
            return 0 - 1;
        }
        guleb(p);
        tag = ULEB_V;
        p = ULEB_P;
        ch = gb(p);
        p = p + 1;
        AB_TAG[code] = tag;
        AB_CH[code] = ch;
        n = 0;
        while n < 8 {
            guleb(p);
            a = ULEB_V;
            p = ULEB_P;
            guleb(p);
            f = ULEB_V;
            p = ULEB_P;
            if a == 0 {
                if f == 0 { break; }
            }
            AB_A[code * 8 + n] = a;
            AB_F[code * 8 + n] = f;
            n = n + 1;
        }
        AB_NAT[code] = n;
    }
    return 0;
}

# ================= .debug_info =================
fn parse_info() -> i64 {
    let p: i64 = S_OFF[I_INFO] + 11;
    let e: i64 = S_OFF[I_INFO] + S_SIZE[I_INFO];
    let code: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    let f: i64 = 0;
    let v: i64 = 0;
    let ln: i64 = 0;
    let sp: i64 = 0;
    let dstart: i64 = 0;
    let cur: i64 = 0;
    cur = 0 - 1;
    ND = 0;
    CU_BASE = S_OFF[I_INFO];
    while p < e {
        dstart = p;
        guleb(p);
        code = ULEB_V;
        p = ULEB_P;
        if code == 0 {
            if sp > 0 {
                sp = sp - 1;
                cur = PSTK[sp];
            }
        }
        if code != 0 {
            if ND >= MAXD {
                print("dwmo: 容量不足 —— DIE 数超过上限 ");
                print_i64(MAXD);
                print_nl();
                CAPERR = 1;
                return 0 - 1;
            }
            D_OFF[ND] = dstart;
            D_TAG[ND] = AB_TAG[code];
            D_PAR[ND] = cur;
            D_NM[ND] = 0;
            D_LO[ND] = 0;
            D_HI[ND] = 0;
            D_FB[ND] = 0;
            D_HFB[ND] = 0;
            D_AD[ND] = 0;
            D_HAD[ND] = 0;
            D_LINE[ND] = 0;
            D_FILE[ND] = 0;
            D_TY[ND] = 0;
            D_MLOC[ND] = 0;
            n = 0;
            while n < AB_NAT[code] {
                a = AB_A[code * 8 + n];
                f = AB_F[code * 8 + n];
                v = 0;
                if f == 8 {
                    D_NM[ND] = p;
                    p = p + strlen(BUF + p) + 1;
                }
                if f == 1 {
                    v = g64(p);
                    p = p + 8;
                }
                if f == 5 {
                    v = g16(p);
                    p = p + 2;
                }
                if f == 6 {
                    v = g32(p);
                    p = p + 4;
                }
                if f == 11 {
                    v = gb(p);
                    p = p + 1;
                }
                if f == 19 {
                    v = g32(p);
                    p = p + 4;
                }
                if f == 24 {
                    guleb(p);
                    ln = ULEB_V;
                    p = ULEB_P;
                    if a == 2 {
                        if gb(p) == 145 {
                            gsleb(p + 1);
                            D_FB[ND] = SLEB_V;
                            D_HFB[ND] = 1;
                        }
                        if gb(p) == 3 {
                            D_AD[ND] = g64(p + 1);
                            D_HAD[ND] = 1;
                        }
                    }
                    p = p + ln;
                }
                if a == 17 { D_LO[ND] = v; }
                if a == 18 { D_HI[ND] = v; }
                if a == 59 { D_LINE[ND] = v; }
                if a == 58 { D_FILE[ND] = v; }
                if a == 73 { D_TY[ND] = v; }
                if a == 11 { D_LO[ND] = v; }
                if a == 56 { D_MLOC[ND] = v; }
                if a == 55 { D_MLOC[ND] = v; }
                n = n + 1;
            }
            ND = ND + 1;
            if AB_CH[code] == 1 {
                PSTK[sp] = cur;
                sp = sp + 1;
                cur = ND - 1;
            }
        }
    }
    return 0;
}


# ================= x86-64 指令长度解码 =================
#
# 只需要"每条指令有多长"，不需要知道它是什么 —— 从函数入口线性扫描，
# 遇到 ModRM 里 rm==5 且 mod!=0 且无 REX.B 的，就是 [rbp+disp]。
#
# 🔴 REX.B 必须排除：rm==5 在 REX.B=1 时是 **r13**，不是 rbp。
#    漏了这条会把 r13 的偏移当成 rbp 的，于是"DWARF 偏移能在机器码
#    里找到"这个断言会**假通过** —— 找的是别人的偏移。

fn is_pfx(b: i64) -> i64 {
    if b == 102 { return 1; }     # 0x66 operand-size
    if b == 103 { return 1; }     # 0x67 address-size
    if b == 240 { return 1; }     # 0xf0 lock
    if b == 242 { return 1; }     # 0xf2 repne
    if b == 243 { return 1; }     # 0xf3 rep
    if b == 46 { return 1; }      # 0x2e cs
    if b == 54 { return 1; }      # 0x36 ss
    if b == 62 { return 1; }      # 0x3e ds
    if b == 38 { return 1; }      # 0x26 es
    if b == 100 { return 1; }     # 0x64 fs
    if b == 101 { return 1; }     # 0x65 gs
    return 0;
}

fn add_rbp(o: i64) -> i64 {
    let i: i64 = 0;
    while i < RBP_N {
        if RBP_O[i] == o { return 0; }
        i = i + 1;
    }
    if RBP_N >= MAXR {
        # 不静默丢弃：否则"DWARF 偏移在机器码里找不到"会假性失败，
        # 看的人会去查 DWARF，而实际是这张表装满了。
        print("dwmo: 容量不足 —— 单函数 rbp 偏移数超过上限 ");
        print_i64(MAXR);
        print_nl();
        CAPERR = 1;
        return 0 - 1;
    }
    RBP_O[RBP_N] = o;
    RBP_N = RBP_N + 1;
    return 0;
}

fn has_rbp(o: i64) -> i64 {
    let i: i64 = 0;
    while i < RBP_N {
        if RBP_O[i] == o { return 1; }
        i = i + 1;
    }
    return 0;
}

# 是否有 ModRM（1 字节 opcode，非 0f 转义）
fn has_mrm1(b: i64) -> i64 {
    if b < 64 {
        if (b & 7) < 4 { return 1; }
        return 0;
    }
    if b == 99 { return 1; }                 # movsxd
    if b == 105 { return 1; }
    if b == 107 { return 1; }
    if b >= 128 {
        if b <= 143 { return 1; }
    }
    if b == 192 { return 1; }
    if b == 193 { return 1; }
    if b == 198 { return 1; }
    if b == 199 { return 1; }
    if b >= 208 {
        if b <= 211 { return 1; }
    }
    if b >= 216 {
        if b <= 223 { return 1; }            # x87
    }
    if b == 246 { return 1; }
    if b == 247 { return 1; }
    if b == 254 { return 1; }
    if b == 255 { return 1; }
    return 0;
}

# 立即数大小（1 字节 opcode，非 0f）
fn imm1(b: i64, rex: i64) -> i64 {
    if b == 4 { return 1; }
    if b == 12 { return 1; }
    if b == 20 { return 1; }
    if b == 28 { return 1; }
    if b == 36 { return 1; }
    if b == 44 { return 1; }
    if b == 52 { return 1; }
    if b == 60 { return 1; }
    if b == 5 { return 4; }
    if b == 13 { return 4; }
    if b == 21 { return 4; }
    if b == 29 { return 4; }
    if b == 37 { return 4; }
    if b == 45 { return 4; }
    if b == 53 { return 4; }
    if b == 61 { return 4; }
    if b == 104 { return 4; }                # push imm32
    if b == 106 { return 1; }                # push imm8
    if b == 105 { return 4; }                # imul imm32
    if b == 107 { return 1; }                # imul imm8
    if b >= 112 {
        if b <= 127 { return 1; }            # jcc rel8
    }
    if b == 128 { return 1; }
    if b == 129 { return 4; }
    if b == 131 { return 1; }
    if b == 168 { return 1; }                # test al,imm8
    if b == 169 { return 4; }
    if b >= 176 {
        if b <= 183 { return 1; }            # mov r8,imm8
    }
    if b >= 184 {
        if b <= 191 {
            if (rex & 8) != 0 { return 8; }  # movabs
            return 4;
        }
    }
    if b == 192 { return 1; }
    if b == 193 { return 1; }
    if b == 194 { return 2; }                # ret imm16
    if b == 198 { return 1; }
    if b == 199 { return 4; }
    if b == 200 { return 3; }                # enter
    if b == 205 { return 1; }                # int imm8
    if b == 212 { return 1; }
    if b == 213 { return 1; }
    if b >= 224 {
        if b <= 227 { return 1; }            # loop/jrcxz rel8
    }
    if b == 228 { return 1; }
    if b == 229 { return 1; }
    if b == 232 { return 4; }                # call rel32
    if b == 233 { return 4; }                # jmp rel32
    if b == 235 { return 1; }                # jmp rel8
    if b == 246 { return 1; }
    if b == 247 { return 4; }
    return 0;
}

# 处理 ModRM/SIB/disp 与 imm，返回相对指令开头的总长度
fn fin(p: i64, i: i64, rex: i64, hm: i64, im: i64) -> i64 {
    let mrm: i64 = 0;
    let mod: i64 = 0;
    let rm: i64 = 0;
    let sib: i64 = 0;
    let base: i64 = 0;
    let disp: i64 = 0;
    let dv: i64 = 0;
    if hm == 1 {
        mrm = gb(p + i);
        mod = mrm >> 6;
        rm = mrm & 7;
        i = i + 1;
        # 🔴 mod == 3 是寄存器直接寻址：既没有 SIB 也没有 disp。
        #    少了这个分支，每条 sub rsp,N（48 81 ec imm32 / 48 83 ec imm8）
        #    都会多算 1 字节 —— 墨语言的每个函数序言都有它，于是扫描从
        #    第一条指令起就整体错位，后面全是乱解。
        if mod == 3 {
            disp = 0;
        } else {
        if rm == 4 {
            sib = gb(p + i);
            base = sib & 7;
            i = i + 1;
            if mod == 1 { disp = 1; }
            if mod == 2 { disp = 4; }
            if mod == 0 {
                if base == 5 { disp = 4; }
            }
        } else {
            if mod == 1 { disp = 1; }
            if mod == 2 { disp = 4; }
            if mod == 0 {
                if rm == 5 { disp = 4; }     # RIP-relative
            }
        }
        if rm == 5 {
            if mod != 0 {
                if (rex & 1) == 0 {
                    if disp == 1 {
                        dv = gb(p + i);
                        if dv >= 128 { dv = dv - 256; }
                        add_rbp(dv);
                    }
                    if disp == 4 {
                        dv = g32(p + i);
                        if dv >= 2147483648 { dv = dv - 4294967296; }
                        add_rbp(dv);
                    }
                }
            }
        }
        }
        i = i + disp;
    }
    i = i + im;
    return i;
}

# 返回一条指令的长度；<=0 表示无法解码
fn ilen(p: i64) -> i64 {
    let i: i64 = 0;
    let rex: i64 = 0;
    let b: i64 = 0;
    let hm: i64 = 0;
    let im: i64 = 0;
    let two: i64 = 0;
    while is_pfx(gb(p + i)) == 1 { i = i + 1; }
    b = gb(p + i);
    if b >= 64 {
        if b <= 79 {
            rex = b;
            i = i + 1;
            b = gb(p + i);
        }
    }
    if b == 15 {
        two = 1;
        i = i + 1;
        b = gb(p + i);
    }
    i = i + 1;
    if two == 1 {
        # 0f 转义：默认有 ModRM、无立即数，特例覆盖
        if b == 56 {                         # 0f 38 xx
            i = i + 1;
            return fin(p, i, rex, 1, 0);
        }
        if b == 58 {                         # 0f 3a xx
            i = i + 1;
            return fin(p, i, rex, 1, 1);
        }
        if b >= 128 {
            if b <= 143 { return fin(p, i, rex, 0, 4); }   # jcc rel32
        }
        if b == 5 { return fin(p, i, rex, 0, 0); }         # syscall
        if b == 11 { return fin(p, i, rex, 0, 0); }        # ud2
        if b == 31 { return fin(p, i, rex, 0, 0); }        # rdtsc
        if b == 162 { return fin(p, i, rex, 0, 0); }       # cpuid
        if b == 30 { return fin(p, i, rex, 0, 0); }        # endbr64-ish
        if b == 55 { return fin(p, i, rex, 0, 0); }
        return fin(p, i, rex, 1, 0);
    }
    hm = has_mrm1(b);
    im = imm1(b, rex);
    # 🔴 group3 (0xf6/0xf7) 只有 /0 /1（test）带立即数；
    #    /2 not /3 neg /4 mul /5 imul /6 div /7 idiv 都不带。
    #    无条件给 imm 会让每条 idiv/neg 之后扫描错位 4 字节，
    #    后面全解成乱指令，直到偶然重新对齐 —— 不报错，只是结果悄悄错。
    if b == 247 {
        if hm == 1 {
            if ((gb(p + i) >> 3) & 7) >= 2 { im = 0; }
        }
    }
    if b == 246 {
        if hm == 1 {
            if ((gb(p + i) >> 3) & 7) >= 2 { im = 0; }
        }
    }
    return fin(p, i, rex, hm, im);
}

# 扫描 [lo,hi)（虚址），收集 [rbp+off]。

# 从 lo 线性扫到 tgt，看是否存在一条指令边界正好落在 tgt。
#
# 🔴 为什么需要这个检查（本轮最重要的发现）：
#   "线性扫描的边界必须精确落在 high_pc" 是**必要但不充分**的。
#   实测：把 mod==3 的分支去掉（1.95 修过的那个 bug），
#   `sub rsp,N` 会多算 1 字节 —— 但扫描**仍然精确落在 high_pc**！
#   原因是解码器会"自同步"：多算 1 字节后，下一条少算 1 字节，
#   两三条之内又对齐了，于是总和对得上，末尾也对得上。
#   只看末尾，这个 bug 会被完全放过。
#
#   所以补一条**独立的结构性不变量**：
#   直接跳转/调用的目标是链接器按真实指令长度算出来的绝对地址，
#   它**不依赖我们的解码器**。目标必须落在我们扫出来的某条指令边界上。
#   解码器一旦错位，边界集合整体偏移，目标就落空。

fn reaches(lo: i64, hi: i64, tgt: i64) -> i64 {
    let off: i64 = S_OFF[I_TEXT] + (lo - S_ADDR[I_TEXT]);
    let end: i64 = S_OFF[I_TEXT] + (hi - S_ADDR[I_TEXT]);
    let t: i64 = S_OFF[I_TEXT] + (tgt - S_ADDR[I_TEXT]);
    let p: i64 = off;
    let l: i64 = 0;
    if t < off { return 0; }
    if t > end { return 0; }
    while p < t {
        l = ilen(p);
        if l <= 0 { return 0 - 1; }
        p = p + l;
    }
    if p == t { return 1; }
    return 0;
}

# 判断一条指令是不是"带相对目标的跳转/调用"，是则返回目标地址，否则返回 0
fn br_target(p: i64, l: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = 0;
    let rel: i64 = 0;
    while is_pfx(gb(p + i)) == 1 { i = i + 1; }
    b = gb(p + i);
    if b >= 64 {
        if b <= 79 { i = i + 1; b = gb(p + i); }
    }
    if b == 232 {
        rel = g32(p + l - 4);
        if rel >= 2147483648 { rel = rel - 4294967296; }
        return p + l + rel;
    }
    if b == 233 {
        rel = g32(p + l - 4);
        if rel >= 2147483648 { rel = rel - 4294967296; }
        return p + l + rel;
    }
    if b == 235 {
        rel = gb(p + l - 1);
        if rel >= 128 { rel = rel - 256; }
        return p + l + rel;
    }
    if b >= 112 {
        if b <= 127 {
            rel = gb(p + l - 1);
            if rel >= 128 { rel = rel - 256; }
            return p + l + rel;
        }
    }
    if b >= 224 {
        if b <= 227 {
            rel = gb(p + l - 1);
            if rel >= 128 { rel = rel - 256; }
            return p + l + rel;
        }
    }
    if b == 227 { }
    if b == 15 {
        b = gb(p + i + 1);
        if b >= 128 {
            if b <= 143 {
                rel = g32(p + l - 4);
                if rel >= 2147483648 { rel = rel - 4294967296; }
                return p + l + rel;
            }
        }
    }
    return 0;
}

# 返回 0 正常；-1 遇到无法解码的指令；-2 指令边界未落在函数末尾。
fn scan(lo: i64, hi: i64) -> i64 {
    let off: i64 = S_OFF[I_TEXT] + (lo - S_ADDR[I_TEXT]);
    let end: i64 = S_OFF[I_TEXT] + (hi - S_ADDR[I_TEXT]);
    let p: i64 = off;
    let l: i64 = 0;
    let ta: i64 = 0;
    RBP_N = 0;
    while p < end {
        l = ilen(p);
        if l <= 0 { return 0 - 1; }
        if br_target(p, l) != 0 {
            ta = S_ADDR[I_TEXT] + (br_target(p, l) - S_OFF[I_TEXT]);
            SC_NBR = SC_NBR + 1;
            if ta >= lo {
                if ta < hi {
                    if reaches(lo, hi, ta) != 1 { SC_NBD = SC_NBD + 1; }
                }
            }
        }
        p = p + l;
        SC_NI = SC_NI + 1;
        SC_NB = SC_NB + l;
    }
    SC_NR = SC_NR + RBP_N;
    if p != end { return 0 - 2; }
    return 0;
}

# ================= .debug_line =================
#
# 为什么值得单独做：.debug_info 里的 DW_AT_decl_line 说"函数定义在第几行"，
# 而 .debug_line 说"哪个地址属于第几行"。这是两个**独立生成**的通道 ——
# 前者在解析 fn 时记下 K_LINE，后者靠 dbg_mark() 在语句边界登记。
# 两者对不上，gdb 就在函数定义行下不了断点，而**编译和运行都不会报错**。
#
# 这里实现完整的 DWARF 行号程序状态机（含 special opcode），
# 而不是只解析自己生成的那三种操作码 —— 否则将来改用 special opcode
# 时，这个校验器会一起错，那就不是独立参照了。

fn build_fns() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let best: i64 = 0;
    let bv: i64 = 0;
    let tmp: i64 = 0;
    NFN = 0;
    i = 0;
    while i < ND {
        if D_TAG[i] == 46 {
            if D_HI[i] > D_LO[i] {
                if D_LO[i] != 0 {
                    if NFN < 4096 {
                        FI[NFN] = i;
                        NFN = NFN + 1;
                    }
                }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < NFN {
        best = i;
        bv = D_LO[FI[i]];
        j = i + 1;
        while j < NFN {
            if D_LO[FI[j]] < bv {
                bv = D_LO[FI[j]];
                best = j;
            }
            j = j + 1;
        }
        tmp = FI[i];
        FI[i] = FI[best];
        FI[best] = tmp;
        i = i + 1;
    }
    i = 0;
    while i < NFN {
        FN_LO[i] = D_LO[FI[i]];
        FN_HI[i] = D_HI[FI[i]];
        FN_NR[i] = 0;
        FN_HIT[i] = 0;
        i = i + 1;
    }
    return 0;
}

fn fn_of(a: i64) -> i64 {
    let lo: i64 = 0;
    let hi: i64 = 0;
    let m: i64 = 0;
    hi = NFN;
    while lo < hi {
        m = (lo + hi) / 2;
        if FN_LO[m] <= a { lo = m + 1; }
        if FN_LO[m] > a { hi = m; }
    }
    if lo == 0 { return 0 - 1; }
    if a < FN_HI[lo - 1] { return lo - 1; }
    return 0 - 1;
}

fn add_row(ad: i64, ln: i64, fn: i64) -> i64 {
    let ta: i64 = 0;
    let te: i64 = 0;
    let f: i64 = 0;
    if NL >= MAXL {
        print("dwmo: 容量不足 —— 行号表记录数超过上限 ");
        print_i64(MAXL);
        print_nl();
        CAPERR = 1;
        return 0 - 1;
    }
    ta = S_ADDR[I_TEXT];
    te = ta + S_SIZE[I_TEXT];
    if ad < ta { LN_BADTXT = LN_BADTXT + 1; }
    if ad >= te { LN_BADTXT = LN_BADTXT + 1; }
    if NL > 0 {
        if ad < L_AD[NL - 1] { LN_BADSORT = LN_BADSORT + 1; }
    }
    if ln > LN_MAXL { LN_MAXL = ln; }
    f = fn_of(ad);
    if f < 0 {
        LN_BADOOB = LN_BADOOB + 1;
    } else {
        FN_NR[f] = FN_NR[f] + 1;
    }
    if fn < 1 { LN_BADFILE = LN_BADFILE + 1; }
    else {
        if fn > NFT { LN_BADFILE = LN_BADFILE + 1; }
        else { FT_ROWS[fn - 1] = FT_ROWS[fn - 1] + 1; }
    }
    L_AD[NL] = ad;
    L_LN[NL] = ln;
    L_FN[NL] = fn;
    NL = NL + 1;
    return 0;
}

fn parse_line() -> i64 {
    let p: i64 = 0;
    let e: i64 = 0;
    let hl: i64 = 0;
    let h: i64 = 0;
    let minil: i64 = 0;
    let lbase: i64 = 0;
    let lrange: i64 = 0;
    let opbase: i64 = 0;
    let n: i64 = 0;
    let q: i64 = 0;
    let op: i64 = 0;
    let addr: i64 = 0;
    let line: i64 = 0;
    let adj: i64 = 0;
    let adv: i64 = 0;
    let ln: i64 = 0;
    let sub: i64 = 0;
    let v: i64 = 0;
    let i: i64 = 0;
    let r: i64 = 0;
    NL = 0;
    LN_NSEQ = 0;
    LN_END = 0;
    LN_MAXL = 0;
    LN_BADTXT = 0;
    LN_BADSORT = 0;
    LN_BADOOB = 0;
    LN_COV = 0;
    p = S_OFF[I_LINE];
    e = p + S_SIZE[I_LINE];
    hl = g32(p + 6);
    h = p + 10;
    minil = gb(h);
    lbase = gb(h + 3);
    # line_base 是有符号字节：251 表示 -5
    if lbase > 127 { lbase = lbase - 256; }
    lrange = gb(h + 4);
    opbase = gb(h + 5);
    i = 0;
    while i < 16 {
        SOL[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < opbase - 1 {
        if i < 16 { SOL[i] = gb(h + 6 + i); }
        i = i + 1;
    }
    # ---- header 尾部的 include_directories + file_names ----
    # 之前 dwmo 直接跳到 h+hl 开始解程序，等于**从不看文件表**：
    # 于是"行号记录指向的文件编号是否有效"这件事一直没被校验。
    let hp: i64 = h + 6 + (opbase - 1);
    let j: i64 = 0;
    while gb(hp) != 0 {
        while gb(hp) != 0 { hp = hp + 1; }
        hp = hp + 1;
    }
    hp = hp + 1;
    NFT = 0;
    FNB = 0;
    while gb(hp) != 0 {
        if NFT < 32 {
            FT_NM[NFT] = FNB;
            j = 0;
            while gb(hp + j) != 0 {
                if FNB < 2040 {
                    store8(&FNBUF + FNB, gb(hp + j));
                    FNB = FNB + 1;
                }
                j = j + 1;
            }
            store8(&FNBUF + FNB, 0);
            FNB = FNB + 1;
            NFT = NFT + 1;
        }
        while gb(hp) != 0 { hp = hp + 1; }
        hp = hp + 1;
        # dir / mtime / length：ULEB，不是固定一字节
        guleb(hp); hp = ULEB_P;
        guleb(hp); hp = ULEB_P;
        guleb(hp); hp = ULEB_P;
    }
    i = 0;
    while i < 32 { FT_ROWS[i] = 0; i = i + 1; }
    q = h + hl;
    addr = 0;
    line = 1;
    let cfile: i64 = 1;
    while q < e {
        op = gb(q);
        q = q + 1;
        if op >= opbase {
            adj = op - opbase;
            adv = adj / lrange;
            addr = addr + adv * minil;
            line = line + lbase + (adj - adv * lrange);
            r = add_row(addr, line, cfile);
            if r != 0 { return r; }
        }
        if op == 0 {
            guleb(q);
            ln = ULEB_V;
            q = ULEB_P;
            sub = gb(q);
            q = q + 1;
            if sub == 1 {
                LN_NSEQ = LN_NSEQ + 1;
                LN_END = addr;
                addr = 0;
                line = 1;
                cfile = 1;
            }
            if sub == 2 {
                addr = g64(q);
                q = q + 8;
            }
            if sub != 1 {
                if sub != 2 { q = q + ln - 1; }
            }
        }
        if op == 1 {
            r = add_row(addr, line, cfile);
            if r != 0 { return r; }
        }
        if op == 2 {
            guleb(q);
            v = ULEB_V;
            q = ULEB_P;
            addr = addr + v * minil;
        }
        if op == 3 {
            gsleb(q);
            v = SLEB_V;
            q = SLEB_P;
            line = line + v;
        }
        if op == 4 {
            guleb(q);
            cfile = ULEB_V;
            q = ULEB_P;
        }
        if op == 5 {
            guleb(q);
            q = ULEB_P;
        }
        if op == 8 {
            adv = (255 - opbase) / lrange;
            addr = addr + adv * minil;
        }
        if op == 9 {
            v = g16(q);
            q = q + 2;
            addr = addr + v;
        }
        if op > 11 {
            n = 0;
            if op < 16 { n = SOL[op]; }
            i = 0;
            while i < n {
                guleb(q);
                q = ULEB_P;
                i = i + 1;
            }
        }
    }
    if NL > 0 {
        LN_COV = LN_END - L_AD[0];
    }
    return 0;
}

fn line_report() -> i64 {
    let i: i64 = 0;
    let f: i64 = 0;
    let te: i64 = 0;
    let cov: i64 = 0;
    te = S_ADDR[I_TEXT] + S_SIZE[I_TEXT];
    LN_FNNOROW = 0;
    LN_FNMISS = 0;
    FN_ENTF = alloc((NFN + 4) * 8);
    if FN_ENTF == 0 { print("dwmo: 入口文件表分配失败\n"); return 1; }
    i = 0;
    while i < NFN + 2 { store64(FN_ENTF + i * 8, 0); i = i + 1; }
    i = 0;
    while i < NL {
        f = fn_of(L_AD[i]);
        if f >= 0 {
            if L_LN[i] == D_LINE[FI[f]] { FN_HIT[f] = 1; }
            if L_AD[i] == FN_LO[f] {
                if load64(FN_ENTF + f * 8) == 0 { store64(FN_ENTF + f * 8, L_FN[i]); }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < NFN {
        if FN_NR[i] == 0 { LN_FNNOROW = LN_FNNOROW + 1; }
        if FN_HIT[i] == 0 { LN_FNMISS = LN_FNMISS + 1; }
        i = i + 1;
    }
    LN_NOFILE = 0;
    i = 0;
    while i < NFT {
        if FT_ROWS[i] == 0 { LN_NOFILE = LN_NOFILE + 1; }
        i = i + 1;
    }
    # 两条独立通道的交叉校验：
    #   decl_file 写在 DIE 里，入口行号记录写在 .debug_line 里。
    #   只查其中一条，另一条错了照样通过（1.99 已经验证过一次：
    #   行号表整体 +1 时，所有 decl_line 相关的检查依然全绿）。
    LN_FNBADF = 0;
    LN_FNNOF = 0;
    i = 0;
    while i < NFN {
        if D_FILE[FI[i]] < 1 { LN_FNNOF = LN_FNNOF + 1; }
        else {
            if load64(FN_ENTF + i * 8) != D_FILE[FI[i]] { LN_FNBADF = LN_FNBADF + 1; }
        }
        i = i + 1;
    }
    print("== .debug_line 行号表 ==");
    print_nl();
    print("  函数数                  ");
    print_i64(NFN);
    print_nl();
    print("  行号记录数              ");
    print_i64(NL);
    print_nl();
    print("  sequence 数             ");
    print_i64(LN_NSEQ);
    print_nl();
    print("  最大行号                ");
    print_i64(LN_MAXL);
    print_nl();
    print("  覆盖 .text 字节         ");
    print_i64(LN_COV);
    print("  / ");
    print_i64(S_SIZE[I_TEXT]);
    print_nl();
    if LN_COV > 0 {
        cov = LN_COV * 100 / S_SIZE[I_TEXT];
        print("  覆盖率                  ");
        print_i64(cov);
        print("%");
        print_nl();
    }
    print("  end_sequence 地址       ");
    print_i64(LN_END);
    print_nl();
    print("  .text 结束地址          ");
    print_i64(te);
    print_nl();
    print("  地址不在 .text 内       ");
    print_i64(LN_BADTXT);
    print_nl();
    print("  地址非递增              ");
    print_i64(LN_BADSORT);
    print_nl();
    print("  地址不在任何函数内      ");
    print_i64(LN_BADOOB);
    print_nl();
    print("  无任何行号记录的函数    ");
    print_i64(LN_FNNOROW);
    print_nl();
    print("  定义行缺失的函数        ");
    print_i64(LN_FNMISS);
    print_nl();
    print("  文件表条目数            ");
    print_i64(NFT);
    print_nl();
    i = 0;
    while i < NFT {
        print("    [");
        print_i64(i + 1);
        print("] ");
        print(&FNBUF + FT_NM[i]);
        print("  记录 ");
        print_i64(FT_ROWS[i]);
        print_nl();
        i = i + 1;
    }
    print("  文件编号越界的记录      ");
    print_i64(LN_BADFILE);
    print_nl();
    print("  表里有却零记录的文件    ");
    print_i64(LN_NOFILE);
    print_nl();
    print("  decl_file 缺失的函数    ");
    print_i64(LN_FNNOF);
    print_nl();
    print("  decl_file 与入口行文件不一致 ");
    print_i64(LN_FNBADF);
    print_nl();
    chk(NL > 0, "解析出行号记录", "一条都没有 —— 节定位或状态机有问题");
    chk(LN_NSEQ > 0, "行号程序以 end_sequence 正常收尾", "没有 end_sequence");
    chk(LN_BADTXT == 0, "所有行号地址都落在 .text 内", "有地址越出代码段 —— 基址算错");
    chk(LN_BADSORT == 0, "行号地址单调递增", "地址回退 —— 状态机或 advance_pc 处理错");
    chk(LN_BADOOB == 0, "每条行号记录都落在某个函数 [lo,hi) 内", "有记录落在函数之间的空隙 —— 地址与函数边界不一致");
    chk(LN_END == te, "end_sequence 地址 == 代码末尾", "行号表没覆盖到最后一条指令");
    chk(LN_FNNOROW == 0, "每个函数都至少有一条行号记录", "有函数完全没有行号 —— 里面下不了断点");
    chk(NFT > 0, "解析出 file_names 表", "文件表为空 —— header 解析或表终止判断错");
    chk(LN_BADFILE == 0, "每条记录的文件编号都在文件表内", "有记录指向不存在的文件 —— set_file 或文件表生成错");
    chk(LN_NOFILE == 0, "文件表里每个文件都真的被用到", "有文件在表里却零记录 —— 它的代码没有行号");
    chk(LN_FNNOF == 0, "每个函数都有 decl_file", "有函数缺 DW_AT_decl_file —— 库函数会被当成主文件的");
    chk(LN_FNBADF == 0, "函数 decl_file == 入口行号记录的文件", "两条通道对不上 —— 断点和 bt 会落在错误的文件");
    chk(LN_FNMISS == 0, "每个函数的定义行都出现在自己的行号记录里", "有函数的定义行不在行号表里 —— gdb 在该行下不了断点");
    return 0;
}

# ================= 源码交叉校验（-L <source>） =================
#
# 为什么需要这一层：
#   到此为止的所有检查都在 DWARF **内部**打转 —— 地址对不对、边界对
#   不对、定义行有没有记录。但行号是编译器自己报的、行号表也是编译器
#   自己生成的，两相比对只能证明"自洽"，证明不了"对得上源码"。
#
#   典型漏网：某个行号整体偏移 1。地址仍然单调、仍然落在函数内、
#   覆盖率仍然 100%、end_sequence 仍然精确相等 —— **全项通过**，
#   而 gdb 会稳稳地停在上一行。1.98 那个"函数定义行下不了断点"就是
#   靠 readelf 外部参照才发现的，不是靠内部断言。
#
#   把源文件喂进来后能做真正语义级的校验，三条都不依赖任何外部工具：
#     1. 行号不能超过源文件行数
#     2. 行号不能指向空白行 / 纯注释行 —— 那种行不可能生成代码
#     3. 函数的定义行（decl_line）必须真的是 fn 那一行
#
# 为什么不用全局变量数组存行表：源文件行数未知（compiler.mo 有 7878 行），
# 且全局区已经接近上限（1.94 踩过"全局数据接近 1MB 时符号表静默损坏"），
# 所以行表走堆。

fn src_load(path: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let ln: i64 = 1;
    SRC = alloc(3145728);
    if SRC == 0 { print("dwmo: 源码缓冲区分配失败\n"); return 1; }
    SRC_SZ = read_file(path, SRC, 3145728);
    if SRC_SZ <= 0 {
        print("dwmo: 无法读取源码 ");
        print(path);
        print_nl();
        return 1;
    }
    n = 1;
    i = 0;
    while i < SRC_SZ {
        if load8(SRC + i) == 10 { n = n + 1; }
        i = i + 1;
    }
    SRC_N = n;
    SRC_OFF = alloc((SRC_N + 4) * 8);
    SRC_HIT = alloc((SRC_N + 4) * 8);
    SRC_TMP = alloc(1024);
    if SRC_OFF == 0 { print("dwmo: 行表分配失败\n"); return 1; }
    if SRC_HIT == 0 { print("dwmo: 行表分配失败\n"); return 1; }
    if SRC_TMP == 0 { print("dwmo: 行表分配失败\n"); return 1; }
    store64(SRC_OFF + 8, 0);
    ln = 1;
    i = 0;
    while i < SRC_SZ {
        if load8(SRC + i) == 10 {
            ln = ln + 1;
            store64(SRC_OFF + ln * 8, i + 1);
        }
        i = i + 1;
    }
    store64(SRC_OFF + (SRC_N + 1) * 8, SRC_SZ);
    i = 0;
    while i <= SRC_N + 2 {
        store64(SRC_HIT + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

# 该行是"代码行"吗：0 = 空白行或纯注释行（不可能生成代码），1 = 有代码
fn src_kind(ln: i64) -> i64 {
    let p: i64 = 0;
    let e: i64 = 0;
    let c: i64 = 0;
    if ln < 1 { return 0; }
    if ln > SRC_N { return 0; }
    p = load64(SRC_OFF + ln * 8);
    e = load64(SRC_OFF + (ln + 1) * 8);
    while p < e {
        c = load8(SRC + p);
        if is_space(c) == 0 { break; }
        p = p + 1;
    }
    if p >= e { return 0; }
    if load8(SRC + p) == 35 { return 0; }
    return 1;
}

# 把第 ln 行拷进 SRC_TMP（NUL 结尾，最多 200 字节），供匹配/打印复用
fn src_line_tmp(ln: i64) -> i64 {
    let p: i64 = 0;
    let e: i64 = 0;
    let j: i64 = 0;
    if ln < 1 { store8(SRC_TMP, 0); return 0; }
    if ln > SRC_N { store8(SRC_TMP, 0); return 0; }
    p = load64(SRC_OFF + ln * 8);
    e = load64(SRC_OFF + (ln + 1) * 8);
    j = 0;
    while p < e {
        if j >= 200 { break; }
        if load8(SRC + p) == 10 { break; }
        store8(SRC_TMP + j, load8(SRC + p));
        j = j + 1;
        p = p + 1;
    }
    store8(SRC_TMP + j, 0);
    return 0;
}

# 该行是否含 needle。
# 🔴 strstr 返回的是**下标**，找不到才返回 -1 —— 命中在行首时返回 0，
#    所以绝不能用 `if strstr(...) != 0` 判断"找到了"，那会漏掉所有
#    出现在行首的匹配。
fn src_has(ln: i64, needle: i64) -> i64 {
    src_line_tmp(ln);
    if strstr(SRC_TMP, needle) < 0 { return 0; }
    return 1;
}

fn src_check() -> i64 {
    let i: i64 = 0;
    let ln: i64 = 0;
    let f: i64 = 0;
    S_OOB = 0;
    S_BADKIND = 0;
    S_DECLN = 0;
    S_DECLBAD = 0;
    S_SHOWN = 0;
    S_CODE = 0;
    S_MISS = 0;
    S_MISSFN = 0;
    S_SHOW2 = 0;
    S_NAMEBAD = 0;
    S_ENTN = 0;
    S_ENTBAD = 0;
    # 入口记录走堆：NFN 已知但仍在涨，且全局区已接近上限
    FN_ENT = alloc((NFN + 4) * 8);
    FN_ENTLN = alloc((NFN + 4) * 8);
    if FN_ENT == 0 { print("dwmo: 入口表分配失败\n"); return 1; }
    if FN_ENTLN == 0 { print("dwmo: 入口表分配失败\n"); return 1; }
    i = 0;
    while i < NFN + 2 {
        store64(FN_ENT + i * 8, 0);
        store64(FN_ENTLN + i * 8, 0);
        i = i + 1;
    }
    i = 0;
    while i < NL {
        ln = L_LN[i];
        f = fn_of(L_AD[i]);
        if f >= 0 {
            if L_AD[i] == FN_LO[f] {
                if load64(FN_ENT + f * 8) == 0 {
                    store64(FN_ENT + f * 8, 1);
                    store64(FN_ENTLN + f * 8, ln);
                }
            }
        }
        if ln < 1 { S_OOB = S_OOB + 1; }
        else {
            if ln > SRC_N { S_OOB = S_OOB + 1; }
            else {
                store64(SRC_HIT + ln * 8, 1);
                if src_kind(ln) == 0 {
                    S_BADKIND = S_BADKIND + 1;
                    if S_SHOWN < 6 {
                        print("  [!!] 行号指向非代码行: 行 ");
                        print_i64(ln);
                        print("  >> ");
                        src_line_tmp(ln);
                        print(SRC_TMP);
                        print_nl();
                        S_SHOWN = S_SHOWN + 1;
                    }
                }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < NFN {
        f = FI[i];
        ln = D_LINE[f];
        if ln > 0 {
            S_DECLN = S_DECLN + 1;
            if src_has(ln, BUF + D_NM[f]) == 0 {
                S_NAMEBAD = S_NAMEBAD + 1;
                if S_SHOWN < 12 {
                    print("  [!!] 定义行里没有该函数名: ");
                    print(BUF + D_NM[f]);
                    print(" 行 ");
                    print_i64(ln);
                    print("  >> ");
                    src_line_tmp(ln);
                    print(SRC_TMP);
                    print_nl();
                    S_SHOWN = S_SHOWN + 1;
                }
            }
            if src_has(ln, "fn ") == 0 {
                S_DECLBAD = S_DECLBAD + 1;
                if S_SHOWN < 12 {
                    print("  [!!] 定义行不是 fn 行: ");
                    # D_NM 存的是 .debug_str 里的**偏移**，不是地址
                    print(BUF + D_NM[f]);
                    print(" 行 ");
                    print_i64(ln);
                    print("  >> ");
                    src_line_tmp(ln);
                    print(SRC_TMP);
                    print_nl();
                    S_SHOWN = S_SHOWN + 1;
                }
            }
        }
        i = i + 1;
    }
    # 入口记录的行号必须含该函数名 —— 这条不依赖 decl_line 属性。
    # 两个通道是独立生成的：decl_line 写进 DIE，行号表另写一份。
    # 只查 decl_line 的话，行号表整体错位照样通过（实测过）。
    i = 0;
    while i < NFN {
        if load64(FN_ENT + i * 8) == 1 {
            S_ENTN = S_ENTN + 1;
            ln = load64(FN_ENTLN + i * 8);
            if src_has(ln, BUF + D_NM[FI[i]]) == 0 {
                S_ENTBAD = S_ENTBAD + 1;
                if S_SHOWN < 16 {
                    print("  [!!] 入口行号记录里没有该函数名: ");
                    print(BUF + D_NM[FI[i]]);
                    print(" 行 ");
                    print_i64(ln);
                    print("  >> ");
                    src_line_tmp(ln);
                    print(SRC_TMP);
                    print_nl();
                    S_SHOWN = S_SHOWN + 1;
                }
            }
        }
        i = i + 1;
    }
    i = 1;
    while i <= SRC_N {
        if src_kind(i) == 1 {
            S_CODE = S_CODE + 1;
            if load64(SRC_HIT + i * 8) == 0 {
                S_MISS = S_MISS + 1;
                # 未覆盖的行里有没有"看起来像函数定义"的 —— 那才是可疑的。
                # 其余（var 声明、类型定义）本来就不生成代码，属正常。
                if src_has(i, "fn ") == 1 {
                    S_MISSFN = S_MISSFN + 1;
                    if S_SHOW2 < 8 {
                        print("  [!!] 疑似漏登记的函数定义行: 行 ");
                        print_i64(i);
                        print("  >> ");
                        src_line_tmp(i);
                        print(SRC_TMP);
                        print_nl();
                        S_SHOW2 = S_SHOW2 + 1;
                    }
                }
            }
        }
        i = i + 1;
    }
    print("== 源码交叉校验（-L）==");
    print_nl();
    print("  源文件行数              ");
    print_i64(SRC_N);
    print_nl();
    print("  其中代码行              ");
    print_i64(S_CODE);
    print_nl();
    print("  行号越界                ");
    print_i64(S_OOB);
    print_nl();
    print("  行号指向空白/注释行     ");
    print_i64(S_BADKIND);
    print_nl();
    print("  有入口行号记录的函数    ");
    print_i64(S_ENTN);
    print_nl();
    print("  入口行号里没有函数名    ");
    print_i64(S_ENTBAD);
    print_nl();
    print("  定义行里没有该函数名    ");
    print_i64(S_NAMEBAD);
    print_nl();
    print("  定义行不是 fn 行        ");
    print_i64(S_DECLBAD);
    print("  / ");
    print_i64(S_DECLN);
    print_nl();
    print("  代码行未被行号表覆盖    ");
    print_i64(S_MISS);
    print_nl();
    print("  其中疑似函数定义行      ");
    print_i64(S_MISSFN);
    print_nl();
    chk(SRC_N > 0, "源文件解析出行", "一行都没有 —— 读文件失败或没有换行");
    chk(S_CODE > 0, "源文件里有代码行", "一个代码行都没有 —— 源码路径给错或分类写错");
    chk(S_OOB == 0, "所有行号都在源文件行数范围内", "有行号超过源文件行数 —— 行号基址算错");
    chk(S_BADKIND == 0, "没有行号指向空白行或纯注释行", "那种行不可能生成代码 —— 行号登记错行");
    chk(S_DECLN > 0, "确实检查过函数的定义行", "没检查到任何 decl_line —— 覆盖面为零");
    chk(S_DECLBAD == 0, "每个函数的定义行都真的是 fn 那一行", "decl_line 与源码不符 —— 断点会停错地方");
    chk(S_NAMEBAD == 0, "每个函数的定义行里都有它自己的名字", "行号对但是函数错位 —— decl_line 挂到了别的函数上");
    chk(S_MISSFN == 0, "源码里没有漏登记的函数定义行", "有 fn 行从未出现在行号表里 —— 那里面下不了断点");
    chk(S_ENTN > 0, "确实找到了函数的入口行号记录", "一个都没有 —— 入口登记或地址比对有问题");
    chk(S_ENTBAD == 0, "函数入口的行号记录里确实写着这个函数", "行号表与 decl_line 是两条独立通道 —— 这条专查行号表那一份");
    return 0;
}

# ================= .debug_frame =================
fn parse_frame() -> i64 {
    let p: i64 = S_OFF[I_FRAME];
    let e: i64 = p + S_SIZE[I_FRAME];
    let len: i64 = 0;
    let id: i64 = 0;
    let q: i64 = 0;
    let fe: i64 = 0;
    let op: i64 = 0;
    let adv: i64 = 0;
    let reg: i64 = 0;
    NFDE = 0;
    while p < e {
        len = g32(p);
        if len == 0 { break; }
        id = g32(p + 4);
        if id == 4294967295 {
            p = p + 4 + len;                # CIE：本实现不需要它的内容
        } else {
            if NFDE >= MAXF {
                print("dwmo: 容量不足 —— FDE 数超过上限 ");
                print_i64(MAXF);
                print_nl();
                CAPERR = 1;
                return 0 - 1;
            }
            q = p + 8;
            F_LO[NFDE] = g64(q);
            F_HI[NFDE] = g64(q + 8);
            q = q + 16;
            fe = p + 4 + len;
            reg = 0;
            while q < fe {
                op = gb(q);
                adv = 1;
                if (op & 192) == 64 { adv = 1; }
                if op == 1 { adv = 2; }
                if op == 2 { adv = 3; }
                if op == 3 { adv = 5; }
                if op == 12 {
                    guleb(q + 1);
                    reg = ULEB_V;
                    guleb(ULEB_P);
                    adv = ULEB_P - q;
                }
                if op == 13 {
                    guleb(q + 1);
                    reg = ULEB_V;
                    adv = ULEB_P - q;
                }
                if op == 14 {
                    guleb(q + 1);
                    adv = ULEB_P - q;
                }
                if op == 15 {
                    guleb(q + 1);
                    adv = ULEB_P + ULEB_V - q;
                }
                if (op & 192) == 128 {
                    guleb(q + 1);
                    adv = ULEB_P - q;
                }
                q = q + adv;
            }
            F_CFA[NFDE] = reg;
            NFDE = NFDE + 1;
        }
        if id != 4294967295 {
            p = p + 4 + len;
        }
    }
fn die_nm_eq(i: i64, nm: i64) -> i64 {
    if D_NM[i] == 0 { return 0; }
    if streq(BUF + D_NM[i], nm) == 1 { return 1; }
    return 0;
}

fn find_tag_nm(tag: i64, nm: i64) -> i64 {
    let i: i64 = 0;
    while i < ND {
        if D_TAG[i] == tag {
            if die_nm_eq(i, nm) == 1 { return i; }
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn chk(ok: i64, nm: i64, info: i64) -> i64 {
    if ok != 0 {
        PASS = PASS + 1;
        print("  OK  ");
        print(nm);
        print_nl();
        return 0;
    }
    FAIL = FAIL + 1;
    print("  BAD ");
    print(nm);
    print("  <<< ");
    print(info);
    print_nl();
    return 0;
}

}

# ============================================================
#  modb：墨语言自己写的调试器
#
#  为什么必须自己写：
#    编译器、链接器、包管理器、LSP 都已经是墨语言写的了，唯独
#    "调试器"这一环还依赖外部工具。调试信息（-g）是自家的，
#    能读它的调试器却不是 —— 自包含生态在这一环是断的。
#
#  能力：ptrace 起停目标进程、按行号/函数名下断点、单步、继续、
#        回溯调用栈、按 DWARF 的 fbreg 偏移读局部变量。
#  全程不借 gdb、不借 libc。
#
#  用法：modb <prog.elf> [-x <命令文件>]
#        不给 -x 时从标准输入逐行读命令。
# ============================================================

var MAXBP: i64 = 32;
var NBP: i64 = 0;
var BP_AD: [32] i64 = 0;
var BP_ORG: [32] i64 = 0;      # 被 int3 覆盖前的原始字节
var BP_ON: [32] i64 = 0;       # 1 = int3 已写入
var BP_HAS: [32] i64 = 0;      # 1 = 该断点带条件（b ... if <expr>）
var BPC: [3072] byte = 0;      # 条件表达式文本：32 个断点 × 96 字节
var NCSKIP: i64 = 0;           # 命中但条件不满足、被自动放过的次数
var CHIT: i64 = 0;             # 本次停止：1=断点命中(条件满足) 0=命中但条件不满足 -1=非断点
var LASTSTEP: i64 = 0;         # 1 = 这次停止来自单步（单步撞上 int3 不算命中）
var QUIET: i64 = 0;            # 1 = 抑制停止信息（观察点单步时用）

# ---------- 条件表达式求值 ----------
var EVP: i64 = 0;              # 扫描位置
var EV_ERR: i64 = 0;           # 1 = 表达式有错（未知名字 / 括号不配对 / 末尾多余字符）
var EV_NCMP: i64 = 0;          # 已求值的比较运算符个数，eval_cond 用它挡住裸变量
var EVNAME: [64] byte = 0;
var VL_OK: i64 = 0;            # vl_find 是否找到

# ---------- 观察点 ----------
var WNAME: [64] byte = 0;
var WHAS: i64 = 0;
var WV0: i64 = 0;
var MAXW: i64 = 200000;        # 软件观察点的单步上限

var CHILD: i64 = 0;
var RUNNING: i64 = 0;          # 1 = 子进程已启动
var EXITED: i64 = 0;
var HITBP: i64 = 0;
var NSTEP: i64 = 0;
var NHIT: i64 = 0;
var QUIT: i64 = 0;

var REGS: [32] i64 = 0;        # user_regs_struct：rip=[16] rbp=[4] rax=[10]
var WST: [4] i64 = 0;
var PROGP: [256] byte = 0;
var CMDP: [256] byte = 0;
var LNCMD: [256] byte = 0;
var CMDB: i64 = 0;
var CURF: i64 = 1;
var MEMFD: i64 = 0;
var MEMP: [64] byte = 0;      # 行号所属的文件编号（文件表里 1 = 主文件）

# ---------- ptrace / wait ----------

fn pt(req: i64, pid: i64, addr: i64, data: i64) -> i64 {
    return syscall(101, req, pid, addr, data, 0, 0);
}

fn wait_child() -> i64 {
    return syscall(61, CHILD, &WST, 0, 0, 0, 0);
}

fn get_regs() -> i64 { return pt(12, CHILD, 0, &REGS); }
fn set_regs() -> i64 { return pt(13, CHILD, 0, &REGS); }
fn get_rip() -> i64 { return REGS[16]; }
fn get_rbp() -> i64 { return REGS[4]; }

# 🔴 为什么内存读写走 /proc/<pid>/mem 而不是 PTRACE_PEEKDATA：
#    实测 ptrace 的 PEEKDATA（request=2）在这条 syscall 通道上一律返回
#    -14（EFAULT），而同样地址的 POKEDATA 却生效 —— 断点确实命中。
#    即"写通、读不通"，是本项目最阴的一类错：表面上功能（下断点）
#    完全正常，只有读数全是无意义的负值。
#    /proc/<pid>/mem 是 tracer 的等效通道，且没有 8 字节对齐限制。
fn mem_open() -> i64 {
    let i: i64 = 0;
    store8(&MEMP, 47);
    store8(&MEMP + 1, 112);
    store8(&MEMP + 2, 114);
    store8(&MEMP + 3, 111);
    store8(&MEMP + 4, 99);
    store8(&MEMP + 5, 47);
    utoa(CHILD, &MEMP + 6, 10);
    while load8(&MEMP + 6 + i) != 0 { i = i + 1; }
    store8(&MEMP + 6 + i, 47);
    store8(&MEMP + 7 + i, 109);
    store8(&MEMP + 8 + i, 101);
    store8(&MEMP + 9 + i, 109);
    store8(&MEMP + 10 + i, 0);
    MEMFD = fopen(&MEMP, 2, 0);
    if MEMFD < 0 {
        print("modb: 无法打开 ");
        print(&MEMP);
        print_nl();
        return 0 - 1;
    }
    return 0;
}

fn peek8(a: i64) -> i64 {
    let c: i64 = 0;
    syscall(8, MEMFD, a, 0, 0, 0, 0);
    syscall(0, MEMFD, &c, 1, 0, 0, 0);
    return c;
}

fn poke8(a: i64, b: i64) -> i64 {
    let c: i64 = b & 255;
    syscall(8, MEMFD, a, 0, 0, 0, 0);
    return syscall(1, MEMFD, &c, 1, 0, 0, 0);
}

fn rdmem(a: i64) -> i64 {
    let v: i64 = 0;
    syscall(8, MEMFD, a, 0, 0, 0, 0);
    syscall(0, MEMFD, &v, 8, 0, 0, 0);
    return v;
}

# ---------- 断点 ----------

fn bp_find(a: i64) -> i64 {
    let i: i64 = 0;
    while i < NBP {
        if BP_AD[i] == a { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn bp_add(a: i64) -> i64 {
    let i: i64 = bp_find(a);
    if i >= 0 { return i; }
    if NBP >= MAXBP {
        print("modb: 断点已达上限 32\n");
        return 0 - 1;
    }
    BP_AD[NBP] = a;
    BP_ORG[NBP] = 0;
    BP_ON[NBP] = 0;
    i = NBP;
    NBP = NBP + 1;
    return i;
}

fn bp_insert(i: i64) -> i64 {
    if i < 0 { return 0 - 1; }
    if BP_ON[i] == 1 { return 0; }
    BP_ORG[i] = peek8(BP_AD[i]);
    poke8(BP_AD[i], 204);
    BP_ON[i] = 1;
    return 0;
}

fn bp_remove(i: i64) -> i64 {
    if i < 0 { return 0 - 1; }
    if BP_ON[i] == 0 { return 0; }
    poke8(BP_AD[i], BP_ORG[i]);
    BP_ON[i] = 0;
    return 0;
}

fn bp_insert_all() -> i64 {
    let i: i64 = 0;
    while i < NBP {
        bp_insert(i);
        i = i + 1;
    }
    return 0;
}

# ---------- 地址 <-> 行号 / 函数 ----------

# 某行号对应的第一个代码地址
fn addr_of_line(ln: i64, fid: i64) -> i64 {
    let i: i64 = 0;
    let best: i64 = 0 - 1;
    while i < NL {
        if L_FN[i] == fid {
            if L_LN[i] == ln {
                if best < 0 { best = L_AD[i]; }
                if L_AD[i] < best { best = L_AD[i]; }
            }
        }
        i = i + 1;
    }
    return best;
}

# 地址所属行号（取最后一条 addr <= a 的记录）
fn line_of(a: i64) -> i64 {
    let i: i64 = 0;
    let best: i64 = 0;
    while i < NL {
        if L_AD[i] <= a { best = L_LN[i]; }
        i = i + 1;
    }
    return best;
}

fn show_pos(a: i64) -> i64 {
    let fi: i64 = fn_of(a);
    let ln: i64 = line_of(a);
    print("  0x");
    print_hex(a);
    print("  ");
    if fi >= 0 {
        print(BUF + D_NM[FI[fi]]);
        print("()");
    } else {
        print("?");
    }
    print("  第 ");
    print_i64(ln);
    print(" 行\n");
    return 0;
}

# ---------- 进程控制 ----------

fn start_child() -> i64 {
    let pid: i64 = syscall(57, 0, 0, 0, 0, 0, 0);
    let av: [2] i64 = 0;
    if pid == 0 {
        pt(0, 0, 0, 0);
        av[0] = &PROGP;
        av[1] = 0;
        syscall(59, &PROGP, &av, 0, 0, 0, 0);
        syscall(60, 127, 0, 0, 0, 0, 0);
        return 0;
    }
    if pid < 0 {
        print("modb: fork 失败\n");
        return 0 - 1;
    }
    CHILD = pid;
    wait_child();
    if mem_open() < 0 { return 0 - 1; }
    return pid;
}

fn step_once() -> i64 {
    NSTEP = NSTEP + 1;
    LASTSTEP = 1;
    pt(9, CHILD, 0, 0);
    wait_child();
    return 0;
}

fn after_stop() -> i64 {
    let st: i64 = WST[0];
    let sig: i64 = 0;
    let rip: i64 = 0;
    let bi: i64 = 0;
    let ws: i64 = LASTSTEP;
    let cv: i64 = 0;
    LASTSTEP = 0;
    if (st & 127) == 0 {
        EXITED = 1;
        print("程序退出，退出码 ");
        print_i64((st >> 8) & 255);
        print_nl();
        return 0;
    }
    if (st & 255) == 127 {
        sig = (st >> 8) & 255;
        if sig == 5 {
            get_regs();
            rip = get_rip();
            # 🔴 单步撞上 int3 不算命中：单步执行 int3 后 rip 指向下一条，
            #    rip-1 正好是断点地址，不判这一步的话，观察点单步时路过
            #    任何断点都会误报"命中"。
            if ws == 1 {
                CHIT = 0 - 1;
                if QUIET == 0 { show_pos(rip); }
                return 0;
            }
            bi = bp_find(rip - 1);
            if bi >= 0 {
                if BP_ON[bi] == 1 {
                    HITBP = bi;
                    REGS[16] = rip - 1;
                    set_regs();
                    if BP_HAS[bi] == 1 {
                        cv = eval_cond(&BPC + bi * 96);
                        if EV_ERR == 1 {
                            # 🔴 条件写错（未知变量名 / 没有比较运算符）时
                            #    绝不能静默当"不成立" —— 那样断点看起来
                            #    就是"没生效"，而真正的原因是表达式错了。
                            print("modb: 断点 #");
                            print_i64(bi);
                            print(" 的条件无法求值: ");
                            print(&BPC + bi * 96);
                            print_nl();
                            NHIT = NHIT + 1;
                            CHIT = 1;
                            if QUIET == 0 { show_pos(rip - 1); }
                            return 0;
                        }
                        if cv == 0 {
                            # 条件不满足：静默放过，由 cont_until_hit 继续跑。
                            # HITBP 保持 >= 0，do_cont 才知道要先单步走过 int3。
                            NCSKIP = NCSKIP + 1;
                            CHIT = 0;
                            return 0;
                        }
                    }
                    # 只有条件真的满足（或无条件断点）才算一次命中：
                    # 否则 stat 里的"命中"会把放过次数也算进去，看不出
                    # 条件到底拦住了多少。
                    NHIT = NHIT + 1;
                    CHIT = 1;
                    if QUIET == 0 {
                        print("断点命中 #");
                        print_i64(bi);
                        print_nl();
                        show_pos(rip - 1);
                    }
                    return 0;
                }
            }
            CHIT = 0 - 1;
            show_pos(rip);
            return 0;
        }
        if sig == 11 {
            print("子进程段错误\n");
            EXITED = 1;
            return 0;
        }
        print("子进程被信号 ");
        print_i64(sig);
        print(" 停止\n");
        return 0;
    }
    print("子进程状态 0x");
    print_hex(st);
    print_nl();
    return 0;
}

fn do_cont() -> i64 {
    let a: i64 = 0;
    if EXITED == 1 {
        print("程序已结束\n");
        return 0;
    }
    # 停在断点上：先恢复原字节、把 rip 退回断点、单步走过这条指令，
    # 再把 int3 装回去，否则继续跑会永远撞同一个断点。
    if HITBP >= 0 {
        a = BP_AD[HITBP];
        bp_remove(HITBP);
        get_regs();
        REGS[16] = a;
        set_regs();
        step_once();
        # 🔴 必须清掉：这次单步不走 after_stop，LASTSTEP 会残留到
        #    后面的 PTRACE_CONT 上，于是真正的断点命中被误判成"单步
        #    路过"，表现为断点跳过一次而不报命中 —— 静默少报。
        LASTSTEP = 0;
        bp_insert(HITBP);
        HITBP = 0 - 1;
    }
    pt(7, CHILD, 0, 0);
    wait_child();
    return after_stop();
}

# 继续跑，直到「条件满足的断点」为止。
# 条件断点不满足时 after_stop 会静默放过（CHIT=0），这里循环再继续；
# 用循环而不是递归，否则循环 10 万次的程序会把调试器自己的栈压爆。
fn cont_until_hit() -> i64 {
    let n: i64 = 0;
    while 1 {
        if EXITED == 1 { return 0; }
        do_cont();
        if EXITED == 1 { return 0; }
        if CHIT != 0 { return 0; }
        n = n + 1;
        if n > 200000 {
            print("modb: 条件断点放过次数超过 200000，放弃\n");
            return 0;
        }
    }
    return 0;
}

fn cmd_step() -> i64 {
    let a: i64 = 0;
    if RUNNING == 0 {
        print("modb: 先用 r 启动\n");
        return 0;
    }
    if EXITED == 1 {
        print("程序已结束\n");
        return 0;
    }
    if HITBP >= 0 {
        a = BP_AD[HITBP];
        bp_remove(HITBP);
        get_regs();
        REGS[16] = a;
        set_regs();
        HITBP = 0 - 1;
    }
    step_once();
    after_stop();
    bp_insert_all();
    return 0;
}

fn cmd_run() -> i64 {
    let pid: i64 = 0;
    if RUNNING == 1 {
        print("modb: 已经在运行了\n");
        return 0;
    }
    pid = start_child();
    if pid < 0 { return 0 - 1; }
    RUNNING = 1;
    HITBP = 0 - 1;
    EXITED = 0;
    bp_insert_all();
    return cont_until_hit();
}

fn cmd_bt() -> i64 {
    let rip: i64 = 0;
    let rbp: i64 = 0;
    let ra: i64 = 0;
    let nb: i64 = 0;
    let d: i64 = 0;
    if RUNNING == 0 {
        print("modb: 先用 r 启动\n");
        return 0;
    }
    get_regs();
    rip = get_rip();
    rbp = get_rbp();
    print("调用栈：\n");
    while d < 32 {
        # 帧没有对应函数的 DIE（_start 之类）就到此为止，不再往上编
        if d > 0 {
            if fn_of(rip) < 0 { return 0; }
        }
        print("#");
        print_i64(d);
        show_pos(rip);
        if rbp == 0 { return 0; }
        ra = rdmem(rbp + 8);
        nb = rdmem(rbp);
        if ra == 0 { return 0; }
        rip = ra - 1;
        rbp = nb;
        d = d + 1;
    }
    return 0;
}

# ---------- 变量查找（条件表达式与观察点共用） ----------
# 先在当前函数的子 DIE 里按 fbreg 找局部/形参，再找带绝对地址的全局。
# VL_OK = 1 表示真的找到了 —— 作用域外必须报 0，否则"变量没变"会被
# 读成"值没变"，观察点就永远触发不了。
fn vl_find(nm: i64) -> i64 {
    let rip: i64 = 0;
    let rbp: i64 = 0;
    let fi: i64 = 0;
    let di: i64 = 0 - 1;
    let i: i64 = 0;
    VL_OK = 0;
    if RUNNING == 0 { return 0; }
    get_regs();
    rip = get_rip();
    rbp = get_rbp();
    fi = fn_of(rip);
    if fi >= 0 { di = FI[fi]; }
    while i < ND {
        if D_PAR[i] == di {
            if D_HFB[i] == 1 {
                if die_nm_eq(i, nm) == 1 {
                    VL_OK = 1;
                    return rdmem(rbp + D_FB[i]);
                }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < ND {
        if D_PAR[i] == 0 - 1 {
            if D_HAD[i] == 1 {
                if die_nm_eq(i, nm) == 1 {
                    VL_OK = 1;
                    return rdmem(D_AD[i]);
                }
            }
        }
        i = i + 1;
    }
    return 0;
}

# ---------- 条件表达式：term (== != < <= > >=) term，term 支持 + - ----------
fn ev_skip() -> i64 {
    let c: i64 = 0;
    # 原来的写法是"先吃空格再吃 tab"，遇到 " \t" 这种混排会漏。
    # 复合条件里括号两侧容易打出混排空白，漏掉就会把 '(' 当成未知符号。
    while 1 {
        c = load8(EVP);
        if c == 32 { EVP = EVP + 1; }
        if c == 9 { EVP = EVP + 1; }
        if c != 32 {
            if c != 9 { break; }
        }
    }
    return 0;
}

fn ev_dig(c: i64) -> i64 {
    if c < 48 { return 0; }
    if c > 57 { return 0; }
    return 1;
}

fn ev_nam(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c >= 48 { if c <= 57 { return 1; } }
    if c == 95 { return 1; }
    return 0;
}

fn ev_prim() -> i64 {
    let c: i64 = 0;
    let neg: i64 = 0;
    let v: i64 = 0;
    let st: i64 = 0;
    let i: i64 = 0;
    ev_skip();
    c = load8(EVP);
    if c == 45 {
        neg = 1;
        EVP = EVP + 1;
        c = load8(EVP);
    }
    if c == 40 {
        EVP = EVP + 1;
        v = ev_or();
        if EV_ERR == 1 { return 0; }
        ev_skip();
        if load8(EVP) == 41 {
            EVP = EVP + 1;
        } else {
            # 括号不配对必须报出来：静默当成"读到了值"的话，
            # 条件看起来只是"不成立"，跟"程序没跑到"没法区分。
            EV_ERR = 1;
            return 0;
        }
        if neg == 1 { v = 0 - v; }
        return v;
    }
    if ev_dig(c) == 1 {
        while ev_dig(load8(EVP)) == 1 {
            v = v * 10 + (load8(EVP) - 48);
            EVP = EVP + 1;
        }
        if neg == 1 { v = 0 - v; }
        return v;
    }
    st = EVP;
    while ev_nam(load8(EVP)) == 1 { EVP = EVP + 1; }
    if EVP == st {
        EV_ERR = 1;
        return 0;
    }
    while i < 63 {
        if st + i >= EVP { break; }
        store8(&EVNAME + i, load8(st + i));
        i = i + 1;
    }
    store8(&EVNAME + i, 0);
    v = vl_find(&EVNAME);
    if VL_OK == 0 { EV_ERR = 1; }
    if neg == 1 { v = 0 - v; }
    return v;
}

fn ev_add() -> i64 {
    let v: i64 = 0;
    let c: i64 = 0;
    v = ev_prim();
    while 1 {
        ev_skip();
        c = load8(EVP);
        if c == 43 {
            EVP = EVP + 1;
            v = v + ev_prim();
        } else {
            if c == 45 {
                EVP = EVP + 1;
                v = v - ev_prim();
            } else {
                return v;
            }
        }
    }
    return v;
}

# ---------- 递归下降条件求值 ----------
#
#   or   := and ( "||" and )*
#   and  := cmp ( "&&" cmp )*
#   cmp  := add [ cmpop add ]
#   add  := prim ( ('+'|'-') prim )*
#   prim := '-'? ( 数字 | 名字 ) | '(' or ')'
#
# && 比 || 紧（C 的约定）。优先级一律靠文法层次表达，不靠运算符表 ——
# 本项目已经三次栽在 mo 自己的运算符优先级上（== 高于 &&），
# 凡是"比较"都写成嵌套 if，绝不在一行里连写两个条件。

# 一个比较项：有比较运算符就比，没有就把值当真值返回。
fn ev_cmp() -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let c2: i64 = 0;
    let op: i64 = 0;
    a = ev_add();
    if EV_ERR == 1 { return 0; }
    ev_skip();
    c = load8(EVP);
    c2 = load8(EVP + 1);
    if c == 61 { if c2 == 61 { op = 1; } }
    if c == 33 { if c2 == 61 { op = 2; } }
    if c == 60 { if c2 == 61 { op = 3; } }
    if c == 62 { if c2 == 61 { op = 4; } }
    if op == 0 {
        if c == 60 { op = 5; }
        if c == 62 { op = 6; }
    }
    # 没有比较运算符就返回这个值本身（真值判断）。
    #   不能在这里报错：括号里的算术子表达式（如 `i == (4 + 1)`）本来
    #   就没有比较，报错会把它一起挡掉。"至少要有一个比较"这条规则
    #   放到 eval_cond 顶层用 EV_NCMP 判。
    if op == 0 { return a; }
    EV_NCMP = EV_NCMP + 1;
    if op == 1 { EVP = EVP + 2; }
    if op == 2 { EVP = EVP + 2; }
    if op == 3 { EVP = EVP + 2; }
    if op == 4 { EVP = EVP + 2; }
    if op == 5 { EVP = EVP + 1; }
    if op == 6 { EVP = EVP + 1; }
    b = ev_add();
    if EV_ERR == 1 { return 0; }
    if op == 1 { if a == b { return 1; } return 0; }
    if op == 2 { if a != b { return 1; } return 0; }
    if op == 3 { if a <= b { return 1; } return 0; }
    if op == 4 { if a >= b { return 1; } return 0; }
    if op == 5 { if a < b { return 1; } return 0; }
    if op == 6 { if a > b { return 1; } return 0; }
    return 0;
}

# 刻意不做短路：两侧都求值。
#   表达式里只有变量读取，没有副作用，多算一次不花代价；
#   而短路会把 `i == 5 && sum == zzz` 里的拼写错误藏起来 —— 断点表现为
#   "条件不成立"，与"程序根本没跑到"完全无法区分。这是本项目反复
#   栽的"静默少报"的又一个入口，宁可多算一次也要把它堵上。
fn ev_and() -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let c2: i64 = 0;
    a = ev_cmp();
    if EV_ERR == 1 { return 0; }
    ev_skip();
    c = load8(EVP);
    c2 = load8(EVP + 1);
    if c == 38 {
        if c2 == 38 {
            EVP = EVP + 2;
            b = ev_and();
            if EV_ERR == 1 { return 0; }
            if a == 0 { return 0; }
            if b == 0 { return 0; }
            return 1;
        }
    }
    return a;
}

fn ev_or() -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let c2: i64 = 0;
    a = ev_and();
    if EV_ERR == 1 { return 0; }
    ev_skip();
    c = load8(EVP);
    c2 = load8(EVP + 1);
    if c == 124 {
        if c2 == 124 {
            EVP = EVP + 2;
            b = ev_or();
            if EV_ERR == 1 { return 0; }
            if a != 0 { return 1; }
            if b != 0 { return 1; }
            return 0;
        }
    }
    return a;
}

# 返回 1 = 条件成立。表达式写错（未知名字 / 没有比较运算符 / 括号不配对
# / 末尾有多余字符）时 EV_ERR=1，调用方要报出来 —— 静默当"不成立"
# 会让断点看起来"没生效"。
fn eval_cond(s: i64) -> i64 {
    let v: i64 = 0;
    EVP = s;
    EV_ERR = 0;
    EV_NCMP = 0;
    v = ev_or();
    if EV_ERR == 1 { return 0; }
    ev_skip();
    if load8(EVP) != 0 {
        EV_ERR = 1;
        return 0;
    }
    # 整个条件里至少要有一次比较。`b 22 if i` 这种漏写比较运算符的，
    # 在这里被挡住 —— 否则裸变量会被当成真值，"写漏了"看起来就和
    # "条件不成立"一模一样。
    if EV_NCMP == 0 {
        EV_ERR = 1;
        return 0;
    }
    if v != 0 { return 1; }
    return 0;
}

# ---------- 类型感知打印 ----------
# 值是什么类型由 DWARF 决定，不是靠猜：byte 占 1 字节、bool 打 true/false、
# f64 是 Q16.16、结构体沿 member DIE 递归、数组按元素大小步进。
# 判据：打印出来的值必须与 DWARF 描述一致 —— 只打 8 字节整数时
#      byte/bool/f64 全都是"看起来有值"，静态看不出错。
var TP_NM: [256] byte = 0;
var VA_OK: i64 = 0;
var VA_AD: i64 = 0;
var VA_TY: i64 = 0;

# 🔴 ref4 的基准是 .debug_info **节区起点**（含 11 字节 unit header），
#    而 D_OFF 存的是 BUF 内绝对偏移（= S_OFF[节区] + 相对值）。
#    两者相差 unit header 的长度，直接比较会**全部匹配不上** ——
#    表现为"每个变量都退化成 8 字节整数"，结构体、数组、byte/bool/f64
#    全打错且不报错。
fn die_at(off: i64) -> i64 {
    let i: i64 = 0;
    let t: i64 = off + CU_BASE;
    while i < ND {
        if D_OFF[i] == t { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

# 变量的**地址**与类型。全局量是 CU 的直接子（D_PAR == 0），
# 原 vl_find 按 D_PAR == -1 找，那是 CU 的兄弟，永远匹配不到 ——
# 所以全局变量此前一律"找不到"。
fn vl_addr(nm: i64) -> i64 {
    let rip: i64 = 0;
    let rbp: i64 = 0;
    let fi: i64 = 0;
    let di: i64 = 0 - 1;
    let i: i64 = 0;
    VA_OK = 0;
    if RUNNING == 0 { return 0; }
    get_regs();
    rip = get_rip();
    rbp = get_rbp();
    fi = fn_of(rip);
    if fi >= 0 { di = FI[fi]; }
    while i < ND {
        if D_PAR[i] == di {
            if D_HFB[i] == 1 {
                if D_TAG[i] == 52 {
                    if die_nm_eq(i, nm) == 1 {
                        VA_OK = 1;
                        VA_AD = rbp + D_FB[i];
                        VA_TY = D_TY[i];
                        return 0;
                    }
                }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < ND {
        if D_PAR[i] == 0 {
            if D_HAD[i] == 1 {
                if D_TAG[i] == 52 {
                    if die_nm_eq(i, nm) == 1 {
                        VA_OK = 1;
                        VA_AD = D_AD[i];
                        VA_TY = D_TY[i];
                        return 0;
                    }
                }
            }
        }
        i = i + 1;
    }
    return 0;
}

fn ty_member(d: i64, nm: i64) -> i64 {
    let i: i64 = 0;
    while i < ND {
        if D_PAR[i] == d {
            if D_TAG[i] == 13 {
                if die_nm_eq(i, nm) == 1 { return i; }
            }
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn ty_esz(t: i64) -> i64 {
    let d: i64 = die_at(t);
    if d >= 0 {
        if D_LO[d] > 0 { return D_LO[d]; }
    }
    return 8;
}

fn pr_f64(v: i64) -> i64 {
    let x: i64 = v;
    let ex: i64 = 0;
    let ma: i64 = 0;
    let shift: i64 = 0;
    let ip: i64 = 0;
    let f: i64 = 0;
    let d: i64 = 0;
    let one: i64 = 4503599627370496;
    if x < 0 {
        print("-");
        x = 0 - x;
    }
    ex = (x >> 52) & 2047;
    ma = x - (x >> 52) * one;
    if ex == 0 {
        print("0.0000");
        return 0;
    }
    if ex == 2047 {
        print("inf");
        return 0;
    }
    if ex >= 1075 {
        print_i64((one + ma) << (ex - 1075));
        print(".0000");
        return 0;
    }
    shift = 1075 - ex;
    ip = (one + ma) >> shift;
    print_i64(ip);
    print(".");
    f = one + ma - (ip << shift);
    d = 0;
    while d < 4 {
        f = f * 10;
        print_i64(f >> shift);
        f = f - ((f >> shift) << shift);
        d = d + 1;
    }
    return 0;
}

fn pr_base(d: i64, a: i64) -> i64 {
    let v: i64 = rdmem(a);
    if die_nm_eq(d, "bool") == 1 {
        if v != 0 { print("true"); return 0; }
        print("false");
        return 0;
    }
    if die_nm_eq(d, "f64") == 1 { return pr_f64(v); }
    if die_nm_eq(d, "byte") == 1 {
        print_i64(v & 255);
        return 0;
    }
    print_i64(v);
    return 0;
}

fn pr_struct(d: i64, a: i64, depth: i64) -> i64 {
    let i: i64 = 0;
    let first: i64 = 1;
    if depth >= 3 {
        print("{...}");
        return 0;
    }
    print("{");
    while i < ND {
        if D_PAR[i] == d {
            if D_TAG[i] == 13 {
                if first == 0 { print(", "); }
                first = 0;
                print(BUF + D_NM[i]);
                print(" = ");
                pr_val(a + D_MLOC[i], D_TY[i], depth + 1);
            }
        }
        i = i + 1;
    }
    print("}");
    return 0;
}

fn pr_arr(d: i64, a: i64, depth: i64) -> i64 {
    let i: i64 = 0;
    let cnt: i64 = 0;
    let et: i64 = D_TY[d];
    let esz: i64 = ty_esz(et);
    while i < ND {
        if D_PAR[i] == d {
            if D_TAG[i] == 33 { cnt = D_MLOC[i]; }
        }
        i = i + 1;
    }
    print("[");
    if cnt > 8 {
        i = 0;
        while i < 3 {
            if i > 0 { print(", "); }
            pr_val(a + i * esz, et, depth + 1);
            i = i + 1;
        }
        print(", ... ");
        pr_val(a + (cnt - 0 - 1) * esz, et, depth + 1);
        print("]");
        return 0;
    }
    i = 0;
    while i < cnt {
        if i > 0 { print(", "); }
        pr_val(a + i * esz, et, depth + 1);
        i = i + 1;
    }
    print("]");
    return 0;
}

fn pr_val(a: i64, ty: i64, depth: i64) -> i64 {
    let d: i64 = die_at(ty);
    if d < 0 {
        print_i64(rdmem(a));
        return 0;
    }
    if D_TAG[d] == 19 { return pr_struct(d, a, depth); }
    if D_TAG[d] == 1 { return pr_arr(d, a, depth); }
    if D_TAG[d] == 36 { return pr_base(d, a); }
    if D_TAG[d] == 15 {
        print("*0x");
        print_hex(rdmem(a));
        return 0;
    }
    print_i64(rdmem(a));
    return 0;
}

# 路径：name [. field | [idx]] ...
# 返回 0 成功；-1 找不到变量；-2 类型不支持该操作；-3 没有这个成员
fn pr_path(nm: i64) -> i64 {
    let p: i64 = nm;
    let q: i64 = 0;
    let c: i64 = 0;
    let a: i64 = 0;
    let ty: i64 = 0;
    let d: i64 = 0;
    let m: i64 = 0;
    let idx: i64 = 0;
    let esz: i64 = 8;
    q = 0;
    while 1 {
        c = load8(p);
        if c == 0 { break; }
        if c == 46 { break; }
        if c == 91 { break; }
        store8(TP_NM + q, c);
        q = q + 1;
        p = p + 1;
    }
    store8(TP_NM + q, 0);
    vl_addr(TP_NM);
    if VA_OK == 0 { return 0 - 1; }
    a = VA_AD;
    ty = VA_TY;
    while 1 {
        c = load8(p);
        if c == 0 { break; }
        if c == 46 {
            p = p + 1;
            q = 0;
            while 1 {
                c = load8(p);
                if c == 0 { break; }
                if c == 46 { break; }
                if c == 91 { break; }
                store8(TP_NM + q, c);
                q = q + 1;
                p = p + 1;
            }
            store8(TP_NM + q, 0);
            d = die_at(ty);
            if d < 0 { return 0 - 2; }
            if D_TAG[d] == 15 {
                a = rdmem(a);
                ty = D_TY[d];
                d = die_at(ty);
                if d < 0 { return 0 - 2; }
            }
            if D_TAG[d] != 19 { return 0 - 2; }
            m = ty_member(d, TP_NM);
            if m < 0 { return 0 - 3; }
            a = a + D_MLOC[m];
            ty = D_TY[m];
        }
        if c == 91 {
            p = p + 1;
            idx = 0;
            while 1 {
                c = load8(p);
                if c < 48 { break; }
                if c > 57 { break; }
                idx = idx * 10 + c - 48;
                p = p + 1;
            }
            if c == 93 { p = p + 1; }
            d = die_at(ty);
            if d < 0 { return 0 - 2; }
            if D_TAG[d] == 15 {
                a = rdmem(a);
                ty = D_TY[d];
                d = die_at(ty);
                if d < 0 { return 0 - 2; }
            }
            if D_TAG[d] != 1 { return 0 - 2; }
            ty = D_TY[d];
            esz = ty_esz(ty);
            a = a + idx * esz;
        }
        if c != 46 {
            if c != 91 { break; }
        }
    }
    pr_val(a, ty, 0);
    print_nl();
    return 0;
}

fn cmd_print(nm: i64) -> i64 {
    let r: i64 = 0;
    if RUNNING == 0 {
        print("modb: 先用 r 启动\n");
        return 0;
    }
    if nm == 0 {
        print("用法: p <变量名>\n");
        return 0;
    }
    print(nm);
    print(" = ");
    r = pr_path(nm);
    if r == 0 { return 0; }
    if r == 0 - 1 {
        print("modb: 当前作用域找不到变量 ");
        print(nm);
        print_nl();
        return 0;
    }
    if r == 0 - 3 {
        print("modb: 没有这个成员: ");
        print(nm);
        print_nl();
        return 0;
    }
    print("modb: 该变量不支持这种访问: ");
    print(nm);
    print_nl();
    return 0;
}

# ---------- 观察点 ----------
# 软件实现：单步并在每一步读变量值，变了就停。
# 为什么不用硬件调试寄存器（DR0-DR7）：那要往 user 区写 debugreg，
# 偏移写错就是静默失效 —— 软件单步虽然慢（O(步数)），但必然正确，
# 而且可以在测试里用"步数/触发"直接验证。MAXW 是上限，不是精度。
fn cmd_watch(nm: i64) -> i64 {
    let v: i64 = 0;
    let n: i64 = 0;
    if RUNNING == 0 {
        print("modb: 先用 r 启动（观察点需要在进程里读变量）\n");
        return 0;
    }
    if EXITED == 1 {
        print("modb: 程序已结束\n");
        return 0;
    }
    if nm == 0 {
        print("用法: watch <变量名>\n");
        return 0;
    }
    strcpy(&WNAME, nm);
    v = vl_find(&WNAME);
    if VL_OK == 0 {
        print("modb: 当前作用域找不到变量 ");
        print(&WNAME);
        print_nl();
        return 0;
    }
    WHAS = 1;
    WV0 = v;
    print("观察点: ");
    print(&WNAME);
    print(" = ");
    print_i64(v);
    print_nl();
    while n < MAXW {
        if EXITED == 1 { return 0; }
        QUIET = 1;
        cmd_step();
        QUIET = 0;
        if EXITED == 1 {
            print("modb: 程序已结束，");
            print(&WNAME);
            print(" 未再改变\n");
            return 0;
        }
        v = vl_find(&WNAME);
        if VL_OK == 1 {
            if v != WV0 {
                print("观察点触发: ");
                print(&WNAME);
                print("  ");
                print_i64(WV0);
                print(" -> ");
                print_i64(v);
                print_nl();
                show_pos(get_rip());
                WV0 = v;
                return 0;
            }
        }
        n = n + 1;
    }
    print("modb: 单步超过 ");
    print_i64(MAXW);
    print(" 步，");
    print(&WNAME);
    print(" 未改变\n");
    return 0;
}

fn cmd_stat() -> i64 {
    print("断点命中   ");
    print_i64(NHIT);
    print_nl();
    print("条件放过   ");
    print_i64(NCSKIP);
    print_nl();
    print("单步次数   ");
    print_i64(NSTEP);
    print_nl();
    return 0;
}

fn cmd_regs() -> i64 {
    if RUNNING == 0 {
        print("modb: 先用 r 启动\n");
        return 0;
    }
    get_regs();
    print("rip 0x");
    print_hex(get_rip());
    print("  rbp 0x");
    print_hex(get_rbp());
    print("  rax ");
    print_i64(REGS[10]);
    print_nl();
    print("  mem(text)    0x");
    print_hex(rdmem(get_rip()));
    print("  file(text)   0x");
    print_hex(g64(get_rip() - S_ADDR[I_TEXT] + S_OFF[I_TEXT]));
    print_nl();
    print("  ptrace(text) 0x");
    print_hex(pt(2, CHILD, get_rip(), 0));
    print("   <- 恒为 -1e(-EFAULT)，见 peek8 处的注释");
    print_nl();
    return 0;
}

# ---------- 命令解析 ----------

fn is_digit_str(s: i64) -> i64 {
    let c: i64 = load8(s);
    if c == 0 { return 0; }
    if c < 48 { return 0; }
    if c > 57 { return 0; }
    return 1;
}

fn cmd_break(arg: i64) -> i64 {
    let a: i64 = 0;
    let ln: i64 = 0;
    let di: i64 = 0;
    let bi: i64 = 0;
    let p: i64 = 0;
    let cond: i64 = 0;
    let d: i64 = 0;
    let j: i64 = 0;
    if arg == 0 {
        print("用法: b <行号> 或 b <函数名> [if <条件>]\n");
        return 0;
    }
    # 拆出 " if "：不能用 strstr 的返回值当布尔，命中行首时它返回 0。
    p = arg;
    while load8(p) != 0 {
        if load8(p) == 32 {
            if load8(p + 1) == 105 {
                if load8(p + 2) == 102 {
                    if load8(p + 3) == 32 {
                        store8(p, 0);
                        cond = p + 4;
                        while load8(cond) == 32 { cond = cond + 1; }
                        if load8(cond) == 0 { cond = 0; }
                        break;
                    }
                }
            }
        }
        p = p + 1;
    }
    if is_digit_str(arg) == 1 {
        ln = atoi(arg);
        a = addr_of_line(ln, CURF);
        if a < 0 {
            print("modb: 第 ");
            print_i64(ln);
            print(" 行没有对应的代码地址\n");
            return 0;
        }
    } else {
        di = find_tag_nm(46, arg);
        if di < 0 {
            print("modb: 找不到函数 ");
            print(arg);
            print_nl();
            return 0;
        }
        a = D_LO[di];
    }
    if bp_add(a) < 0 { return 0; }
    bi = bp_find(a);
    print("断点 ");
    print_i64(bi);
    print(" @ 0x");
    print_hex(a);
    if cond != 0 {
        # 条件文本必须拷进独立缓冲区：arg 指向命令行缓冲，交互式下
        # 下一条命令就会把它覆盖掉。
        d = bi * 96;
        j = 0;
        while j < 95 {
            if load8(cond + j) == 0 { break; }
            store8(&BPC + d + j, load8(cond + j));
            j = j + 1;
        }
        store8(&BPC + d + j, 0);
        BP_HAS[bi] = 1;
        print(" if ");
        print(&BPC + d);
    }
    if RUNNING == 1 { bp_insert(bi); }
    print_nl();
    return 0;
}

fn cmd_help() -> i64 {
    print("命令：\n");
    print("  b <行号|函数名>   下断点\n");
    print("  b <位置> if <条件>  条件断点（条件不满足就自动继续）\n");
    print("     条件形如  i == 5  /  sum > 100  /  n - 1 <= 3\n");
    print("     支持 && || 与括号： (i > 3) && (i < 6)  /  i == 1 || i == 8\n");
    print("     && 比 || 紧；两侧都求值（不做短路），好把拼错的变量名报出来\n");
    print("     整个条件里至少要有一个比较运算符（b 22 if i 会报错）\n");
    print("  watch <变量名>    观察点：变量值改变时停下（软件单步实现）\n");
    print("  r                 启动（并在启动前装好全部断点）\n");
    print("  c                 继续\n");
    print("  s                 单步一条指令\n");
    print("  bt                回溯调用栈\n");
    print("  p <变量名>        打印变量值（局部变量按 fbreg 读）\n");
    print("  regs              打印 rip/rbp/rax\n");
    print("  stat              统计：断点命中 / 条件放过 / 单步次数\n");
    print("  q                 退出\n");
    return 0;
}

fn do_line(line: i64) -> i64 {
    let p: i64 = 0;
    let arg: i64 = 0;
    let c: i64 = 0;
    p = line;
    while load8(p) != 0 {
        c = load8(p);
        if c == 13 { store8(p, 0); }
        p = p + 1;
    }
    p = line;
    while load8(p) != 0 {
        c = load8(p);
        if c == 32 { break; }
        if c == 9 { break; }
        p = p + 1;
    }
    if load8(p) != 0 {
        store8(p, 0);
        arg = p + 1;
        while load8(arg) == 32 || load8(arg) == 9 { arg = arg + 1; }
        if load8(arg) == 0 { arg = 0; }
    }
    if load8(line) == 0 { return 0; }
    if streq(line, "b") == 1 { return cmd_break(arg); }
    if streq(line, "break") == 1 { return cmd_break(arg); }
    if streq(line, "r") == 1 { return cmd_run(); }
    if streq(line, "run") == 1 { return cmd_run(); }
    if streq(line, "c") == 1 { return cont_until_hit(); }
    if streq(line, "cont") == 1 { return cont_until_hit(); }
    if streq(line, "watch") == 1 { return cmd_watch(arg); }
    if streq(line, "stat") == 1 { return cmd_stat(); }
    if streq(line, "s") == 1 { return cmd_step(); }
    if streq(line, "step") == 1 { return cmd_step(); }
    if streq(line, "bt") == 1 { return cmd_bt(); }
    if streq(line, "p") == 1 { return cmd_print(arg); }
    if streq(line, "regs") == 1 { return cmd_regs(); }
    if streq(line, "help") == 1 { return cmd_help(); }
    if streq(line, "q") == 1 { QUIT = 1; return 0; }
    if streq(line, "quit") == 1 { QUIT = 1; return 0; }
    print("modb: 未知命令 ");
    print(line);
    print_nl();
    return 0;
}

# 从文件中逐行读命令（不用标准输入，把 stdin 留给被调试程序）
fn run_script(path: i64) -> i64 {
    let sz: i64 = 0;
    let i: i64 = 0;
    let st: i64 = 0;
    sz = read_file(path, CMDB, 65536);
    if sz <= 0 {
        print("modb: 无法读命令文件\n");
        return 0 - 1;
    }
    st = 0;
    while i <= sz {
        if i == sz {
            do_line(CMDB + st);
            i = i + 1;
        } else {
            if load8(CMDB + i) == 10 {
                store8(CMDB + i, 0);
                do_line(CMDB + st);
                st = i + 1;
                if QUIT == 1 { return 0; }
            }
            i = i + 1;
        }
    }
    return 0;
}

# 交互式：逐字节读标准输入，避免行缓冲把被调试程序的输入吃掉
fn run_stdin() -> i64 {
    let i: i64 = 0;
    let r: i64 = 0;
    while QUIT == 0 {
        i = 0;
        print("(modb) ");
        while i < 250 {
            r = syscall(0, 0, &LNCMD + i, 1, 0, 0, 0);
            if r <= 0 {
                if i == 0 { QUIT = 1; }
                break;
            }
            if load8(&LNCMD + i) == 10 { break; }
            i = i + 1;
        }
        if QUIT == 1 { return 0; }
        store8(&LNCMD + i, 0);
        do_line(&LNCMD);
    }
    return 0;
}

fn main() -> i64 {
    let i: i64 = 1;
    let a: i64 = 0;
    let hasx: i64 = 0;
    if argc() < 2 {
        print("用法: modb <prog.elf> [-x <命令文件>]\n");
        print("  不给 -x 时进入交互模式，从标准输入逐行读命令\n");
        return 1;
    }
    if heap_ready() == 0 { heap_init(); }
    BUF = alloc(BUFSZ);
    CMDB = alloc(65536);
    if BUF == 0 {
        print("modb: 堆分配失败\n");
        return 1;
    }
    strcpy(&PROGP, argv(1));
    while i < argc() {
        a = argv(i);
        if streq(a, "-x") == 1 {
            i = i + 1;
            if i < argc() {
                strcpy(&CMDP, argv(i));
                hasx = 1;
            }
        }
        i = i + 1;
    }
    FSZ = read_file(argv(1), BUF, BUFSZ);
    if FSZ <= 0 {
        print("modb: 无法读取 ");
        print(argv(1));
        print_nl();
        return 1;
    }
    I_TEXT = 0 - 1;
    I_INFO = 0 - 1;
    I_ABBR = 0 - 1;
    I_FRAME = 0 - 1;
    I_LINE = 0 - 1;
    if parse_elf() < 0 {
        print("modb: 不是 ELF64\n");
        return 1;
    }
    if I_INFO < 0 {
        print("modb: 没有 .debug_info（编译时加 -g）\n");
        return 1;
    }
    if I_ABBR < 0 {
        print("modb: 没有 .debug_abbrev\n");
        return 1;
    }
    parse_abbrev();
    if CAPERR == 1 { return 1; }
    parse_info();
    if CAPERR == 1 { return 1; }
    if I_LINE < 0 {
        print("modb: 没有 .debug_line（编译时加 -g）\n");
        return 1;
    }
    build_fns();
    parse_line();
    if CAPERR == 1 { return 1; }
    print("modb: 已加载 ");
    print(argv(1));
    print("  函数 ");
    print_i64(NFN);
    print("  行号记录 ");
    print_i64(NL);
    print_nl();
    if hasx == 1 { run_script(&CMDP); }
    if RUNNING == 1 {
        if EXITED == 0 { pt(8, CHILD, 0, 0); }
        wait_child();
    }
    return 0;
}
