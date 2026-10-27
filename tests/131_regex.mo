# 131 —— 正则引擎：Thompson NFA + Pike VM        # expect: 0
#
# ── 概念 ────────────────────────────────────────────────────────────
#   Ken Thompson 1968 的 NFA 构造 + Rob Pike 1998 的并行模拟（Pike VM）。
#   主流语言（Perl/PCRE/Python/Java/JS）的正则都是**回溯**，最坏情况
#   指数 —— 这就是 ReDoS。Thompson 模拟是 O(n*m)，因为同一轮里每个
#   状态只访问一次（visited 去重）。
#
# ── 最关键的一条断言 ────────────────────────────────────────────────
#   same-verdict：对同一输入，Thompson 与回溯必须给出**一致结论**。
#   没有它，"回溯步数暴涨"可能只是"回溯引擎根本是坏的"。
#
# ── 线性 vs 指数（实测，n = a 的个数，模式 (a+)+b）──────────────────
#   n      4    6    8   10   12   14   16    18     20
#   Thom  45   65   85  105  125  145  165   185    205     ← 每 +1 个 a 增 10
#   Back  62  254 1022 4094 16k  65k  262k  1048k  >4M      ← 每 +1 个 a 乘 2

import "io.mo";
import "assert.mo";
import "scat.mo";
import "regex.mo";

fn mkn(n: i64) -> str {
    let s: str = "";
    let i: i64 = 0;
    while i < n {
        s = s + "a";
        i = i + 1;
    }
    return s;
}

fn main() -> i64 {
    # ── ① 基本匹配 ──
    assert_eq("lit", re_exec("abc", "xxabcxx"), 2);
    assert_eq("lit-end", re_endpos(), 5);
    assert_eq("lit-none", re_exec("abc", "abx"), 0 - 1);
    assert_eq("star", re_exec("a*", "baaab"), 0);
    assert_eq("plus", re_exec("a+b", "aaab"), 0);
    assert_eq("plus-end", re_endpos(), 4);
    assert_eq("ques", re_exec("a?b", "b"), 0);
    assert_eq("alt", re_exec("a|b", "zzb"), 2);
    assert_eq("grp-alt", re_exec("(a|b)c", "xbc"), 1);
    assert_eq("dot", re_exec("a.c", "abc"), 0);

    # ── ② 字符类 ──
    assert_eq("cls-range", re_exec("[a-z]+", "ABcdE"), 2);
    assert_eq("cls-range-end", re_endpos(), 4);
    assert_eq("cls-neg", re_exec("[^0-9]+", "ab1cd"), 0);
    assert_eq("cls-neg-end", re_endpos(), 2);

    # ── ③ 锚点 ──
    assert_eq("bol-ok", re_exec("^abc", "abc"), 0);
    assert_eq("bol-no", re_exec("^abc", "xabc"), 0 - 1);
    assert_eq("eol-ok", re_exec("abc$", "xxabc"), 2);
    assert_eq("eol-no", re_exec("abc$", "abcx"), 0 - 1);

    # ── ④ 捕获组 ──
    re_exec("(a+)(b+)", "xxaabby");
    assert_eq("cap-start", re_endpos(), 6);
    assert_eq("cap-g0s", re_gs(0), 2);
    assert_eq("cap-g0e", re_ge(0), 4);
    assert_eq("cap-g1s", re_gs(1), 4);
    assert_eq("cap-g1e", re_ge(1), 6);

    # ── ⑤ 贪婪 ──
    re_exec("a+", "aaa");
    assert_eq("greedy", re_endpos(), 3);

    # ── ⑥ 嵌套组 ──
    re_exec("((a)(b))+", "abab");
    assert_eq("nested", re_endpos(), 4);

    # ── ⑦ 线性 vs 指数 ──
    re_exec("^(a+)+b$", mkn(8));
    let t8: i64 = re_steps();
    re_exec("^(a+)+b$", mkn(12));
    let t12: i64 = re_steps();
    re_exec("^(a+)+b$", mkn(16));
    let t16: i64 = re_steps();
    let d1: i64 = t12 - t8;
    let d2: i64 = t16 - t12;
    assert_eq("thompson-linear", d1, d2);
    assert_eq("thompson-small", t16, 165);

    rx_bt("(a+)+b", mkn(10), 4000000);
    let b10: i64 = rx_bt_steps();
    rx_bt("(a+)+b", mkn(12), 4000000);
    let b12: i64 = rx_bt_steps();
    if b12 > b10 * 3 {
        assert_eq("backtrack-exp", 1, 1);
    } else {
        assert_eq("backtrack-exp", b12, 0 - 1);
    }

    # ── ⑧ 同结论守卫（没有它，上面两条都可能是空转）──
    assert_eq("same-yes", re_exec("^(a+)+b$", mkn(4) + "b"), 0);
    assert_eq("same-yes-bt", rx_bt("(a+)+b", mkn(4) + "b", 4000000), 1);
    assert_eq("same-no", re_exec("^(a+)+b$", mkn(4)), 0 - 1);
    assert_eq("same-no-bt", rx_bt("(a+)+b", mkn(4), 4000000), 0);

    # ── ⑨ 编译错误必须报错，不是静默 ──
    assert_eq("bad-paren", re_exec("(a", "aa"), 0 - 2);

    return test_done();
}
