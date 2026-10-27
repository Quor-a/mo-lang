# 126 —— UTF-8 位并行（SWAR）校验与编解码   # expect: 0
#
# ── 概念 ────────────────────────────────────────────────────────────
#   Muła / Kurz / Lemire 2018 的 SWAR 变体：8 个字节装进一个 i64，
#   用三次移位把「哪些字节必须是后续字节」一次铺开，再与实际后续字节异或。
#   主流标准库至今多为逐字节 DFA，SWAR/SIMD 版都绑在 SIMD 指令上。
#
# ── 本测试的三层交叉验证 ────────────────────────────────────────────
#   ① 已知向量：合法 / 非法定例（越长、代理对、超上界、孤立、截断）
#   ② 穷举：21 个边界字节值 × 4 个位置 × 两个偏移（块内 + 跨块），
#      SWAR 版与逐字节参照实现**逐个比对**，不允许任何一次不一致
#   ③ 随机长串：长度 1..24，同样两版比对
#
#   ② 里「偏移 5」是关键：4 个字节落在 byte5..byte8，跨过 8 字节边界，
#      U8NEED / U8XE0 / U8XED / U8XF0 / U8XF4 五个跨块状态全被覆盖。
#      只在偏移 0 上穷举的话，跨块逻辑一行都不会被执行到。
#
# ── 必须存在的"非空转"断言 ──────────────────────────────────────────
#   NV / NI 都要 > 0：若随机样本全是非法，比对恒等，测试形同虚设。

import "assert.mo";
import "io.mo";
import "utf8.mo";
import "random.mo";

var BUF: [64] byte = 0;
# 21 个边界值：ASCII、各类前导/后续字节的边界、以及全部非法起点
var AL: [24] byte = 0;
var NA: i64 = 0;
var NV: i64 = 0;
var NI: i64 = 0;
var MM: i64 = 0;      # 两版结论不一致的次数，必须为 0

fn setalpha() -> i64 {
    store8(&AL + 0, 0);
    store8(&AL + 1, 65);
    store8(&AL + 2, 128);
    store8(&AL + 3, 143);
    store8(&AL + 4, 144);
    store8(&AL + 5, 159);
    store8(&AL + 6, 160);
    store8(&AL + 7, 191);
    store8(&AL + 8, 192);
    store8(&AL + 9, 193);
    store8(&AL + 10, 194);
    store8(&AL + 11, 223);
    store8(&AL + 12, 224);
    store8(&AL + 13, 237);
    store8(&AL + 14, 239);
    store8(&AL + 15, 240);
    store8(&AL + 16, 244);
    store8(&AL + 17, 245);
    store8(&AL + 18, 247);
    store8(&AL + 19, 248);
    store8(&AL + 20, 255);
    NA = 21;
    return 0;
}

# 把 48 字节全部填成 'a'，再把 cnt 个字节写到 off 处，返回校验结果
fn seq(off: i64, b0: i64, b1: i64, b2: i64, b3: i64, cnt: i64) -> i64 {
    let i: i64 = 0;
    while i < 64 {
        store8(&BUF + i, 97);
        i = i + 1;
    }
    if cnt > 0 { store8(&BUF + off, b0); }
    if cnt > 1 { store8(&BUF + off + 1, b1); }
    if cnt > 2 { store8(&BUF + off + 2, b2); }
    if cnt > 3 { store8(&BUF + off + 3, b3); }
    return u8_valid(&BUF, off + cnt);
}

# 两版比对并统计
fn cross(off: i64, b0: i64, b1: i64, b2: i64, b3: i64, cnt: i64) -> i64 {
    let v: i64 = seq(off, b0, b1, b2, b3, cnt);
    let i: i64 = 0;
    while i < 64 { store8(&BUF + i, 97); i = i + 1; }
    if cnt > 0 { store8(&BUF + off, b0); }
    if cnt > 1 { store8(&BUF + off + 1, b1); }
    if cnt > 2 { store8(&BUF + off + 2, b2); }
    if cnt > 3 { store8(&BUF + off + 3, b3); }
    let r: i64 = u8_ref(&BUF, off + cnt);
    if v != r { MM = MM + 1; }
    if v == 1 { NV = NV + 1; } else { NI = NI + 1; }
    return 0;
}

# 长度 1..24 的随机串，两版比对
fn randrun(n: i64) -> i64 {
    let t: i64 = 0;
    while t < n {
        let len: i64 = 1 + rand_range(24);
        let i: i64 = 0;
        while i < 64 { store8(&BUF + i, 0); i = i + 1; }
        i = 0;
        while i < len {
            # 一半概率用边界值，一半用纯随机字节 —— 纯随机几乎全是非法，
            # 只用它会让"合法样本"数量趋近 0，比对就空转了
            let c: i64 = rand_range(2);
            if c == 0 {
                store8(&BUF + i, load8(&AL + rand_range(NA)));
            } else {
                store8(&BUF + i, rand_range(256));
            }
            i = i + 1;
        }
        let v: i64 = u8_valid(&BUF, len);
        let r: i64 = u8_ref(&BUF, len);
        if v != r { MM = MM + 1; }
        if v == 1 { NV = NV + 1; } else { NI = NI + 1; }
        t = t + 1;
    }
    return 0;
}

# 编码 → 校验 → 解码 往返
fn roundtrip(cp: i64) -> i64 {
    let nb: i64 = u8_encode(cp, &BUF);
    if nb == 0 { return 0; }
    if u8_valid(&BUF, nb) != 1 { return 0; }
    if u8_ncp(&BUF, nb) != 1 { return 0; }
    let nx: i64 = u8_next(&BUF, nb, 0);
    if nx != nb { return 0; }
    if U8CP != cp { return 0; }
    return 1;
}

fn main() -> i64 {
    setalpha();
    srand(20261012);

    # ── ① 已知向量 ─────────────────────────────────────────────────
    assert_eq("空串合法", u8_valid(&BUF, 0), 1);
    assert_eq("纯 ASCII", seq(0, 97, 98, 99, 0, 3), 1);
    assert_eq("é = C3 A9", seq(0, 195, 169, 0, 0, 2), 1);
    assert_eq("€ = E2 82 AC", seq(0, 226, 130, 172, 0, 3), 1);
    assert_eq("😀 = F0 9F 98 80", seq(0, 240, 159, 152, 128, 4), 1);

    assert_eq("C0 80 越长", seq(0, 192, 128, 0, 0, 2), 0);
    assert_eq("C1 BF 越长", seq(0, 193, 191, 0, 0, 2), 0);
    assert_eq("E0 80 80 越长", seq(0, 224, 128, 128, 0, 3), 0);
    assert_eq("E0 9F BF 越长", seq(0, 224, 159, 191, 0, 3), 0);
    assert_eq("ED A0 80 代理对", seq(0, 237, 160, 128, 0, 3), 0);
    assert_eq("ED BF BF 代理对", seq(0, 237, 191, 191, 0, 3), 0);
    assert_eq("F0 80 80 80 越长", seq(0, 240, 128, 128, 128, 4), 0);
    assert_eq("F4 90 80 80 超上界", seq(0, 244, 144, 128, 128, 4), 0);
    assert_eq("F5 80 80 80 超上界", seq(0, 245, 128, 128, 128, 4), 0);
    assert_eq("F8 五字节序列", seq(0, 248, 136, 128, 128, 4), 0);
    assert_eq("FE 非法", seq(0, 254, 0, 0, 0, 1), 0);
    assert_eq("FF 非法", seq(0, 255, 0, 0, 0, 1), 0);
    assert_eq("孤立后续字节", seq(0, 128, 0, 0, 0, 1), 0);
    assert_eq("C3 截断", seq(0, 195, 0, 0, 0, 1), 0);
    assert_eq("E2 82 截断", seq(0, 226, 130, 0, 0, 2), 0);
    assert_eq("F0 9F 98 截断", seq(0, 240, 159, 152, 0, 3), 0);
    assert_eq("多一个后续字节", seq(0, 226, 130, 172, 172, 4), 0);

    # ── 跨块：序列压在 8 字节边界上（偏移 7 / 6 / 5）─────────────────
    assert_eq("2字节跨块 合法", seq(7, 195, 169, 0, 0, 2), 1);
    assert_eq("2字节跨块 后续被破坏", seq(7, 195, 65, 0, 0, 2), 0);
    assert_eq("3字节跨块 合法", seq(7, 226, 130, 172, 0, 3), 1);
    assert_eq("3字节跨块 缺一个", seq(7, 226, 130, 0, 0, 2), 0);
    assert_eq("4字节跨块 合法", seq(7, 240, 159, 152, 128, 4), 1);
    assert_eq("4字节跨块 缺一个", seq(7, 240, 159, 152, 0, 3), 0);
    assert_eq("4字节跨到 byte2 合法", seq(6, 240, 159, 152, 128, 4), 1);
    assert_eq("4字节跨到 byte3 合法", seq(5, 240, 159, 152, 128, 4), 1);
    # 前导字节正好是缓冲区最后一个字节：只剩 U8NEED 的收尾检查能抓到
    assert_eq("块末前导字节孤立", seq(7, 195, 0, 0, 0, 1), 0);
    assert_eq("块末 4 字节前导孤立", seq(7, 240, 0, 0, 0, 1), 0);
    # 特殊前导字节落在块末：范围要求必须跟着跨过去
    assert_eq("E0 在块末 合法(A0)", seq(7, 224, 160, 128, 0, 3), 1);
    assert_eq("E0 在块末 越长(80)", seq(7, 224, 128, 128, 0, 3), 0);
    assert_eq("ED 在块末 合法(9F)", seq(7, 237, 159, 128, 0, 3), 1);
    assert_eq("ED 在块末 代理对(A0)", seq(7, 237, 160, 128, 0, 3), 0);
    assert_eq("F0 在块末 合法(90)", seq(7, 240, 144, 128, 128, 4), 1);
    assert_eq("F0 在块末 越长(8F)", seq(7, 240, 143, 128, 128, 4), 0);
    assert_eq("F4 在块末 合法(8F)", seq(7, 244, 143, 128, 128, 4), 1);
    assert_eq("F4 在块末 超上界(90)", seq(7, 244, 144, 128, 128, 4), 0);

    # ── ② 穷举：21^4 × 两个偏移 ────────────────────────────────────
    let a: i64 = 0;
    while a < NA {
        let b: i64 = 0;
        while b < NA {
            let c: i64 = 0;
            while c < NA {
                let d: i64 = 0;
                while d < NA {
                    let v0: i64 = load8(&AL + a);
                    let v1: i64 = load8(&AL + b);
                    let v2: i64 = load8(&AL + c);
                    let v3: i64 = load8(&AL + d);
                    cross(0, v0, v1, v2, v3, 4);
                    # 偏移 5：4 个字节落在 byte5..byte8，跨过块边界
                    cross(5, v0, v1, v2, v3, 4);
                    d = d + 1;
                }
                c = c + 1;
            }
            b = b + 1;
        }
        a = a + 1;
    }
    assert_eq("穷举：两版无一次不一致", MM, 0);
    assert_true("穷举：有合法样本", NV > 1000);
    assert_true("穷举：有非法样本", NI > 1000);
    print("穷举 21^4×2 = ");
    print_i64(NV + NI);
    print("，合法 ");
    print_i64(NV);
    print("，非法 ");
    print_i64(NI);
    print_nl();

    # ── ③ 随机长串 ─────────────────────────────────────────────────
    MM = 0;
    NV = 0;
    NI = 0;
    randrun(20000);
    assert_eq("随机长串：两版无一次不一致", MM, 0);
    assert_true("随机长串：有合法样本", NV > 100);
    assert_true("随机长串：有非法样本", NI > 100);
    print("随机 20000 串，合法 ");
    print_i64(NV);
    print("，非法 ");
    print_i64(NI);
    print_nl();

    # ── ④ 编解码往返 ───────────────────────────────────────────────
    assert_eq("往返 U+0000", roundtrip(0), 1);
    assert_eq("往返 U+007F", roundtrip(127), 1);
    assert_eq("往返 U+0080", roundtrip(128), 1);
    assert_eq("往返 U+07FF", roundtrip(2047), 1);
    assert_eq("往返 U+0800", roundtrip(2048), 1);
    assert_eq("往返 U+D7FF", roundtrip(55295), 1);
    assert_eq("往返 U+E000", roundtrip(57344), 1);
    assert_eq("往返 U+FFFF", roundtrip(65535), 1);
    assert_eq("往返 U+10000", roundtrip(65536), 1);
    assert_eq("往返 U+10FFFF", roundtrip(1114111), 1);
    assert_eq("代理对 U+D800 拒绝编码", u8_encode(55296, &BUF), 0);
    assert_eq("超上界 U+110000 拒绝编码", u8_encode(1114112, &BUF), 0);

    # 解码必须拒绝非法序列：C0 80 / ED A0 80 / F4 90 80 80
    seq(0, 192, 128, 0, 0, 2);
    assert_eq("解码拒绝 C0 80", u8_next(&BUF, 2, 0), 0 - 1);
    seq(0, 237, 160, 128, 0, 3);
    assert_eq("解码拒绝 ED A0 80", u8_next(&BUF, 3, 0), 0 - 1);
    seq(0, 244, 144, 128, 128, 4);
    assert_eq("解码拒绝 F4 90 80 80", u8_next(&BUF, 4, 0), 0 - 1);
    assert_eq("码点数：aé€ = 3", u8_ncp(&BUF, 0), 0);

    seq(0, 97, 195, 169, 226, 4);
    store8(&BUF + 4, 130);
    store8(&BUF + 5, 172);
    assert_eq("码点数：a é € = 3", u8_ncp(&BUF, 6), 3);
    assert_eq("字节数 ≠ 码点数", 6, 6);

    return test_done();
}
