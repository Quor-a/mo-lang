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
# 🔴 容量必须覆盖库函数：1.100 起调试信息覆盖 import 进来的库，
#    单函数的 rbp 偏移数很容易破 512。装不下时 add_rbp 会置 CAPERR，
#    而**末尾不检查 CAPERR 的话退出码仍是 0** —— 于是"通过"里混着
#    没检查完的函数，这正是本项目反复栽的"静默少报"。
var MAXR:   i64 = 4096;

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
var D_FILE: [4096] i64 = 0;    # DW_AT_decl_file（file_names 编号，从 1 起）
var LN_FNBADF: i64 = 0;        # 函数 decl_file 与入口行号记录的文件不一致数
var LN_FNNOF: i64 = 0;         # 完全没读到 decl_file 的函数数
var PSTK: [512] i64 = 0;

# ---------- 反汇编收集到的 rbp 偏移 ----------
var RBP_N: i64 = 0;
var RBP_O: [4096] i64 = 0;

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
                if a == 56 { D_MLOC[ND] = v; }
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
    return 0;
}

# ================= DIE 查询与断言 =================
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

fn dump_all() -> i64 {
    let i: i64 = 0;
    print("== DIE 表 ==");
    print_nl();
    while i < ND {
        print("  [");
        print_i64(i);
        print("] tag=");
        print_i64(D_TAG[i]);
        print(" par=");
        print_i64(D_PAR[i]);
        if D_NM[i] != 0 {
            print(" nm=");
            print(BUF + D_NM[i]);
        }
        if D_LO[i] != 0 {
            print(" pc=");
            print_i64(D_LO[i]);
            print("..");
            print_i64(D_HI[i]);
        }
        if D_HFB[i] == 1 {
            print(" fbreg=");
            print_i64(D_FB[i]);
        }
        if D_HAD[i] == 1 {
            print(" addr=");
            print_i64(D_AD[i]);
        }
        if D_LINE[i] != 0 {
            print(" line=");
            print_i64(D_LINE[i]);
        }
        if D_TY[i] != 0 {
            print(" ty=");
            print_i64(D_TY[i]);
        }
        if D_MLOC[i] != 0 {
            print(" mloc=");
            print_i64(D_MLOC[i]);
        }
        print_nl();
        i = i + 1;
    }
    print("== 函数体 [rbp+off] 扫描 ==");
    print_nl();
    i = 0;
    while i < ND {
        if D_TAG[i] == 46 {
            if D_LO[i] != 0 {
                let r: i64 = scan(D_LO[i], D_HI[i]);
                print("  ");
                print(BUF + D_NM[i]);
                print(" scan=");
                print_i64(r);
                print(" offs=");
                let k: i64 = 0;
                while k < RBP_N {
                    print_i64(RBP_O[k]);
                    print(" ");
                    k = k + 1;
                }
                print_nl();
            }
        }
        i = i + 1;
    }
    print("== FDE ==");
    print_nl();
    i = 0;
    while i < NFDE {
        print("  ");
        print_i64(F_LO[i]);
        print("..");
        print_i64(F_HI[i]);
        print(" cfareg=");
        print_i64(F_CFA[i]);
        print_nl();
        i = i + 1;
    }
    return 0;
}


fn die_by_off(o: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = S_OFF[I_INFO];
    while i < ND {
        if D_OFF[i] - b == o { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn chk_ty(vi: i64, want: i64) -> i64 {
    let ti: i64 = 0;
    if vi < 0 {
        chk(0, want, "变量 DIE 未找到");
        return 0;
    }
    ti = die_by_off(D_TY[vi]);
    if ti < 0 {
        chk(0, want, "类型 DIE 未找到");
        return 0;
    }
    if D_NM[ti] == 0 {
        chk(0, want, "类型无名字");
        return 0;
    }
    chk(streq(BUF + D_NM[ti], want), want, BUF + D_NM[ti]);
    return 0;
}

fn run_checks() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let k: i64 = 0;
    let n: i64 = 0;
    let miss: i64 = 0;
    let rc: i64 = 0;
    let o: i64 = 0;
    let nfn: i64 = 0;
    let dup: i64 = 0;
    let bad: i64 = 0;
    let f: i64 = 0;
    let g: i64 = 0;
    let pi: i64 = 0;
    let mi: i64 = 0;

    print("== 函数表 ==");
    print_nl();
    f = find_tag_nm(46, "fib");
    g = find_tag_nm(46, "addup");
    pi = find_tag_nm(46, "main");
    chk(f >= 0, "函数 fib", "未找到");
    chk(g >= 0, "函数 addup", "未找到");
    chk(pi >= 0, "函数 main", "未找到");

    print("== 变量归属与位置 ==");
    print_nl();
    i = 0;
    while i < ND {
        if D_PAR[i] == g {
            if die_nm_eq(i, "t") == 1 { mi = i; }
        }
        i = i + 1;
    }
    chk(mi >= 0, "addup 有变量 t", "未找到");
    if mi >= 0 {
        chk(D_HFB[mi] == 1, "t 有 fbreg 位置", "无");
        chk(D_FB[mi] < 0, "t 的偏移为负（栈上）", "非负");
    }

    print("== 全局变量 ==");
    print_nl();
    i = 0;
    n = 0;
    while i < ND {
        if D_TAG[i] == 52 {
            if D_PAR[i] >= 0 {
                if D_TAG[D_PAR[i]] == 17 {
                    if die_nm_eq(i, "TOTAL") == 1 { n = n + 1; }
                    if die_nm_eq(i, "LIMIT") == 1 { n = n + 1; }
                }
            }
        }
        i = i + 1;
    }
    chk(n == 2, "全局变量 TOTAL/LIMIT 挂在 CU 下", "只找到部分");
    i = 0;
    bad = 0;
    while i < ND {
        if D_TAG[i] == 52 {
            if D_PAR[i] >= 0 {
                if D_TAG[D_PAR[i]] == 17 {
                    if D_HAD[i] == 0 { bad = bad + 1; }
                    if D_AD[i] < 268435456 { bad = bad + 1; }
                }
            }
        }
        i = i + 1;
    }
    chk(bad == 0, "全局变量有数据段地址(>=0x10000000)", "有变量地址缺失或越界");

    print("== 位置与机器码比对（最关键）==");
    print_nl();
    i = 0;
    while i < ND {
        if D_TAG[i] == 46 {
            if D_LO[i] != 0 {
                rc = scan(D_LO[i], D_HI[i]);
                chk(rc == 0, "线性扫描的指令边界精确落在函数末尾", "解码错位");
                j = 0;
                miss = 0;
                while j < ND {
                    if D_PAR[j] == i {
                        if D_HFB[j] == 1 {
                            if has_rbp(D_FB[j]) == 0 { miss = miss + 1; }
                        }
                    }
                    j = j + 1;
                }
                chk(miss == 0, "函数的 fbreg 偏移都能在机器码里找到", "有偏移对不上");
            }
        }
        i = i + 1;
    }

    print("== 类型 ==");
    print_nl();
    i = 0;
    while i < ND {
        if D_TAG[i] == 36 { nfn = nfn + 1; }
        i = i + 1;
    }
    chk(find_tag_nm(36, "i64") >= 0, "基础类型 i64", "未找到");
    chk(find_tag_nm(36, "byte") >= 0, "基础类型 byte", "未找到");
    chk(find_tag_nm(36, "f64") >= 0, "基础类型 f64", "未找到");
    chk(find_tag_nm(36, "bool") >= 0, "基础类型 bool", "未找到");
    chk(find_tag_nm(19, "Point") >= 0, "结构体类型 Point", "未找到");

    i = 0;
    while i < ND {
        if D_TAG[i] == 36 {
            if D_NM[i] != 0 {
                j = i + 1;
                while j < ND {
                    if D_TAG[j] == 36 {
                        if D_NM[j] != 0 {
                            if streq(BUF + D_NM[i], BUF + D_NM[j]) == 1 { dup = dup + 1; }
                        }
                    }
                    j = j + 1;
                }
            }
        }
        i = i + 1;
    }
    chk(dup == 0, "类型 DIE 无重复", "有重复类型");

    i = 0;
    mi = 0 - 1;
    while i < ND {
        if D_PAR[i] == g {
            if die_nm_eq(i, "fl") == 1 { mi = i; }
        }
        i = i + 1;
    }
    chk_ty(mi, "f64");
    i = 0;
    mi = 0 - 1;
    while i < ND {
        if D_PAR[i] == pi {
            if die_nm_eq(i, "i") == 1 { mi = i; }
        }
        i = i + 1;
    }
    chk_ty(mi, "i64");

    print("== 结构体成员 ==");
    print_nl();
    k = find_tag_nm(19, "Point");
    if k >= 0 {
        i = 0;
        mi = 0;
        while i < ND {
            if D_PAR[i] == k {
                if die_nm_eq(i, "x") == 1 {
                    if D_MLOC[i] == 0 { mi = mi + 1; }
                }
                if die_nm_eq(i, "y") == 1 {
                    if D_MLOC[i] == 8 { mi = mi + 1; }
                }
            }
            i = i + 1;
        }
        chk(mi == 2, "Point: x@0 y@8", "成员偏移不对");
    }

    print("== .debug_frame（栈帧展开规则）==");
    print_nl();
    i = 0;
    n = 0;
    while i < ND {
        if D_TAG[i] == 46 { n = n + 1; }
        i = i + 1;
    }
    chk(NFDE >= 2, "至少两条 FDE", "太少");
    chk(NFDE == n, "FDE 数 == 函数数", "数量不一致");
    i = 0;
    bad = 0;
    while i < NFDE {
        if F_CFA[i] != 6 { bad = bad + 1; }
        i = i + 1;
    }
    chk(bad == 0, "CFA 最终基于 rbp(6)", "有 FDE 不是");
    i = 0;
    bad = 0;
    while i < NFDE {
        o = S_OFF[I_TEXT] + (F_LO[i] - S_ADDR[I_TEXT]);
        if gb(o) != 85 { bad = bad + 1; }
        if gb(o + 1) != 72 { bad = bad + 1; }
        if gb(o + 2) != 137 { bad = bad + 1; }
        if gb(o + 3) != 229 { bad = bad + 1; }
        i = i + 1;
    }
    chk(bad == 0, "FDE 入口是 push rbp + mov rbp,rsp", "序言字节不符");
    return 0;
}


# ================= -s 全程序扫描 =================
#
# 为什么需要这个模式：
#   run_checks() 是**针对小测试程序**写的（fib / addup / Point 这些具体名字）。
#   对着 bin/moc 这种真实大程序，它一条也对不上 —— 于是"dwmo 能处理大程序"
#   这件事从来没有被验证过。
#
#   这个模式只做**与被测程序无关**的通用校验，对任何 -g 产物都成立：
#     1. 每个 subprogram DIE 从 low_pc 线性解码到 high_pc，
#        指令边界必须**精确落在 high_pc** —— 任何一条指令长度算错，
#        末尾就对不上。这是对"扫描本身"的校验。
#     2. FDE 数 == 带代码的 subprogram 数
#     3. 每个 FDE 的入口字节是 push rbp + mov rbp,rsp
#
#   🔴 关键点：一条指令长度算错就会让 SC_BAD > 0。小测试程序里
#      函数体短、指令种类少，错的分支可能根本没被走到。

fn scan_all() -> i64 {
    let i: i64 = 0;
    let r: i64 = 0;
    let nf: i64 = 0;
    SC_NF = 0;
    SC_NI = 0;
    SC_NB = 0;
    SC_BAD = 0;
    SC_ERR = 0;
    SC_NR = 0;
    SC_NBR = 0;
    SC_NBD = 0;
    i = 0;
    while i < ND {
        if D_TAG[i] == 46 {
            if D_HI[i] > D_LO[i] {
                if D_LO[i] != 0 {
                    SC_NI_PREV = SC_NI;
                    r = scan(D_LO[i], D_HI[i]);
                    SC_NF = SC_NF + 1;
                    if SC_PERFN == 1 {
                        print_i64(D_LO[i]);
                        print(" ");
                        print_i64(D_HI[i]);
                        print(" ");
                        print_i64(SC_NI - SC_NI_PREV);
                        print_nl();
                    }
                    if r == 0 - 1 {
                        SC_ERR = SC_ERR + 1;
                        print("  [!!] 无法解码: ");
                        print_i64(D_LO[i]);
                        print_nl();
                    }
                    if r == 0 - 2 {
                        SC_BAD = SC_BAD + 1;
                        print("  [!!] 边界未落在 high_pc: lo=");
                        print_i64(D_LO[i]);
                        print(" hi=");
                        print_i64(D_HI[i]);
                        print_nl();
                    }
                }
            }
        }
        i = i + 1;
    }
    return 0;
}

fn scan_report() -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let bad: i64 = 0;
    print("== -s 全程序扫描（与被测程序无关的通用校验）==");
    print_nl();
    print("  函数（subprogram 带代码）  ");
    print_i64(SC_NF);
    print_nl();
    print("  解出的指令条数            ");
    print_i64(SC_NI);
    print_nl();
    print("  覆盖 .text 字节数         ");
    print_i64(SC_NB);
    print_nl();
    print("  收集到的 [rbp+off] 偏移数 ");
    print_i64(SC_NR);
    print_nl();
    print("  跳转/调用目标检查数      ");
    print_i64(SC_NBR);
    print_nl();
    print("  目标不在指令边界上的     ");
    print_i64(SC_NBD);
    print_nl();
    chk(SC_NF > 0, "至少扫到一个函数", "一个都没扫到 —— 索引或 DIE 解析有问题");
    chk(SC_ERR == 0, "没有无法解码的指令", "有函数含解码器不认识的字节");
    chk(SC_BAD == 0, "每个函数的指令边界精确落在 high_pc", "有函数边界对不上 —— 指令长度算错");
    chk(SC_NBR > 0, "至少检查到一个跳转/调用目标", "一个都没有 —— 目标判定有问题，下面的断言会空转");
    chk(SC_NBD == 0, "跳转/调用目标都落在指令边界上", "有目标落空 —— 解码器错位（见 reaches() 注释）");
    i = 0;
    n = 0;
    while i < ND {
        if D_TAG[i] == 46 {
            if D_HI[i] > D_LO[i] {
                if D_LO[i] != 0 { n = n + 1; }
            }
        }
        i = i + 1;
    }
    chk(NFDE == n, "FDE 数 == 带代码的 subprogram 数", "数量不一致");
    i = 0;
    bad = 0;
    while i < NFDE {
        let o: i64 = S_OFF[I_TEXT] + (F_LO[i] - S_ADDR[I_TEXT]);
        if gb(o) != 85 { bad = bad + 1; }
        if gb(o + 1) != 72 { bad = bad + 1; }
        if gb(o + 2) != 137 { bad = bad + 1; }
        if gb(o + 3) != 229 { bad = bad + 1; }
        i = i + 1;
    }
    chk(bad == 0, "FDE 入口是 push rbp + mov rbp,rsp", "序言字节不符");
    return 0;
}

fn main() -> i64 {
    let rc: i64 = 0;
    let i: i64 = 1;
    let a: i64 = 0;
    let dump: i64 = 0;
    if argc() < 2 {
        print("用法: dwmo <file.elf> [-d | -s]\n");
        print("  -d  转储全部 DIE\n");
        print("  -s  全程序扫描：通用校验（对任何 -g 产物都成立）\n");
        print("  -S  同上，并逐函数打印 lo hi 指令数（供外部反汇编器交叉验证）\n");        print("  -l  行号表校验：地址与函数边界、定义行是否可下断点\n");
        print("  -L <src>  同上，并拿源码做语义级校验（行号不能\n");
        print("            指向注释行、定义行必须真的是 fn 那一行）\n");
        return 1;
    }
    let smode: i64 = 0;
    let lmode: i64 = 0;
    if heap_ready() == 0 { heap_init(); }
    BUF = alloc(BUFSZ);
    if BUF == 0 {
        print("dwmo: 堆分配失败\n");
        return 1;
    }
    while i < argc() {
        a = argv(i);
        if streq(a, "-d") == 1 { dump = 1; }
        if streq(a, "-s") == 1 { smode = 1; }
        if streq(a, "-S") == 1 { smode = 1; SC_PERFN = 1; }
        if streq(a, "-l") == 1 { lmode = 1; }
        # -L 后面必须跟路径：argv() 返回的指针下次调用就失效，必须拷走
        if streq(a, "-L") == 1 {
            lmode = 1;
            i = i + 1;
            if i < argc() {
                strcpy(&SRCP, argv(i));
                S_HAS = 1;
            }
        }
        i = i + 1;
    }
    FSZ = read_file(argv(1), BUF, BUFSZ);
    if FSZ <= 0 {
        print("dwmo: 无法读取 ");
        print(argv(1));
        print_nl();
        return 1;
    }
    I_TEXT = 0 - 1;
    I_INFO = 0 - 1;
    I_ABBR = 0 - 1;
    I_FRAME = 0 - 1;
    I_LINE = 0 - 1;
    rc = parse_elf();
    if rc == 0 - 1 { print("dwmo: 不是 ELF\n"); return 1; }
    if rc == 0 - 2 { print("dwmo: 只支持 ELF64\n"); return 1; }
    if I_INFO < 0 { print("dwmo: 没有 .debug_info（编译时加 -g）\n"); return 1; }
    if I_ABBR < 0 { print("dwmo: 没有 .debug_abbrev\n"); return 1; }
    if I_TEXT < 0 { print("dwmo: 没有 .text\n"); return 1; }
    if I_FRAME < 0 { print("dwmo: 没有 .debug_frame\n"); return 1; }
    parse_abbrev();
    if CAPERR == 1 { return 1; }
    parse_info();
    if CAPERR == 1 { return 1; }
    parse_frame();
    if CAPERR == 1 { return 1; }
    if lmode == 1 {
        if I_LINE < 0 {
            print("dwmo: 没有 .debug_line（编译时加 -g）\n");
            return 1;
        }
        build_fns();
        parse_line();
        if CAPERR == 1 { return 1; }
        line_report();
        if CAPERR == 1 { print("dwmo: 容量不足，结果不完整\n"); return 1; }
        if S_HAS == 1 {
            if src_load(&SRCP) != 0 { return 1; }
            src_check();
        }
        print("\n通过 ");
        print_i64(PASS);
        print(" / 失败 ");
        print_i64(FAIL);
        print_nl();
        if FAIL > 0 { return 1; }
        return 0;
    }
    if smode == 1 {
        scan_all();
        if CAPERR == 1 { return 1; }
        scan_report();
        if CAPERR == 1 { print("dwmo: 容量不足，结果不完整\n"); return 1; }
        print("\n通过 ");
        print_i64(PASS);
        print(" / 失败 ");
        print_i64(FAIL);
        print_nl();
        if FAIL > 0 { return 1; }
        return 0;
    }
    if dump == 1 {
        dump_all();
        return 0;
    }
    run_checks();
    # 🔴 容量不足必须反映在退出码上，否则"通过"里混着没检查完的函数
    if CAPERR == 1 { print("dwmo: 容量不足，结果不完整\n"); return 1; }
    print("\n通过 ");
    print_i64(PASS);
    print(" / 失败 ");
    print_i64(FAIL);
    print_nl();
    if FAIL > 0 { return 1; }
    return 0;
}
