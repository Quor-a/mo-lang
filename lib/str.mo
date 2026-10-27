# 字符串与字节缓冲区
#   用 ptr（指向字节的指针）与下标语法写成，不再手工 load8 / store8
#   ptr 没有长度信息，所以下标不做越界检查——这与 C 的字符指针一致

fn strlen(s: ptr) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 {
        i = i + 1;
    }
    return i;
}

fn streq(a: ptr, b: ptr) -> i64 {
    let i: i64 = 0;
    while a[i] != 0 {
        if a[i] != b[i] {
            return 0;
        }
        i = i + 1;
    }
    if b[i] != 0 {
        return 0;
    }
    return 1;
}

fn strcmp(a: ptr, b: ptr) -> i64 {
    let i: i64 = 0;
    while 1 {
        if a[i] != b[i] {
            return a[i] - b[i];
        }
        if a[i] == 0 {
            return 0;
        }
        i = i + 1;
    }
    return 0;
}

fn strcpy(dst: ptr, src: ptr) -> i64 {
    let i: i64 = 0;
    while src[i] != 0 {
        dst[i] = src[i];
        i = i + 1;
    }
    dst[i] = 0;
    return dst;
}

fn strcat(dst: ptr, src: ptr) -> i64 {
    let i: i64 = strlen(dst);
    let j: i64 = 0;
    while src[j] != 0 {
        dst[i] = src[j];
        i = i + 1;
        j = j + 1;
    }
    dst[i] = 0;
    return dst;
}

# 在「到下一个 \n 为止」的范围内找子串；找到返回起始下标，找不到返回 -1
# 把整数转成十进制追加到 dst 末尾。返回 0。
#
# sfmt 需要它：f"..." 里的 i64 插值，目标是拼接而不是打印。
# 用 utoa 转到一个局部缓冲再 strcat。
fn strcat_i64(dst: ptr, v: i64) -> i64 {
    # ⚠️ 不能 import "io.mo" 来用 utoa：那会形成 str→io→str 的循环依赖，
    # 于是 wc.mo / sort.mo 这些只 import str.mo 的示例全部编译失败
    #（第一版就是这么错的，回归从 126 掉到 121）。
    # 这里自己写一份十进制转换（无符号，符号单独处理）。
    let buf: [24] byte = 0;
    let neg: i64 = 0;
    let x: i64 = v;
    if x < 0 { neg = 1; x = 0 - x; }
    let i: i64 = 22;
    if x == 0 {
        store8(&buf + i, 48);
        i = i - 1;
    } else {
        while x > 0 {
            store8(&buf + i, 48 + (x - (x / 10) * 10));
            i = i - 1;
            x = x / 10;
        }
    }
    if neg == 1 { store8(&buf + i, 45); i = i - 1; }
    strcat(dst, &buf + i + 1);
    return 0;
}

fn strchr(s: ptr, c: i64) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 {
        if s[i] == c {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn is_digit(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 {
            return 1;
        }
    }
    return 0;
}

# 十进制字符串转整数。支持前导 '-'，遇非数字停止。
fn atoi(s: ptr) -> i64 {
    let i: i64 = 0;
    let neg: i64 = 0;
    if s[0] == 45 {
        neg = 1;
        i = 1;
    }
    let v: i64 = 0;
    while is_digit(s[i]) == 1 {
        v = v * 10 + (s[i] - 48);
        i = i + 1;
    }
    if neg == 1 {
        return 0 - v;
    }
    return v;
}

# 以下按字节操作内存，不解释为字符串
fn memset(p: i64, v: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store8(p + i, v);
        i = i + 1;
    }
    return p;
}

fn memcpy(dst: i64, src: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store8(dst + i, load8(src + i));
        i = i + 1;
    }
    return dst;
}

fn memcmp(a: i64, b: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if load8(a + i) != load8(b + i) {
            return load8(a + i) - load8(b + i);
        }
        i = i + 1;
    }
    return 0;
}

# 找子串，返回起始下标，找不到返回 -1
fn strstr(hay: ptr, needle: ptr) -> i64 {
    let i: i64 = 0;
    let hn: i64 = strlen(hay);
    let nn: i64 = strlen(needle);
    if nn == 0 { return 0; }
    while i + nn <= hn {
        let j: i64 = 0;
        while hay[i + j] == needle[j] {
            j = j + 1;
            if j == nn { return i; }
        }
        i = i + 1;
    }
    return 0 - 1;
}

# ==========================================================================
#  以下函数是写 examples/site.mo（静态站点生成器）时缺什么补什么的产物。
#  不是"想着该有"加的，是"用到发现没有"才加的。
# ==========================================================================
import "mem.mo";
import "vec.mo";

# 把字符串拷进堆并返回新地址。
# 用途：往 vec 里存字符串时必须拷一份，否则调用方一复用缓冲区，
#       表里的键/值全变了（早期容器最常踩的坑）。
# 注意：墨语言的函数返回类型目前不支持 ptr，所以返回 i64（即地址）。
# 调用方拿到的是地址，可以再赋回 ptr 变量。
fn str_dup(s: ptr) -> i64 {
    let n: i64 = strlen(s);
    let p: i64 = alloc(n + 1);
    if p == 0 { return 0; }
    memcpy(p, s, n + 1);
    return p;
}

fn is_space(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    if c == 10 { return 1; }
    if c == 13 { return 1; }
    return 0;
}

# 去掉首尾空白（原地：写回 NUL 并返回新的起始偏移）
# 同上：返回类型是 i64（地址）
fn str_trim(s: ptr) -> i64 {
    let i: i64 = 0;
    while is_space(load8(s + i)) == 1 { i = i + 1; }
    let p: i64 = s + i;
    let n: i64 = strlen(p);
    while n > 0 {
        if is_space(load8(p + n - 1)) == 0 { break; }
        n = n - 1;
    }
    store8(p + n, 0);
    return p;
}

fn str_starts_with(s: ptr, pre: ptr) -> i64 {
    let n: i64 = strlen(pre);
    if strlen(s) < n { return 0; }
    if memcmp(s, pre, n) == 0 { return 1; }
    return 0;
}

fn str_ends_with(s: ptr, suf: ptr) -> i64 {
    let n: i64 = strlen(s);
    let m: i64 = strlen(suf);
    if n < m { return 0; }
    if memcmp(s + n - m, suf, m) == 0 { return 1; }
    return 0;
}

# 分割字符串，返回一个 vec（元素是 str_dup 出来的堆字符串）
# 局部数组不能声明在循环体内：墨语言在栈帧里给每个 let 分配空间，
# 循环内声明 = 每次迭代都多占一份，512 字节 × 迭代数很容易爆栈。
# 所以缓冲在函数开头声明一次，循环里复用。
fn str_split(s: ptr, sep: ptr) -> i64 {
    let v: i64 = vec_new();
    let sl: i64 = strlen(sep);
    let i: i64 = 0;
    let start: i64 = 0;
    let part: [512] byte = 0;
    while load8(s + i) != 0 {
        if sl == 1 {
            if load8(s + i) == load8(sep) {
                memcpy(&part, s + start, i - start);
                store8(&part + (i - start), 0);
                vec_push(v, str_dup(&part));
                start = i + 1;
            }
        } else {
            if memcmp(s + i, sep, sl) == 0 {
                memcpy(&part, s + start, i - start);
                store8(&part + (i - start), 0);
                vec_push(v, str_dup(&part));
                i = i + sl;
                start = i;
            }
        }
        i = i + 1;
    }
    memcpy(&part, s + start, i - start);
    store8(&part + (i - start), 0);
    vec_push(v, str_dup(&part));
    return v;
}

# 路径拼接：自动处理末尾斜杠，避免 "dir//file"
var TBUF16: [32] byte = 0;   # itoa_base 逆序临时缓冲（函数内部，模块级声明）
# str_itoa_base(dst, v, base)：v 转 2..16 进制字符串（负数带 '-'）。返回 dst。
fn str_itoa_base(dst: ptr, v: i64, base: i64) -> i64 {
    if base < 2 { base = 2; }
    if base > 16 { base = 16; }
    let neg: i64 = 0;
    if v < 0 { neg = 1; v = 0 - v; }
    # 单临时缓冲（逆序），再反转拷出
    let i: i64 = 0;
    if v == 0 {
        store8(&TBUF16, 48);
        i = 1;
    }
    while v > 0 {
        let d: i64 = v % base;
        if d < 10 { store8(&TBUF16 + i, 48 + d); } else { store8(&TBUF16 + i, 87 + d); }
        i = i + 1;
        v = v / base;
    }
    let o: i64 = 0;
    if neg == 1 { store8(dst, 45); o = 1; }
    while i > 0 {
        i = i - 1;
        store8(dst + o, load8(&TBUF16 + i));
        o = o + 1;
    }
    store8(dst + o, 0);
    return dst;
}

# str_toupper / str_tolower：就地 ASCII 大小写。返回 dst。
fn str_toupper(dst: ptr) -> i64 {
    let i: i64 = 0;
    while load8(dst + i) != 0 {
        let c: i64 = load8(dst + i);
        if c >= 97 && c <= 122 { store8(dst + i, c - 32); }
        i = i + 1;
    }
    return dst;
}

fn str_tolower(dst: ptr) -> i64 {
    let i: i64 = 0;
    while load8(dst + i) != 0 {
        let c: i64 = load8(dst + i);
        if c >= 65 && c <= 90 { store8(dst + i, c + 32); }
        i = i + 1;
    }
    return dst;
}

# str_replace(dst, src, from, to)：把 src 中 from 全替换为 to。返回 dst。
fn str_replace(dst: ptr, src: ptr, from: ptr, to: ptr) -> i64 {
    let fl: i64 = strlen(from);
    if fl == 0 { strcpy(dst, src); return dst; }
    let i: i64 = 0;
    let o: i64 = 0;
    while load8(src + i) != 0 {
        if str_starts_with(src + i, from) == 1 {
            let j: i64 = 0;
            while j < strlen(to) { store8(dst + o, load8(to + j)); o = o + 1; j = j + 1; }
            i = i + fl;
        } else {
            store8(dst + o, load8(src + i));
            o = o + 1;
            i = i + 1;
        }
    }
    store8(dst + o, 0);
    return dst;
}

# ---------- Q16.16 定点格式化（v1.232）----------
# f2sq16(dst, q)：Q16.16 定点值 → "d.dddd"（4 位小数，四舍五入）。dst ≥ 24B。
var F2S_D: [20] i64 = 0;

fn f2sq16(dst: ptr, q: i64) -> i64 {
    let neg: i64 = 0;
    let v: i64 = q;
    if v < 0 { neg = 1; v = 0 - v; }
    let ip: i64 = v >> 16;
    let frac: i64 = v & 65535;
    let d4: i64 = (frac * 10000 + 32768) / 65536;
    if d4 >= 10000 { ip = ip + 1; d4 = d4 - 10000; }
    let o: i64 = 0;
    if neg == 1 { store8(dst, 45); o = 1; }
    if ip == 0 {
        store8(dst + o, 48);
        o = o + 1;
    } else {
        let nd: i64 = 0;
        while ip > 0 {
            F2S_D[nd] = ip % 10;
            nd = nd + 1;
            ip = ip / 10;
        }
        while nd > 0 {
            nd = nd - 1;
            store8(dst + o, 48 + F2S_D[nd]);
            o = o + 1;
        }
    }
    store8(dst + o, 46);
    o = o + 1;
    store8(dst + o, 48 + (d4 / 1000) % 10);
    store8(dst + o + 1, 48 + (d4 / 100) % 10);
    store8(dst + o + 2, 48 + (d4 / 10) % 10);
    store8(dst + o + 3, 48 + d4 % 10);
    store8(dst + o + 4, 0);
    return dst;
}

# q16f2s(s)：十进制字符串 "1.75"/"-0.5"/"3" → Q16.16 定点。容错：无小数点/
#   小数多于 4 位（截断忽略更低位）。非法输入返 0。返回定点值。
var Q2S_V: i64 = 0;

fn q16f2s(s: ptr) -> i64 {
    let neg: i64 = 0;
    let ip: i64 = 0;
    let fp: i64 = 0;      # 小数位已读数
    let fv: i64 = 0;      # 小数累计（万分位）
    let i: i64 = 0;
    let st: i64 = 0;      # 0=整数段 1=小数段
    let n: i64 = strlen(s);
    if n == 0 { return 0; }
    if load8(s) == 45 { neg = 1; i = 1; }
    while i < n {
        let c: i64 = load8(s + i);
        if c == 46 {
            st = 1;
        } else {
            if c < 48 { if c > 57 { i = n; } }
            if c >= 48 {
                if c <= 57 {
                    let d: i64 = c - 48;
                    if st == 0 {
                        ip = ip * 10 + d;
                    } else {
                        if fp < 4 {
                            fv = fv * 10 + d;
                            fp = fp + 1;
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    while fp < 4 { fv = fv * 10; fp = fp + 1; }
    let q: i64 = ip * 65536 + (fv * 65536 + 5000) / 10000;
    if neg == 1 { q = 0 - q; }
    return q;
}

fn path_join(dst: ptr, a: ptr, b: ptr) -> i64 {
    strcpy(dst, a);
    let n: i64 = strlen(dst);
    if n > 0 {
        if load8(dst + n - 1) != 47 { strcat(dst, "/"); }
    }
    strcat(dst, b);
    return dst;
}

# ---------- v1.246 进制全家 + hex/url 编解码 ----------
var PB_V: i64 = 0;
var PB_I: i64 = 0;
var PB_C: i64 = 0;
var PB_D: i64 = 0;
var PB_NEG: i64 = 0;

# 通用进制解析：base 2/8/10/16，负号，"0x"/"0b" 前缀；非法字符停（返回累计值，i=已消费）
fn parse_base(s: ptr, base: i64) -> i64 {
    PB_V = 0;
    PB_I = 0;
    PB_NEG = 0;
    if load8(s) == 45 { PB_NEG = 1; PB_I = 1; }
    if load8(s + PB_I) == 48 {
        let n2: i64 = load8(s + PB_I + 1);
        if n2 == 120 || n2 == 88 { PB_I = PB_I + 2; if base == 10 { PB_V = -9999; return PB_V; } }
        if n2 == 98 || n2 == 66 { PB_I = PB_I + 2; if base != 2 { PB_V = -9999; return PB_V; } }
    }
    while 1 {
        PB_C = load8(s + PB_I);
        if PB_C == 0 { break; }
        if PB_C >= 48 && PB_C <= 57 { PB_D = PB_C - 48; }
        else if PB_C >= 97 && PB_C <= 122 { PB_D = PB_C - 87; }   # a=10
        else if PB_C >= 65 && PB_C <= 90 { PB_D = PB_C - 55; }    # A=10
        else { break; }
        if PB_D >= base { break; }
        PB_V = PB_V * base + PB_D;
        PB_I = PB_I + 1;
    }
    if PB_NEG == 1 { PB_V = 0 - PB_V; }
    return PB_V;
}

fn parse_hex(s: ptr) -> i64 { return parse_base(s, 16); }
fn parse_bin(s: ptr) -> i64 { return parse_base(s, 2); }
fn parse_oct(s: ptr) -> i64 { return parse_base(s, 8); }

# 字节 → 小写 hex 字符串（dst 容量 2n+1）
var HEXD: [17] byte = "0123456789abcdef";
var HEX_I: i64 = 0;
var HEX_B: i64 = 0;
fn hex_encode(dst: ptr, src: i64, n: i64) -> i64 {
    HEX_I = 0;
    while HEX_I < n {
        HEX_B = load8(src + HEX_I);
        store8(dst + HEX_I * 2, load8(&HEXD + ((HEX_B >> 4) & 15)));
        store8(dst + HEX_I * 2 + 1, load8(&HEXD + (HEX_B & 15)));
        HEX_I = HEX_I + 1;
    }
    store8(dst + n * 2, 0);
    return n * 2;
}

# hex 字符串 → 字节（返回字节数，-1 非法）
var HEXD2: i64 = 0;
var HEXD2_J: i64 = 0;
var HEXD2_HI: i64 = 0;
var HEXD2_LO: i64 = 0;
fn hex_decode(dst: ptr, hex: ptr) -> i64 {
    let sl: i64 = strlen(hex);
    if sl < 2 { return -1; }
    HEXD2_J = 0;
    HEXD2 = 0;
    while HEXD2 < sl {
        HEXD2_HI = parse_nib(load8(hex + HEXD2));
        HEXD2_LO = parse_nib(load8(hex + HEXD2 + 1));
        if HEXD2_HI < 0 || HEXD2_LO < 0 { return -1; }
        store8(dst + HEXD2_J, HEXD2_HI * 16 + HEXD2_LO);
        HEXD2_J = HEXD2_J + 1;
        HEXD2 = HEXD2 + 2;
    }
    return HEXD2_J;
}
fn parse_nib(c: i64) -> i64 {
    if c >= 48 && c <= 57 { return c - 48; }
    if c >= 97 && c <= 102 { return c - 87; }
    if c >= 65 && c <= 70 { return c - 55; }
    return 0 - 1;
}

# URL 编码：非 [A-Za-z0-9._~-] → %XX
var UE_I: i64 = 0;
var UE_C: i64 = 0;
var UE_O: i64 = 0;
fn url_encode(dst: ptr, s: ptr) -> i64 {
    UE_I = 0; UE_O = 0;
    while 1 {
        UE_C = load8(s + UE_I);
        if UE_C == 0 { break; }
        if (UE_C >= 48 && UE_C <= 57) || (UE_C >= 65 && UE_C <= 90) || (UE_C >= 97 && UE_C <= 122) || UE_C == 46 || UE_C == 95 || UE_C == 126 || UE_C == 45 {
            store8(dst + UE_O, UE_C); UE_O = UE_O + 1;
        } else {
            store8(dst + UE_O, 37);   # %
            store8(dst + UE_O + 1, load8(&HEXD + ((UE_C >> 4) & 15)));
            store8(dst + UE_O + 2, load8(&HEXD + (UE_C & 15)));
            UE_O = UE_O + 3;
        }
        UE_I = UE_I + 1;
    }
    store8(dst + UE_O, 0);
    return UE_O;
}

# URL 解码：%XX 与 '+'→空格（返回长度）
var UD_I: i64 = 0;
var UD_O: i64 = 0;
var UD_C: i64 = 0;
fn url_decode(dst: ptr, s: ptr) -> i64 {
    UD_I = 0; UD_O = 0;
    while 1 {
        UD_C = load8(s + UD_I);
        if UD_C == 0 { break; }
        if UD_C == 43 { store8(dst + UD_O, 32); UD_O = UD_O + 1; }
        else if UD_C == 37 {
            let h: i64 = parse_nib(load8(s + UD_I + 1));
            let l: i64 = parse_nib(load8(s + UD_I + 2));
            if h >= 0 && l >= 0 { store8(dst + UD_O, h * 16 + l); UD_I = UD_I + 2; UD_O = UD_O + 1; }
            else { store8(dst + UD_O, UD_C); UD_O = UD_O + 1; }
        }
        else { store8(dst + UD_O, UD_C); UD_O = UD_O + 1; }
        UD_I = UD_I + 1;
    }
    store8(dst + UD_O, 0);
    return UD_O;
}

# query 组装："?k=v&k2=v2"（值 url_encode）；kv 交替数组 qv[2n]
var AQQ_I: i64 = 0;
var AQQ_O: i64 = 0;
var AQQ_K: i64 = 0;
fn http_build_query(dst: ptr, keys: i64, vals: i64, n: i64) -> i64 {
    AQQ_I = 0; AQQ_O = 0;
    while AQQ_I < n {
        if AQQ_I == 0 { store8(dst + AQQ_O, 63); AQQ_O = AQQ_O + 1; }
        else { store8(dst + AQQ_O, 38); AQQ_O = AQQ_O + 1; }   # &
        AQQ_K = load64(keys + AQQ_I * 8);
        strcpy(dst + AQQ_O, AQQ_K);
        AQQ_O = AQQ_O + strlen(AQQ_K);
        store8(dst + AQQ_O, 61); AQQ_O = AQQ_O + 1;
        AQQ_O = AQQ_O + url_encode(dst + AQQ_O, load64(vals + AQQ_I * 8));
        AQQ_I = AQQ_I + 1;
    }
    store8(dst + AQQ_O, 0);
    return AQQ_O;
}

# 前缀 n 字节比较：同返 1 异返 0
var SCMP_I: i64 = 0;
fn str_ncmp(a: ptr, b: ptr, n: i64) -> i64 {
    SCMP_I = 0;
    while SCMP_I < n {
        if load8(a + SCMP_I) != load8(b + SCMP_I) { return 0; }
        if load8(a + SCMP_I) == 0 { return 1; }
        SCMP_I = SCMP_I + 1;
    }
    return 1;
}
