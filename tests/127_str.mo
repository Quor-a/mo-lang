# 127 —— str：字符串成为一等类型（== 按内容比较）   # expect: 0
#
# ── 做了什么 ────────────────────────────────────────────────────────
#   str 进入类型系统（kind 10）：可作局部变量、全局变量、形参、返回类型。
#   值与 ptr 完全一样（一个指向 NUL 结尾字节的地址，占一个 8 字节槽），
#   变的只是**类型标记** —— 于是 == / != 走内容比较而不是地址比较。
#
# ── 最关键的一条断言 ────────────────────────────────────────────────
#   addr-differs / lit-addr-differs：先证明两个缓冲区的地址**确实不同**。
#   没有这两条，"内容相等"有可能只是"地址相等"的巧合 —— 那样的话
#   ①②③ 三条全照样通过，而比较根本没按内容走。
#   这正是本项目反复出现的那类问题：结果照样好 ≠ 没问题。
#
# ── 刻意保留的对照 ──────────────────────────────────────────────────
#   ptr-addr-cmp：ptr 仍然按**地址**比较。改动不能悄悄把旧语义改掉。

import "io.mo";
import "assert.mo";

fn first(s: str) -> i64 { return s[0]; }
fn ident(s: str) -> str { return s; }

fn main() -> i64 {
    # ── ① 字面量之间 ──
    assert_eq("lit-eq", "abc" == "abc", 1);
    assert_eq("lit-ne", "abc" == "abd", 0);

    # ── ② 运行期构造的缓冲区 与 字面量 ──
    let x: [16] byte = 0;
    x[0] = 104; x[1] = 101; x[2] = 108; x[3] = 108; x[4] = 111;
    let p: str = &x;
    assert_eq("buf-vs-lit", p == "hello", 1);

    # ── ③ 两个独立缓冲区、内容相同 ──
    let y: [16] byte = 0;
    y[0] = 104; y[1] = 101; y[2] = 108; y[3] = 108; y[4] = 111;
    let q: str = &y;
    assert_eq("buf-vs-buf", p == q, 1);
    assert_eq("buf-ne", p != q, 0);

    # ── ④ 非空转守卫：地址确实不同 ──
    let ap: i64 = &x;
    let aq: i64 = &y;
    assert_true("addr-differs", ap != aq);
    let lit: str = "hello";
    let al: i64 = lit;
    assert_true("lit-addr-differs", ap != al);

    # ── ⑤ 改一个字节就不等 ──
    y[0] = 106;
    assert_eq("after-mut", p == q, 0);
    assert_eq("after-mut-ne", p != q, 1);

    # ── ⑥ 长度不同：前缀不算相等；空串 ──
    assert_eq("prefix", p == "hell", 0);
    let e: [16] byte = 0;
    let pe: str = &e;
    assert_eq("empty-vs-empty", pe == "", 1);
    assert_eq("empty-vs-a", pe == "a", 0);

    # ── ⑦ 下标按字节步进 ──
    assert_eq("idx0", p[0], 104);
    assert_eq("lit-idx", "hello"[1], 101);

    # ── ⑧ str 作形参与返回类型 ──
    assert_eq("param", first(p), 104);
    assert_eq("ret", ident(p) == "hello", 1);

    # ── ⑨ ptr 仍是地址比较（不许被悄悄改掉）──
    let r: ptr = &x;
    let s2: ptr = "hello";
    assert_eq("ptr-addr-cmp", r == s2, 0);

    # 🔴 必须 return test_done()：写成 `test_done(); return 0;` 的话
    #    断言失败不影响退出码，测试恒为通过（projcheck 第 8 项专门盯这个）。
    return test_done();
}
