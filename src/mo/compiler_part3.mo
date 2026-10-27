
# ==========================================================================
#  词法分析
# ==========================================================================
# 读取「当前文件」的第 i 个字节（支持 import 多文件）
fn sbyte(i: i64) -> i64 {
    return load8(heap + gv(K_SRCBASE) + i);
}

fn is_alpha(c: i64) -> i64 {
    if c >= 97 {
        if c <= 122 { return 1; }
    }
    if c >= 65 {
        if c <= 90 { return 1; }
    }
    return 0;
}

fn is_digit(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return 1; }
    }
    return 0;
}

fn is_alnum(c: i64) -> i64 {
    if is_alpha(c) == 1 { return 1; }
    if is_digit(c) == 1 { return 1; }
    if c == 95 { return 1; }
    return 0;
}

fn hexval(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return c - 48; }
    }
    if c >= 97 {
        if c <= 102 { return c - 87; }
    }
    if c >= 65 {
        if c <= 70 { return c - 55; }
    }
    return -1;
}

# 跳过空白与 '#' 注释，返回下一个有效字符位置
fn skip_comment(p: i64) -> i64 {
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        if sbyte(p) == 10 { return p + 1; }
        p = p + 1;
    }
    return p;
}

fn skip_ws() -> i64 {
    let p: i64 = gv(K_POS);
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        let c: i64 = sbyte(p);
        if c == 35 {
            p = skip_comment(p);
        } else {
            if c == 32 { p = p + 1; }
            else {
                if c == 9 { p = p + 1; }
                else {
                    if c == 10 { p = p + 1; }
                    else {
                        if c == 13 { p = p + 1; }
                        else { return p; }
                    }
                }
            }
        }
    }
    return p;
}

fn tokbuf() -> i64 {
    return heap + O_SCAL + K_TOKBUF;
}

fn lex_ident(p: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = tokbuf();
    while is_alnum(sbyte(p + i)) == 1 {
        store8(b + i, sbyte(p + i));
        i = i + 1;
    }
    store8(b + i, 0);
    sv(K_POS, p + i);
    sv(K_TKIND, 1);
    return 0;
}

fn lex_hex(p: i64) -> i64 {
    let v: i64 = 0;
    let h: i64 = hexval(sbyte(p));
    while h >= 0 {
        v = v * 16 + h;
        p = p + 1;
        h = hexval(sbyte(p));
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

fn lex_number(p: i64) -> i64 {
    # 🔴 这四个状态必须在**任何**返回路径之前清零 —— 包括 0x.. 的十六进制。
    #
    # 原先 `0x...` 走 lex_hex 提前 return，而清零写在函数后半段，
    # 于是十六进制字面量**保留上一个 token 的 K_TFLT**。
    # 后果：紧跟在浮点字面量后面的十六进制字面量被当成浮点解析，
    # 而且用的是**上一个字面量的数字**（K_TFDIG/K_TFDIGN 同样是残留值）：
    #
    #   assert_eq("vs-any", fbits(0.5), 0x1111111111111111)
    #                                   ^ 被解析成 0.5 的位模式
    #
    # 于是 want == got，**断言恒真**。tests/127 那 23 条浮点断言就是这样
    # 整批空转的 —— 而且它骗过了 1.115 的变异验证（改坏词法器，断言照样绿）。
    # 这类"看起来通过、实际什么都没验"正是本项目最该防的模式。
    sv(K_TFLT, 0);
    sv(K_TFDIG, 0);
    sv(K_TFDIGN, 0);
    FSTICKY = 0;
    if sbyte(p) == 48 {
        if sbyte(p + 1) == 120 { return lex_hex(p + 2); }
        if sbyte(p + 1) == 88 { return lex_hex(p + 2); }
    }
    # 整数部分：**不能截断位数**。
    #
    # 🔴 这里踩过一次：第一版给整数部分也加了 18 位上限，
    #   结果 `9223372036854775807`（19 位，i64::MAX）被读成 922337203685477580。
    #   自举立刻报不一致 —— 因为汇编 seed 的词法器是另一套实现，没跟着截。
    #   而 `0 - 9223372036854775807 - 1` 正是墨语言写 i64::MIN 的惯用法，
    #   这个改动会静默改掉全语言的整数下限。
    # 限度只在**浮点**字面量的分子上（N = v*10^k + fd 必须 < 10^18）。
    let v: i64 = 0;
    let idn: i64 = 0;
    let seen: i64 = 0;
    let dc: i64 = 0;
    while is_digit(sbyte(p)) == 1 {
        dc = sbyte(p) - 48;
        v = v * 10 + dc;
        if dc != 0 { seen = 1; }
        if seen == 1 { idn = idn + 1; }
        p = p + 1;
    }
    # 浮点字面量：整数部分后紧跟 '.' 且 '.' 后是数字。
    #
    # ⚠️ 必须同时判断'.'后是数字：`obj.field` 里 `.` 后面是标识符，
    #    只判断 '.' 会把 `r.w` 的 `r` 当成浮点数开头，把 `.w` 吞掉。
    #    这个 bug 会表现为"方法调用莫名其妙报语法错误"。
    #
    # 给 f64_bits 的接口：K_TFDIG = 分子 N，K_TFDIGN = 十进制指数 k，即 值 = N / 10^k。
    sv(K_TFLT, 0);
    sv(K_TFDIG, 0);
    sv(K_TFDIGN, 0);
    FSTICKY = 0;
    if sbyte(p) == 46 {
        if is_digit(sbyte(p + 1)) == 1 {
            p = p + 1;
            # 前导零不占有效位预算，但要计入十进制指数
            let z: i64 = 0;
            while sbyte(p) == 48 { z = z + 1; p = p + 1; }
            let fd: i64 = 0;
            let fdn: i64 = 0;
            # 有效数字预算：整数 + 小数合计 18 位（N 必须 < 10^18）。
            # 十进制指数 k 的上限：v>0 时 N=v*10^k+fd 决定 k <= 18-idn；
            # v==0 时 N=fd，只受「归一化倍增会不会溢出」限制（见 f64_bits）：
            # 需要 2*5^k < 2^63，即 5^k < 4.61e18 —— 5^26=1.49e18 ✓，5^27=7.45e18 ✗。
            # 于是 k 上限取 26，可表示范围从 1e-18 扩大到 1e-26。
            let sig: i64 = 18 - idn;
            let kmax: i64 = sig;
            if v == 0 { kmax = 26; }
            let budget: i64 = 0;
            let k: i64 = 0;
            if z >= kmax {
                # 全部小数位都在可表示范围之外
                while is_digit(sbyte(p)) == 1 {
                    if sbyte(p) != 48 { FSTICKY = 1; }
                    p = p + 1;
                }
            } else {
                budget = sig;
                if kmax - z < budget { budget = kmax - z; }
                while is_digit(sbyte(p)) == 1 {
                    if fdn < budget {
                        fd = fd * 10 + (sbyte(p) - 48);
                        fdn = fdn + 1;
                    } else {
                        if sbyte(p) != 48 { FSTICKY = 1; }
                    }
                    p = p + 1;
                }
                k = z + fdn;
            }
            let N: i64 = fd;
            if v != 0 { N = v * pow10i(k) + fd; }
            sv(K_TFLT, 1);
            sv(K_TFDIG, N);
            sv(K_TFDIGN, k);
        }
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

# 转义序列：p 指向反斜杠，返回字节值，结束位置写入 K_ESCP。
#
# 🔴 \xHH 此前**完全不支持**，而且是静默的：
#    \x 后面的 'x' 不匹配 n/t/r/0，于是落到"原样输出"分支，
#    输出字符 'x' 自己。所以 "\xe4\xb8\xad" 会安静地变成 "xe4xb8xad"
#    —— 不报错、不崩溃，字符串只是变成了另一个。
#    本轮（1.120）就是在用 \x 构造 UTF-8 用例时发现它的：
#    测出来「中 > z」与「中 < a」同时为 0，两个方向都假，
#    只可能是数据本身不对。
#
# 位数不足的 \x 必须报错，不能悄悄给个值 —— 静默是这个项目
# 反复出现的最危险模式。
fn lex_esc(p: i64) -> i64 {
    let c: i64 = sbyte(p + 1);
    if c == 110 { sv(K_ESCP, p + 2); return 10; }   # \n
    if c == 116 { sv(K_ESCP, p + 2); return 9;  }   # \t
    if c == 114 { sv(K_ESCP, p + 2); return 13; }   # \r
    if c == 48  { sv(K_ESCP, p + 2); return 0;  }   # \0
    if c == 120 {                                    # \xHH
        let hi: i64 = hexval(sbyte(p + 2));
        if hi < 0 { return die("error: bad \\x escape\n"); }
        let lo: i64 = hexval(sbyte(p + 3));
        if lo < 0 { return die("error: bad \\x escape\n"); }
        sv(K_ESCP, p + 4);
        return hi * 16 + lo;
    }
    sv(K_ESCP, p + 2);
    return c;                                        # \\ \" \' 等原样
}

# 字符串字面量：内容写入输出数据段（供生成的程序用），
# 同时拷贝一份到编译器侧字符串池 O_STRS（供编译器自身读取）
fn lex_string(p: i64) -> i64 {
    p = p + 1;
    let addr: i64 = 268435456 + gv(K_DLEN);
    let so: i64 = gv(K_NSTR);
    sv(K_STROFF, so);
    while sbyte(p) != 34 {
        let c: i64 = sbyte(p);
        if c == 92 {
            c = lex_esc(p);
            p = gv(K_ESCP);
        } else {
            p = p + 1;
        }
        dbyte(c);
        store8(heap + O_STRS + so, c);
        so = so + 1;
    }
    p = p + 1;
    dbyte(0);
    store8(heap + O_STRS + so, 0);
    so = so + 1;
    sv(K_NSTR, so);
    sv(K_POS, p);
    sv(K_TKIND, 3);
    sv(K_TIVAL, addr);
    store8(tokbuf(), 0);
    return 0;
}

# f-string 的一个字面片段，例如 f"共 {n} 篇" 里的 "共 " 和 " 篇"。
#
# p 指向开引号。
#   - 遇到 '{'：**提前结束**本片段，且不消费 '{'（让它成为下一个 token）
#   - 遇到 '"' ：正常结束，并把 K_FMODE 清零（f-string 到此为止）
#
# 结束状态记在 K_FEND 里，解析器靠它决定下一步。
fn lex_fstring() -> i64 {
    #
    # 从 **K_FPOS** 读，不从参数读。
    #
    # 因为 f"A{n}B\n" 里片段之间**没有引号** —— 整个 f-string 只有
    # 开头一个 f" 和结尾一个 "。第一版我让 next_token 每次从开引号读，
    # 结果 '}' 之后 p 指向的是片段内容 'B'，被当成引号跳掉，
    # 于是每个后续片段都**丢掉第一个字符**（"B\n" 变成 "\n"）。
    let p: i64 = gv(K_FPOS);
    let addr: i64 = 268435456 + gv(K_DLEN);
    let so: i64 = gv(K_NSTR);
    sv(K_STROFF, so);
    sv(K_FEND, 0);
    let done: i64 = 0;
    while done == 0 {
        let c: i64 = sbyte(p);
        if c == 34 { done = 1; }
        else {
            if c == 123 {
                done = 1;
                sv(K_FEND, 1);
                sv(K_FMODE, 2);      # 进入 { 表达式 } 内部，按普通 token 走
            } else {
                if c == 92 {
                    c = lex_esc(p);
                    p = gv(K_ESCP);
                } else {
                    p = p + 1;
                }
                dbyte(c);
                store8(heap + O_STRS + so, c);
                so = so + 1;
            }
        }
    }
    # '{' 结束时 p 正指向 '{'，留给下一个 token；'"' 结束时吃掉引号并退出 f 模式
    if gv(K_FEND) == 0 {
        p = p + 1;
        sv(K_FMODE, 0);
    }
    dbyte(0);
    store8(heap + O_STRS + so, 0);
    so = so + 1;
    sv(K_NSTR, so);
    sv(K_FPOS, p);
    sv(K_POS, p);
    sv(K_TKIND, 5);
    sv(K_TIVAL, addr);
    store8(tokbuf(), 0);
    return 0;
}

# 当前字符串字面量在编译器侧的可读地址
fn strpool() -> i64 {
    return heap + O_STRS + gv(K_STROFF);
}

fn set_tok(a: i64, b: i64, adv: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, 0);
    sv(K_POS, p + adv);
    sv(K_TKIND, 4);
    return 0;
}

# 三字符 token（<<= >>=）。与 set_tok 同构，只是多写一个字节、多吃一个字符。
fn set_tok3(a: i64, b: i64, c: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, c);
    store8(t + 3, 0);
    sv(K_POS, p + 3);
    sv(K_TKIND, 4);
    return 0;
}

fn lex_punct(p: i64) -> i64 {
    let c: i64 = sbyte(p);
    let d: i64 = sbyte(p + 1);
    if c == 61 {
        if d == 61 { return set_tok(61, 61, 2, p); }
    }
    # 复合赋值：+= -= *= /= %= &= |= ^=
    # 必须比单字符更早匹配，否则 '+=' 会被当成 '+' 再跟一个 '='
    if c == 43 {
        if d == 61 { return set_tok(43, 61, 2, p); }
        if d == 43 { return set_tok(43, 43, 2, p); }
    }
    if c == 42 {
        if d == 61 { return set_tok(42, 61, 2, p); }
    }
    if c == 47 {
        if d == 61 { return set_tok(47, 61, 2, p); }
    }
    if c == 37 {
        if d == 61 { return set_tok(37, 61, 2, p); }
    }
    if c == 94 {
        if d == 61 { return set_tok(94, 61, 2, p); }
    }
    if c == 33 {
        if d == 61 { return set_tok(33, 61, 2, p); }
    }
    if c == 60 {
        # 三字符必须先试：'<' '<' '=' 若按两字符匹配会切成 "<<" + "="
        if d == 60 {
            if sbyte(p + 2) == 61 { return set_tok3(60, 60, 61, p); }
            return set_tok(60, 60, 2, p);
        }
        if d == 61 { return set_tok(60, 61, 2, p); }
    }
    if c == 62 {
        if d == 62 {
            if sbyte(p + 2) == 61 { return set_tok3(62, 62, 61, p); }
            return set_tok(62, 62, 2, p);
        }
        if d == 61 { return set_tok(62, 61, 2, p); }
    }
    if c == 38 {
        if d == 38 { return set_tok(38, 38, 2, p); }
        if d == 61 { return set_tok(38, 61, 2, p); }
    }
    if c == 124 {
        if d == 124 { return set_tok(124, 124, 2, p); }
        if d == 61 { return set_tok(124, 61, 2, p); }
    }
    if c == 45 {
        if d == 62 { return set_tok(45, 62, 2, p); }
        if d == 61 { return set_tok(45, 61, 2, p); }
        if d == 45 { return set_tok(45, 45, 2, p); }
    }
    return set_tok(c, 0, 1, p);
}

# 字符字面量 'a' / '\n' / '\\' / '\'' —— 值就是一个整数
fn lex_char(p: i64) -> i64 {
    p = p + 1;
    let c: i64 = sbyte(p);
    if c == 92 {
        c = lex_esc(p);
        p = gv(K_ESCP);
    } else {
        p = p + 1;
    }
    # 允许但不强制闭合引号：吃掉它（存在就吃）
    if sbyte(p) == 39 { p = p + 1; }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, c);
    store8(tokbuf(), 0);
    return 0;
}

fn next_token() -> i64 {
    let p: i64 = skip_ws();
    sv(K_PLINE, gv(K_LINE));
    sv(K_PCOL, gv(K_COL));
    sv(K_PPOS, gv(K_TOKPOS));
    advance_lc(p);
    sv(K_POS, p);
    sv(K_TOKPOS, p);
    if p >= gv(K_SRCLEN) {
        sv(K_TKIND, 0);
        return 0;
    }
    let c: i64 = sbyte(p);
    # f-string 未结束时，下一个 token 一定是片段（以引号开头）。
    # 不能走普通 lex：'}' 之后紧跟的是片段内容而不是 '}'，
    # 普通 lex 会把它识别成标识符（第一版就是这么错的）。
    if gv(K_FMODE) == 1 { return lex_fstring(); }
    # 'f' 后面紧跟引号才是插值字符串；单独的 f 仍然是普通标识符
    if c == 102 {
        if sbyte(p + 1) == 34 {
            sv(K_FMODE, 1);
            sv(K_FPOS, p + 2);
            return lex_fstring();
        }
    }
    if is_alpha(c) == 1 { return lex_ident(p); }
    if c == 95 { return lex_ident(p); }
    if is_digit(c) == 1 { return lex_number(p); }
    if c == 34 { return lex_string(p); }
    if c == 39 { return lex_char(p); }
    return lex_punct(p);
}

fn set_pos(p: i64) -> i64 {
    sv(K_POS, p);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    next_token();
    return 0;
}

fn tok_is(s: i64) -> i64 {
    if gv(K_TKIND) == 0 { return 0; }
    return streq(tokbuf(), s);
}

fn expect(s: i64) -> i64 {
    if tok_is(s) == 0 { return syntax_error(); }
    next_token();
    return 0;
}

fn accept(s: i64) -> i64 {
    if tok_is(s) == 0 { return 0; }
    next_token();
    return 1;
}
