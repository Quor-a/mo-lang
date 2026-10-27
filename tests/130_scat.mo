# 130 —— str 的 '+'：带生命周期的拼接（region）   # expect: 0
#
# ── 做了什么 ────────────────────────────────────────────────────────
#   str 支持 '+'：a + b 返回**新分配**的串，两个入参都不改动。
#   分配出来的东西归 region（lib/scat.mo）所有：不单独 free，
#   整批一起丢弃（scat_reset），且丢弃后内存**保留复用**。
#
# ── 最关键的两条断言 ────────────────────────────────────────────────
#   copy-100 / copy-200：复制字节数精确等于 n(n+1)/2。
#   这不是"跑通就行"，是把朴素拼接的 O(n^2) **量成数字** ——
#   n 翻倍、复制量 4 倍，这条曲线才是本特性的全部意义。
#
#   reuse-mov / reuse-cap：reset 之后再拼同样多，
#   brk 次数与容量都**不变**。只测 used==0 证明不了复用 ——
#   一个"reset 时把内存还给内核、下次重新申请"的实现同样能让
#   used 归零，但那不是复用。
#
# ── 刻意保留的对照 ──────────────────────────────────────────────────
#   indep-*：两次拼接的结果互不覆盖。若实现返回同一个静态缓冲，
#   第二次会把第一次的内容冲掉，而这些断言会立刻变红。

import "io.mo";
import "assert.mo";
import "scat.mo";

fn main() -> i64 {
    # ── ① 基本拼接：内容正确 ──
    let a: str = "abc";
    let b: str = "def";
    let c: str = a + b;
    assert_eq("cat-len", scat_len(c), 6);
    assert_eq("cat-b0", c[0], 97);
    assert_eq("cat-b1", c[1], 98);
    assert_eq("cat-b2", c[2], 99);
    assert_eq("cat-b3", c[3], 100);
    assert_eq("cat-b4", c[4], 101);
    assert_eq("cat-b5", c[5], 102);
    assert_eq("cat-nul", c[6], 0);

    # ── ② 链式：结果类型仍是 str，可以继续拼 ──
    let d: str = a + b + "ghi";
    assert_eq("chain-len", scat_len(d), 9);
    assert_eq("chain-eq", d == "abcdefghi", 1);

    # ── ③ 入参不被改动（转成 strcat 就地追加会破坏 a）──
    assert_eq("a-intact-len", scat_len(a), 3);
    assert_eq("a-intact-val", a == "abc", 1);
    assert_eq("b-intact-len", scat_len(b), 3);
    assert_eq("b-intact-val", b == "def", 1);

    # ── ④ 空串两侧 ──
    let e1: str = "" + "x";
    assert_eq("empty-l", scat_len(e1), 1);
    assert_eq("empty-l-v", e1[0], 120);
    let e2: str = "x" + "";
    assert_eq("empty-r", scat_len(e2), 1);
    assert_eq("empty-r-v", e2[0], 120);

    # ── ⑤ 结果独立：第二次拼接不能覆盖第一次 ──
    let p1: str = "aa" + "bb";
    let p2: str = "cc" + "dd";
    assert_eq("indep-p1", p1 == "aabb", 1);
    assert_eq("indep-p2", p2 == "ccdd", 1);
    assert_eq("indep-ne", p1 == p2, 0);

    # ── ⑥ O(n^2)：复制量精确等于 n(n+1)/2 ──
    scat_reset();
    let c0: i64 = scat_copy();
    let s: str = "";
    let i: i64 = 0;
    while i < 100 {
        s = s + "x";
        i = i + 1;
    }
    let c100: i64 = scat_copy() - c0;
    assert_eq("copy-100", c100, 5050);
    assert_eq("len-100", scat_len(s), 100);
    assert_eq("last-byte", s[99], 120);

    scat_reset();
    let c1: i64 = scat_copy();
    s = "";
    i = 0;
    while i < 200 {
        s = s + "x";
        i = i + 1;
    }
    let c200: i64 = scat_copy() - c1;
    assert_eq("copy-200", c200, 20100);
    assert_eq("len-200", scat_len(s), 200);

    # n 翻倍 → 复制量约 4 倍（二次增长，不是线性）
    assert_true("quadratic", c200 > c100 * 3);
    # 反过来：若是线性的，c200 只会是 c100 的 2 倍
    assert_true("not-linear", c200 > c100 * 2 + 1000);

    # ── ⑦ region：整批丢弃 + 内存复用 ──
    let cap0: i64 = scat_cap();
    let m0: i64 = scat_mov();
    assert_true("cap-pos", cap0 > 0);
    assert_true("mov-pos", m0 > 0);

    scat_reset();
    assert_eq("reset-used", scat_used(), 0);
    assert_eq("reset-n", scat_n(), 0);
    assert_eq("reuse-cap", scat_cap(), cap0);

    # reset 之后再做同样多的拼接：不应该再向内核要内存
    let c2: i64 = scat_copy();
    s = "";
    i = 0;
    while i < 200 {
        s = s + "x";
        i = i + 1;
    }
    assert_eq("reuse-copy", scat_copy() - c2, 20100);
    assert_eq("reuse-mov", scat_mov(), m0);
    assert_eq("reuse-cap2", scat_cap(), cap0);
    assert_eq("reuse-len", scat_len(s), 200);

    # ── ⑧ '+=' 必须是拼接 ──
    #    走地址相加的话，"ab" 的地址加上 "cd" 的地址会落到未映射内存，
    #    实测直接段错误（exit 139）；落到已映射内存则**静默**给出偏移后的串。
    let t: str = "ab";
    t += "cd";
    assert_eq("pluseq-len", scat_len(t), 4);
    assert_eq("pluseq-val", t == "abcd", 1);
    t += "";
    assert_eq("pluseq-empty", scat_len(t), 4);

    assert_eq("no-err", scat_err(), 0);

    # 🔴 必须 return test_done()：写成 `test_done(); return 0;` 的话
    #    断言失败不影响退出码，测试恒为通过（projcheck 第 8 项专门盯这个）。
    return test_done();
}
