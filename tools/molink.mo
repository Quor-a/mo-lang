# molink.mo —— 墨语言自己写的静态链接器
#
# 为什么要写这个：
#   此前「链接」这一步必须借 GNU ld 的手（tools/molink.sh）：
#       ld --section-start=.data=0x10000000 -e _start ...
#   而 -nostdlib 时还要先用 `as` 汇编 tools/mocrt.s 补一个 exit。
#   也就是说：编译器是自己写的，链接器和运行时却不是 —— 自包含生态
#   在这一环上是断的。
#
# 本文件把 -nostdlib 这条静态链接路径完全自己做掉：
#   1. 直接解析 .o 的 ELF64：section 表 / symtab / .rela.*
#   2. 布局：.text → 0x400000，.data → 0x10000000
#      （0x10000000 是编译器生成 movabs 绝对地址时硬编码的基址，
#        搬错地址不报错，只是全局变量全读成垃圾）
#   3. 对 UND 的 exit 直接注入 9 字节 exit_group 系统调用 stub，
#      于是 mocrt.s 和 `as` 都不再需要
#   4. 自己写 ELF 头 + 2 个 PT_LOAD 落盘，全程不调 ld
#
# 不支持（会明确报错而不是静默产出坏文件）：
#   - 依赖 libc 的动态链接（需要 .interp/.dynamic/.plt，那条路请用 molink.sh）
#   - 未定义的外部符号（extern 声明的 C 函数）

import "fs.mo";
import "io.mo";
import "str.mo";
import "mem.mo";

# 缓冲区走堆而不走全局数组：全局数据总量接近 1MB 时编译器会静默
# 损坏符号表（表现为别处报 undefined symbol），而 .o 可以有几百 KB。
var BUFSZ: i64 = 1572864;          # 1.5MB
var OBJF: i64 = 0;                 # 输入 .o 缓冲区（堆）
var OUTIMG: i64 = 0;               # 输出 ELF 映像（堆）
var ON: i64 = 0;
var OUTN: i64 = 0;

# ---- 段表 ----
var SN: i64 = 0;
var S_TYPE: [64] i64 = 0;
var S_OFF: [64] i64 = 0;
var S_SIZE: [64] i64 = 0;
var S_ADDR: [64] i64 = 0;
var S_LINK: [64] i64 = 0;
var S_INFO: [64] i64 = 0;
var TI: i64 = 0;                 # .text（main 里初始化为 -1）
var DI: i64 = 0;                 # .data
var YI: i64 = 0;                 # .symtab
var STRI: i64 = 0;               # .strtab

# ---- 重定位段（可能有 .rela.text / .rela.data 多个）----
var RELAI: [16] i64 = 0;
var NREL: i64 = 0;

# ---- 符号 ----
var YN: i64 = 0;
var Y_SEC: [512] i64 = 0;
var Y_VAL: [512] i64 = 0;
var Y_STNAME: [512] i64 = 0;     # 名字在 .strtab 内的偏移
var EXIT_I: i64 = 0;             # UND 的 exit 符号下标（0 = 无）
var START_V: i64 = 0;            # _start 的绝对地址

var TEXT_ADDR: i64 = 4198400;     # 0x401000（第 2 页：第 1 页留给 ELF 头+程序头）
var DATA_ADDR: i64 = 268435456;   # 0x10000000
var STUB_ADDR: i64 = 0;           # 注入的 exit stub 地址
var HAS_STUB: i64 = 0;

var OBJP: [256] byte = 0;
var OUTP: [256] byte = 0;
var VERBOSE: i64 = 0;

# ---------------- 原始字节读写 ----------------

fn gb(i: i64) -> i64 { return load8(OBJF + i); }

fn g32(i: i64) -> i64 {
    return gb(i) + gb(i + 1) * 256 + gb(i + 2) * 65536 + gb(i + 3) * 16777216;
}

fn g64(i: i64) -> i64 {
    return g32(i) + g32(i + 4) * 4294967296;
}

fn pb(i: i64, v: i64) -> i64 { store8(OUTIMG + i, v); return 0; }

fn ob32(off: i64, v: i64) -> i64 {
    store8(OBJF + off, v & 255);
    store8(OBJF + off + 1, (v / 256) & 255);
    store8(OBJF + off + 2, (v / 65536) & 255);
    store8(OBJF + off + 3, (v / 16777216) & 255);
    return 0;
}

fn ob64(off: i64, v: i64) -> i64 {
    ob32(off, v & 4294967295);
    ob32(off + 4, v / 4294967296);
    return 0;
}

fn p32(i: i64, v: i64) -> i64 {
    pb(i, v & 255);
    pb(i + 1, (v / 256) & 255);
    pb(i + 2, (v / 65536) & 255);
    pb(i + 3, (v / 16777216) & 255);
    return 0;
}

fn p64(i: i64, v: i64) -> i64 {
    p32(i, v & 4294967295);
    p32(i + 4, v / 4294967296);
    return 0;
}

fn alignup(v: i64, a: i64) -> i64 {
    let r: i64 = v - (v / a) * a;
    if r == 0 { return v; }
    return v + a - r;
}

# ---------------- 解析 ----------------

fn parse_elf() -> i64 {
    if gb(0) != 127 { return 0 - 1; }
    if gb(1) != 69 { return 0 - 1; }
    if gb(2) != 76 { return 0 - 1; }
    if gb(3) != 70 { return 0 - 1; }
    if gb(4) != 2 { return 0 - 2; }

    let ty: i64 = gb(16) + gb(17) * 256;
    if ty != 1 { return 0 - 3; }

    let shoff: i64 = g64(40);
    let shnum: i64 = gb(60) + gb(61) * 256;
    let shent: i64 = gb(58) + gb(59) * 256;
    let shstri: i64 = gb(62) + gb(63) * 256;

    SN = shnum;
    if SN > 64 { return 0 - 4; }

    # 先拿 .shstrtab 的文件偏移（在遍历之前，靠 shstri 直接读）
    let h0: i64 = shoff + shstri * shent;
    let shstroff: i64 = g64(h0 + 24);

    let i: i64 = 0;
    let h: i64 = 0;
    let nm: i64 = 0;
    NREL = 0;
    while i < SN {
        h = shoff + i * shent;
        S_TYPE[i] = g32(h + 4);
        S_OFF[i] = g64(h + 24);
        S_SIZE[i] = g64(h + 32);
        S_LINK[i] = g32(h + 40);
        S_INFO[i] = g32(h + 44);
        S_ADDR[i] = 0;
        nm = OBJF + shstroff + g32(h);
        if streq(nm, ".text") == 1 { TI = i; }
        if streq(nm, ".data") == 1 { DI = i; }
        if streq(nm, ".symtab") == 1 { YI = i; STRI = S_LINK[i]; }
        if S_TYPE[i] == 4 {
            if NREL < 16 { RELAI[NREL] = i; NREL = NREL + 1; }
        }
        i = i + 1;
    }
    if TI < 0 { return 0 - 5; }
    if YI < 0 { return 0 - 6; }
    return 0;
}

fn parse_syms() -> i64 {
    let base: i64 = S_OFF[YI];
    let n: i64 = S_SIZE[YI] / 24;
    if n > 512 { return 0 - 1; }
    YN = n;
    let stroff: i64 = S_OFF[STRI];
    let i: i64 = 0;
    let e: i64 = 0;
    let nm: i64 = 0;
    EXIT_I = 0;
    while i < n {
        e = base + i * 24;
        Y_STNAME[i] = g32(e);
        Y_SEC[i] = gb(e + 6) + gb(e + 7) * 256;
        Y_VAL[i] = g64(e + 8);
        if Y_SEC[i] == 0 {
            nm = OBJF + stroff + Y_STNAME[i];
            if streq(nm, "exit") == 1 { EXIT_I = i; }
            if streq(nm, "_start") == 1 { EXIT_I = EXIT_I; }
        }
        i = i + 1;
    }
    return 0;
}

# 布局 + 解析未定义符号
# 返回 0 成功；返回负数表示有无法解析的外部符号
fn layout() -> i64 {
    S_ADDR[TI] = TEXT_ADDR;
    if DI >= 0 { S_ADDR[DI] = DATA_ADDR; }

    HAS_STUB = 0;
    if EXIT_I > 0 {
        HAS_STUB = 1;
        STUB_ADDR = TEXT_ADDR + S_SIZE[TI];
    }

    # _start 的地址
    let i: i64 = 1;
    let stroff: i64 = S_OFF[STRI];
    let nm: i64 = 0;
    let found: i64 = 0;
    START_V = TEXT_ADDR;
    while i < YN {
        nm = OBJF + stroff + Y_STNAME[i];
        if streq(nm, "_start") == 1 {
            if Y_SEC[i] == TI { START_V = TEXT_ADDR + Y_VAL[i]; }
            found = 1;
        }
        i = i + 1;
    }
    if found == 0 { return 0 - 1; }

    # 其它 UND 符号（除 exit）无法解析 → 明确报错
    i = 1;
    while i < YN {
        if Y_SEC[i] == 0 {
            if i != EXIT_I {
                nm = OBJF + stroff + Y_STNAME[i];
                print("molink: 未定义的外部符号: ");
                print(nm);
                print_nl();
                print("        （静态自链接不支持 extern；请用 molink.sh 走 ld）\n");
                return 0 - 2;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn sym_addr(si: i64) -> i64 {
    if EXIT_I > 0 {
        if si == EXIT_I { return STUB_ADDR; }
    }
    let sec: i64 = Y_SEC[si];
    if sec <= 0 { return 0; }
    if sec >= SN { return 0; }
    return S_ADDR[sec] + Y_VAL[si];
}

fn apply_relocs() -> i64 {
    let k: i64 = 0;
    let r: i64 = 0;
    let base: i64 = 0;
    let n: i64 = 0;
    let j: i64 = 0;
    let e: i64 = 0;
    let roff: i64 = 0;
    let rinfo: i64 = 0;
    let radd: i64 = 0;
    let typ: i64 = 0;
    let si: i64 = 0;
    let tgt: i64 = 0;
    let S: i64 = 0;
    let P: i64 = 0;
    let V: i64 = 0;
    let at: i64 = 0;
    while k < NREL {
        r = RELAI[k];
        base = S_OFF[r];
        n = S_SIZE[r] / 24;
        tgt = S_INFO[r];
        j = 0;
        while j < n {
            e = base + j * 24;
            roff = g64(e);
            rinfo = g64(e + 8);
            radd = g64(e + 16);
            typ = rinfo & 4294967295;
            si = rinfo / 4294967296;
            S = sym_addr(si);
            P = S_ADDR[tgt] + roff;
            at = S_OFF[tgt] + roff;
            if typ == 2 {
                V = S + radd - P;
                ob32(at, V);
            }
            if typ == 4 {
                # R_X86_64_PLT32：符号在镜像内本地定义时就是 PC32
                V = S + radd - P;
                ob32(at, V);
            }
            if typ == 1 {
                V = S + radd;
                ob64(at, V);
            }
            if typ == 11 {
                V = S + radd;
                ob32(at, V);
            }
            if typ != 1 {
                if typ != 2 {
                    if typ != 4 {
                        if typ != 11 {
                            print("molink: 不支持的重定位类型 ");
                            print_i64(typ);
                            print_nl();
                            return 0 - 1;
                        }
                    }
                }
            }
            j = j + 1;
        }
        k = k + 1;
    }
    return 0;
}

# ---------------- 输出 ----------------

fn emit() -> i64 {
    let tsize: i64 = S_SIZE[TI];
    let stubn: i64 = 0;
    if HAS_STUB == 1 { stubn = 9; }
    let tsz: i64 = tsize + stubn;
    let doff: i64 = alignup(4096 + tsz, 4096);
    let dsize: i64 = 0;
    if DI >= 0 { dsize = S_SIZE[DI]; }

    let i: i64 = 0;
    while i < BUFSZ { store8(OUTIMG + i, 0); i = i + 1; }

    # ---- ELF header ----
    pb(0, 127); pb(1, 69); pb(2, 76); pb(3, 70);
    pb(4, 2); pb(5, 1); pb(6, 1); pb(7, 0);
    pb(8, 0); pb(9, 0); pb(10, 0); pb(11, 0);
    pb(12, 0); pb(13, 0); pb(14, 0); pb(15, 0);
    pb(16, 2); pb(17, 0);            # ET_EXEC
    pb(18, 62); pb(19, 0);           # EM_X86_64
    p32(20, 1);                      # EV_CURRENT
    p64(24, START_V);                # e_entry
    p64(32, 64);                     # e_phoff
    p64(40, 0);                      # e_shoff
    p32(48, 0);                      # e_flags
    pb(52, 64); pb(53, 0);           # e_ehsize
    pb(54, 56); pb(55, 0);           # e_phentsize
    pb(56, 3); pb(57, 0);            # e_phnum
    pb(58, 64); pb(59, 0);           # e_shentsize
    pb(60, 0); pb(61, 0);            # e_shnum
    pb(62, 0); pb(63, 0);            # e_shstrndx

    # ---- PT_LOAD #1: ELF 头 + 程序头（只读，不可执行）----
    p32(64, 1);
    p32(68, 4);
    p64(72, 0);
    p64(80, 4194304);
    p64(88, 4194304);
    p64(96, 4096);
    p64(104, 4096);
    p64(112, 4096);

    # ---- PT_LOAD #2: text ----
    p32(120, 1);
    p32(124, 5);                      # R|X
    p64(128, 4096);
    p64(136, TEXT_ADDR);
    p64(144, TEXT_ADDR);
    p64(152, tsz);
    p64(160, tsz);
    p64(168, 4096);

    # ---- PT_LOAD #3: data ----
    p32(176, 1);
    p32(180, 6);                      # R|W
    p64(184, doff);
    p64(192, DATA_ADDR);
    p64(200, DATA_ADDR);
    p64(208, dsize);
    p64(216, dsize);
    p64(224, 4096);

    # ---- 拷 .text ----
    let src: i64 = S_OFF[TI];
    let dst: i64 = 4096;
    i = 0;
    while i < tsize { store8(OUTIMG + dst + i, load8(OBJF + src + i)); i = i + 1; }

    # ---- 注入 exit stub: mov $60,%rax ; syscall ----
    if HAS_STUB == 1 {
        store8(OUTIMG + dst + tsize + 0, 72);
        store8(OUTIMG + dst + tsize + 1, 199);
        store8(OUTIMG + dst + tsize + 2, 192);
        store8(OUTIMG + dst + tsize + 3, 60);
        store8(OUTIMG + dst + tsize + 4, 0);
        store8(OUTIMG + dst + tsize + 5, 0);
        store8(OUTIMG + dst + tsize + 6, 0);
        store8(OUTIMG + dst + tsize + 7, 15);
        store8(OUTIMG + dst + tsize + 8, 5);
    }

    # ---- 拷 .data ----
    if DI >= 0 {
        src = S_OFF[DI];
        i = 0;
        while i < dsize { store8(OUTIMG + doff + i, load8(OBJF + src + i)); i = i + 1; }
    }

    OUTN = doff + dsize;

    let fd: i64 = fopen(&OUTP, 577, 493);
    if fd < 0 {
        print("molink: 无法创建输出文件\n");
        return 0 - 1;
    }
    fwrite(fd, OUTIMG, OUTN);
    fclose(fd);
    syscall(90, &OUTP, 493, 0, 0, 0, 0);     # chmod 0755

    if VERBOSE == 1 {
        print("molink: 自链接完成  text=");
        print_i64(tsz);
        print("  data=");
        print_i64(dsize);
        print("  entry=0x");
        print_hex(START_V);
        print_nl();
    }
    return 0;
}

fn usage() -> i64 {
    print("molink —— 墨语言静态链接器（墨语言实现，不调用 ld）\n");
    print("\n");
    print("用法: molink prog.o -o prog [-v]\n");
    print("\n");
    print("  -o PATH   输出文件\n");
    print("  -v        打印布局信息\n");
    print("\n");
    print("限制：只做不依赖 libc 的静态链接。\n");
    print("      需要 libc / extern 时请用 tools/molink.sh（走 ld）。\n");
    return 2;
}

fn main() -> i64 {
    if argc() < 2 { return usage(); }

    if heap_ready() == 0 { heap_init(); }
    OBJF = alloc(BUFSZ);
    OUTIMG = alloc(BUFSZ);
    if OBJF == 0 { print("molink: 堆分配失败\n"); return 1; }

    TI = 0 - 1;
    DI = 0 - 1;
    YI = 0 - 1;
    STRI = 0 - 1;

    let i: i64 = 1;
    let a: i64 = 0;
    while i < argc() {
        a = argv(i);
        if streq(a, "-o") == 1 {
            i = i + 1;
            if i < argc() { strcpy(&OUTP, argv(i)); }
        }
        if streq(a, "-v") == 1 { VERBOSE = 1; }
        if streq(a, "-h") == 1 { return usage(); }
        if streq(a, "--help") == 1 { return usage(); }
        if load8(a) != 45 { strcpy(&OBJP, a); }     # 非 '-' 开头的当输入
        i = i + 1;
    }

    if load8(&OBJP) == 0 { return usage(); }
    if load8(&OUTP) == 0 { strcpy(&OUTP, &OBJP); }

    ON = read_file(&OBJP, OBJF, BUFSZ);
    if ON <= 0 {
        print("molink: 无法读取 ");
        print(&OBJP);
        print_nl();
        return 1;
    }

    let rc: i64 = parse_elf();
    if rc == 0 - 1 { print("molink: 不是 ELF 文件\n"); return 1; }
    if rc == 0 - 2 { print("molink: 只支持 ELF64\n"); return 1; }
    if rc == 0 - 3 { print("molink: 不是可重定位文件(.o)\n"); return 1; }
    if rc == 0 - 4 { print("molink: 段数过多\n"); return 1; }
    if rc == 0 - 5 { print("molink: 找不到 .text\n"); return 1; }
    if rc == 0 - 6 { print("molink: 找不到 .symtab\n"); return 1; }

    rc = parse_syms();
    if rc < 0 { print("molink: 符号表过大\n"); return 1; }

    rc = layout();
    if rc == 0 - 1 { print("molink: 找不到 _start\n"); return 1; }
    if rc == 0 - 2 { return 1; }

    rc = apply_relocs();
    if rc < 0 { return 1; }

    rc = emit();
    if rc < 0 { return 1; }

    if VERBOSE == 0 {
        print("linked: ");
        print(&OUTP);
        print_nl();
    }
    return 0;
}
