import "io.mo";
# mokern —— 自举 aarch64 的**内核生成器**
#
# 与 a64mmu / a64pkg 的差别：那些内核的源码是**手写 .s**，由 a64as 汇编；
# 这一个的内核是**墨语言程序直接构造出来的机器码**（逐条 emit 指令字 +
# 逐字节写 ELF），不经过任何汇编源文件，也不经过 C / zig / libc。
#
# 于是"自举"这一层是闭合的：
#   墨语言程序（跑在 ARM64 上）→ 产出 ARM64 裸机内核 → 裸机启动
#
# 内核本身做的事，件件都是"内核"而不是"程序"：
#   - 设置自己的内核栈（msr sp_el1）+ 用户栈（msr sp_el0）
#   - 装异常向量表（msr vbar_el1）
#   - 建二级页表、开 MMU（ttbr0 / tcr / mair / sctlr）
#   - 把 CPU 降到 EL0 跑用户任务（eret）
#   - 用户只能 svc 陷入；直接读内核私有页 → data abort（EC=0x24）
#   - data abort 的返回地址要 +4，否则原地重来 → 死循环
#
# 期望输出（见 tools/mokerntest.sh）：
#   MO-KERN / U OK / PF2 / DONE

var CODE: [4096] i64 = 0;
var NC: i64 = 0;
var DAT: [8192] i64 = 0;
var ND: i64 = 0;
var OUT: [24576] i64 = 0;

# 标签：0 = 未定义，>0 = 指令索引（代码标签）或字节偏移+1（数据标签）
var LBV: [64] i64 = 0;
var FXC: [512] i64 = 0;
var FXL: [512] i64 = 0;
var FXT: [512] i64 = 0;      # 0=b, 1=bl, 2=b.eq, 3=adr
var NFX: i64 = 0;

var BASE: i64 = 1073741824;  # 0x40000000

# 标签编号
var L_PUTS: i64 = 1;
var L_PUTSL: i64 = 2;
var L_PUTSE: i64 = 3;
var L_BPT: i64 = 4;
var L_EMMU: i64 = 5;
var L_USER: i64 = 6;
var L_VEC: i64 = 7;
var L_EXC: i64 = 8;
var L_DOSVC: i64 = 9;
var L_SYSW: i64 = 10;
var L_SYSE: i64 = 11;
var L_DABT: i64 = 12;
var L_EXCR: i64 = 13;
var L_HALT: i64 = 14;
var D_BOOT: i64 = 20;
var D_U: i64 = 21;
var D_PF: i64 = 22;
var D_DONE: i64 = 23;

fn fail(m: ptr) -> i64 {
    print("mokern: ");
    print(m);
    print_nl();
    return 1;
}

fn emit(w: i64) -> i64 {
    if NC >= 4096 { return fail("code overflow"); }
    CODE[NC] = w;
    NC = NC + 1;
    return 0;
}

fn db(b: i64) -> i64 {
    store8(&DAT + ND, b);
    ND = ND + 1;
    return 0;
}

# 写一个 C 字符串（不含结尾 0 与换行），再补 '\n' 与 0
fn dmsg(s: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(&DAT + ND, load8(s + i));
        ND = ND + 1;
        i = i + 1;
    }
    store8(&DAT + ND, 10);
    ND = ND + 1;
    store8(&DAT + ND, 0);
    ND = ND + 1;
    return 0;
}

# ── 指令编码 ──
# 每条都由 capstone / LLVM 独立核对过（见 docs/mokern.md 的编码表）

fn movz_(rt: i64, imm: i64, hw: i64) -> i64 {
    return emit(3531603968 + hw * 2097152 + imm * 32 + rt);
}
fn movk_(rt: i64, imm: i64, hw: i64) -> i64 {
    return emit(4068474880 + hw * 2097152 + imm * 32 + rt);
}
fn addi(rd: i64, rn: i64, imm: i64) -> i64 {
    return emit(2432696320 + imm * 1024 + rn * 32 + rd);
}
fn subi(rd: i64, rn: i64, imm: i64) -> i64 {
    return emit(3506438144 + imm * 1024 + rn * 32 + rd);
}
fn addsp(imm: i64) -> i64 { return emit(2432696320 + imm * 1024 + 1023); }
fn subsp(imm: i64) -> i64 { return emit(3506438144 + imm * 1024 + 1023); }
fn strx(rt: i64, rn: i64, off: i64) -> i64 {
    return emit(4177526784 + (off / 8) * 1024 + rn * 32 + rt);
}
fn ldrx(rt: i64, rn: i64, off: i64) -> i64 {
    return emit(4181721088 + (off / 8) * 1024 + rn * 32 + rt);
}
fn ldrb_(rt: i64, rn: i64) -> i64 { return emit(960495616 + rn * 32 + rt); }
fn strb_(rt: i64, rn: i64) -> i64 { return emit(956301312 + rn * 32 + rt); }
fn cmp_(rn: i64, imm: i64) -> i64 {
    return emit(4043309056 + imm * 1024 + rn * 32 + 31);
}
fn lsr_(rd: i64, rn: i64, sh: i64) -> i64 {
    return emit(3544186880 + sh * 65536 + 64512 + rn * 32 + rd);
}
# msr / mrs：底字 = 0xD5000000 | (sysreg << 5)；L 在 **bit21**，mrs 加 0x200000。
# 早先按 0xD5100000 算，sp_el1 编成 0xd5284120（多了 bit20）—— 真值是 0xd5184120。
fn msr_(sys: i64, rt: i64) -> i64 { return emit(3573547008 + sys * 32 + rt); }
fn mrs_(sys: i64, rt: i64) -> i64 { return emit(3575644160 + sys * 32 + rt); }

fn fix(c: i64, l: i64, t: i64) -> i64 {
    FXC[NFX] = c;
    FXL[NFX] = l;
    FXT[NFX] = t;
    NFX = NFX + 1;
    return 0;
}

fn b_(l: i64) -> i64 { fix(NC, l, 0); return emit(335544320); }
fn bl_(l: i64) -> i64 { fix(NC, l, 1); return emit(2483027968); }
fn beq_(l: i64) -> i64 { fix(NC, l, 2); return emit(1409286144); }
fn adr_(rt: i64, l: i64) -> i64 { fix(NC, l, 3); return emit(268435456 + rt); }

fn ret_() -> i64 { return emit(3596551104); }
fn eret_() -> i64 { return emit(3600745440); }
fn svc_() -> i64 { return emit(3556769793); }
fn wfi_() -> i64 { return emit(3573751935); }
fn dsb_() -> i64 { return emit(3573759903); }
fn isb_() -> i64 { return emit(3573759967); }

# 用 movz(lsl#16) 装一个 0x???????? 形式的高半字地址
fn ldaddr(rt: i64, hi16: i64) -> i64 {
    movz_(rt, hi16, 1);
    return 0;
}
# 装一个 64 位描述符：lo16 / mid16 / hi16 / top16
fn ld64(rt: i64, a: i64, b: i64, c: i64, d: i64) -> i64 {
    movz_(rt, a, 0);
    movk_(rt, b, 1);
    movk_(rt, c, 2);
    movk_(rt, d, 3);
    return 0;
}

fn def(l: i64) -> i64 {
    LBV[l] = NC + 1;
    return 0;
}
fn ddef(l: i64) -> i64 {
    LBV[l] = ND + 1;
    return 0;
}

# ── 内核正文 ──
fn gen() -> i64 {
    # _start
    ldaddr(0, 16448);              # 0x40400000
    addi(0, 0, 2048);
    addi(0, 0, 2048);              # 0x40401000 内核栈
    msr_(49673, 0);                # msr sp_el1, x0
    adr_(0, L_VEC);
    msr_(50688, 0);                # msr vbar_el1, x0
    ldaddr(0, 16385);              # 0x40010000 用户栈
    msr_(49672, 0);                # msr sp_el0, x0
    adr_(20, D_BOOT);
    bl_(L_PUTS);
    bl_(L_BPT);
    bl_(L_EMMU);
    adr_(0, L_USER);
    msr_(49665, 0);                # msr elr_el1, x0
    movz_(0, 0, 0);                # PSTATE = 0 → EL0t
    msr_(49664, 0);                # msr spsr_el1, x0
    eret_();
    b_(L_HALT);

    # puts：x20 = 字符串地址；逐字节写 UART 0x09000000
    def(L_PUTS);
    ldaddr(25, 2304);              # 0x09000000
    def(L_PUTSL);
    ldrb_(26, 20);
    cmp_(26, 0);
    beq_(L_PUTSE);
    strb_(26, 25);
    addi(20, 20, 1);
    b_(L_PUTSL);
    def(L_PUTSE);
    ret_();

    # build_pt：L1 = 0x40402000，L2_dev = 0x40403000，L2_ram = 0x40404000
    def(L_BPT);
    ldaddr(11, 16448);
    addi(11, 11, 2048);
    addi(11, 11, 2048);
    addi(11, 11, 2048);
    addi(11, 11, 2048);            # 0x40402000 L1
    ldaddr(13, 16448);
    addi(13, 13, 2048);
    addi(13, 13, 2048);
    addi(13, 13, 2048);
    addi(13, 13, 2048);
    addi(13, 13, 2048);
    addi(13, 13, 2048);            # 0x40403000 L2_dev
    ldaddr(14, 16448);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);
    addi(14, 14, 2048);            # 0x40404000 L2_ram
    addi(9, 13, 3);
    strx(9, 11, 0);
    addi(9, 14, 3);
    strx(9, 11, 8);
    # L2_dev[72] → UART 0x09000000，设备内存、EL1 独享
    ld64(9, 1029, 0, 2304, 96);
    strx(9, 13, 576);
    # L2_ram[0] → 0x40000000：AP=01，可执行（放代码/数据/用户栈）
    ld64(9, 1089, 0, 16384, 32);
    strx(9, 14, 0);
    # L2_ram[1] → 0x40200000：AP=01
    ld64(9, 1089, 0, 16416, 32);
    strx(9, 14, 8);
    # L2_ram[2] → 0x40400000：AP=00（EL0 一律 abort）、UXN=1
    ld64(9, 1025, 0, 16448, 64);
    strx(9, 14, 16);
    ret_();

    # enable_mmu
    def(L_EMMU);
    ldaddr(9, 16448);
    addi(9, 9, 2048);
    addi(9, 9, 2048);
    addi(9, 9, 2048);
    addi(9, 9, 2048);              # L1 = 0x40402000
    msr_(49408, 9);                # ttbr0_el1
    movz_(9, 13593, 0);            # 0x3519：T0SZ=25
    msr_(49410, 9);                # tcr_el1
    movz_(9, 255, 0);
    msr_(50448, 9);                # mair_el1
    dsb_();
    isb_();
    movz_(9, 4101, 0);             # 0x1005：M=1
    msr_(49280, 9);                # sctlr_el1
    isb_();
    ret_();

    # 用户任务（EL0）：svc 打印 → 读内核私有页（应被 abort）→ svc exit
    def(L_USER);
    movz_(8, 64, 0);               # write
    adr_(1, D_U);
    movz_(2, 5, 0);                # len("U OK\n")
    svc_();
    ldaddr(9, 16448);              # 0x40400000 内核私有
    ldrx(10, 9, 0);                # ← 应触发 data abort
    movz_(8, 93, 0);               # exit
    svc_();
    b_(L_HALT);

    # 异常向量表：必须 2048 对齐，VBAR+0x400 = 来自 lower EL 的同步异常
    while (NC * 4) / 2048 * 2048 != NC * 4 { emit(0); }
    def(L_VEC);
    let i: i64 = 0;
    while i < 256 { emit(0); i = i + 1; }   # .zero 1024
    b_(L_EXC);

    def(L_EXC);
    subsp(128);
    strx(0, 31, 0);
    strx(1, 31, 8);
    strx(2, 31, 16);
    strx(8, 31, 24);
    strx(20, 31, 32);
    strx(25, 31, 40);
    strx(26, 31, 48);
    strx(30, 31, 56);
    mrs_(49808, 0);                # mrs x0, esr_el1
    lsr_(1, 0, 26);                # EC
    cmp_(1, 21);                   # 0x15 = SVC
    beq_(L_DOSVC);
    cmp_(1, 36);                   # 0x24 = data abort from lower EL
    beq_(L_DABT);
    b_(L_EXCR);

    def(L_DOSVC);
    ldrx(8, 31, 24);
    cmp_(8, 64);
    beq_(L_SYSW);
    cmp_(8, 93);
    beq_(L_SYSE);
    b_(L_EXCR);

    def(L_SYSW);
    ldrx(1, 31, 8);
    movz_(0, 0, 0);
    addi(20, 1, 0);                # mov x20, x1（orr 形式不适用时退化为 add）
    bl_(L_PUTS);
    b_(L_EXCR);

    def(L_SYSE);
    adr_(20, D_DONE);
    bl_(L_PUTS);
    b_(L_HALT);

    def(L_DABT);
    adr_(20, D_PF);
    bl_(L_PUTS);
    mrs_(49665, 0);                # mrs x0, elr_el1
    addi(0, 0, 4);                 # 返回地址 +4，否则原地重来 → 死循环
    msr_(49665, 0);
    b_(L_EXCR);

    def(L_EXCR);
    ldrx(30, 31, 56);
    ldrx(26, 31, 48);
    ldrx(25, 31, 40);
    ldrx(20, 31, 32);
    ldrx(8, 31, 24);
    ldrx(2, 31, 16);
    ldrx(1, 31, 8);
    ldrx(0, 31, 0);
    addsp(128);
    eret_();

    def(L_HALT);
    wfi_();
    b_(L_HALT);

    # ── 数据段 ──
    ddef(D_BOOT);
    dmsg("MO-KERN");
    ddef(D_U);
    dmsg("U OK");
    ddef(D_PF);
    dmsg("PF2");
    ddef(D_DONE);
    dmsg("DONE");
    return 0;
}

# 解析 fixup：把标签换成真实偏移
fn resolve() -> i64 {
    let i: i64 = 0;
    while i < NFX {
        let c: i64 = FXC[i];
        let l: i64 = FXL[i];
        let t: i64 = FXT[i];
        if LBV[l] == 0 { return fail("undefined label"); }
        if t == 3 {
            # adr：目标可能是**代码标签**（LBV 存指令索引+1）也可能是
            # **数据标签**（存数据段字节偏移+1），两者算法完全不同。
            # 混淆会让 eret 跳到镜像之外（实测 PC=0x40000d1c，已超出整个
            # 镜像），而报错只说"停机指令"，完全不指向 adr 这一条。
            # 数据标签一律 >= 20，代码标签 < 20 —— 靠编号区分而不是靠
            # 再加一张表，是因为两张表不同步的代价更高。
            let off: i64 = 0;
            if l >= 20 {
                off = (NC - c) * 4 + (LBV[l] - 1);
            }
            else {
                off = (LBV[l] - 1 - c) * 4;
            }
            if off < 0 { return fail("adr negative"); }
            if off > 1048575 { return fail("adr out of range"); }
            let rt: i64 = CODE[c] - 268435456;
            CODE[c] = 268435456 + (off - off / 4 * 4) * 536870912
                      + (off / 4) * 32 + rt;
            i = i + 1;
        }
        else {
            let off: i64 = (LBV[l] - 1 - c) * 4;
            # 🔴 负偏移必须用**补码**而不是加法：b 的 imm26 是有符号的，
            #    0x14000000 + (-5) 会借位把操作码 000101 变成 000100（非法
            #    指令）；真编码是 0x14000000 | (imm26 & 0x3FFFFFF)。
            #    症状是"跳到某条指令就停"，而那条指令本身完全正确。
            let d: i64 = off / 4;
            if t != 3 {
                if d < 0 { d = d + 67108864; }
            }
            if t == 0 { CODE[c] = 335544320 + d; }
            if t == 1 { CODE[c] = 2483027968 + d; }
            if t == 2 {
                let e: i64 = off / 4;
                if e < 0 { e = e + 524288; }
                CODE[c] = 1409286144 + e * 32;
            }
            i = i + 1;
        }
    }
    return 0;
}

# ── 写出 ARM64 裸机 ELF ──
fn st16(o: i64, v: i64) -> i64 {
    store8(&OUT + o, v - v / 256 * 256);
    store8(&OUT + o + 1, v / 256);
    return 0;
}
fn st32(o: i64, v: i64) -> i64 {
    let x: i64 = v;
    let i: i64 = 0;
    while i < 4 {
        store8(&OUT + o + i, x - x / 256 * 256);
        x = x / 256;
        i = i + 1;
    }
    return 0;
}
fn st64(o: i64, v: i64) -> i64 {
    let x: i64 = v;
    let i: i64 = 0;
    while i < 8 {
        store8(&OUT + o + i, x - x / 256 * 256);
        x = x / 256;
        i = i + 1;
    }
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
    st16(18, 183);                 # EM_AARCH64
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
    st64(104, n);
    st64(112, 4096);
    let k: i64 = 0;
    while k < NC {
        st32(120 + k * 4, CODE[k] - CODE[k] / 4294967296 * 4294967296);
        k = k + 1;
    }
    let j: i64 = 0;
    while j < ND {
        store8(&OUT + 120 + NC * 4 + j, load8(&DAT + j));
        j = j + 1;
    }
    let fd: i64 = syscall(2, path, 577, 420, 0, 0);
    if fd < 0 { return fail("cannot create output"); }
    let w: i64 = syscall(1, fd, &OUT, total, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if w != total { return fail("short write"); }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: mokern <out.elf>");
        print_nl();
        return 1;
    }
    gen();
    if resolve() != 0 { return 1; }
    if write_elf(argv(1)) != 0 { return 1; }
    print("mokern: ");
    print_i64(NC);
    print(" insns, ");
    print_i64(ND);
    print(" data bytes");
    print_nl();
    return 0;
}
