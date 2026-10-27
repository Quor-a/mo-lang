# 145 —— Unicode 字符分类与大小写转换                        # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   Unicode General Category（UAX #44）；大小写映射取自 UnicodeData.txt
#   的 Simple_Uppercase / Simple_Lowercase。C/C++ 的 <ctype.h> 只有 ASCII
#   且受 locale 支配；Java / Go / Rust / Python 的字符分类依赖运行时自带的
#   完整表且不可裁剪。本实现是 **可裁剪的纯数据表 + 二分查找**。
#
# ── 本测试钉住的**定量**结论 ────────────────────────────────
#   ① 覆盖段内 23440 个码点全部命中（区间表无缝隙、无重叠、无错位）
#   ② 粗类别计数逐项精确：Lu 461 / Ll 547 / Lo 21110 / Nd 20 / Sm 330 /
#      Zs 18 / Cc 65 / Cn 69 —— 任一项错位都会让这些数字变
#   ③ **简单大小写映射不是对合**：lower(upper(c)) == lower(c) 在覆盖段内
#      有 **12 个反例**，upper(lower(c)) == upper(c) 有 **4 个反例**。
#      这是 Unicode 的真实性质（如 U+03C2 ς → Σ → σ ≠ ς），不是实现缺陷。
#      断言的是反例的**精确个数**，而不是"应该为 0"。
#   ④ 特殊「一码点变多码点」映射共 6 个（U+00DF ß、U+0130 İ、U+0149 ŉ、
#      U+01F0 ǰ、U+0390 ΐ、U+03B0 ΰ），命中时置 UNI_SPEC 并返回原码点。
#   ⑤ 覆盖范围之外（如 U+0500、U+1F600 emoji）返回 -1 并置 UNI_UNK，
#      **不**静默给出一个像样的答案。

import "assert.mo";
import "uni.mo";

fn count_cat(want: i64) -> i64 {
    let s: i64  = 0;
    let n: i64  = 0;
    while s < 12 {
        let cp: i64  = UNI_SEG[s];
        let j: i64  = s + 1;
        let hi: i64  = UNI_SEG[j];
        while cp < hi {
            if uni_cat(cp) == want { n = n + 1; }
            cp = cp + 1;
        }
        s = s + 2;
    }
    return n;
}

# 覆盖段内 uni_cat 返回非 -1 的码点总数
fn count_covered() -> i64 {
    let s: i64  = 0;
    let n: i64  = 0;
    while s < 12 {
        let cp: i64  = UNI_SEG[s];
        let j: i64  = s + 1;
        let hi: i64  = UNI_SEG[j];
        while cp < hi {
            if uni_cat(cp) >= 0 { n = n + 1; }
            cp = cp + 1;
        }
        s = s + 2;
    }
    return n;
}

# lower(upper(c)) != lower(c) 的反例数
fn count_rt1() -> i64 {
    let s: i64  = 0;
    let n: i64  = 0;
    while s < 12 {
        let cp: i64  = UNI_SEG[s];
        let j: i64  = s + 1;
        let hi: i64  = UNI_SEG[j];
        while cp < hi {
            let u: i64  = uni_upper(cp);
            let ku: i64 = UNI_SPEC;
            let mu: i64 = UNI_UNK;
            if ku == 0 {
                if mu == 0 {
                    let a: i64  = uni_lower(u);
                    let k1: i64 = UNI_SPEC;
                    let m1: i64 = UNI_UNK;
                    let b: i64  = uni_lower(cp);
                    let k2: i64 = UNI_SPEC;
                    let m2: i64 = UNI_UNK;
                    if k1 == 0 {
                        if k2 == 0 {
                            if m1 == 0 {
                                if m2 == 0 {
                                    if a != b { n = n + 1; }
                                }
                            }
                        }
                    }
                }
            }
            cp = cp + 1;
        }
        s = s + 2;
    }
    return n;
}

# upper(lower(c)) != upper(c) 的反例数
fn count_rt2() -> i64 {
    let s: i64  = 0;
    let n: i64  = 0;
    while s < 12 {
        let cp: i64  = UNI_SEG[s];
        let j: i64  = s + 1;
        let hi: i64  = UNI_SEG[j];
        while cp < hi {
            let l: i64  = uni_lower(cp);
            let kl: i64 = UNI_SPEC;
            let ml: i64 = UNI_UNK;
            if kl == 0 {
                if ml == 0 {
                    let a: i64  = uni_upper(l);
                    let k1: i64 = UNI_SPEC;
                    let m1: i64 = UNI_UNK;
                    let b: i64  = uni_upper(cp);
                    let k2: i64 = UNI_SPEC;
                    let m2: i64 = UNI_UNK;
                    if k1 == 0 {
                        if k2 == 0 {
                            if m1 == 0 {
                                if m2 == 0 {
                                    if a != b { n = n + 1; }
                                }
                            }
                        }
                    }
                }
            }
            cp = cp + 1;
        }
        s = s + 2;
    }
    return n;
}

# 命中特殊多字符映射的码点数
fn count_spec() -> i64 {
    let s: i64  = 0;
    let n: i64  = 0;
    while s < 12 {
        let cp: i64  = UNI_SEG[s];
        let j: i64  = s + 1;
        let hi: i64  = UNI_SEG[j];
        while cp < hi {
            let u: i64  = uni_upper(cp);
            if UNI_SPEC == 1 { n = n + 1; }
            let l: i64  = uni_lower(cp);
            if UNI_SPEC == 1 { n = n + 1; }
            cp = cp + 1;
        }
        s = s + 2;
    }
    return n;
}

fn main() -> i64 {
    uni_init();

    # ── ① ASCII 分类：粗类别编号 ──────────────────────────────
    assert_eq("A is Lu", uni_cat(65), 1);
    assert_eq("a is Ll", uni_cat(97), 2);
    assert_eq("0 is Nd", uni_cat(48), 7);
    assert_eq("space is Zs", uni_cat(32), 18);
    assert_eq("dot is Po", uni_cat(46), 13);
    assert_eq("dash is Pd", uni_cat(45), 10);
    assert_eq("under is Pc", uni_cat(95), 9);
    assert_eq("lparen is Ps", uni_cat(40), 11);
    assert_eq("rparen is Pe", uni_cat(41), 12);
    assert_eq("plus is Sm", uni_cat(43), 14);
    assert_eq("dollar is Sc", uni_cat(36), 15);
    assert_eq("caret is Sk", uni_cat(94), 16);
    assert_eq("tab is Cc", uni_cat(9), 19);
    assert_eq("NUL is Cc", uni_cat(0), 19);

    # ── ② 谓词 ────────────────────────────────────────────────
    assert_eq("isupper A", uni_isupper(65), 1);
    assert_eq("islower a", uni_islower(97), 1);
    assert_eq("isalpha A", uni_isalpha(65), 1);
    assert_eq("isalpha 0", uni_isalpha(48), 0);
    assert_eq("isdigit 0", uni_isdigit(48), 1);
    assert_eq("isdigit 中", uni_isdigit(20013), 0);
    assert_eq("isalnum a", uni_isalnum(97), 1);
    assert_eq("isspace tab", uni_isspace(9), 1);
    assert_eq("isspace A", uni_isspace(65), 0);
    assert_eq("ispunct dot", uni_ispunct(46), 1);
    assert_eq("issymbol plus", uni_issymbol(43), 1);
    assert_eq("iscntrl tab", uni_iscntrl(9), 1);
    assert_eq("isprint A", uni_isprint(65), 1);
    assert_eq("isprint tab", uni_isprint(9), 0);
    assert_eq("isdigit 全角1", uni_isdigit(65297), 1);   # U+FF11 FULLWIDTH ONE

    # ── ③ 大小写：ASCII 与 Latin-1 ────────────────────────────
    assert_eq("upper a", uni_upper(97), 65);
    assert_eq("lower A", uni_lower(65), 97);
    assert_eq("upper z", uni_upper(122), 90);
    assert_eq("lower Z", uni_lower(90), 122);
    assert_eq("upper 0 不变", uni_upper(48), 48);
    assert_eq("upper e-acute", uni_upper(233), 201);      # é → É
    assert_eq("lower E-acute", uni_lower(201), 233);
    assert_eq("upper sharp-s 特殊", uni_upper(223), 223); # ß 需多字符
    assert_eq("sharp-s 置 SPEC", UNI_SPEC, 1);
    assert_eq("upper 中 不变", uni_upper(20013), 20013);

    # ── ④ 非拉丁：希腊、西里尔 ────────────────────────────────
    assert_eq("upper alpha", uni_upper(945), 913);        # α → Α
    assert_eq("upper final-sigma", uni_upper(962), 931);  # ς → Σ
    assert_eq("lower Sigma", uni_lower(931), 963);        # Σ → σ（不是 ς！）
    assert_eq("lower Cyrillic De", uni_lower(1044), 1076);# Д → д

    # ── ⑤ title：Lt 保持自身，其余取 upper ────────────────────
    assert_eq("title a", uni_title(97), 65);
    assert_eq("title U+01C5 保持", uni_title(453), 453);  # ǅ 是 Lt

    # ── ⑥ 覆盖范围之外必须显式报错 ────────────────────────────
    assert_eq("cat U+0500 未覆盖", uni_cat(1280), 0 - 1);
    assert_eq("未覆盖置 UNK", UNI_UNK, 1);
    assert_eq("upper emoji 未覆盖", uni_upper(128512), 0 - 1);
    assert_eq("emoji 置 UNK", UNI_UNK, 1);
    assert_eq("cat 负数", uni_cat(0 - 1), 0 - 1);

    # ── ⑥b 区间末端：右边界写成开区间会让末端码点**死循环** ────
    #    二分里 cp == hi 时既不走 lo=mid+1 也不 return，lo/hi 都不变。
    #    这不是静默错误而是挂住，但只在区间末端触发 —— 抽查中间值永远
    #    碰不到，所以这里逐个把每段末端钉死。
    assert_eq("Cc 区间末端 U+001F", uni_cat(31), 19);
    assert_eq("单点区间 U+0020", uni_cat(32), 18);
    assert_eq("Cc 区间末端 U+007F", uni_cat(127), 19);
    assert_eq("第一段末端 U+04FF", uni_cat(1279), 2);
    assert_eq("U+04FF 大写", uni_upper(1279), 1278);
    assert_eq("CJK 段末端 U+9FFF 未分配", uni_cat(40959), 0);
    assert_eq("末段末端 U+FFEF 未分配", uni_cat(65519), 0);
    assert_eq("U+2300 段外", uni_cat(8960), 0 - 1);

    # ── ⑦ 全扫描：覆盖完整性与类别计数 ────────────────────────
    assert_eq("覆盖码点总数", count_covered(), 23440);
    assert_eq("Lu 计数", count_cat(1), 461);
    assert_eq("Ll 计数", count_cat(2), 547);
    assert_eq("Lo 计数", count_cat(5), 21110);
    assert_eq("Nd 计数", count_cat(7), 20);
    assert_eq("Nl/No 计数", count_cat(8), 92);
    assert_eq("Sm 计数", count_cat(14), 330);
    assert_eq("Zs/Zl/Zp 计数", count_cat(18), 18);
    assert_eq("Cc 计数", count_cat(19), 65);
    assert_eq("Cn 计数", count_cat(0), 69);
    assert_eq("Mn/Mc/Me 计数", count_cat(6), 158);
    assert_eq("Pc 计数", count_cat(9), 5);

    # ── ⑧ 往返不是恒等式，反例个数必须精确 ────────────────────
    assert_eq("lower(upper) 反例数", count_rt1(), 12);
    assert_eq("upper(lower) 反例数", count_rt2(), 4);
    assert_eq("特殊多字符映射数", count_spec(), 6);

    print("  covered=");
    print_i64(count_covered());
    print(" Lu/Ll/Lo=");
    print_i64(count_cat(1));
    print_i64(count_cat(2));
    print_i64(count_cat(5));
    print_nl();

    return test_done();
}
