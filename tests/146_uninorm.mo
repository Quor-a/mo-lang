# 146 —— Unicode 规范化 NFC / NFD（UAX #15）              # expect: 0
#
# ── 为什么补这个测试 ────────────────────────────────────────
#   lib/uninorm.mo 在 v1.142 就写好了（库 + 文档齐全），但**没有任何
#   测试引用它** —— 是 projcheck 第 3 项把它报出来的。这和 v1.130 的
#   actor.mo 是同一类：能编译、能跑、退出码 0，于是"从未被验证过"
#   这件事本身不会发出任何信号。
#
# ── 期望值全部来自 Python 3.10 的 unicodedata（Unicode 13.0.0）──
#   不凭记忆构造：U+D7A3 的 NFD 我以为是 1112 1175 11A8，
#   Python 给的是 **1112 1175 11C2**。手写的期望错起来毫无征兆。
#
# ── 覆盖的四条规则 ──────────────────────────────────────────
#   ① 递归分解   U+1E14 → 0045 0304 0300（U+0112 还要再拆一层）
#   ② 规范排序   0041 030A 0327 → NFD 0041 0327 030A（按 ccc 稳定排序）
#   ③ 阻挡规则   组合时记号前存在 ccc(B) >= ccc(C) 的 B 则不得组合
#   ④ Hangul      U+AC00 → 1100 1161；U+D7A3 → 1112 1175 11C2
#
# ── 覆盖守卫 ────────────────────────────────────────────────
#   UN_MAXD >= 2 且 UN_NREC > 0：若恒为 1 / 0，说明**递归分解分支
#   一次都没走到**，上面的"递归分解"断言就是靠单级分解碰巧通过的。

import "assert.mo";
import "uninorm.mo";

fn set1(a: i64) -> i64 {
    UN_IN[0] = a;
    UN_NN = 1;
    return 0;
}
fn set3(a: i64, b: i64, c: i64, n: i64) -> i64 {
    UN_IN[0] = a;
    UN_IN[1] = b;
    UN_IN[2] = c;
    UN_NN = n;
    return 0;
}
fn nfd_match(w0: i64, w1: i64, w2: i64, wn: i64) -> i64 {
    if UN_LN != wn { return 0; }
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    if wn > 0 { a = UN_D2[0]; }
    if wn > 1 { b = UN_D2[1]; }
    if wn > 2 { c = UN_D2[2]; }
    if a != w0 { return 0; }
    if b != w1 { return 0; }
    if c != w2 { return 0; }
    return 1;
}
fn nfc_match(w0: i64, w1: i64, w2: i64, wn: i64) -> i64 {
    if UN_LC != wn { return 0; }
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    if wn > 0 { a = UN_OUT[0]; }
    if wn > 1 { b = UN_OUT[1]; }
    if wn > 2 { c = UN_OUT[2]; }
    if a != w0 { return 0; }
    if b != w1 { return 0; }
    if c != w2 { return 0; }
    return 1;
}

fn tdec() -> i64 {
    set1(0x00C5); un_nfd();
    assert_eq("U+00C5 的 NFD", nfd_match(0x0041, 0x030A, 0, 2), 1);
    set1(0x1E14); un_nfd();
    assert_eq("U+1E14 的 NFD(递归二级)", nfd_match(0x0045, 0x0304, 0x0300, 3), 1);
    set1(0x1E0A); un_nfd();
    assert_eq("U+1E0A 的 NFD", nfd_match(0x0044, 0x0307, 0, 2), 1);
    set1(0x0104); un_nfd();
    assert_eq("U+0104 的 NFD", nfd_match(0x0041, 0x0328, 0, 2), 1);
    return 0;
}

fn thangul() -> i64 {
    set1(0xAC00); un_nfd();
    assert_eq("U+AC00 的 NFD", nfd_match(0x1100, 0x1161, 0, 2), 1);
    set1(0xD7A3); un_nfd();
    assert_eq("U+D7A3 的 NFD", nfd_match(0x1112, 0x1175, 0x11C2, 3), 1);
    set1(0xAC00); un_nfc();
    assert_eq("U+AC00 的 NFC", nfc_match(0xAC00, 0, 0, 1), 1);
    set1(0xD7A3); un_nfc();
    assert_eq("U+D7A3 的 NFC", nfc_match(0xD7A3, 0, 0, 1), 1);
    return 0;
}

fn treorder() -> i64 {
    # 0041 030A(ccc230) 0327(ccc202) → NFD 0041 0327 030A
    set3(0x0041, 0x030A, 0x0327, 3); un_nfd();
    assert_eq("排序 NFD", nfd_match(0x0041, 0x0327, 0x030A, 3), 1);
    set3(0x0041, 0x030A, 0x0327, 3); un_nfc();
    assert_eq("排序 NFC", nfc_match(0x00C5, 0x0327, 0, 2), 1);
    # 0041 0300(230) 0316(220) → NFD 0041 0316 0300，NFC 00C0 0316
    set3(0x0041, 0x0300, 0x0316, 3); un_nfd();
    assert_eq("阻挡 NFD", nfd_match(0x0041, 0x0316, 0x0300, 3), 1);
    set3(0x0041, 0x0300, 0x0316, 3); un_nfc();
    assert_eq("阻挡 NFC", nfc_match(0x00C0, 0x0316, 0, 2), 1);
    return 0;
}

# 幂等性：NFD(NFD(x))==NFD(x)、NFC(NFC(x))==NFC(x)、NFC(NFD(x))==NFC(x)
fn tidem() -> i64 {
    let cp: i64 = 0x00C0;
    let bad1: i64 = 0;
    let bad2: i64 = 0;
    let bad3: i64 = 0;
    let cnt: i64 = 0;
    while cp <= 0x017F {
        set1(cp); un_nfd();
        let n1: i64 = UN_LN;
        un_snap_nfd();
        un_from_nfd();
        un_nfd();
        if un_cmp_nfd() != 1 { bad1 = bad1 + 1; }
        set1(cp); un_nfc();
        un_snap_nfc();
        un_from_nfc();
        un_nfc();
        if un_cmp_nfc() != 1 { bad2 = bad2 + 1; }
        set1(cp); un_nfc();
        un_snap_nfc();
        set1(cp); un_nfd();
        un_from_nfd();
        un_nfc();
        if un_cmp_nfc() != 1 { bad3 = bad3 + 1; }
        if n1 > 1 { cnt = cnt + 1; }
        cp = cp + 1;
    }
    assert_eq("NFD 幂等违反数", bad1, 0);
    assert_eq("NFC 幂等违反数", bad2, 0);
    assert_eq("NFC(NFD)==NFC 违反数", bad3, 0);
    # 空转守卫：这一段里必须真的有可分解的码点
    assert_eq("存在可分解码点(空转守卫)", cnt > 20, 1);
    return 0;
}

# 覆盖守卫：递归分解分支必须真的被走到
fn tguard() -> i64 {
    set1(0x1E14); un_nfd();
    assert_eq("U+1E14 的最大分解深度>=2", UN_MAXD >= 2, 1);
    assert_eq("U+1E14 的递归展开次数>0", UN_NREC > 0, 1);
    return 0;
}

fn tunk() -> i64 {
    # 覆盖范围外必须响出来，而不是静默给个像样的结果
    set1(0x4E00); un_nfd();
    assert_eq("范围外置 UN_UNK", UN_UNK, 1);
    return 0;
}

fn main() -> i64 {
    un_init();
    tdec();
    thangul();
    treorder();
    tidem();
    tguard();
    tunk();
    return test_done();
}
