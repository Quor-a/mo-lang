# pack —— 二进制数据的打包与解包（用墨语言自己写的）
#
# 为什么需要它：墨语言有 byte / ptr / load8，能读写任意字节，
# 但直接 load8(p) + load8(p+1) * 256 ... 拼一个 32 位数既啰嗦又容易
# 把字节序写反。协议解析、文件格式解析全是这种活。
#
# 命名沿用 Python struct 的习惯，但只做定长整数，不做浮点（墨语言也没有浮点）。
#
import "io.mo";

#   b/B = 1 字节     h/H = 2 字节     w/W = 4 字节     q/Q = 8 字节
#   小写 = 小端（little-endian）      大写 = 大端（big-endian）
#
# 例：
#   let n: i64 = unpack_u32be(p + 4);      # 读一个大端 32 位
#   pack_u32le(p, 305419896);              # 写一个小端 32 位
#
# unpack_fmt 的首字符 < 或 > 决定**整串**的字节序；
# 此后字母大小写表示有无符号（小写无符号、大写有符号），
# 与 Python struct 一致 —— 不要再用大小写表示字节序，那会双重指定。

# ---------------- 读 ----------------

fn unpack_u8(p: i64) -> i64 {
    return load8(p) & 255;
}

fn unpack_u16le(p: i64) -> i64 {
    return (load8(p) & 255) + (load8(p + 1) & 255) * 256;
}
fn unpack_u16be(p: i64) -> i64 {
    return (load8(p) & 255) * 256 + (load8(p + 1) & 255);
}

# 32 位：分成两个 16 位再乘，避免中间值溢出。
# 直接写 load8(p+3)*16777216 在 v >= 2^31 时会变成负数。
fn unpack_u32le(p: i64) -> i64 {
    let lo: i64 = unpack_u16le(p);
    let hi: i64 = unpack_u16le(p + 2);
    return lo + hi * 65536;
}
fn unpack_u32be(p: i64) -> i64 {
    let hi: i64 = unpack_u16be(p);
    let lo: i64 = unpack_u16be(p + 2);
    return hi * 65536 + lo;
}

# 64 位无符号：墨语言的 i64 是有符号的，所以值 >= 2^63 会读成负数。
# 这是语言层面的限制，调用方需要注意；绝大多数文件格式用不到这么大。
fn unpack_u64le(p: i64) -> i64 {
    let lo: i64 = unpack_u32le(p);
    let hi: i64 = unpack_u32le(p + 4);
    return lo + hi * 4294967296;
}
fn unpack_u64be(p: i64) -> i64 {
    let hi: i64 = unpack_u32be(p);
    let lo: i64 = unpack_u32be(p + 4);
    return hi * 4294967296 + lo;
}

# 有符号：先读无符号，再做符号扩展
fn sext(v: i64, bits: i64) -> i64 {
    let sign: i64 = 1;
    let i: i64 = 1;
    while i < bits {
        sign = sign * 2;
        i = i + 1;
    }
    if v >= sign { return v - sign * 2; }
    return v;
}

fn unpack_i8(p: i64) -> i64  { return sext(unpack_u8(p), 8); }
fn unpack_i16le(p: i64) -> i64 { return sext(unpack_u16le(p), 16); }
fn unpack_i16be(p: i64) -> i64 { return sext(unpack_u16be(p), 16); }
fn unpack_i32le(p: i64) -> i64 { return sext(unpack_u32le(p), 32); }
fn unpack_i32be(p: i64) -> i64 { return sext(unpack_u32be(p), 32); }

# ---------------- 写 ----------------

fn pack_u8(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    return 0;
}
fn pack_u16le(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    return 0;
}
fn pack_u16be(p: i64, v: i64) -> i64 {
    store8(p, (v / 256) & 255);
    store8(p + 1, v & 255);
    return 0;
}
fn pack_u32le(p: i64, v: i64) -> i64 {
    pack_u16le(p, v & 65535);
    pack_u16le(p + 2, (v / 65536) & 65535);
    return 0;
}
fn pack_u32be(p: i64, v: i64) -> i64 {
    pack_u16be(p, (v / 65536) & 65535);
    pack_u16be(p + 2, v & 65535);
    return 0;
}
fn pack_u64le(p: i64, v: i64) -> i64 {
    pack_u32le(p, v & 4294967295);
    pack_u32le(p + 4, (v / 4294967296) & 4294967295);
    return 0;
}
fn pack_u64be(p: i64, v: i64) -> i64 {
    pack_u32be(p, (v / 4294967296) & 4294967295);
    pack_u32be(p + 4, v & 4294967295);
    return 0;
}

# ---------------- 格式串驱动 ----------------
#
#   unpack_fmt(p, "<wWh", out)   # 小端：u32、i16、u16
#
# 首字符必须是 '<'（小端）或 '>'（大端），之后每个字母读一个字段，
# 结果依次写入 out（每个占 8 字节）。返回消耗的字节数；
# 格式串非法返回 -1。
#
# 用它的理由：解析一个固定布局的头部时，一行就能读完所有字段，
# 不用手数偏移。

fn fmt_size(c: i64) -> i64 {
    if c == 98 { return 1; }    # b
    if c == 66 { return 1; }    # B
    if c == 104 { return 2; }   # h
    if c == 72 { return 2; }    # H
    if c == 119 { return 4; }   # w
    if c == 87 { return 4; }    # W
    if c == 113 { return 8; }   # q
    if c == 81 { return 8; }    # Q
    return -1;
}

# 读一个字段。字节序由前缀决定，**大小写表示有符号/无符号**：
#   小写 = 无符号（b h w q）   大写 = 有符号（B H W Q）
# 与 Python struct 的约定一致。
fn fmt_read(p: i64, c: i64, big: i64) -> i64 {
    if c == 98 { return unpack_u8(p); }
    if c == 66 { return unpack_i8(p); }
    if c == 104 { if big == 1 { return unpack_u16be(p); } return unpack_u16le(p); }
    if c == 72 { if big == 1 { return unpack_i16be(p); } return unpack_i16le(p); }
    if c == 119 { if big == 1 { return unpack_u32be(p); } return unpack_u32le(p); }
    if c == 87 { if big == 1 { return unpack_i32be(p); } return unpack_i32le(p); }
    if c == 113 { if big == 1 { return unpack_u64be(p); } return unpack_u64le(p); }
    if c == 81 { if big == 1 { return unpack_u64be(p); } return unpack_u64le(p); }
    return 0;
}

fn unpack_fmt(p: i64, fmt: i64, out: i64) -> i64 {
    let i: i64 = 0;
    let big: i64 = 0;
    if load8(fmt) == 62 { big = 1; i = 1; }
    else {
        if load8(fmt) == 60 { i = 1; }
        else { return -1; }
    }
    let off: i64 = 0;
    let n: i64 = 0;
    while load8(fmt + i) != 0 {
        let c: i64 = load8(fmt + i);
        # 允许空格分隔：">w h b" 与 ">whb" 等价。
        # 第一版没跳过空格，把 32 当格式字符 → 整串判为非法。
        if c == 32 { i = i + 1; continue; }
        let sz: i64 = fmt_size(c);
        if sz < 0 { return -1; }
        store64(out + n * 8, fmt_read(p + off, c, big));
        off = off + sz;
        n = n + 1;
        i = i + 1;
    }
    return off;
}

# ---------------- 便捷：十六进制转储 ----------------
#
# 调试二进制数据最重要的一件事就是"能看到"。
fn hexdump(p: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let v: i64 = load8(p + i) & 255;
        let b: [24] byte = 0;
        utoa(v, &b, 16);
        if v < 16 { print("0"); }
        print(&b);
        if (i & 15) == 15 { print_nl(); } else { print(" "); }
        i = i + 1;
    }
    if (n & 15) != 0 { print_nl(); }
    return 0;
}
