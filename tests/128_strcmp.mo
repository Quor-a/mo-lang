# 128 —— str 的字典序比较（< <= > >=）   # expect: 0
#
# ── 做了什么 ────────────────────────────────────────────────────────
#   1.118 让 str 成为一等类型（== 按内容比），但 < <= > >= 仍按**地址**比。
#   本版补齐：两侧都是 str 时走无符号字节字典序，一侧不是 str 时退回地址比。
#
# ── 最关键的一条：必须无符号 ────────────────────────────────────────
#   UTF-8 的多字节码与续接字节都 >= 0x80。把它们当**有符号** char 比，
#   0xE4 变成 -28，于是"中" < "a" —— 整个 CJK 区间跑到 ASCII 前面，
#   排序 / 二分查找 / 最值全部静默错位（这正是 C 规定 strcmp 按
#   unsigned char 比较的原因）。
#   实测：有符号实现下 cjk-gt-z 与 cjk-gt-a 都会变成 0。
#
# ── 一条可验证的性质 ────────────────────────────────────────────────
#   UTF-8 的**字节序 == 码点序**。⑤ 用 utf8.mo 解码出码点再比一次：
#   两条完全独立的通路（位比较 / 解码）必须给出同样的顺序。
#
# ── 刻意保留的对照 ──────────────────────────────────────────────────
#   ptr 仍然按地址比；str 与整数比也退回地址比（与 == 的规则一致）。

import "io.mo";
import "assert.mo";
import "utf8.mo";
import "str.mo";

var b1: [16] byte = 0;      # "a"          U+0061
var b2: [16] byte = 0;      # "z"          U+007A
var b3: [16] byte = 0;      # "é"  C3 A9   U+00E9
var b4: [16] byte = 0;      # "中" E4 B8 AD U+4E2D
var b5: [16] byte = 0;      # "😀" F0 9F 98 80  U+1F600

# 独立参照：解出**首码点**。字节比较与它必须是同一个顺序。
fn first_cp(p: str) -> i64 {
    let n: i64 = strlen(p);
    let k: i64 = u8_next(p, n, 0);
    return U8CP;
}

fn main() -> i64 {
    u8_init();
    b1[0] = 97;
    b2[0] = 122;
    b3[0] = 195; b3[1] = 169;
    b4[0] = 228; b4[1] = 184; b4[2] = 173;
    b5[0] = 240; b5[1] = 159; b5[2] = 152; b5[3] = 128;

    let s1: str = &b1;
    let s2: str = &b2;
    let s3: str = &b3;
    let s4: str = &b4;
    let s5: str = &b5;

    # ── ① 字面量基本序 ──
    assert_eq("lt", "abc" < "abd", 1);
    assert_eq("lt-rev", "abd" < "abc", 0);
    assert_eq("eq-lt", "abc" < "abc", 0);
    assert_eq("eq-gt", "abc" > "abc", 0);
    assert_eq("le", "abc" <= "abc", 1);
    assert_eq("ge", "abc" >= "abc", 1);
    assert_eq("gt", "abd" > "abc", 1);

    # ── ② 前缀：更短者更小（走到 NUL 时左=0 < 右）──
    assert_eq("prefix-lt", "ab" < "abc", 1);
    assert_eq("prefix-gt", "abc" > "ab", 1);
    assert_eq("prefix-le", "ab" <= "abc", 1);

    # ── ③ 空串 ──
    assert_eq("empty-lt", "" < "a", 1);
    assert_eq("a-gt-empty", "a" > "", 1);
    assert_eq("empty-eq-lt", "" < "", 0);
    assert_eq("empty-le", "" <= "", 1);
    assert_eq("empty-ge", "" >= "", 1);

    # ── ④ 🔴 无符号字节（本节才是本版的核心）──
    assert_eq("cjk-gt-z", s4 > s2, 1);
    assert_eq("cjk-gt-a", s4 > s1, 1);
    # 用 **<** 方向的 ASCII vs 高字节：有符号实现下这两条也会翻
    assert_eq("z-lt-cjk", s2 < s4, 1);
    assert_eq("a-lt-cjk", s1 < s4, 1);
    assert_eq("cjk-gt-z-le", s4 >= s2, 1);
    assert_eq("cjk-lt-emoji", s4 < s5, 1);
    # 非空转守卫：确实有 >= 0x80 的字节参与比较。
    # 没有它，④ 可能只是"都在比 ASCII"，有符号实现也能全绿。
    assert_true("high-byte-cjk", s4[0] > 127);
    assert_true("high-byte-emoji", s5[0] > 127);

    # ── ⑤ UTF-8 字节序 == 码点序（两条独立通路互证）──
    assert_eq("a-lt-z", s1 < s2, 1);
    assert_eq("z-lt-eacute", s2 < s3, 1);
    assert_eq("eacute-lt-cjk", s3 < s4, 1);
    assert_true("cp-a-lt-z", first_cp(s1) < first_cp(s2));
    assert_true("cp-z-lt-eacute", first_cp(s2) < first_cp(s3));
    assert_true("cp-eacute-lt-cjk", first_cp(s3) < first_cp(s4));
    assert_true("cp-cjk-lt-emoji", first_cp(s4) < first_cp(s5));
    # 守卫：解码必须真的成功（U+4E2D / U+1F600），否则上面全是 0<0
    assert_eq("cp-cjk", first_cp(s4), 20013);
    assert_eq("cp-emoji", first_cp(s5), 128512);

    # ── ⑥ 按内容比，不是按地址比 ──
    # 先声明的局部变量地址更高，于是"内容序"与"地址序"相反：
    # 内容 a < b，地址 &x > &y。按地址比会得到 0，按内容比才是 1。
    let x: [8] byte = 0;
    let y: [8] byte = 0;
    x[0] = 97;
    y[0] = 98;
    let sx: str = &x;
    let sy: str = &y;
    assert_eq("content-not-addr", sx < sy, 1);
    assert_true("addr-opposite", &x > &y);

    # ── ⑦ ptr 仍是地址比（不许被悄悄改掉）──
    let p1: ptr = &x;
    let p2: ptr = &y;
    assert_eq("ptr-addr-order", p1 < p2, 0);

    # 🔴 必须 return test_done()：写成 `test_done(); return 0;` 的话
    #    断言失败不影响退出码，测试恒为通过（projcheck 第 8 项专门盯这个）。
    return test_done();
}
