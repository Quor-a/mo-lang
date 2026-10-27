# 129 —— \xHH 十六进制转义   # expect: 0
#
# ── 做了什么 ────────────────────────────────────────────────────────
#   \xHH 此前**完全不支持**，而且是**静默**的：\x 后面的 'x' 不匹配
#   n/t/r/0，于是落到"原样输出"分支，输出字符 'x' 自己。
#     "\xe4\xb8\xad"  ->  "xe4xb8xad"（9 字节）
#   不报错、不崩溃，字符串只是安静地变成了另一个。
#
# ── 它是怎么被发现的 ────────────────────────────────────────────────
#   1.119 在用 \x 构造 UTF-8 用例时，测出来「中 > z」与「中 < a」
#   **同时为 0**。两个方向都假，只可能是数据本身不对 —— 否则至少
#   有一个方向会成立。这条现在是 ⑦。
#
# ── 刻意保留的对照 ──────────────────────────────────────────────────
#   ⑤ 检查 \\ \" 等"原样"分支没被这次改动波及 —— 它们靠的正是
#   "不匹配任何已知转义就输出该字符本身"这条规则。

import "io.mo";
import "assert.mo";
import "str.mo";

fn main() -> i64 {
    # ① "中" = E4 B8 AD。必须是 3 字节，而不是 9 个可见字符。
    let zh: str = "\xe4\xb8\xad";
    assert_eq("len-3", strlen(zh), 3);
    assert_eq("b0", zh[0], 228);
    assert_eq("b1", zh[1], 184);
    assert_eq("b2", zh[2], 173);

    # ② 非空转守卫：真出 bug 时第一个字节是 'x'（120）。
    #    只测"长度 == 3"还不够 —— 得确认内容真的是那三个字节。
    assert_eq("not-literal-x", zh[0] == 120, 0);

    # ③ 大小写十六进制都要认
    assert_eq("lowercase", "\xe4"[0], 228);
    assert_eq("uppercase", "\xE4"[0], 228);
    assert_eq("mixed-case", "\xAd"[0], 173);

    # ④ 与可见字符混排，且结果要能按内容判等
    assert_eq("mix-eq", "a\x62c" == "abc", 1);

    # ⑤ 原样分支不许被波及
    assert_eq("backslash", "\\"[0], 92);
    assert_eq("quote", "\""[0], 34);
    assert_eq("nl", "\n"[0], 10);
    assert_eq("tab", "\t"[0], 9);
    assert_eq("cr", "\r"[0], 13);
    assert_eq("nul", "\0"[0], 0);

    # ⑥ 字符字面量同样支持 \xHH
    assert_eq("char-A", '\x41', 65);
    assert_eq("char-z", '\x7a', 122);
    assert_eq("char-ff", '\xff', 255);
    assert_eq("char-00", '\x00', 0);

    # ⑦ 当初暴露这个缺陷的那条：字节序 == 码点序。
    #    有符号比较 / 字面量错乱都会让这两条至少挂一条。
    assert_eq("cjk-gt-z", zh > "z", 1);
    assert_eq("cjk-lt-a", zh < "a", 0);
    assert_eq("cjk-gt-a", zh > "a", 1);

    # 🔴 必须 return test_done()：写成 `test_done(); return 0;` 的话
    #    断言失败不影响退出码，测试恒为通过（projcheck 第 8 项专门盯这个）。
    return test_done();
}
