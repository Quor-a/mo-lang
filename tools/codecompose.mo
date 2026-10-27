# codecompose.mo —— 代码段体积构成分析（墨语言版）
#
# 取代 tools/codecompose.py。原版要借 readelf + objdump 两个外部工具：
#   先 readelf 找可执行 LOAD 段 → 抠成裸二进制 → objdump -D 反汇编 → 按助记符分组。
# 也就是说：**度量自己代码体积的工具，自己却不是自己写的**，而且反汇编
# 这件事完全交给 objdump 这个黑盒 —— 它说某条指令是 mov 就是 mov，
# 没人验证过它扫得对不对。
#
# 本版直接读 ELF：
#   1. 自己解析 ELF64 节头表，按名字找 .text（不需要 readelf）
#   2. 自己写 x86-64 指令长度解码器（不需要 objdump）
#   3. 自己按 opcode 字节归类助记符
# 全程不调任何外部工具。
#
# 🔴 比 Python 版多一条断言：线性扫描的指令边界必须精确落在 .text 末尾。
#    任何一条指令长度算错，末尾就对不上 —— 这是校验"扫描本身"，
#    而不是只校验扫描结果。objdump 版做不到这件事。
#
# 用法：codecompose <file.elf>

import "fs.mo";
import "io.mo";
import "str.mo";
import "mem.mo";

var BUFSZ: i64 = 4194304;
var BUF: i64 = 0;
var FSZ: i64 = 0;

var T_OFF: i64 = 0;
var T_SIZE: i64 = 0;
var T_PAD: i64 = 0;
var T_ENTRY: i64 = 0;
var T_START: i64 = 0;
var T_VA: i64 = 0;

# ---------- 助记符分类 ----------
var C_MOV: i64 = 1;
var C_MOVABS: i64 = 2;
var C_PUSH: i64 = 3;
var C_POP: i64 = 4;
var C_CALL: i64 = 5;
var C_JMP: i64 = 6;
var C_JCC: i64 = 7;
var C_RET: i64 = 8;
var C_LEA: i64 = 9;
var C_TEST: i64 = 10;
var C_CMP: i64 = 11;
var C_ARITH: i64 = 12;
var C_IDIV: i64 = 13;
var C_SYSC: i64 = 14;
var C_SSE: i64 = 15;
var C_SETCC: i64 = 17;
var C_CMOV: i64 = 18;
var C_OTHER: i64 = 16;

var NU: i64 = 0;
var U_B: [64] i64 = 0;
var U_T: [64] i64 = 0;
var U_N: [64] i64 = 0;
var U_OFF: [64] i64 = 0;

var NC: i64 = 0;
var C_ID: [32] i64 = 0;
var C_BY: [32] i64 = 0;
var C_NU: [32] i64 = 0;
var C_SK: [32] i64 = 0;   # 排序键副本 —— 不能直接在 C_BY 上打标记，
                         # 否则排完序数据就被毁了（第一版就是这样，
                         # push+pop 合计算出负数）

# ================= 基础读取 =================
fn gb(i: i64) -> i64 { return load8(BUF + i); }


fn g16(i: i64) -> i64 {
    let a: i64 = gb(i);
    let b: i64 = gb(i + 1);
    return a | (b << 8);
}


fn g32(i: i64) -> i64 {
    let a: i64 = gb(i);
    let b: i64 = gb(i + 1);
    let c: i64 = gb(i + 2);
    let d: i64 = gb(i + 3);
    return a | (b << 8) | (c << 16) | (d << 24);
}


fn g64(i: i64) -> i64 {
    let a: i64 = g32(i);
    let b: i64 = g32(i + 4);
    return a | (b << 32);
}

# ================= 统计表 =================
fn addc(c: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < NC {
        if C_ID[i] == c {
            C_BY[i] = C_BY[i] + n;
            C_NU[i] = C_NU[i] + 1;
            return 0;
        }
        i = i + 1;
    }
    if NC < 32 {
        C_ID[NC] = c;
        C_BY[NC] = n;
        C_NU[NC] = 1;
        NC = NC + 1;
    }
    return 0;
}


fn addu(b: i64, two: i64, off: i64) -> i64 {
    let i: i64 = 0;
    while i < NU {
        if U_B[i] == b {
            if U_T[i] == two {
                U_N[i] = U_N[i] + 1;
                return 0;
            }
        }
        i = i + 1;
    }
    if NU < 64 {
        U_B[NU] = b;
        U_T[NU] = two;
        U_N[NU] = 1;
        U_OFF[NU] = off;
        NU = NU + 1;
    }
    return 0;
}


# 归不到类时不能默默吞掉 —— 记下 opcode，用 -u 可以看到 other 里到底是什么
fn cother(b: i64, two: i64, off: i64) -> i64 {
    addu(b, two, off);
    return C_OTHER;
}


fn cname(c: i64) -> ptr {
    if c == 1 { return "mov"; }
    if c == 2 { return "movabs"; }
    if c == 3 { return "push"; }
    if c == 4 { return "pop"; }
    if c == 5 { return "call"; }
    if c == 6 { return "jmp"; }
    if c == 7 { return "jcc"; }
    if c == 8 { return "ret"; }
    if c == 9 { return "lea"; }
    if c == 10 { return "test"; }
    if c == 11 { return "cmp"; }
    if c == 12 { return "arith"; }
    if c == 13 { return "idiv"; }
    if c == 14 { return "syscall"; }
    if c == 15 { return "sse"; }
    if c == 17 { return "setcc"; }
    if c == 18 { return "cmov"; }
    return "other";
}

# ================= 指令解码（与 dwmo.mo 同源） =================
fn is_pfx(b: i64) -> i64 {
    if b == 102 { return 1; }
    if b == 103 { return 1; }
    if b == 240 { return 1; }
    if b == 242 { return 1; }
    if b == 243 { return 1; }
    if b == 46 { return 1; }
    if b == 54 { return 1; }
    if b == 62 { return 1; }
    if b == 38 { return 1; }
    if b == 100 { return 1; }
    if b == 101 { return 1; }
    return 0;
}


fn has_mrm1(b: i64) -> i64 {
    if b < 64 {
        if (b & 7) < 4 { return 1; }
        return 0;
    }
    if b == 99 { return 1; }
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
        if b <= 223 { return 1; }
    }
    if b == 246 { return 1; }
    if b == 247 { return 1; }
    if b == 254 { return 1; }
    if b == 255 { return 1; }
    return 0;
}


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
    if b == 104 { return 4; }
    if b == 106 { return 1; }
    if b == 105 { return 4; }
    if b == 107 { return 1; }
    if b >= 112 {
        if b <= 127 { return 1; }
    }
    if b == 128 { return 1; }
    if b == 129 { return 4; }
    if b == 131 { return 1; }
    if b == 168 { return 1; }
    if b == 169 { return 4; }
    if b >= 176 {
        if b <= 183 { return 1; }
    }
    if b >= 184 {
        if b <= 191 {
            if (rex & 8) != 0 { return 8; }
            return 4;
        }
    }
    if b == 192 { return 1; }
    if b == 193 { return 1; }
    if b == 194 { return 2; }
    if b == 198 { return 1; }
    if b == 199 { return 4; }
    if b == 200 { return 3; }
    if b == 205 { return 1; }
    if b == 212 { return 1; }
    if b == 213 { return 1; }
    if b >= 224 {
        if b <= 227 { return 1; }
    }
    if b == 228 { return 1; }
    if b == 229 { return 1; }
    if b == 232 { return 4; }
    if b == 233 { return 4; }
    if b == 235 { return 1; }
    if b == 246 { return 1; }
    if b == 247 { return 4; }
    return 0;
}


fn fin(p: i64, i: i64, hm: i64, im: i64) -> i64 {
    let mrm: i64 = 0;
    let mod: i64 = 0;
    let rm: i64 = 0;
    let sib: i64 = 0;
    let base: i64 = 0;
    let disp: i64 = 0;
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
                if rm == 5 { disp = 4; }
            }
        }
        }
        i = i + disp;
    }
    i = i + im;
    return i;
}


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
        if b == 56 {
            i = i + 1;
            return fin(p, i, 1, 0);
        }
        if b == 58 {
            i = i + 1;
            return fin(p, i, 1, 1);
        }
        if b >= 128 {
            if b <= 143 { return fin(p, i, 0, 4); }
        }
        if b == 5 { return fin(p, i, 0, 0); }
        if b == 11 { return fin(p, i, 0, 0); }
        if b == 31 { return fin(p, i, 0, 0); }
        if b == 162 { return fin(p, i, 0, 0); }
        if b == 30 { return fin(p, i, 0, 0); }
        if b == 55 { return fin(p, i, 0, 0); }
        return fin(p, i, 1, 0);
    }
    hm = has_mrm1(b);
    im = imm1(b, rex);
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
    return fin(p, i, hm, im);
}

# 按 opcode 字节归类助记符（不依赖外部反汇编器）
fn cls(p: i64) -> i64 {
    let i: i64 = 0;
    let rex: i64 = 0;
    let b: i64 = 0;
    let two: i64 = 0;
    let rg: i64 = 0;
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
    # Group opcode 的区分只能靠 ModRM.reg —— 0x81/0x83 是一个 opcode 覆盖
    # add/or/adc/sbb/and/sub/xor/cmp 八条指令。objdump 能分开是因为它读了
    # reg 字段；只按 opcode 归类的 naive 做法会把 cmp 算进 arith。
    if has_mrm1(b) == 1 { rg = (gb(p + i) >> 3) & 7; }
    if two == 1 {
        if b >= 128 {
            if b <= 143 { return C_JCC; }
        }
        if b == 5 { return C_SYSC; }
        if b >= 144 {
            if b <= 159 { return C_SETCC; }       # setcc
        }
        if b >= 64 {
            if b <= 79 { return C_CMOV; }         # cmovcc
        }
        if b == 182 { return C_MOV; }             # movzbl
        if b == 183 { return C_MOV; }
        if b == 190 { return C_MOV; }             # movsbl
        if b == 191 { return C_MOV; }
        if b == 174 { return C_ARITH; }
        if b == 175 { return C_ARITH; }
        if b == 16 { return C_SSE; }
        if b == 17 { return C_SSE; }
        if b == 40 { return C_SSE; }
        if b == 41 { return C_SSE; }
        if b >= 44 {
            if b <= 47 { return C_SSE; }
        }
        if b >= 64 {
            if b <= 95 { return C_SSE; }
        }
        return cother(b, two, p);
    }
    if b >= 80 {
        if b <= 87 { return C_PUSH; }
    }
    if b >= 88 {
        if b <= 95 { return C_POP; }
    }
    if b >= 184 {
        if b <= 191 {
            if (rex & 8) != 0 { return C_MOVABS; }
            return C_MOV;
        }
    }
    if b == 104 { return C_PUSH; }
    if b == 106 { return C_PUSH; }
    if b == 232 { return C_CALL; }
    if b == 233 { return C_JMP; }
    if b == 235 { return C_JMP; }
    if b == 255 {
        if rg == 2 { return C_CALL; }
        if rg == 3 { return C_CALL; }
        if rg == 4 { return C_JMP; }
        if rg == 5 { return C_JMP; }
        if rg == 6 { return C_PUSH; }            # push r/m64 —— 墨语言传参大量使用
        if rg == 0 { return C_ARITH; }           # inc
        if rg == 1 { return C_ARITH; }           # dec
        return cother(b, two, p);
    }
    if b == 195 { return C_RET; }
    if b == 201 { return C_RET; }
    if b == 194 { return C_RET; }
    if b >= 112 {
        if b <= 127 { return C_JCC; }
    }
    if b == 137 { return C_MOV; }
    if b == 139 { return C_MOV; }
    if b == 136 { return C_MOV; }
    if b == 138 { return C_MOV; }
    if b == 199 { return C_MOV; }
    if b == 198 { return C_MOV; }
    if b == 141 { return C_LEA; }
    if b == 133 { return C_TEST; }
    if b == 132 { return C_TEST; }
    if b == 168 { return C_TEST; }
    if b == 169 { return C_TEST; }
    if b == 61 { return C_CMP; }
    if b == 59 { return C_CMP; }
    if b == 57 { return C_CMP; }
    if b == 60 { return C_CMP; }
    if b == 58 { return C_CMP; }
    if b == 131 {
        if rg == 7 { return C_CMP; }
        return C_ARITH;
    }
    if b == 129 {
        if rg == 7 { return C_CMP; }
        return C_ARITH;
    }
    if b == 128 {
        if rg == 7 { return C_CMP; }
        return C_ARITH;
    }
    if b == 247 {
        if rg == 7 { return C_IDIV; }
        if rg == 6 { return C_IDIV; }
        return C_ARITH;
    }
    if b == 246 {
        if rg == 7 { return C_IDIV; }
        if rg == 6 { return C_IDIV; }
        return C_ARITH;
    }
    if b == 99 { return C_MOV; }                  # movsxd
    if b == 152 { return C_IDIV; }                # cwtl：除法前的符号扩展
    if b == 153 { return C_IDIV; }                # cltd/cqto
    if b == 192 { return C_ARITH; }               # shl/shr/sar/rol 等移位
    if b == 193 { return C_ARITH; }
    if b >= 208 {
        if b <= 211 { return C_ARITH; }
    }
    if b == 105 { return C_ARITH; }               # imul imm
    if b == 107 { return C_ARITH; }
    if b == 84 { return C_TEST; }
    if b == 1 { return C_ARITH; }
    if b == 3 { return C_ARITH; }
    if b == 41 { return C_ARITH; }
    if b == 43 { return C_ARITH; }
    if b == 49 { return C_ARITH; }
    if b == 51 { return C_ARITH; }
    if b == 33 { return C_ARITH; }
    if b == 35 { return C_ARITH; }
    if b == 5 { return C_ARITH; }
    if b == 13 { return C_ARITH; }
    if b == 21 { return C_ARITH; }
    if b == 29 { return C_ARITH; }
    if b == 37 { return C_ARITH; }
    if b == 45 { return C_ARITH; }
    if b == 53 { return C_ARITH; }
    if b == 8 { return C_ARITH; }
    if b == 9 { return C_ARITH; }
    if b == 10 { return C_ARITH; }
    if b == 11 { return C_ARITH; }
    if b == 12 { return C_ARITH; }
    if b == 45 { return C_ARITH; }
    return cother(b, two, p);
}

# ================= 输出排版 =================
fn two_show(b: i64, two: i64) -> i64 { return two; }


fn pdecw(v: i64, nd: i64, w: i64) -> i64 {
    let p: i64 = 1;
    let i: i64 = 0;
    let ip: i64 = 0;
    let d: i64 = 1;
    let k: i64 = 0;
    while i < nd {
        p = p * 10;
        i = i + 1;
    }
    ip = v / p;
    while ip >= 10 {
        ip = ip / 10;
        d = d + 1;
    }
    while k + d + 1 + nd < w {
        print(" ");
        k = k + 1;
    }
    pdec(v, nd);
    return 0;
}


fn pads(s: ptr, w: i64) -> i64 {
    let n: i64 = strlen(s);
    let k: i64 = 0;
    print(s);
    while k + n < w {
        print(" ");
        k = k + 1;
    }
    return 0;
}


fn padn(v: i64, w: i64) -> i64 {
    let t: i64 = v;
    let d: i64 = 1;
    let k: i64 = 0;
    if v < 0 { t = 0 - v; }
    while t >= 10 {
        t = t / 10;
        d = d + 1;
    }
    while k + d < w {
        print(" ");
        k = k + 1;
    }
    print_i64(v);
    return 0;
}


# v 已放大 10^nd 倍
fn pdec(v: i64, nd: i64) -> i64 {
    let p: i64 = 1;
    let i: i64 = 0;
    let r: i64 = 0;
    while i < nd {
        p = p * 10;
        i = i + 1;
    }
    print_i64(v / p);
    print(".");
    r = v % p;
    if nd == 2 {
        if r < 10 { print("0"); }
    }
    print_i64(r);
    return 0;
}

# ================= ELF =================
#
# 🔴 这里必须解析**程序头**而不是节头表。
#    bin/moc 是自己链接器产出的，为了体积不写节头表（readelf -S 直接报
#    "There are no sections in this file"）。Python 版能跑通是因为它用
#    `readelf -lW` 找可执行 LOAD 段 —— 走的是程序头。
#    第一版我照抄 dwmo.mo 的节头表解析，结果报「没有 .text」，而 dwmo
#    从来不出这个错，因为校验 -g 产物时链接器是会写节头表的。
fn parse_elf() -> i64 {
    let i: i64 = 0;
    let phoff: i64 = 0;
    let phent: i64 = 0;
    let phnum: i64 = 0;
    let h: i64 = 0;
    let ty: i64 = 0;
    let fl: i64 = 0;
    let sz: i64 = 0;
    let found: i64 = 0;
    if g32(0) != 1179403647 { return 0 - 1; }
    if gb(4) != 2 { return 0 - 2; }
    T_ENTRY = g64(24);
    phoff = g64(32);
    phent = g16(54);
    phnum = g16(56);
    if phnum > 64 { phnum = 64; }
    while i < phnum {
        h = phoff + i * phent;
        ty = g32(h);
        fl = g32(h + 4);
        if ty == 1 {
            if (fl & 1) == 1 {
                T_OFF = g64(h + 8);
                T_VA = g64(h + 16);
                sz = g64(h + 32);
                if sz > T_SIZE { T_SIZE = sz; }
                found = 1;
            }
        }
        i = i + 1;
    }
    if found == 0 { return 0 - 3; }
    # 去掉尾部对齐填充。
    # 链接器把 filesz 对齐到 0x1000（bin/moc: 0x23000 = 140KiB 整），末尾是
    # 一串 0x00。而 0x00 是合法的 `add %al,(%rax)` —— 不剔除的话会被当成
    # 634 条指令计入 arith，把"代码体积"和"各类占比"整体带偏。
    # objdump 遇到长串零会打印 "..." 跳过，所以它天然不含这段；自己解码就
    # 必须显式处理。
    let e: i64 = T_OFF + T_SIZE;
    while e > T_OFF {
        if gb(e - 1) != 0 { break; }
        e = e - 1;
    }
    T_PAD = T_OFF + T_SIZE - e;
    T_SIZE = e - T_OFF;
    # 可执行段的开头是 ELF 头 + 程序头表，不是代码。
    # 直接从 offset 0 扫会把 0x7f 'E' 'L' 'F' 当指令解 —— 第一版就中了这招：
    # -u 里冒出一堆计数为 1 的怪 opcode（0xcd int / 0xef out / 0xe4 in），
    # 那正是 ELF 魔数和头字段的字节。真代码从入口点开始。
    T_START = T_OFF;
    if T_ENTRY >= T_VA {
        if T_ENTRY - T_VA < T_SIZE { T_START = T_OFF + (T_ENTRY - T_VA); }
    }
    return 0;
}

# ================= main =================
fn main() -> i64 {
    let rc: i64 = 0;
    let p: i64 = 0;
    let e: i64 = 0;
    let l: i64 = 0;
    let c: i64 = 0;
    let t: i64 = 0;
    let n: i64 = 0;
    let i: i64 = 0;
    let bad: i64 = 0;
    let pb: i64 = 0;
    let pn: i64 = 0;
    let b: i64 = 0;
    let j: i64 = 0;
    let bi: i64 = 0;
    let path: ptr = "bin/moc";
    let trace: i64 = 0;
    if argc() >= 2 { path = argv(1); }
    if argc() >= 3 {
        if streq(argv(2), "-t") == 1 { trace = 1; }
    }
    if heap_ready() == 0 { heap_init(); }
    BUF = alloc(BUFSZ);
    if BUF == 0 {
        print("codecompose: 堆分配失败\n");
        return 1;
    }
    FSZ = read_file(path, BUF, BUFSZ);
    if FSZ <= 0 {
        print("codecompose: 无法读取 ");
        print(path);
        print_nl();
        return 1;
    }
    rc = parse_elf();
    if rc == 0 - 1 { print("codecompose: 不是 ELF\n"); return 1; }
    if rc == 0 - 2 { print("codecompose: 只支持 ELF64\n"); return 1; }
    if rc == 0 - 3 { print("codecompose: 没有 .text\n"); return 1; }

    p = T_START;
    e = T_OFF + T_SIZE;
    while p < e {
        l = ilen(p);
        if l <= 0 {
            bad = bad + 1;
            if bad > 4 { break; }
            p = p + 1;
        } else {
            c = cls(p);
            addc(c, l);
            if trace == 1 {
                print_hex(p);
                print(" ");
                print_i64(l);
                print(" ");
                print_i64(c);
                print_nl();
            }
            p = p + l;
        }
    }
    if bad > 0 {
        print("codecompose: 有 ");
        print_i64(bad);
        print(" 个字节无法解码\n");
        return 1;
    }
    if p != e {
        print("codecompose: 指令边界未落在 .text 末尾（差 ");
        print_i64(e - p);
        print(" 字节）—— 解码器算错了长度\n");
        return 1;
    }

    i = 0;
    while i < NC {
        t = t + C_BY[i];
        n = n + C_NU[i];
        i = i + 1;
    }

    print("代码段 ");
    print_i64(t);
    print(" 字节 / ");
    print_i64(n);
    print(" 条指令（可执行段 ");
    print_i64(t + T_PAD);
    print("，已剔除 ELF 头与尾部对齐填充 ");
    print_i64(T_PAD + (T_START - T_OFF));
    print(" 字节）");
    print(" 条指令 (");
    print(path);
    print(")\n");
    pads("insn", 10);
    pads("bytes", 9);
    pads("pct", 8);
    pads("count", 8);
    pads("avg", 7);
    print_nl();

    # 按字节数降序输出前 15（选择排序；每次把已输出的置 -1）
    j = 0;
    while j < NC {
        C_SK[j] = C_BY[j];
        j = j + 1;
    }
    i = 0;
    while i < NC {
        b = 0;
        bi = 0 - 1;
        j = 0;
        while j < NC {
            if C_SK[j] > b {
                b = C_SK[j];
                bi = j;
            }
            j = j + 1;
        }
        if bi < 0 { break; }
        if i < 15 {
            pads(cname(C_ID[bi]), 10);
            padn(C_BY[bi], 9);
            pdecw(C_BY[bi] * 1000 / t, 1, 7);
            print("%");
            padn(C_NU[bi], 8);
            pdecw(C_BY[bi] * 100 / C_NU[bi], 2, 7);
            print_nl();
        }
        C_SK[bi] = 0 - 1;
        i = i + 1;
    }

    # 关键比值：push/pop 编码极短，这是"寄存器分配是否省体积"的依据
    i = 0;
    while i < NC {
        if C_ID[i] == C_PUSH { pb = pb + C_BY[i]; pn = pn + C_NU[i]; }
        if C_ID[i] == C_POP { pb = pb + C_BY[i]; pn = pn + C_NU[i]; }
        i = i + 1;
    }
    print("\npush+pop 合计 ");
    print_i64(pb);
    print(" 字节，占比 ");
    pdec(pb * 1000 / t, 1);
    print("%，均长 ");
    pdec(pb * 100 / pn, 2);
    print("\n");
    print("若换成寄存器传送(mov, 3 字节)，体积是增还是减，取决于这个均长。\n");
    if argc() >= 3 {
        if streq(argv(2), "-u") == 1 {
            print("\nother 桶的构成（未归类的 opcode）：\n");
            j = 0;
            while j < NU {
                if two_show(U_B[j], U_T[j]) == 0 { print("  "); }
                print_i64(U_B[j]);
                print(" @");
                print_hex(U_OFF[j]);
                print(" (0x");
                print_hex(U_B[j]);
                print(") x");
                print_i64(U_N[j]);
                print_nl();
                j = j + 1;
            }
        }
    }
    return 0;
}
