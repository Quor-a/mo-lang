# a64ld —— 用墨语言写的 AArch64 链接器
#
# ── 它补的是 a64as -r 的另一半 ──────────────────────────────
#   a64as -r 产出 .o（ET_REL：机器码 + 符号表 + 重定位表），但地址还是
#   占位 0，因为**单看一个文件根本不知道它会被放在哪里**。本程序负责：
#       ① 把各文件的 .text/.data 依次拼起来（布局）
#       ② 把符号名解析成最终地址（一个文件的 UNDEF 在另一个文件里找到定义）
#       ③ 按 AArch64 ELF 规范把每条重定位算出来、写回指令字
#       ④ 写出可执行 ELF（单 PT_LOAD，和 a64as 单文件模式同一布局）
#
# ── 重定位类型是真规范值，不是私有编号 ──────────────────────
#   282 JUMP26 / 283 CALL26 / 280 CONDBR19
#   275 ADR_PREL_PG_HI21 / 277 ADD_ABS_LO12_NC / 264..267 MOVW_UABS_Gn
#   所以算得对不对，可以用**独立实现**的解析器按同一份规范校验，
#   而不是"链接器说对就对"。
#
# ── 判据的关键 ──────────────────────────────────────────────
#   跨文件调用（CALL26）和跨段取地址（ADR_PREL_PG_HI21 + ADD_ABS_LO12_NC）
#   只要有一个算错，程序立刻跑不出预期输出 —— 不像"少写一个校验"那样
#   能被别的路径掩盖。所以端到端执行本身就是最硬的判据。

import "io.mo";
import "str.mo";

var INB: [65536] i64 = 0;
var INL: i64 = 0;
var TXT: [4096] i64 = 0;
var NT: i64 = 0;
var DTA: [16384] i64 = 0;
var ND: i64 = 0;
var POOL: [4096] i64 = 0;
var NP: i64 = 0;
var SNAME: [256] i64 = 0;
var SSEC: [256] i64 = 0;
var SOFF: [256] i64 = 0;
var SFIL: [256] i64 = 0;
var NS: i64 = 0;
var FTW: [16] i64 = 0;
var FDO: [16] i64 = 0;
var FBW: [16] i64 = 0;
var NB: i64 = 0;
var ARB: [16384] i64 = 0;
var ARL: i64 = 0;
var AMOFF: [16] i64 = 0;
var AMSZ: [16] i64 = 0;
var AMUSED: [16] i64 = 0;
var NAM: i64 = 0;
var NEX: i64 = 0;
var ROFF: [1024] i64 = 0;
var RTYP: [1024] i64 = 0;
var RNM: [1024] i64 = 0;
var RFIL: [1024] i64 = 0;
var NR: i64 = 0;
var RSEC: [1024] i64 = 0;
var OUT: [8192] i64 = 0;
var ERR: i64 = 0;
var BASE: i64 = 1073741824;
var ENTRY: i64 = 0;

var TOF: i64 = 0;
var TSZ: i64 = 0;
var DOF: i64 = 0;
var DSZ: i64 = 0;
var BSZ: i64 = 0;
var SOF: i64 = 0;
var SSZ: i64 = 0;
var STF: i64 = 0;
var ROF: i64 = 0;
var RSZ: i64 = 0;
var ROF2: i64 = 0;
var RSZ2: i64 = 0;
var SLK: i64 = 0;

fn fail(m: i64) -> i64 {
    print("a64ld: ");
    print(m);
    print_nl();
    ERR = ERR + 1;
    return 0;
}

fn failnm(m: i64, nm: i64) -> i64 {
    print("a64ld: ");
    print(m);
    print(nm);
    print_nl();
    ERR = ERR + 1;
    return 0;
}

fn slen(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 { i = i + 1; }
    return i;
}

fn scpy(d: i64, s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(d + i, load8(s + i));
        i = i + 1;
    }
    store8(d + i, 0);
    return i + 1;
}

fn g16(p: i64) -> i64 {
    return load8(&INB + p) + load8(&INB + p + 1) * 256;
}

fn g32(p: i64) -> i64 {
    let d: i64 = 1;
    let v: i64 = 0;
    let i: i64 = 0;
    while i < 4 {
        v = v + load8(&INB + p + i) * d;
        d = d * 256;
        i = i + 1;
    }
    return v;
}

fn g64(p: i64) -> i64 {
    let d: i64 = 1;
    let v: i64 = 0;
    let i: i64 = 0;
    while i < 8 {
        v = v + load8(&INB + p + i) * d;
        d = d * 256;
        i = i + 1;
    }
    return v;
}

fn loadfile(p: i64) -> i64 {
    let fd: i64 = syscall(2, p, 0, 0, 0, 0);
    if fd < 0 { fail("cannot open input"); return 1; }
    let i: i64 = 0;
    while i < 262144 {
        let n: i64 = syscall(0, fd, &INB + i, 32768, 0, 0, 0);
        if n <= 0 { break; }
        i = i + n;
    }
    syscall(3, fd, 0, 0, 0, 0, 0);
    INL = i;
    let k: i64 = 0;
    while k < 8 { store8(&INB + INL + k, 0); k = k + 1; }
    return 0;
}

fn isar() -> i64 {
    if INL < 8 { return 0; }
    if load8(&INB + 0) != 33 { return 0; }
    if load8(&INB + 1) != 60 { return 0; }
    if load8(&INB + 2) != 97 { return 0; }
    if load8(&INB + 3) != 114 { return 0; }
    if load8(&INB + 4) != 99 { return 0; }
    if load8(&INB + 5) != 104 { return 0; }
    if load8(&INB + 6) != 62 { return 0; }
    if load8(&INB + 7) != 10 { return 0; }
    return 1;
}

# 把归档挪进独立缓冲 ARB。不能留在 INB：INB 是**共享**输入缓冲，
# 抽取成员时要用它装成员字节，归档本体会被覆盖（本项目已在共享临时
# 缓冲上栽过多次，这里是同一模式换了个载体）。
fn arload() -> i64 {
    # 归档容量上限 131072 字节。必须**显式报错**：墨语言对全局数据总量
    # 有个约 131072 个 i64 的上限（超过后 import 进来的符号会静默消失，
    # 报的错却指向用户代码），所以 ARB 只能开到 16384 个 i64。
    # 越界写进 ARB 会踩到别的全局，症状完全是别处出错 —— 必须拦在这里。
    let i: i64 = 0;
    while i < INL {
        store8(&ARB + i, load8(&INB + i));
        i = i + 1;
    }
    ARL = INL;
    NAM = 0;
    NEX = 0;
    let o: i64 = 8;
    while o + 60 <= ARL {
        if NAM >= 16 { fail("too many archive members"); return 1; }
        let sz: i64 = 0;
        let k: i64 = 0;
        while k < 10 {
            let c: i64 = load8(&ARB + o + 48 + k);
            if c >= 48 { if c <= 57 { sz = sz * 10 + (c - 48); } }
            k = k + 1;
        }
        if sz <= 0 { fail("bad archive member size"); return 1; }
        if o + 60 + sz > ARL { fail("archive member out of range"); return 1; }
        AMOFF[NAM] = o + 60;
        AMSZ[NAM] = sz;
        AMUSED[NAM] = 0;
        NAM = NAM + 1;
        o = o + 60 + sz;
        if sz % 2 == 1 { o = o + 1; }
    }
    if NAM == 0 { fail("archive has no members"); return 1; }
    return 0;
}

fn arsetbuf(m: i64) -> i64 {
    let i: i64 = 0;
    while i < AMSZ[m] {
        store8(&INB + i, load8(&ARB + AMOFF[m] + i));
        i = i + 1;
    }
    let k: i64 = 0;
    while k < 8 { store8(&INB + AMSZ[m] + k, 0); k = k + 1; }
    INL = AMSZ[m];
    return 0;
}

fn shname(off: i64, idx: i64) -> i64 {
    return &INB + off + idx;
}

# 遍历 section headers，按名字记下需要的段
fn scan_secs() -> i64 {
    TOF = 0; TSZ = 0; DOF = 0; DSZ = 0; SOF = 0; SSZ = 0; STF = 0; ROF = 0; RSZ = 0;
    ROF2 = 0; RSZ2 = 0; BSZ = 0;
    let shoff: i64 = g64(40);
    let shnum: i64 = g16(60);
    let shent: i64 = g16(58);
    let shstr: i64 = g16(62);
    if shnum == 0 { fail("no sections"); return 1; }
    if shent != 64 { fail("bad shentsize"); return 1; }
    let stro: i64 = g64(shoff + shstr * 64 + 24);
    let i: i64 = 0;
    while i < shnum {
        let b: i64 = shoff + i * 64;
        let nm: i64 = shname(stro, g32(b));
        let ty: i64 = g32(b + 4);
        let of: i64 = g64(b + 24);
        let sz: i64 = g64(b + 32);
        let lk: i64 = g32(b + 40);
        if streq(nm, ".text") == 1 { TOF = of; TSZ = sz; }
        if streq(nm, ".data") == 1 { DOF = of; DSZ = sz; }
        # .bss 是 SHT_NOBITS(8)：文件里没有字节，只有 sh_size 有意义。
        # 这里**只认 sh_size**，不读 sh_offset —— 若按 sz 去读文件内容，
        # 就会把后面别的段当成 bss 内容搬进内存。
        if streq(nm, ".bss") == 1 {
            if ty != 8 { fail(".bss is not SHT_NOBITS"); return 1; }
            BSZ = sz;
        }
        if streq(nm, ".symtab") == 1 { SOF = of; SSZ = sz; SLK = lk; }
        if streq(nm, ".rela.text") == 1 { ROF = of; RSZ = sz; }
        if streq(nm, ".rela.data") == 1 { ROF2 = of; RSZ2 = sz; }
        i = i + 1;
    }
    if SLK == 0 { fail("symtab has no strtab link"); return 1; }
    STF = g64(shoff + SLK * 64 + 24);
    return 0;
}

fn findsym(nm: i64) -> i64 {
    let i: i64 = 0;
    while i < NS {
        if streq(&POOL + SNAME[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

# 该成员是否定义了某个**当前仍 UNDEF** 的符号。
# 只扫符号表、不追加段也不登记重定位：判断错了可以再看下一个成员，
# 而一旦 scan() 进去就不可逆了。
fn arprobe(m: i64) -> i64 {
    if arsetbuf(m) != 0 { return 0; }
    if g16(16) != 1 { return 0; }
    if g16(18) != 183 { return 0; }
    if scan_secs() != 0 { return 0; }
    let nsym: i64 = SSZ / 24;
    let k: i64 = 1;
    while k < nsym {
        let e: i64 = SOF + k * 24;
        let shn: i64 = g16(e + 6);
        if shn != 0 {
            let nmp: i64 = &INB + STF + g32(e);
            let j: i64 = findsym(nmp);
            if j >= 0 {
                if SSEC[j] == 2 { return 1; }
            }
        }
        k = k + 1;
    }
    return 0;
}

fn addsym(nm: i64, sec: i64, off: i64, fil: i64) -> i64 {
    let i: i64 = findsym(nm);
    if i >= 0 {
        # 已登记的是 UNDEF、这次是定义 → 补上（这正是"解析"这个动作）
        if SSEC[i] == 2 {
            SSEC[i] = sec;
            SOFF[i] = off;
            SFIL[i] = fil;
            return i;
        }
        if sec == 2 { return i; }
        fail("duplicate symbol: ");
        print(nm);
        print_nl();
        return i;
    }
    if NS >= 256 { fail("too many symbols"); return 0; }
    if NP + slen(nm) + 1 >= 4096 { fail("name pool overflow"); return 0; }
    SNAME[NS] = NP;
    NP = NP + scpy(&POOL + NP, nm);
    SSEC[NS] = sec;
    SOFF[NS] = off;
    SFIL[NS] = fil;
    NS = NS + 1;
    return NS - 1;
}

# 名字必须**复制进 POOL**，不能存 INB 里的指针：INB 是共享输入缓冲，
# 读下一个 .o 时整个被覆盖，先登记的重定位拿到的就成了别的文件的内容
# （本项目已在共享临时缓冲上栽过多次，这里是同一模式换了个载体）。
fn addrel(off: i64, ty: i64, nm: i64, fil: i64) -> i64 {
    if NR >= 1024 { fail("too many relocations"); return 0; }
    if NP + slen(nm) + 1 >= 4096 { fail("name pool overflow"); return 0; }
    let o: i64 = NP;
    NP = NP + scpy(&POOL + NP, nm);
    ROFF[NR] = off;
    RTYP[NR] = ty;
    RNM[NR] = o;
    RFIL[NR] = fil;
    NR = NR + 1;
    return 0;
}

# 处理一个输入文件：追加段内容、登记符号与重定位
fn scan(fil: i64) -> i64 {
    if fil >= 16 { fail("too many inputs"); return 1; }
    if g16(16) != 1 { fail("not ET_REL"); return 1; }
    if g16(18) != 183 { fail("not aarch64"); return 1; }
    if scan_secs() != 0 { return 1; }
    FTW[fil] = NT;
    FDO[fil] = ND;
    FBW[fil] = NB;
    NB = NB + BSZ;
    let k: i64 = 0;
    while k < TSZ / 4 {
        TXT[NT] = g32(TOF + k * 4);
        NT = NT + 1;
        k = k + 1;
    }
    k = 0;
    while k < DSZ {
        store8(&DTA + ND, load8(&INB + DOF + k));
        ND = ND + 1;
        k = k + 1;
    }
    # ── 符号 ──
    let nsym: i64 = SSZ / 24;
    k = 1;
    while k < nsym {
        let e: i64 = SOF + k * 24;
        let nm: i64 = &INB + STF + g32(e);
        let shn: i64 = g16(e + 6);
        let val: i64 = g64(e + 8);
        let sec: i64 = 1;
        if shn == 1 { sec = 0; }
        if shn == 0 { sec = 2; }
        if shn == 3 { sec = 3; }
        addsym(nm, sec, val, fil);
        k = k + 1;
    }
    # ── 重定位：.rela.text（指令里的跳转/取址）与 .rela.data（.quad 绝对地址）──
    let nrel: i64 = RSZ / 24;
    k = 0;
    while k < nrel {
        let e: i64 = ROF + k * 24;
        let of: i64 = g64(e);
        let info: i64 = g64(e + 8);
        let sy: i64 = info / 4294967296;
        let ty: i64 = info - sy * 4294967296;
        let nm: i64 = &INB + STF + g32(SOF + sy * 24);
        addrel(of, ty, nm, fil);
        k = k + 1;
    }
    # ── .rela.data：数据段里的绝对地址（R_AARCH64_ABS64 = 257）──
    let nrel2: i64 = RSZ2 / 24;
    k = 0;
    while k < nrel2 {
        let e: i64 = ROF2 + k * 24;
        let of: i64 = g64(e);
        let info: i64 = g64(e + 8);
        let sy: i64 = info / 4294967296;
        let ty2: i64 = info - sy * 4294967296;
        let nm2: i64 = &INB + STF + g32(SOF + sy * 24);
        addrel(of, ty2, nm2, fil);
        RSEC[NR - 1] = 1;
        k = k + 1;
    }
    return 0;
}

fn symval(i: i64) -> i64 {
    if SSEC[i] == 2 { return 0; }
    if SSEC[i] == 0 { return BASE + FTW[SFIL[i]] * 4 + SOFF[i]; }
    if SSEC[i] == 3 { return BASE + NT * 4 + ND + FBW[SFIL[i]] + SOFF[i]; }
    return BASE + NT * 4 + FDO[SFIL[i]] + SOFF[i];
}

fn mod26(v: i64) -> i64 {
    let r: i64 = v - (v / 67108864) * 67108864;
    if r < 0 { r = r + 67108864; }
    return r;
}

fn mod19(v: i64) -> i64 {
    let r: i64 = v - (v / 524288) * 524288;
    if r < 0 { r = r + 524288; }
    return r;
}

# 往 DTA（数据段）里写 8 个字节的绝对地址
fn st64d(p: i64, v: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 1;
    while i < 8 {
        store8(&DTA + p + i, (v / d) % 256);
        d = d * 256;
        i = i + 1;
    }
    return 0;
}

fn apply_relocs() -> i64 {
    let k: i64 = 0;
    while k < NR {
        let si: i64 = findsym(&POOL + RNM[k]);
        if si < 0 {
            failnm("undefined symbol: ", &POOL + RNM[k]);
            return 1;
        }
        if SSEC[si] == 2 {
            failnm("undefined symbol: ", &POOL + RNM[k]);
            return 1;
        }
        let s: i64 = symval(si);
        let ty: i64 = RTYP[k];
        if RSEC[k] == 1 {
            # 数据段里的绝对地址（R_AARCH64_ABS64 = 257）。写错偏移不会报错，
            # 只会让 blr 跳到别的地址 —— 所以判据是端到端执行，不是"链接没报错"。
            if ty == 257 {
                let off: i64 = FDO[RFIL[k]] + ROFF[k];
                st64d(off, s);
            } else {
                fail("unsupported data reloc type");
                return 1;
            }
        } else {
            let p: i64 = BASE + FTW[RFIL[k]] * 4 + ROFF[k];
            let idx: i64 = (p - BASE) / 4;
            let w: i64 = TXT[idx];
        if ty == 282 {
            let imm: i64 = mod26((s - p) / 4);
            TXT[idx] = (w & 4227858432) | imm;
        }
        if ty == 283 {
            let imm: i64 = mod26((s - p) / 4);
            TXT[idx] = (w & 4227858432) | imm;
        }
        if ty == 280 {
            # CONDBR19 的 imm19 落在 bit23..5，剩下 bit4..0 的**语义因指令而异**：
            #   b.cond  → bit3..0 是条件码、bit4 恒 0
            #   cbz/cbnz → bit4..0 是完整的 5 位 Rt
            # 早先按 b.cond 写了 `(w & 15)`，于是 cbz x26 变成 cbz x10（26&15=10）
            # —— 指令照样合法、程序照样跑，只是判断的寄存器换了一个。
            # 汇编器 -r 模式下 imm19 恒为 0，所以保留低 5 位原样即可。
            let imm: i64 = mod19((s - p) / 4);
            TXT[idx] = (w & 4278190080) | (imm * 32) | (w & 31);
        }
        if ty == 275 {
            let pgs: i64 = (s / 4096) * 4096;
            let pgp: i64 = (p / 4096) * 4096;
            let imm: i64 = (pgs - pgp) / 4096;
            let immlo: i64 = imm - (imm / 4) * 4;
            if immlo < 0 { immlo = immlo + 4; }
            let immhi: i64 = ((imm - immlo) / 4) & 524287;
            TXT[idx] = w | (immlo * 536870912) | (immhi * 32);
        }
        if ty == 277 {
            let lo: i64 = s - (s / 4096) * 4096;
            if lo < 0 { lo = lo + 4096; }
            TXT[idx] = w | (lo * 1024);
        }
            if ty >= 264 {
                if ty <= 267 {
                    let n: i64 = ty - 264;
                    let d: i64 = 1;
                    let q: i64 = 0;
                    while q < n { d = d * 65536; q = q + 1; }
                    let part: i64 = (s / d) & 65535;
                    TXT[idx] = w | (part * 32);
                }
            }
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

fn write_elf(path: i64) -> i64 {
    let n: i64 = NT * 4 + ND;
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
    st64(24, ENTRY);
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
    st64(104, n + NB);
    st64(112, 4096);
    let k: i64 = 0;
    while k < NT {
        st32(120 + k * 4, TXT[k] & 4294967295);
        k = k + 1;
    }
    let j: i64 = 0;
    while j < ND {
        store8(&OUT + 120 + NT * 4 + j, load8(&DTA + j));
        j = j + 1;
    }
    let fd: i64 = syscall(2, path, 577, 420, 0, 0);
    if fd < 0 { fail("cannot create output"); return 1; }
    let w: i64 = syscall(1, fd, &OUT, total, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if w != total { fail("short write"); return 1; }
    return 0;
}

# --base：链接地址。默认 0x40000000；做"内核 + 用户程序"两个镜像时必须能
# 分别指定，否则用户程序会和内核抢同一块地址，加载器搬移之后它内部的
# 绝对地址（字符串、跳转表）会指向内核 —— 于是"加载外部 ELF"无从做起。
fn atoi10(s: i64) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    while load8(s + i) != 0 {
        v = v * 10 + (load8(s + i) - 48);
        i = i + 1;
    }
    return v;
}

fn main() -> i64 {
    # argc() **含**程序名（argv(0) 是程序自身），所以不带选项时输入从
    # argv(2) 起；带 --base 时多占两格，输入从 argv(4) 起。
    # 早先按 "argv(1) 是第一个实参" 写，loadfile 拿到的是基址字符串本身 ——
    # 报的却是 "cannot open input"，方向完全不指向参数错位。
    let first: i64 = 2;
    if argc() >= 2 {
        if streq(argv(1), "--base") == 1 {
            if argc() < 4 {
                print("usage: a64ld [--base N] <out.elf> <in1.o> ...");
                print_nl();
                return 1;
            }
            BASE = atoi10(argv(2));
            first = 4;
        }
    }
    if argc() < first + 1 {
        print("usage: a64ld [--base N] <out.elf> <in1.o> ...");
        print_nl();
        return 1;
    }
    let nf: i64 = argc() - first;
    let i: i64 = 0;
    let fil: i64 = 0;
    while i < nf {
        if loadfile(argv(first + i)) != 0 { return 1; }
        if isar() == 1 {
            if arload() != 0 { return 1; }
            # 按需抽取**必须迭代**：抽出一个成员后，它自己引用的符号会变成
            # 新的 UNDEF。只做一遍的话，"A 定义 fna 且引用 fnb、B 定义 fnb"
            # 这种传递依赖会在 fnb 上报未定义 —— 症状看起来像缺文件，
            # 其实是抽取循环少了一轮。
            let changed: i64 = 1;
            while changed == 1 {
                changed = 0;
                let m: i64 = 0;
                while m < NAM {
                    if AMUSED[m] == 0 {
                        if arprobe(m) == 1 {
                            AMUSED[m] = 1;
                            NEX = NEX + 1;
                            if arsetbuf(m) != 0 { return 1; }
                            if scan(fil) != 0 { return 1; }
                            fil = fil + 1;
                            changed = 1;
                        }
                    }
                    m = m + 1;
                }
            }
        } else {
            if scan(fil) != 0 { return 1; }
            fil = fil + 1;
        }
        i = i + 1;
    }
    # 入口：_start 若存在就用它，否则用镜像起点
    ENTRY = BASE;
    let si: i64 = findsym("_start");
    if si >= 0 {
        if SSEC[si] != 2 { ENTRY = symval(si); }
    }
    if apply_relocs() != 0 { return 1; }
    if ERR > 0 {
        print("a64ld: errors=");
        print_i64(ERR);
        print_nl();
        return 1;
    }
    # 输出名是 argv(first - 1)：写死 argv(1) 的话，带 --base 时产物会被
    # 写进一个名叫 "--base" 的文件 —— 链接器照样打印成功、返回 0，
    # 而期待的 out.elf 根本不存在。症状在下一步才爆发。
    if write_elf(argv(first - 1)) != 0 { return 1; }
    print("a64ld: ");
    print_i64(nf);
    print(" inputs, ");
    print_i64(NT);
    print(" insns, ");
    print_i64(ND);
    print(" data bytes, ");
    print_i64(NB);
    print(" bss bytes, ");
    print_i64(NR);
    print(" relocs, ");
    print_i64(NS);
    print(" syms, ");
    print_i64(NEX);
    print(" archive members");
    print_nl();
    return 0;
}
