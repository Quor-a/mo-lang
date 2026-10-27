# utf8 —— 位并行（SWAR）UTF-8 校验与编解码
#
# ── 概念 ────────────────────────────────────────────────────────────
#   Muła / Kurz / Lemire，《Validating UTF-8 In Less Than One Instruction
#   Per Byte》，Software: Practice and Experience 48(5), 2018。
#
#   论文的载体是 SIMD。这里实现的是它的 **SWAR 变体**：把 8 个字节装进一个
#   i64，用几次移位把「哪些字节必须是后续字节」一次性铺开，再与实际的后续
#   字节做一次异或。不需要任何 SIMD 指令，纯整数运算。
#
#   为什么算「概念」而不是「工程惯例」：主流标准库里的 UTF-8 校验至今大多是
#   Höhrmann 的标量 DFA（逐字节查表）—— glibc、Go 1.18 之前、Python、
#   多数嵌入实现都是。SWAR/SIMD 版近几年才进 Rust / Go 1.19+，且都绑死在
#   SIMD 上；没有 SIMD 的环境只能退回逐字节。本实现证明不绑 SIMD 也能位并行。
#
# ── 三条移位做了什么 ────────────────────────────────────────────────
#   x      = 8 个字节（byte j 占 bit 8j..8j+7）
#   a      = x & M80            → 每字节的 bit7（非 ASCII）
#   s1..s4 = (x<<1..4) & M80    → 把 bit6/bit5/bit4/bit3 搬到 bit7 位置
#   lead   = a & s1             → bit7、bit6 都置 = 前导字节（11xxxxxx）
#   cont   = a & (s1 ^ M80)     → bit7 置、bit6 清   = 后续字节（10xxxxxx）
#   l3     = lead & s2          → 1110xxxx / 11110xxx（长度 ≥ 3）
#   l4     = l3 & s3            → 11110xxx          （长度 = 4）
#   bad    = l4 & s4            → 11111xxx          （长度 ≥ 5，直接非法）
#
#   期望的后续字节位置 = (lead << 8) | (l3 << 16) | (l4 << 24)
#     前导字节在位置 j 时 bit7 落在 8j+7；左移 8 位正好落到 8(j+1)+7，
#     即下一个字节的 bit7。三次移位对应「需要第 1 / 2 / 3 个后续字节」。
#   于是 cont ^ exp 的每一位就是一处不一致：
#     exp 有而 cont 没有 → 序列被截断
#     cont 有而 exp 没有 → 孤立后续字节
#
# ── 范围检查（越长编码 / 代理对 / 超上界）也是位并行的 ──────────────
#   全部能化成「后续字节第 1 个的 bit5 / bit4」：
#     0xE0 后必须 ≥ 0xA0（bit5 = 1）      0xED 后必须 ≤ 0x9F（bit5 = 0）
#     0xF0 后必须 ≥ 0x90（bit5 或 bit4）  0xF4 后必须 ≤ 0x8F（bit5、bit4 都 0）
#   「某字节等于常数」用 SWAR 零字节检测：haszero(x ^ broadcast(k))。
#
# ── 跨块 ────────────────────────────────────────────────────────────
#   序列可以跨 8 字节边界，最多延伸 3 个字节。块末把「下一块前 3 个字节
#   必须是后续字节」记进 U8NEED，下一块并进 exp。四种特殊前导字节
#   （E0/ED/F0/F4）若落在本块最后一字节，它们的范围要求也要带过去。

# 墨语言的 var 初始值只接受非负整数字面量（0-1 与 -1 都是语法错误），
# 所以这三个常数在函数里算出来。u8_valid 每次都会调用 u8_init，
# 直接调 u8_block 的人必须自己先调一次。
var M01: i64 = 0;                          # 0x0101_0101_0101_0101
var M80: i64 = 0;                          # 0x8080_8080_8080_8080
var MN1: i64 = 0;                          # 全 1

fn u8_init() -> i64 {
    M01 = 72340172838076673;
    M80 = 0 - 9187201950435737472;
    MN1 = 0 - 1;
    return 0;
}

var U8NEED: i64 = 0;   # 下一块 byte0..2 必须是后续字节（bit7 置位）
var U8XE0: i64 = 0;    # 上一块末字节是 E0
var U8XED: i64 = 0;    # 上一块末字节是 ED
var U8XF0: i64 = 0;    # 上一块末字节是 F0
var U8XF4: i64 = 0;    # 上一块末字节是 F4
var U8CP:  i64 = 0;    # u8_next 解出的码点

# 把字节 b 广播到 8 个字节。b ≤ 255 时 b * 0x0101..01 正好等于广播值。
fn bc(b: i64) -> i64 {
    return b * M01;
}

# SWAR 零字节检测：哪些字节为 0（结果 bit7 置位）
#   (v - 1) & ~v & 0x80 —— b = 0 时 (0-1) = 0xFF，与 ~0 = 0xFF 相与得 0x80。
#   借位会传到更高位字节，但那只会把一个 ≤0x7F 的字节减 1，bit7 仍为 0，
#   不会产生假阳性。
fn haszero(v: i64) -> i64 {
    let t: i64 = v - M01;
    let u: i64 = ~v;
    return (t & u) & M80;
}

# 哪些字节等于常数 b
fn beq(x: i64, b: i64) -> i64 {
    return haszero(x ^ bc(b));
}

# ── 单块（8 字节）校验。返回 0 = 合法，非 0 = 非法 ──────────────────
fn u8_block(x: i64) -> i64 {
    let a:  i64 = x & M80;
    let s1: i64 = (x << 1) & M80;   # bit6 → bit7
    let s2: i64 = (x << 2) & M80;   # bit5 → bit7
    let s3: i64 = (x << 3) & M80;   # bit4 → bit7
    let s4: i64 = (x << 4) & M80;   # bit3 → bit7

    let lead: i64 = a & s1;
    let cont: i64 = a & (s1 ^ M80);
    let l3:   i64 = lead & s2;
    let l4:   i64 = l3 & s3;
    let bad:  i64 = l4 & s4;
    if bad != 0 { return 1; }

    # 结构：期望的后续字节 vs 实际的后续字节
    let exp: i64 = (lead << 8) | (l3 << 16) | (l4 << 24);
    exp = exp & M80;
    exp = exp | U8NEED;
    if (cont ^ exp) != 0 { return 1; }

    # 范围：越长编码 / 代理对 / 超上界
    let e0: i64 = beq(x, 224);
    let ed: i64 = beq(x, 237);
    let f0: i64 = beq(x, 240);
    let f4: i64 = beq(x, 244);
    let c0: i64 = beq(x, 192);
    let c1: i64 = beq(x, 193);
    let f1: i64 = beq(x, 241);
    let f2: i64 = beq(x, 242);
    let f3: i64 = beq(x, 243);
    let fok: i64 = f0 | f1 | f2 | f3 | f4;

    let not5: i64 = s2 ^ M80;      # bit5 清
    let not4: i64 = s3 ^ M80;      # bit4 清

    let r: i64 = c0 | c1;                       # 0xC0 / 0xC1：越长
    r = r | (l4 & (fok ^ M80));                 # 0xF5..0xF7：超过 U+10FFFF
    r = r | ((e0 << 8) & not5);                 # E0 后必须 ≥ 0xA0
    r = r | ((ed << 8) & s2);                   # ED 后必须 ≤ 0x9F（排除代理对）
    r = r | ((f0 << 8) & (not5 & not4));        # F0 后必须 ≥ 0x90
    r = r | ((f4 << 8) & (s2 | s3));            # F4 后必须 ≤ 0x8F
    # 上一块末字节是特殊前导时，要求落在本块 byte0
    r = r | (U8XE0 & not5);
    r = r | (U8XED & s2);
    r = r | (U8XF0 & (not5 & not4));
    r = r | (U8XF4 & (s2 | s3));
    if r != 0 { return 1; }

    # 跨块：byte 5/6/7 上的前导字节会要求下一块的前几个字节
    #   >> 是算术右移，位 63 为 1 时高位补 1；& 1 只取原位，不受影响。
    let b5: i64 = (lead >> 47) & 1;
    let c5: i64 = (l3 >> 47) & 1;
    let d5: i64 = (l4 >> 47) & 1;
    let b6: i64 = (lead >> 55) & 1;
    let c6: i64 = (l3 >> 55) & 1;
    let d6: i64 = (l4 >> 55) & 1;
    let b7: i64 = (lead >> 63) & 1;
    let c7: i64 = (l3 >> 63) & 1;
    let d7: i64 = (l4 >> 63) & 1;

    U8NEED = ((b7 | c6 | d5) << 7) | ((c7 | d6) << 15) | (d7 << 23);
    U8XE0 = ((e0 >> 63) & 1) << 7;
    U8XED = ((ed >> 63) & 1) << 7;
    U8XF0 = ((f0 >> 63) & 1) << 7;
    U8XF4 = ((f4 >> 63) & 1) << 7;
    return 0;
}

# ── 主入口：p 指向 n 个字节，返回 1 = 合法 UTF-8，0 = 非法 ───────────
fn u8_valid(p: i64, n: i64) -> i64 {
    u8_init();
    U8NEED = 0;
    U8XE0 = 0;
    U8XED = 0;
    U8XF0 = 0;
    U8XF4 = 0;
    if n < 0 { return 0; }
    let tail: [8] byte = 0;
    let i: i64 = 0;
    while i + 8 <= n {
        if u8_block(load64(p + i)) != 0 { return 0; }
        i = i + 8;
    }
    if i < n {
        let j: i64 = 0;
        while i + j < n {
            store8(&tail + j, load8(p + i + j));
            j = j + 1;
        }
        if u8_block(load64(&tail)) != 0 { return 0; }
    }
    # 输入结束时若还有未满足的后续字节要求 = 序列被截断
    if U8NEED != 0 { return 0; }
    return 1;
}

# ════════════════════════════════════════════════════════════════════
#  参照实现：逐字节标量状态机（Höhrmann 那一派，Unicode Table 3-7）
#  刻意写成与 SWAR 版完全无关的形式 —— 它是独立参照，用来交叉验证。
#  两条独立路径给出同样结论，结论才可信；只跑一条证明不了什么。
# ════════════════════════════════════════════════════════════════════
fn u8_iscont(p: i64, k: i64) -> i64 {
    let c: i64 = load8(p + k);
    if c < 128 { return 0; }
    if c > 191 { return 0; }
    return 1;
}

fn u8_ref(p: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let b: i64 = load8(p + i);
        if b < 128 {
            i = i + 1;
        } else {
            if b < 192 {
                return 0;
            } else {
                if b < 224 {
                    if b < 194 { return 0; }
                    if i + 2 > n { return 0; }
                    if u8_iscont(p, i + 1) == 0 { return 0; }
                    i = i + 2;
                } else {
                    if b < 240 {
                        if i + 3 > n { return 0; }
                        if u8_iscont(p, i + 1) == 0 { return 0; }
                        if u8_iscont(p, i + 2) == 0 { return 0; }
                        let c1: i64 = load8(p + i + 1);
                        if b == 224 { if c1 < 160 { return 0; } }
                        if b == 237 { if c1 > 159 { return 0; } }
                        i = i + 3;
                    } else {
                        if b < 248 {
                            if b > 244 { return 0; }
                            if i + 4 > n { return 0; }
                            if u8_iscont(p, i + 1) == 0 { return 0; }
                            if u8_iscont(p, i + 2) == 0 { return 0; }
                            if u8_iscont(p, i + 3) == 0 { return 0; }
                            let d1: i64 = load8(p + i + 1);
                            if b == 240 { if d1 < 144 { return 0; } }
                            if b == 244 { if d1 > 143 { return 0; } }
                            i = i + 4;
                        } else {
                            return 0;
                        }
                    }
                }
            }
        }
    }
    return 1;
}

# ════════════════════════════════════════════════════════════════════
#  解码 / 编码
# ════════════════════════════════════════════════════════════════════

# 从 i 处解出一个码点，码点写入 U8CP，返回下一个字节下标；非法返回 -1
fn u8_next(p: i64, n: i64, i: i64) -> i64 {
    U8CP = 0;
    if i < 0 { return 0 - 1; }
    if i >= n { return 0 - 1; }
    let b: i64 = load8(p + i);
    if b < 128 {
        U8CP = b;
        return i + 1;
    }
    if b < 192 { return 0 - 1; }
    if b < 224 {
        if i + 2 > n { return 0 - 1; }
        let c: i64 = load8(p + i + 1);
        if c < 128 { return 0 - 1; }
        if c > 191 { return 0 - 1; }
        if b < 194 { return 0 - 1; }
        U8CP = (b - 192) * 64 + (c - 128);
        return i + 2;
    }
    if b < 240 {
        if i + 3 > n { return 0 - 1; }
        let c: i64 = load8(p + i + 1);
        let d: i64 = load8(p + i + 2);
        if c < 128 { return 0 - 1; }
        if c > 191 { return 0 - 1; }
        if d < 128 { return 0 - 1; }
        if d > 191 { return 0 - 1; }
        if b == 224 { if c < 160 { return 0 - 1; } }
        if b == 237 { if c > 159 { return 0 - 1; } }
        U8CP = (b - 224) * 4096 + (c - 128) * 64 + (d - 128);
        return i + 3;
    }
    if b < 248 {
        if b > 244 { return 0 - 1; }
        if i + 4 > n { return 0 - 1; }
        let c: i64 = load8(p + i + 1);
        let d: i64 = load8(p + i + 2);
        let e: i64 = load8(p + i + 3);
        if c < 128 { return 0 - 1; }
        if c > 191 { return 0 - 1; }
        if d < 128 { return 0 - 1; }
        if d > 191 { return 0 - 1; }
        if e < 128 { return 0 - 1; }
        if e > 191 { return 0 - 1; }
        if b == 240 { if c < 144 { return 0 - 1; } }
        if b == 244 { if c > 143 { return 0 - 1; } }
        U8CP = (b - 240) * 262144 + (c - 128) * 4096 + (d - 128) * 64 + (e - 128);
        return i + 4;
    }
    return 0 - 1;
}

# 码点数（不是字节数）
fn u8_ncp(p: i64, n: i64) -> i64 {
    let c: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let nx: i64 = u8_next(p, n, i);
        if nx < 0 { return 0 - 1; }
        i = nx;
        c = c + 1;
    }
    return c;
}

# 把一个码点编码到 dst，返回写入的字节数；非法码点返回 0
fn u8_encode(cp: i64, dst: i64) -> i64 {
    if cp < 0 { return 0; }
    if cp < 128 {
        store8(dst, cp);
        return 1;
    }
    if cp < 2048 {
        store8(dst, 192 + cp / 64);
        store8(dst + 1, 128 + (cp - (cp / 64) * 64));
        return 2;
    }
    if cp < 65536 {
        if cp >= 55296 {
            if cp <= 57343 { return 0; }
        }
        let r: i64 = cp - (cp / 4096) * 4096;
        store8(dst, 224 + cp / 4096);
        store8(dst + 1, 128 + r / 64);
        store8(dst + 2, 128 + (r - (r / 64) * 64));
        return 3;
    }
    if cp < 1114112 {
        let r: i64 = cp - (cp / 262144) * 262144;
        let s: i64 = r - (r / 4096) * 4096;
        let t: i64 = s - (s / 64) * 64;
        store8(dst, 240 + cp / 262144);
        store8(dst + 1, 128 + r / 4096);
        store8(dst + 2, 128 + s / 64);
        store8(dst + 3, 128 + t);
        return 4;
    }
    return 0;
}
