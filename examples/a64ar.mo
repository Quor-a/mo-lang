# a64ar —— 用墨语言写的 ar 归档器（自举 AArch64 工具链的一员）
#
# ── 它补的是 a64ld 的另一半 ────────────────────────────────
#   a64ld 能把多个 .o 链成可执行 ELF，但命令行上必须逐个列出每个文件。
#   真实项目里库是**一包 .o**：链接器只把"真正被用到的"抽出来，
#   没用到的留在归档里不进产物。本程序负责打包，a64ld 负责按需抽取。
#
# ── ar 格式（SVR4 / GNU 通用） ─────────────────────────────
#   全局头    "!<arch>\n"                                    8 字节
#   每个成员  60 字节头 + 数据 + 偶数对齐填充
#     name[16]  mtime[12]  uid[6]  gid[6]  mode[8]  size[10]  fmag[2]="`\n"
#
# ── 两个最容易静默出错的点 ─────────────────────────────────
#   ① size 是**十进制补空格**，不是十六进制、也不是二进制。
#      写成十六进制的话，小文件（size < 10）恰好一样，只有超过 9 字节
#      才错位 —— 而 .o 永远超过 9 字节，所以真错的时候症状是
#      "下一个成员头的偏移整体跑飞，读出来的 size 是天文数字"。
#   ② 成员数据按 **2 字节对齐**，奇数长度补一个 '\n'。
#      不做对齐的话，下一个成员头整体错位 1 字节。
#   这两条都属于"改错了仍然能写出一个文件"，所以判据必须逐字段钉住。

import "io.mo";
import "str.mo";

var INB: [32768] i64 = 0;
var INL: i64 = 0;
var OUT: [49152] i64 = 0;
var NO: i64 = 0;
var ERR: i64 = 0;

fn fail(m: i64) -> i64 {
    print("a64ar: ");
    print(m);
    print_nl();
    ERR = ERR + 1;
    return 0;
}

fn basename(p: i64) -> i64 {
    let i: i64 = 0;
    let last: i64 = 0;
    while load8(p + i) != 0 {
        if load8(p + i) == 47 { last = i + 1; }
        i = i + 1;
    }
    return p + last;
}

fn loadf(p: i64) -> i64 {
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
    if INL == 0 { fail("empty input"); return 1; }
    return 0;
}

# 写 w 宽的十进制数，右对齐、左侧补空格（ar 头所有数字字段的写法）
fn wrnum(v: i64, w: i64) -> i64 {
    let t: i64 = 1;
    let d: i64 = 1;
    while v / t >= 10 { t = t * 10; d = d + 1; }
    let k: i64 = 0;
    while k < w - d {
        store8(&OUT + NO, 32);
        NO = NO + 1;
        k = k + 1;
    }
    let x: i64 = v;
    while d > 0 {
        let dg: i64 = x / t;
        store8(&OUT + NO, 48 + dg);
        NO = NO + 1;
        x = x - dg * t;
        t = t / 10;
        d = d - 1;
    }
    return 0;
}

fn wrstr(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(&OUT + NO, load8(s + i));
        NO = NO + 1;
        i = i + 1;
    }
    return 0;
}

# name 字段 16 字节：GNU 风格以 '/' 结尾，其余补空格
fn wrname(s: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    while load8(s + i) != 0 {
        if i < 15 {
            store8(&OUT + NO, load8(s + i));
            NO = NO + 1;
            n = n + 1;
        }
        i = i + 1;
    }
    if n < 15 {
        store8(&OUT + NO, 47);
        NO = NO + 1;
        n = n + 1;
    }
    while n < 16 {
        store8(&OUT + NO, 32);
        NO = NO + 1;
        n = n + 1;
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 3 {
        print("usage: a64ar <out.a> <in1.o> ...");
        print_nl();
        return 1;
    }
    NO = 0;
    ERR = 0;
    wrstr("!<arch>");
    store8(&OUT + NO, 10);
    NO = NO + 1;

    let nm: i64 = argc() - 2;
    if nm > 16 { fail("too many members"); return 1; }
    let i: i64 = 0;
    while i < nm {
        if loadf(argv(2 + i)) != 0 { return 1; }
        wrname(basename(argv(2 + i)));
        wrnum(0, 12);
        wrnum(0, 6);
        wrnum(0, 6);
        wrstr("644     ");
        wrnum(INL, 10);
        store8(&OUT + NO, 96);
        NO = NO + 1;
        store8(&OUT + NO, 10);
        NO = NO + 1;
        let k: i64 = 0;
        while k < INL {
            store8(&OUT + NO, load8(&INB + k));
            NO = NO + 1;
            k = k + 1;
        }
        if INL % 2 == 1 {
            store8(&OUT + NO, 10);
            NO = NO + 1;
        }
        print("a64ar: add ");
        print(basename(argv(2 + i)));
        print(" ");
        print_i64(INL);
        print(" bytes");
        print_nl();
        i = i + 1;
    }
    if ERR > 0 { return 1; }

    let fd: i64 = syscall(2, argv(1), 577, 420, 0, 0);
    if fd < 0 { fail("cannot create output"); return 1; }
    let w: i64 = syscall(1, fd, &OUT, NO, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if w != NO { fail("short write"); return 1; }
    print("a64ar: ");
    print_i64(nm);
    print(" members, ");
    print_i64(NO);
    print(" bytes total");
    print_nl();
    return 0;
}
