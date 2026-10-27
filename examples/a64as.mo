# a64as —— 用墨语言写的 AArch64 汇编器（直接输出机器码 + ELF）
#
# ── 与 cfs-aarch64 的差别（本程序存在的理由）────────────────
#   现有 cfs-aarch64 后端是「墨语言 → C 源码 → 外部 clang/ld.lld → ELF」，
#   产物由**外部工具链**决定。本程序是另一条路：
#       墨语言 → 墨语言写的编码器 → aarch64 机器码字节 → ELF
#   全程没有任何 C 编译器、汇编器、链接器参与；ELF 头与程序头
#   的每个字节都是本程序用 store8 写出来的。
#
# ── 两遍汇编 ────────────────────────────────────────────────
#   pass1 完整编码一遍（只为定出 label 地址），丢弃 fixup；
#   pass2 再编码一遍并回填跳转偏移。
#   之所以不采用「pass1 只数指令条数」：像 mov rd,#imm 这种
#   按立即数大小变长的伪指令，两遍必须走**同一条编码路径**，
#   否则条数算错 → 所有 label 偏移整体错位（静默）。
#
# ── 段与地址 ────────────────────────────────────────────────
#   单 PT_LOAD：代码在前、数据在后，全部映射到 BASE。
#     text 第 i 条指令地址 = BASE + i*4
#     data 第 j 字节地址   = BASE + NC*4 + j

import "io.mo";
import "str.mo";

var SRC: [16384] i64 = 0;
var SL: i64 = 0;
var CODE: [8192] i64 = 0;
var NC: i64 = 0;
var DAT: [16384] i64 = 0;
var ND: i64 = 0;
# .bss：只计大小、不产生任何文件字节（SHT_NOBITS）。bss 第 j 字节地址
# = BASE + NC*4 + ND + j。若把它当 .data 写出去，"零初始化"就变成了
# "文件里存了一堆 0" —— 文件变大但行为完全一样，看不出来。
var NBB: i64 = 0;
var LBL: [256] i64 = 0;
var LBS: [256] i64 = 0;
var LBO: [256] i64 = 0;
var NL: i64 = 0;
var NMP: [4096] i64 = 0;
var NPP: i64 = 0;
var FXC: [2048] i64 = 0;
var FXL: [2048] i64 = 0;
var FXT: [2048] i64 = 0;
var NF: i64 = 0;
# .rela.data：数据段里的绝对地址（.quad sym），类型恒为 257 R_AARCH64_ABS64
var DFXO: [512] i64 = 0;
var DFXL: [512] i64 = 0;
var NDF: i64 = 0;
var OUT: [8192] i64 = 0;
var ERR: i64 = 0;
var PP: i64 = 0;
var LINE: [512] i64 = 0;
var TMP: [64] i64 = 0;
var TMP2: [64] i64 = 0;
var CURSEC: i64 = 0;
var BASE: i64 = 1073741824;

# ── -r 模式（输出可重定位目标文件 ET_REL）────────────────────
#   单文件模式下所有地址当场可算（BASE 已知），于是 fixup 直接回填。
#   -r 模式下地址要等链接器布局，所以 fixup **不回填**，改成写进
#   .rela.text —— 重定位类型用 AArch64 ELF 的真实值（不是私有编号）：
#     283 CALL26 · 282 JUMP26 · 280 CONDBR19
#     275 ADR_PREL_PG_HI21 · 277 ADD_ABS_LO12_NC · 264.. MOVW_UABS_Gn
#   这样链接器产出的重定位语义可以被独立工具按规范交叉验证。
var RELM: i64 = 0;
var GLB: [128] i64 = 0;
var NGL: i64 = 0;
# rdreg 把 sp / xzr 都解析成 31，但**两者在指令里的含义不一样**：
# add/sub/ldr/str 里 31 是 SP，orr(=mov 寄存器形式) 里 31 是 XZR。
# 不区分的话 `mov x21, sp` 会被编成 `orr x21, xzr, xzr`，栈顶变成 0，
# 第一次写栈就落到 0xFFFFFFFFFFFFFFF8 —— 报 Invalid memory write，
# 症状看着像内存布局错了，根因只是寄存器名。
var LASTSP: i64 = 0;
# ldr/str 原先**恒编 64 位**（size=11），写 `ldr w10, [x9]` 也照样编出 0xF94...。
# 于是读 GIC 这类 32 位 MMIO 寄存器会顺带把**相邻的下一个寄存器**读进来：
# IAR(0x...000C) 的 8 字节里有一半是 EOIR(0x...0010)，第二次读就变成
# 0x1E0000001E。缺了 32 位变体，内核连"正确访问 32 位寄存器"都写不出来。
var LASTW: i64 = 0;

# 参数是**字符串**，声明成 i64 在 moc 下能过（墨语言里 i64 与地址同宽），
# 但 mo2x 的 C 后端会真的区分类型：print(m) 变成把 long long 传给 print(
# unsigned char*)，54 处调用全部报 incompatible pointer/integer conversion。
# 声明成 ptr 才是它本来的语义。
fn fail(m: ptr) -> i64 {
    print("a64as: ");
    print(m);
    print_nl();
    ERR = ERR + 1;
    return 0;
}

fn emit(w: i64) -> i64 {
    if NC >= 8192 { fail("code overflow"); return 0; }
    CODE[NC] = w;
    NC = NC + 1;
    return 0;
}

fn bbyte() -> i64 {
    if NBB >= 262144 { fail("bss overflow"); return 0; }
    NBB = NBB + 1;
    return 0;
}

fn dbyte(b: i64) -> i64 {
    if CURSEC == 3 { return bbyte(); }
    if ND >= 16384 { fail("data overflow"); return 0; }
    store8(&DAT + ND, b);
    ND = ND + 1;
    return 0;
}

fn skipsp() -> i64 {
    while 1 {
        let c: i64 = load8(&LINE + PP);
        if c == 32 { PP = PP + 1; }
        else {
            if c == 9 { PP = PP + 1; }
            else { break; }
        }
    }
    return 0;
}

fn isident(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c >= 48 { if c <= 57 { return 1; } }
    if c == 95 { return 1; }
    if c == 46 { return 1; }
    return 0;
}

fn rdnum() -> i64 {
    let neg: i64 = 0;
    let c: i64 = load8(&LINE + PP);
    if c == 45 { neg = 1; PP = PP + 1; }
    let v: i64 = 0;
    c = load8(&LINE + PP);
    if c == 48 {
        if load8(&LINE + PP + 1) == 120 {
            PP = PP + 2;
            while 1 {
                let d: i64 = load8(&LINE + PP);
                let dv: i64 = -1;
                if d >= 48 { if d <= 57 { dv = d - 48; } }
                if d >= 97 { if d <= 102 { dv = d - 87; } }
                if d >= 65 { if d <= 70 { dv = d - 55; } }
                if dv < 0 { break; }
                v = v * 16 + dv;
                PP = PP + 1;
            }
            if neg == 1 { v = 0 - v; }
            return v;
        }
    }
    while 1 {
        let d: i64 = load8(&LINE + PP);
        if d < 48 { break; }
        if d > 57 { break; }
        v = v * 10 + (d - 48);
        PP = PP + 1;
    }
    if neg == 1 { v = 0 - v; }
    return v;
}

# xzr / wzr 必须显式支持：此前只有裸 "zr" 走得通，于是 "str xzr, [x0,#8]"
# 把 "zr" 当成寄存器号去解析 —— 报的是 expected , / expected [（指向后面的
# 操作数），而真正的错是**寄存器名没被认出来**。症状离根因很远。
fn rdreg() -> i64 {
    skipsp();
    let c: i64 = load8(&LINE + PP);
    LASTSP = 0;
    LASTW = 0;
    if c == 115 {
        if load8(&LINE + PP + 1) == 112 { PP = PP + 2; LASTSP = 1; return 31; }
    }
    if c == 122 { PP = PP + 3; return 31; }
    if c == 119 {
        if load8(&LINE + PP + 1) == 122 {
            if load8(&LINE + PP + 2) == 114 { PP = PP + 3; return 31; }
        }
        PP = PP + 1;
        LASTW = 1;
        return rdnum();
    }
    if c == 120 {
        if load8(&LINE + PP + 1) == 122 {
            if load8(&LINE + PP + 2) == 114 { PP = PP + 3; return 31; }
        }
        PP = PP + 1;
        return rdnum();
    }
    fail("bad register");
    return 31;
}

fn expectcomma() -> i64 {
    skipsp();
    let c: i64 = load8(&LINE + PP);
    if c == 44 { PP = PP + 1; return 0; }
    fail("expected ,");
    return 0;
}

fn rdimm() -> i64 {
    skipsp();
    let c: i64 = load8(&LINE + PP);
    if c == 35 { PP = PP + 1; }
    return rdnum();
}

# imm12 只有 12 位。不检查就会**静默截断**：
#   cmp x0, #5050 → 5050 & 0xFFF = 954，编出一条合法但语义错误的指令，
#   程序照跑、退出码正常，只是判据永远不成立（本轮实测踩到）。
fn rdimm12() -> i64 {
    let v: i64 = rdimm();
    if v < 0 { fail("immediate out of range (imm12: 0..4095)"); return 0; }
    if v > 4095 { fail("immediate out of range (imm12: 0..4095)"); return 0; }
    return v;
}

# 载入/存储的偏移按 8 字节缩放后仍要能放进 imm12；
# 非 8 倍数的偏移会被 /8 静默抹成错的字节数
fn rdoff() -> i64 {
    let v: i64 = rdimm();
    if v < 0 { fail("negative offset"); return 0; }
    if (v / 8) * 8 != v { fail("offset must be a multiple of 8"); return 0; }
    if v / 8 > 4095 { fail("offset too large"); return 0; }
    return v;
}

fn rdident(dst: ptr) -> i64 {
    # 必须先跳空白：`bl  f` / `ldaddr x0, x` 的分隔符后面都有空格，
    # 不跳的话读到的是空串 —— 症状是「undefined label」，指向用户代码
    skipsp();
    let i: i64 = 0;
    while isident(load8(&LINE + PP)) == 1 {
        store8(dst + i, load8(&LINE + PP));
        i = i + 1;
        PP = PP + 1;
    }
    store8(dst + i, 0);
    return i;
}

fn deflabel(a: i64, b: i64) -> i64 {
    let off: i64 = NPP;
    let i: i64 = a;
    while i < b {
        store8(&NMP + NPP, load8(&LINE + i));
        NPP = NPP + 1;
        i = i + 1;
    }
    store8(&NMP + NPP, 0);
    NPP = NPP + 1;
    if NL >= 256 { fail("too many labels"); return 0; }
    LBL[NL] = off;
    LBS[NL] = CURSEC;
    if CURSEC == 0 { LBO[NL] = NC; }
    else {
        if CURSEC == 3 { LBO[NL] = NBB; } else { LBO[NL] = ND; }
    }
    NL = NL + 1;
    return 0;
}

fn findlbl(nm: ptr) -> i64 {
    let i: i64 = 0;
    while i < NL {
        if streq(&NMP + LBL[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

fn lbl_addr(i: i64) -> i64 {
    if LBS[i] == 2 { return 0; }
    if LBS[i] == 0 { return BASE + LBO[i] * 4; }
    if LBS[i] == 3 { return BASE + NC * 4 + ND + LBO[i]; }
    return BASE + NC * 4 + LBO[i];
}

# 引用了本文件没有定义的符号：在 -r 模式下它不是错误，而是登记一个
# SHN_UNDEF 符号交给链接器解析（st_shndx=0 由 LBS==2 表示）。
fn addextern(nm: ptr) -> i64 {
    let i: i64 = findlbl(nm);
    if i >= 0 { return i; }
    let off: i64 = NPP;
    let j: i64 = 0;
    while load8(nm + j) != 0 {
        store8(&NMP + NPP, load8(nm + j));
        NPP = NPP + 1;
        j = j + 1;
    }
    store8(&NMP + NPP, 0);
    NPP = NPP + 1;
    if NL >= 256 { fail("too many labels"); return 0; }
    LBL[NL] = off;
    LBS[NL] = 2;
    LBO[NL] = 0;
    NL = NL + 1;
    return NL - 1;
}

fn isglobal(nm: ptr) -> i64 {
    let i: i64 = 0;
    while i < NGL {
        if streq(&NMP + GLB[i], nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

# -r 模式下解析一个 label 引用；resolve==0 是 pass1（前向 label 尚未登记，
# 其 fixup 会被丢弃），resolve==1 是 pass2。
fn reflbl(nm: ptr, resolve: i64) -> i64 {
    let li: i64 = findlbl(nm);
    if li >= 0 { return li; }
    if RELM == 1 {
        if resolve == 0 { return 0; }
        return addextern(nm);
    }
    if resolve == 1 { fail("undefined label"); return 0; }
    return 0;
}

fn addfix(li: i64, ty: i64) -> i64 {
    if NF >= 2048 { fail("fixup overflow"); return 0; }
    FXC[NF] = NC;
    FXL[NF] = li;
    FXT[NF] = ty;
    NF = NF + 1;
    return 0;
}

# ── 伪指令 ──────────────────────────────────────────────────
fn do_directive(resolve: i64) -> i64 {
    PP = PP + 1;
    rdident(&TMP);
    if streq(&TMP, "text") == 1 { CURSEC = 0; return 0; }
    if streq(&TMP, "data") == 1 { CURSEC = 1; return 0; }
    if streq(&TMP, "bss") == 1 { CURSEC = 3; return 0; }
    if streq(&TMP, "zero") == 1 {
        let n: i64 = rdimm();
        # .zero 在 **.text** 里必须真的推进代码指针：第一版只调 dbyte()，
        # 于是在代码段里写 .zero 会把字节塞进 .data，NC 一动不动 ——
        # 异常向量表因此少了一整块间隔，sync_lower 落到 VBAR+0x000 而不是
        # +0x400，CPU 从错误偏移取指（静默跑飞，不报错）。
        if CURSEC == 0 {
            let nw: i64 = (n + 3) / 4;
            let j: i64 = 0;
            while j < nw { emit(0); j = j + 1; }
            return 0;
        }
        let i: i64 = 0;
        while i < n { dbyte(0); i = i + 1; }
        return 0;
    }
    if streq(&TMP, "byte") == 1 {
        if CURSEC == 3 { fail("cannot initialize .bss"); return 0; }
        while 1 {
            dbyte(rdimm());
            skipsp();
            if load8(&LINE + PP) != 44 { break; }
            PP = PP + 1;
        }
        return 0;
    }
    if streq(&TMP, "asciz") == 1 {
        if CURSEC == 3 { fail("cannot initialize .bss"); return 0; }
        do_ascii();
        dbyte(0);
        return 0;
    }
    if streq(&TMP, "ascii") == 1 {
        if CURSEC == 3 { fail("cannot initialize .bss"); return 0; }
        return do_ascii();
    }
    if streq(&TMP, "align") == 1 {
        let n: i64 = rdimm();
        if n <= 0 { n = 4; }
        if CURSEC == 3 {
            while (NBB - (NBB / n) * n) != 0 { bbyte(); }
            return 0;
        }
        if CURSEC == 0 {
            let m: i64 = n / 4;
            if m < 1 { m = 1; }
            while (NC - (NC / m) * m) != 0 { emit(3573751839); }
            return 0;
        }
        while (ND - (ND / n) * n) != 0 { dbyte(0); }
        return 0;
    }
    if streq(&TMP, "quad") == 1 {
        if CURSEC == 3 { fail("cannot initialize .bss"); return 0; }
        while 1 {
            skipsp();
            rdident(&TMP2);
            if load8(&TMP2) == 0 { fail(".quad needs a symbol"); return 0; }
            let li: i64 = reflbl(&TMP2, resolve);
            if resolve == 1 {
                if NDF >= 512 { fail("data fixup overflow"); return 0; }
                DFXO[NDF] = ND;
                DFXL[NDF] = li;
                NDF = NDF + 1;
            }
            let i: i64 = 0;
            while i < 8 { dbyte(0); i = i + 1; }
            skipsp();
            if load8(&LINE + PP) != 44 { break; }
            PP = PP + 1;
        }
        return 0;
    }
    if streq(&TMP, "globl") == 1 {
        skipsp();
        let i: i64 = 0;
        while isident(load8(&LINE + PP)) == 1 {
            store8(&TMP2 + i, load8(&LINE + PP));
            i = i + 1;
            PP = PP + 1;
        }
        store8(&TMP2 + i, 0);
        if i == 0 { fail(".globl needs a name"); return 0; }
        if NGL >= 128 { fail("too many globals"); return 0; }
        # 名字存进 NMP 池，与 label 名共用一份存储，比较时才能直接 streq
        let off: i64 = NPP;
        let j: i64 = 0;
        while load8(&TMP2 + j) != 0 {
            store8(&NMP + NPP, load8(&TMP2 + j));
            NPP = NPP + 1;
            j = j + 1;
        }
        store8(&NMP + NPP, 0);
        NPP = NPP + 1;
        GLB[NGL] = off;
        NGL = NGL + 1;
        return 0;
    }
    return 0;
}

fn do_ascii() -> i64 {
    skipsp();
    if load8(&LINE + PP) != 34 { fail("expected string"); return 0; }
    PP = PP + 1;
    while 1 {
        let c: i64 = load8(&LINE + PP);
        if c == 34 { PP = PP + 1; break; }
        if c == 0 { fail("unterminated string"); return 0; }
        if c == 92 {
            PP = PP + 1;
            let e: i64 = load8(&LINE + PP);
            if e == 110 { dbyte(10); }
            else {
                if e == 48 { dbyte(0); }
                else { dbyte(e); }
            }
            PP = PP + 1;
        } else {
            dbyte(c);
            PP = PP + 1;
        }
    }
    return 0;
    fail("unknown directive");
    return 0;
}

fn pow16(k: i64) -> i64 {
    if k == 0 { return 1; }
    if k == 1 { return 65536; }
    if k == 2 { return 4294967296; }
    return 281474976710656;
}

fn cond_of(nm: ptr) -> i64 {
    if streq(nm, "eq") == 1 { return 0; }
    if streq(nm, "ne") == 1 { return 1; }
    if streq(nm, "cs") == 1 { return 2; }
    if streq(nm, "cc") == 1 { return 3; }
    if streq(nm, "mi") == 1 { return 4; }
    if streq(nm, "pl") == 1 { return 5; }
    if streq(nm, "vs") == 1 { return 6; }
    if streq(nm, "vc") == 1 { return 7; }
    if streq(nm, "hi") == 1 { return 8; }
    if streq(nm, "ls") == 1 { return 9; }
    if streq(nm, "ge") == 1 { return 10; }
    if streq(nm, "lt") == 1 { return 11; }
    if streq(nm, "gt") == 1 { return 12; }
    if streq(nm, "le") == 1 { return 13; }
    return -1;
}

# 系统寄存器编码：op0:op1:CRn:CRm:op2 = (op0<<14)|(op1<<11)|(CRn<<7)|(CRm<<3)|op2
# 这是 ARM ARM 里 MRS/MSR 的**规范**编码，不是自定义编号 —— 所以产出的
# 机器码能被第三方反汇编器（capstone）按同一份规范核对。
fn sysreg_of(nm: ptr) -> i64 {
    if streq(nm, "vbar_el1") == 1 { return 50688; }
    if streq(nm, "elr_el1") == 1 { return 49665; }
    if streq(nm, "spsr_el1") == 1 { return 49664; }
    if streq(nm, "sp_el0") == 1 { return 49672; }
    # sp_el1：内核用它指定**自己**的栈。缺了它，陷入后切过去的是模拟器给的
    # 默认栈（程序照样跑完，"内核栈没按内核意图设置"永远测不出来）。
    if streq(nm, "sp_el1") == 1 { return 49673; }
    # 异常相关的两个寄存器：没有 esr_el1 就**无法区分**异常原因（SVC？
    # 被陷入的特权指令？数据中止？），内核只能盲猜 —— 这是 v1.172 加 svc
    # 支持时立刻撞上的缺口：助记符和 eret 都在，偏偏读不出异常原因。
    if streq(nm, "esr_el1") == 1 { return 49808; }
    if streq(nm, "far_el1") == 1 { return 49920; }
    if streq(nm, "cntfrq_el0") == 1 { return 57088; }
    if streq(nm, "cntvct_el0") == 1 { return 57090; }
    if streq(nm, "tpidr_el1") == 1 { return 50820; }
    # MMU 四个寄存器：缺了它们就**无法**在墨语言写的内核里开页表 ——
    # 没有 MMU 时 EL0/EL1 的隔离只是"约定"（见 docs/a64svc.md 的已知限制），
    # 有了它们，隔离变成**页表里的 AP 位**说了算。
    # 五个编码都由 capstone 按 ARM ARM 独立核对过：
    #   0xd5182000 = msr ttbr0_el1, x0   0xd5182020 = msr ttbr1_el1, x0
    #   0xd5182040 = msr tcr_el1,  x0   0xd518a200 = msr mair_el1, x0
    #   0xd5181000 = msr sctlr_el1,x0
    if streq(nm, "ttbr0_el1") == 1 { return 49408; }
    if streq(nm, "ttbr1_el1") == 1 { return 49409; }
    if streq(nm, "tcr_el1") == 1 { return 49410; }
    if streq(nm, "mair_el1") == 1 { return 50448; }
    if streq(nm, "sctlr_el1") == 1 { return 49280; }
    return -1;
}

# STP/LDP 的偏移是 imm7，**按 8 字节缩放**。
# 不检查"必须是 8 的倍数"就会被 /8 静默抹成另一个字节数 —— 和 imm12
# 静默截断是同一类错：指令合法、程序照跑、只是搬错了地方。
fn rdoff7() -> i64 {
    let v: i64 = rdimm();
    if v < 0 { fail("negative offset"); return 0; }
    if (v / 8) * 8 != v { fail("pair offset must be a multiple of 8"); return 0; }
    if v / 8 > 127 { fail("pair offset out of range (imm7: 0..1016)"); return 0; }
    return v / 8;
}

# STP/LDP（64 位，signed offset）：
#   |opc=10|101|V=0|L|imm7(21:15)|Rt2(14:10)|Rn(9:5)|Rt(4:0)|
#   store 基址 0xA9000000 · load 基址 0xA9400000
# 上下文切换必须成对搬运寄存器，没有它就得一条条 str/ldr —— 那既不原子
# 也写不出像样的现场保存。
fn do_pair(isld: i64) -> i64 {
    let rt: i64 = rdreg();
    expectcomma();
    let rt2: i64 = rdreg();
    expectcomma();
    skipsp();
    if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
    PP = PP + 1;
    let rn: i64 = rdreg();
    let off: i64 = 0;
    skipsp();
    if load8(&LINE + PP) == 44 {
        PP = PP + 1;
        off = rdoff7();
    }
    skipsp();
    if load8(&LINE + PP) != 93 { fail("expected ]"); return 0; }
    PP = PP + 1;
    let base: i64 = 2835349504;
    if isld == 1 { base = 2839543808; }
    emit(base | (off * 32768) | (rt2 * 1024) | (rn * 32) | rt);
    return 0;
}

# 一条指令的编码。
#   **所有** label 引用一律登记 fixup，最后统一 apply_fixups 回填。
#   早先 pass2 在这里内联算偏移，用的是「当时的 NC」；而数据段地址要用
#   「最终 NC」—— 两处算法不一致，ldaddr 拿到的是 0x40000008 这种
#   指向代码区的地址，程序读到的字节是机器码而非字符串（静默无输出）。
fn do_insn(resolve: i64) -> i64 {
    rdident(&TMP);
    if streq(&TMP, "movz") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let im: i64 = rdimm();
        let sh: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            skipsp();
            rdident(&TMP);
            if streq(&TMP, "lsl") == 1 { sh = rdimm(); }
        }
        let hw: i64 = sh / 16;
        emit(0xD2800000 | (hw * 2097152) | (im * 32) | rd);
        return 0;
    }
    if streq(&TMP, "movk") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let im: i64 = rdimm();
        let sh: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            skipsp();
            rdident(&TMP);
            if streq(&TMP, "lsl") == 1 { sh = rdimm(); }
        }
        let hw: i64 = sh / 16;
        emit(0xF2800000 | (hw * 2097152) | (im * 32) | rd);
        return 0;
    }
    if streq(&TMP, "mov") == 1 {
        let rd: i64 = rdreg();
        let dsp: i64 = LASTSP;
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm();
            let sh: i64 = 0;
            while sh < 64 {
                let part: i64 = (im / pow16(sh / 16)) % 65536;
                if sh == 0 {
                    emit(0xD2800000 | (part * 32) | rd);
                } else {
                    if part != 0 {
                        emit(0xF2800000 | ((sh / 16) * 2097152) | (part * 32) | rd);
                    }
                }
                sh = sh + 16;
            }
            return 0;
        }
        let rm: i64 = rdreg();
        let ssp: i64 = LASTSP;
        if ssp == 1 {
            # mov Xd, sp → **add Xd, sp, #0**（0x91000000 | 31<<5 | rd）
            emit(0x91000000 | (31 * 32) | rd);
            return 0;
        }
        if dsp == 1 {
            # mov sp, Xm → add sp, Xm, #0
            emit(0x91000000 | (rm * 32) | 31);
            return 0;
        }
        emit(0xAA000000 | (rm * 65536) | (31 * 32) | rd);
        return 0;
    }
    if streq(&TMP, "add") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm12();
            emit(0x91000000 | (im * 1024) | (rn * 32) | rd);
            return 0;
        }
        let rm: i64 = rdreg();
        emit(0x8B000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "sub") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm12();
            emit(0xD1000000 | (im * 1024) | (rn * 32) | rd);
            return 0;
        }
        let rm: i64 = rdreg();
        emit(0xCB000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "cmp") == 1 {
        let rn: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm12();
            emit(0xF1000000 | (im * 1024) | (rn * 32) | 31);
            return 0;
        }
        let rm: i64 = rdreg();
        emit(0xEB000000 | (rm * 65536) | (rn * 32) | 31);
        return 0;
    }
    # ── 第二批：算术与条件 ────────────────────────────────────
    # udiv/sdiv：AArch64 的整数除法**不设标志**，且除零返回 0 而不 trap。
    # 这与 x86 的 idiv（除零 #DE、溢出 #DE）是两种语义，照搬直觉会出错。
    if streq(&TMP, "udiv") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0x9AC00800 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "sdiv") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0x9AC00C00 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    # msub xd, xn, xm, xa  ==>  xd = xa - xn * xm
    # 取余只能靠它（a - (a/b)*b）。Ra 在 bit14..10，与 Rm 的 bit20..16
    # 是两个不同字段 —— 写错位置会得到「合法但值不对」的指令。
    if streq(&TMP, "msub") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        expectcomma();
        let ra: i64 = rdreg();
        emit(0x9B008000 | (rm * 65536) | (ra * 1024) | (rn * 32) | rd);
        return 0;
    }
    # lsr/asr 立即数是 UBFM/SBFM 的别名：immr=sh、imms=63。
    # 注意与 lsl 的 immr=(64-sh)%64、imms=63-sh 不同 —— 同族指令的另一
    # 个成员，参数化方式不一样，不能套同一个公式。
    if streq(&TMP, "lsr") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let sh: i64 = rdimm();
        if sh < 0 { fail("bad shift"); return 0; }
        if sh > 63 { fail("shift out of range"); return 0; }
        emit(0xD3400000 | (sh * 65536) | (63 * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "asr") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let sh: i64 = rdimm();
        if sh < 0 { fail("bad shift"); return 0; }
        if sh > 63 { fail("shift out of range"); return 0; }
        emit(0x93400000 | (sh * 65536) | (63 * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "neg") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0xCB000000 | (rm * 65536) | (31 * 32) | rd);
        return 0;
    }
    if streq(&TMP, "bic") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0x8A200000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "mvn") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0xAA200000 | (rm * 65536) | (31 * 32) | rd);
        return 0;
    }
    # csel xd, xn, xm, cond —— 条件码在 bit15..12（不是 b.cond 的 bit3..0）
    if streq(&TMP, "csel") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        expectcomma();
        skipsp();
        rdident(&TMP);
        let cd: i64 = cond_of(&TMP);
        if cd < 0 { fail("bad cond"); return 0; }
        emit(0x9A800000 | (rm * 65536) | (cd * 4096) | (rn * 32) | rd);
        return 0;
    }
    # cbz/cbnz：imm19 落在 bit23..5，与 b.cond 完全一致，故 fixup 类型
    # 复用 1(CONDBR19)。但**指令字不同**，而 reltype 是按字反推的 ——
    # 不加那两条分类的话，-r 模式会 fail("cannot classify relocation")，
    # 症状看着像「用了不支持的指令」，实为重定位分类漏了两个字。
    if streq(&TMP, "cbz") == 1 {
        let rt: i64 = rdreg();
        expectcomma();
        skipsp();
        rdident(&TMP);
        let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 1);
        emit(0xB4000000 | rt);
        return 0;
    }
    if streq(&TMP, "cbnz") == 1 {
        let rt: i64 = rdreg();
        expectcomma();
        skipsp();
        rdident(&TMP);
        let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 1);
        emit(0xB5000000 | rt);
        return 0;
    }
    # subs/adds 带 S 位会设标志（cmp 就是 subs 写 xzr）。缺了它们，
    # 循环计数只能靠额外的 cmp —— 多一条指令且掩盖了标志的来源。
    if streq(&TMP, "subs") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm12();
            emit(0xF1000000 | (im * 1024) | (rn * 32) | rd);
            return 0;
        }
        let rm: i64 = rdreg();
        emit(0xEB000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "adds") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) == 35 {
            let im: i64 = rdimm12();
            emit(0xB1000000 | (im * 1024) | (rn * 32) | rd);
            return 0;
        }
        let rm: i64 = rdreg();
        emit(0xAB000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    # 半字：offset 的缩放量是 2 字节，与 ldr/str 的 8 字节不是一个量纲。
    if streq(&TMP, "ldrh") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdoff();
        }
        emit(0x79400000 | ((off / 2) * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "strh") == 1 {
        let rs: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdoff();
        }
        emit(0x79000000 | ((off / 2) * 1024) | (rn * 32) | rs);
        return 0;
    }
    if streq(&TMP, "mul") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0x9B000000 | (rm * 65536) | (31 * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "and") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0x8A000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "orr") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0xAA000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "eor") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let rm: i64 = rdreg();
        emit(0xCA000000 | (rm * 65536) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "lsl") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        let sh: i64 = rdimm();
        let immr: i64 = (64 - sh) % 64;
        let imms: i64 = 63 - sh;
        emit(0xD3400000 | (immr * 65536) | (imms * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "ldr") == 1 {
        let rd: i64 = rdreg();
        let dw: i64 = LASTW;
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdoff();
        }
        if dw == 1 { emit(0xB9400000 | ((off / 4) * 1024) | (rn * 32) | rd); }
        else { emit(0xF9400000 | ((off / 8) * 1024) | (rn * 32) | rd); }
        return 0;
    }
    if streq(&TMP, "str") == 1 {
        let rs: i64 = rdreg();
        let sw: i64 = LASTW;
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdoff();
        }
        if sw == 1 { emit(0xB9000000 | ((off / 4) * 1024) | (rn * 32) | rs); }
        else { emit(0xF9000000 | ((off / 8) * 1024) | (rn * 32) | rs); }
        return 0;
    }
    if streq(&TMP, "ldrb") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdimm();
        }
        emit(0x39400000 | (off * 1024) | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "strb") == 1 {
        let rs: i64 = rdreg();
        expectcomma();
        skipsp();
        if load8(&LINE + PP) != 91 { fail("expected ["); return 0; }
        PP = PP + 1;
        let rn: i64 = rdreg();
        let off: i64 = 0;
        skipsp();
        if load8(&LINE + PP) == 44 {
            PP = PP + 1;
            off = rdimm();
        }
        emit(0x39000000 | (off * 1024) | (rn * 32) | rs);
        return 0;
    }
    if streq(&TMP, "ret") == 1 { emit(0xD65F03C0); return 0; }
    if streq(&TMP, "wfi") == 1 { emit(0xD503207F); return 0; }
    if streq(&TMP, "nop") == 1 { emit(0xD503201F); return 0; }
    # 屏障：改完页表/系统寄存器后必须 dsb+isb，否则"改了不生效"。
    # 0xD5033F9F = dsb sy，0xD5033FDF = isb（capstone 核对过）。
    if streq(&TMP, "dsb") == 1 { emit(0xD5033F9F); return 0; }
    if streq(&TMP, "isb") == 1 { emit(0xD5033FDF); return 0; }
    if streq(&TMP, "svc") == 1 { emit(0xD4000001); return 0; }
    if streq(&TMP, "br") == 1 {
        let rn: i64 = rdreg();
        emit(0xD61F0000 | (rn * 32));
        return 0;
    }
    if streq(&TMP, "b") == 1 {
        rdident(&TMP);
		let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 0);
        emit(0x14000000);
        return 0;
    }
    if streq(&TMP, "adrp") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        rdident(&TMP);
        let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 7);
        emit(0x90000000 | rd);
        return 0;
    }
    if streq(&TMP, "addlo") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        let rn: i64 = rdreg();
        expectcomma();
        rdident(&TMP);
        let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 8);
        emit(0x91000000 | (rn * 32) | rd);
        return 0;
    }
    if streq(&TMP, "bl") == 1 {
        rdident(&TMP);
		let li: i64 = reflbl(&TMP, resolve);
        addfix(li, 0);
        emit(0x94000000);
        return 0;
    }
    if streq(&TMP, "blr") == 1 {
        let rn: i64 = rdreg();
        emit(0xD63F0000 | (rn * 32));
        return 0;
    }
    # b.eq / b.ne / ... ：rdident 会把 "b.eq" 整个读进来（'.' 属于 isident），
    # 所以这里按 TMP[0..1] == "b." 判断，条件码取 &TMP+2
    if load8(&TMP + 0) == 98 {
        if load8(&TMP + 1) == 46 {
            let cd: i64 = cond_of(&TMP + 2);
            if cd < 0 { fail("bad cond"); return 0; }
            rdident(&TMP);
			let li: i64 = reflbl(&TMP, resolve);
            addfix(li, 1);
            emit(0x54000000 | cd);
            return 0;
        }
    }
    if streq(&TMP, "ldaddr") == 1 {
        let rd: i64 = rdreg();
        expectcomma();
        rdident(&TMP);
		let li: i64 = reflbl(&TMP, resolve);
        let k: i64 = 0;
        while k < 4 {
            addfix(li, 2 + k);
            if k == 0 { emit(0xD2800000 | rd); }
            else { emit(0xF2800000 | (k * 2097152) | rd); }
            k = k + 1;
        }
        return 0;
    }
    if streq(&TMP, "stp") == 1 { return do_pair(0); }
    if streq(&TMP, "ldp") == 1 { return do_pair(1); }
    if streq(&TMP, "mrs") == 1 {
        let rt2: i64 = rdreg();
        expectcomma();
        rdident(&TMP2);
        let sr: i64 = sysreg_of(&TMP2);
        if sr < 0 { fail("unknown system register"); return 0; }
        emit(3576692736 | (sr * 32) | rt2);
        return 0;
    }
    if streq(&TMP, "msr") == 1 {
        rdident(&TMP2);
        let sr: i64 = sysreg_of(&TMP2);
        if sr < 0 { fail("unknown system register"); return 0; }
        expectcomma();
        let rt2: i64 = rdreg();
        emit(3574595584 | (sr * 32) | rt2);
        return 0;
    }
    if streq(&TMP, "eret") == 1 {
        emit(3600745440);
        return 0;
    }
    fail("unknown mnemonic: ");
    print(&TMP);
    print_nl();
    return 0;
}

# 处理一行
fn do_line(resolve: i64) -> i64 {
    PP = 0;
    skipsp();
    let c: i64 = load8(&LINE + PP);
    if c == 0 { return 0; }
    if c == 35 { return 0; }
    if c == 46 { return do_directive(resolve); }
    # label 定义？
    if isident(c) == 1 {
        let sv: i64 = PP;
        while isident(load8(&LINE + PP)) == 1 { PP = PP + 1; }
        if load8(&LINE + PP) == 58 {
            if resolve == 0 { deflabel(sv, PP); }
            PP = PP + 1;
            skipsp();
            c = load8(&LINE + PP);
            if c == 0 { return 0; }
            if c == 35 { return 0; }
            if c == 46 { return do_directive(resolve); }
            return do_insn(resolve);
        }
        PP = sv;
    }
    return do_insn(resolve);
}

fn assemble(resolve: i64) -> i64 {
    NC = 0;
    ND = 0;
    # NBB 必须和 NC/ND 一样每遍归零：两遍汇编下不复位会得到 **两倍** 的
    # bss 大小。它不报错、程序照跑（bss 只是多了一半空闲空间），
    # 只有"文件大小 vs memsz"这类判据能发现 —— 端到端执行发现不了。
    NBB = 0;
    CURSEC = 0;
    if resolve == 0 {
        NL = 0;
        NPP = 0;
        NF = 0;
        NDF = 0;
    }
    let p: i64 = 0;
    while p < SL {
        let q: i64 = p;
        while q < SL {
            if load8(&SRC + q) == 10 { break; }
            q = q + 1;
        }
        let i: i64 = 0;
        while p + i < q {
            store8(&LINE + i, load8(&SRC + p + i));
            i = i + 1;
        }
        # 去掉行尾 \r
        if i > 0 {
            if load8(&LINE + i - 1) == 13 { i = i - 1; }
        }
        store8(&LINE + i, 0);
        do_line(resolve);
        p = q + 1;
    }
    return 0;
}

fn apply_fixups() -> i64 {
    # -r 模式下地址要等链接器布局，这里**不能**回填，否则 .rela 里的
    # r_offset 会与已写死的立即数打架（链接器再算一遍 = 算两次）。
    if RELM == 1 { return 0; }
    let k: i64 = 0;
    while k < NF {
        let ci: i64 = FXC[k];
        let li: i64 = FXL[k];
        let ty: i64 = FXT[k];
        let insaddr: i64 = BASE + ci * 4;
        if ty == 0 {
            let d: i64 = (lbl_addr(li) - insaddr) / 4;
            CODE[ci] = CODE[ci] | (d & 67108863);
        }
        if ty == 1 {
            let d: i64 = (lbl_addr(li) - insaddr) / 4;
            CODE[ci] = CODE[ci] | ((d & 524287) * 32);
        }
        if ty >= 2 {
            let a: i64 = lbl_addr(li);
            let part: i64 = (a / pow16(ty - 2)) % 65536;
            CODE[ci] = CODE[ci] | (part * 32);
        }
        # adrp：页相对 21 位有符号。immlo 在 bit29、immhi 在 bit5，
        # 负数必须按补码取低位 —— 直接 `imm % 4` 在 imm<0 时得到的是
        # 向零取整的余数（-1 → -1 而非 3），编出的指令**合法但页错**。
        if ty == 7 {
            let a: i64 = lbl_addr(li);
            let pgp: i64 = (insaddr / 4096) * 4096;
            let pgs: i64 = (a / 4096) * 4096;
            let imm: i64 = (pgs - pgp) / 4096;
            let immlo: i64 = imm - (imm / 4) * 4;
            if immlo < 0 { immlo = immlo + 4; }
            let immhi: i64 = ((imm - immlo) / 4) & 524287;
            CODE[ci] = CODE[ci] | (immlo * 536870912) | (immhi * 32);
        }
        # add rd, rn, #:lo12:label —— 取绝对地址低 12 位，不检查溢出
        if ty == 8 {
            let a: i64 = lbl_addr(li);
            let lo: i64 = a - (a / 4096) * 4096;
            if lo < 0 { lo = lo + 4096; }
            CODE[ci] = CODE[ci] | (lo * 1024);
        }
        k = k + 1;
    }
    return 0;
}

fn st64(p: i64, v: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 1;
    while i < 8 {
        store8(&OUT + p + i, (v / d) % 256);
        d = d * 256;
        i = i + 1;
    }
    return 0;
}

fn st32(p: i64, v: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 1;
    while i < 4 {
        store8(&OUT + p + i, (v / d) % 256);
        d = d * 256;
        i = i + 1;
    }
    return 0;
}

fn st16(p: i64, v: i64) -> i64 {
    store8(&OUT + p, v % 256);
    store8(&OUT + p + 1, (v / 256) % 256);
    return 0;
}


var SYN: [256] i64 = 0;

fn slen(s: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 { i = i + 1; }
    return i;
}

fn scp(d: ptr, s: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(d + i, load8(s + i));
        i = i + 1;
    }
    store8(d + i, 0);
    return i + 1;
}

# ── 重定位类型判定 ──────────────────────────────────────────
#   按**指令字**分类，而不是在 addfix 时另存一个私有编号：这样"指令编码"
#   和"重定位类型"只有一处真相，改了编码类型自动跟着变，不会出现
#   「编码已改、reloc 还写着旧值」这种静默不一致。
#   数值全部是 AArch64 ELF 的真实重定位类型，可被独立工具按规范校验。
fn reltype(w: i64) -> i64 {
    if (w & 4227858432) == 2483027968 { return 283; }
    if (w & 4227858432) == 335544320 { return 282; }
    if (w & 4278190096) == 1409286144 { return 280; }
    # cbz / cbnz：imm19 同处 bit23..5，ELF 里也归 CONDBR19
    if (w & 4278190080) == 3019898880 { return 280; }
    if (w & 4278190080) == 3036676096 { return 280; }
    if (w & 2667577344) == 2415919104 { return 275; }
    if (w & 4278190080) == 2432696320 { return 277; }
    if (w & 4286578688) == 3531603968 { return 264; }
    if (w & 4286578688) == 4068474880 { return 264 + ((w / 2097152) & 3); }
    fail("cannot classify relocation");
    return 0;
}

fn wsh(b: i64, nm: i64, ty: i64, fl: i64, off: i64, sz: i64, lk: i64, inf: i64, es: i64) -> i64 {
    st32(b, nm);
    st32(b + 4, ty);
    st64(b + 8, fl);
    st64(b + 16, 0);
    st64(b + 24, off);
    st64(b + 32, sz);
    st32(b + 40, lk);
    st32(b + 44, inf);
    let al: i64 = 1;
    if ty == 4 { al = 8; }
    if ty == 2 { al = 8; }
    if ty == 1 { al = 4; }
    st64(b + 48, al);
    st64(b + 56, es);
    return 0;
}

# ── 输出 ET_REL 可重定位目标文件 ────────────────────────────
#   布局：ehdr(64) .text .data(.bss 不占字节) .rela.text .symtab .strtab .shstrtab shdrs(9×64)
#   第 0 个符号是 null symbol；本文件未定义的符号 st_shndx=0 交给链接器解析。
fn write_rel(path: ptr) -> i64 {
    let tsize: i64 = NC * 4;
    let dsize: i64 = ND;
    let bsize: i64 = NBB;
    let rsize: i64 = NF * 24;
    let rdsize: i64 = NDF * 24;
    let ysize: i64 = (NL + 1) * 24;
    let strsz: i64 = 1;
    let i: i64 = 0;
    while i < NL { strsz = strsz + slen(&NMP + LBL[i]) + 1; i = i + 1; }
    let shssz: i64 = 576;
    # 尾部余量必须 >= 段头表大小（9x64=576）。原先的 512 只够 8 个段头，
    # 加了 .bss 之后段头表写到文件末尾之外 —— 症状是链接器读到
    # "symtab has no strtab link"(SLK=0)，看着像文件坏了，实为段头表被截断。
    let total: i64 = 64 + tsize + dsize + rsize + rdsize + ysize + strsz + shssz + 1024;
    if total > 65536 { fail("output too large for -r"); return 1; }
    i = 0;
    while i < total { store8(&OUT + i, 0); i = i + 1; }

    let tof: i64 = 64;
    let dof: i64 = tof + tsize;
    let rof: i64 = dof + dsize;
    let rdf: i64 = rof + rsize;
    let yof: i64 = rdf + rdsize;
    let sof: i64 = yof + ysize;
    let hof: i64 = sof + strsz;
    let shof: i64 = hof + shssz;

    # ── .text ──
    let k: i64 = 0;
    while k < NC { st32(tof + k * 4, CODE[k] & 4294967295); k = k + 1; }
    # ── .data ──
    k = 0;
    while k < ND { store8(&OUT + dof + k, load8(&DAT + k)); k = k + 1; }
    # ── .shstrtab ──
    store8(&OUT + hof, 0);
    let n1: i64 = hof + 1;
    scp(&OUT + n1, ".text");
    let n2: i64 = n1 + 7;
    scp(&OUT + n2, ".data");
    let nb: i64 = n2 + 6;
    scp(&OUT + nb, ".bss");
    let n3: i64 = nb + 5;
    scp(&OUT + n3, ".rela.text");
    let n4: i64 = n3 + 11;
    scp(&OUT + n4, ".rela.data");
    let n5: i64 = n4 + 11;
    scp(&OUT + n5, ".symtab");
    let n6: i64 = n5 + 8;
    scp(&OUT + n6, ".strtab");
    let n7: i64 = n6 + 8;
    scp(&OUT + n7, ".shstrtab");
    # ── .strtab + 记下每个符号名的偏移 ──
    store8(&OUT + sof, 0);
    let sp: i64 = sof + 1;
    i = 0;
    while i < NL {
        SYN[i] = sp - sof;
        sp = sp + scp(&OUT + sp, &NMP + LBL[i]);
        i = i + 1;
    }
    # ── .symtab ──
    k = 0;
    while k < 24 { store8(&OUT + yof + k, 0); k = k + 1; }
    i = 0;
    while i < NL {
        let e: i64 = yof + (i + 1) * 24;
        st32(e, SYN[i]);
        let bind: i64 = 0;
        if isglobal(&NMP + LBL[i]) == 1 { bind = 1; }
        let ty: i64 = 1;
        if LBS[i] == 0 { ty = 2; }
        if LBS[i] == 2 { ty = 0; }
        store8(&OUT + e + 4, bind * 16 + ty);
        store8(&OUT + e + 5, 0);
        let shn: i64 = 2;
        if LBS[i] == 0 { shn = 1; }
        if LBS[i] == 2 { shn = 0; }
        if LBS[i] == 3 { shn = 3; }
        st16(e + 6, shn);
        let v: i64 = LBO[i];
        if LBS[i] == 0 { v = LBO[i] * 4; }
        if LBS[i] == 2 { v = 0; }
        st64(e + 8, v);
        st64(e + 16, 0);
        i = i + 1;
    }
    # ── .rela.text ──
    k = 0;
    while k < NF {
        let e: i64 = rof + k * 24;
        st64(e, FXC[k] * 4);
        let rt: i64 = reltype(CODE[FXC[k]]);
        st64(e + 8, (FXL[k] + 1) * 4294967296 + rt);
        st64(e + 16, 0);
        k = k + 1;
    }
    # ── .rela.data ──
    k = 0;
    while k < NDF {
        let e: i64 = rdf + k * 24;
        st64(e, DFXO[k]);
        st64(e + 8, (DFXL[k] + 1) * 4294967296 + 257);
        st64(e + 16, 0);
        k = k + 1;
    }
    # ── section headers ──
    wsh(shof + 0, 0, 0, 0, 0, 0, 0, 0, 0);
    wsh(shof + 64, n1 - hof, 1, 6, tof, tsize, 0, 0, 0);
    wsh(shof + 128, n2 - hof, 1, 3, dof, dsize, 0, 0, 0);
    # .bss：SHT_NOBITS=8，只有 sh_size 有意义；sh_offset 给个不重叠的值
    # 纯属惯例 —— 它不占任何文件字节。若这里误写成 1(PROGBITS)，链接器
    # 会把 NBB 个字节真的读进 data，于是 bss 与 data 在内存里重叠。
    wsh(shof + 192, nb - hof, 8, 3, dof + dsize, bsize, 0, 0, 0);
    wsh(shof + 256, n3 - hof, 4, 0, rof, rsize, 6, 1, 24);
    wsh(shof + 320, n4 - hof, 4, 0, rdf, rdsize, 6, 2, 24);
    wsh(shof + 384, n5 - hof, 2, 0, yof, ysize, 7, 1, 24);
    wsh(shof + 448, n6 - hof, 3, 0, sof, strsz, 0, 0, 0);
    wsh(shof + 512, n7 - hof, 3, 0, hof, shssz, 0, 0, 0);
    # ── ELF header ──
    store8(&OUT + 0, 127);
    store8(&OUT + 1, 69);
    store8(&OUT + 2, 76);
    store8(&OUT + 3, 70);
    store8(&OUT + 4, 2);
    store8(&OUT + 5, 1);
    store8(&OUT + 6, 1);
    st16(16, 1);
    st16(18, 183);
    st32(20, 1);
    st64(24, 0);
    st64(32, 0);
    st64(40, shof);
    st32(48, 0);
    st16(52, 64);
    st16(54, 0);
    st16(56, 0);
    st16(58, 64);
    st16(60, 9);
    st16(62, 8);
    let fd: i64 = syscall(2, path, 577, 420, 0, 0);
    if fd < 0 { fail("cannot create output"); return 1; }
    let w: i64 = syscall(1, fd, &OUT, total, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if w != total { fail("short write"); return 1; }
    return 0;
}

fn write_elf(path: ptr) -> i64 {
    let n: i64 = NC * 4 + ND;
    let total: i64 = 120 + n;
    let i: i64 = 0;
    while i < total { store8(&OUT + i, 0); i = i + 1; }
    store8(&OUT + 0, 127);
    store8(&OUT + 1, 69);
    store8(&OUT + 2, 76);
    store8(&OUT + 3, 70);
    store8(&OUT + 4, 2);
    store8(&OUT + 5, 1);
    store8(&OUT + 6, 1);
    st16(16, 2);
    st16(18, 183);
    st32(20, 1);
    st64(24, BASE);
    st64(32, 64);
    st64(40, 0);
    st32(48, 0);
    st16(52, 64);
    st16(54, 56);
    st16(56, 1);
    st16(58, 0);
    st16(60, 0);
    st16(62, 0);
    st32(64, 1);
    st32(68, 7);
    st64(72, 120);
    st64(80, BASE);
    st64(88, BASE);
    st64(96, n);
    st64(104, n + NBB);
    st64(112, 4096);
    let k: i64 = 0;
    while k < NC {
        st32(120 + k * 4, CODE[k] & 4294967295);
        k = k + 1;
    }
    let j: i64 = 0;
    while j < ND {
        store8(&OUT + 120 + NC * 4 + j, load8(&DAT + j));
        j = j + 1;
    }
    let fd: i64 = syscall(2, path, 577, 420, 0, 0);
    if fd < 0 { fail("cannot create output"); return 1; }
    let w: i64 = syscall(1, fd, &OUT, total, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if w != total { fail("short write"); return 1; }
    return 0;
}

fn readfile(p: ptr) -> i64 {
    let fd: i64 = syscall(2, p, 0, 0, 0, 0);
    if fd < 0 { fail("cannot open input"); return 1; }
    let i: i64 = 0;
    while i < 131071 {
        let n: i64 = syscall(0, fd, &SRC + i, 1, 0, 0, 0);
        if n <= 0 { break; }
        i = i + 1;
    }
    syscall(3, fd, 0, 0, 0, 0, 0);
    SL = i;
    store8(&SRC + SL, 0);
    return 0;
}

fn main() -> i64 {
    RELM = 0;
    let ai: i64 = 1;
    if argc() >= 4 {
        if streq(argv(1), "-r") == 1 { RELM = 1; ai = 2; }
    }
    if argc() < ai + 2 {
        print("usage: a64as [-r] <in.s> <out>");
        print_nl();
        return 1;
    }
    if readfile(argv(ai)) != 0 { return 1; }
    assemble(0);
    NF = 0;
    assemble(1);
    apply_fixups();
    if ERR > 0 {
        print("a64as: errors=");
        print_i64(ERR);
        print_nl();
        return 1;
    }
    if RELM == 1 {
        if write_rel(argv(ai + 1)) != 0 { return 1; }
    } else {
        if write_elf(argv(ai + 1)) != 0 { return 1; }
    }
    print("a64as: ");
    print_i64(NC);
    print(" insns, ");
    print_i64(ND);
    print(" data bytes, ");
    print_i64(NL);
    print(" labels");
    print_nl();
    return 0;
}
