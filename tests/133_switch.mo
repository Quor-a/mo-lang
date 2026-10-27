# 133 —— switch
#
# 判据全是具体数值，不是"能不能编译/会不会崩"：
#   - 跳转表模式下若槽位填错（比如全部指向 default），命中任何 case
#     都会得到 default 的结果，而**不会崩** —— 只有具体数字能区分。
#   - continue 若在 switch 里错误地跳到 switch 出口，外层 for 会少跑
#     若干轮，和值会偏小但程序正常退出，同样只有数字能抓住。
#
# 与 C 的两处刻意差异（理由见 docs/switch.md）：
#   · case 不穿透 —— 漏写 break 是最经典的静默错误来源
#   · 要穿透必须写 fallthrough;
import "assert.mo";

# ---- 比较链路径：case 少于 4 个，或值稀疏 ----
fn t_chain() -> i64 {
    let r: i64 = 0;
    switch (2) {
        case 1: r = 10;
        case 2: r = 20;
        case 3: r = 30;
    }
    return r;
}

fn t_chain_default() -> i64 {
    let r: i64 = 0;
    switch (99) {
        case 1: r = 10;
        case 2: r = 20;
        default: r = 777;
    }
    return r;
}

# 稀疏：范围 1000000，只有 4 个 case —— 建表要 8MB，必须退回比较链
fn t_sparse() -> i64 {
    let r: i64 = 0;
    switch (1000000) {
        case 1: r = 1;
        case 10: r = 2;
        case 100: r = 3;
        case 1000000: r = 4;
        default: r = 9;
    }
    return r;
}

# ---- 跳转表路径：>= 4 个 case 且密集 ----
fn t_table() -> i64 {
    let r: i64 = 0;
    switch (3) {
        case 0: r = 100;
        case 1: r = 101;
        case 2: r = 102;
        case 3: r = 103;
        case 4: r = 104;
        default: r = 999;
    }
    return r;
}

# 表里的"空洞"（没有 case 的值）必须落到 default
fn t_hole() -> i64 {
    let r: i64 = 0;
    switch (7) {
        case 0: r = 1;
        case 2: r = 2;
        case 4: r = 3;
        case 6: r = 4;
        default: r = 555;
    }
    return r;
}

# 范围下界之外：val < mn。跳转表用无符号回绕来抓，这里验负方向。
fn t_below() -> i64 {
    let r: i64 = 0;
    switch (0 - 1) {
        case 0: r = 1;
        case 1: r = 2;
        case 2: r = 3;
        case 3: r = 4;
        default: r = 888;
    }
    return r;
}

# 范围上界之外
fn t_above() -> i64 {
    let r: i64 = 0;
    switch (100) {
        case 0: r = 1;
        case 1: r = 2;
        case 2: r = 3;
        case 3: r = 4;
        default: r = 666;
    }
    return r;
}

# 负数 case 值 + 负数下界：sub rax, mn 里 mn 是负数
fn t_neg() -> i64 {
    let r: i64 = 0;
    switch (0 - 2) {
        case 0 - 3: r = 31;
        case 0 - 2: r = 32;
        case 0 - 1: r = 33;
        case 0: r = 34;
        case 1: r = 35;
        default: r = 444;
    }
    return r;
}

# ---- 不穿透 ----
fn t_no_fallthrough() -> i64 {
    let r: i64 = 0;
    switch (1) {
        case 1: r = 1;
        case 2: r = r + 100;
        case 3: r = r + 1000;
    }
    # 若穿透，r 会是 1101
    return r;
}

# 显式 fallthrough：只穿透一层
fn t_fallthrough() -> i64 {
    let r: i64 = 0;
    switch (1) {
        case 1: r = 1; fallthrough;
        case 2: r = r + 10; fallthrough;
        case 3: r = r + 100;
    }
    return r;
}

# 空 case（多个标签共享同一段 body）—— C 里是穿透，这里必须同义
fn t_empty_case() -> i64 {
    let r: i64 = 0;
    switch (2) {
        case 1:
        case 2:
        case 3:
            r = 42;
        case 4:
            r = 7;
    }
    return r;
}

# ---- break 跳出 switch（而不是跳出外层循环）----
fn t_break() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 5 {
        switch (i) {
            case 2: break;
            default: s = s + 1;
        }
        i = i + 1;
    }
    # 若 break 错误地跳出了 while，s 会停在 2
    return s;
}

# ---- continue 在 switch 里作用于外层循环 ----
fn t_continue_in_switch() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 6 {
        i = i + 1;
        switch (i) {
            case 3: continue;
            default: s = s + i;
        }
    }
    # 1+2+4+5+6 = 18；若 continue 跳到 switch 出口，s 会包含 3
    return s;
}

# for + switch + continue：continue 必须走 for 的 step，否则死循环
fn t_continue_for() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 6; i++) {
        switch (i) {
            case 3: continue;
            default: s = s + i;
        }
    }
    return s;
}

# ---- 嵌套 switch ----
fn t_nested() -> i64 {
    let r: i64 = 0;
    switch (1) {
        case 1:
            switch (2) {
                case 1: r = 10;
                case 2: r = 20;
                default: r = 30;
            }
        case 2:
            r = 99;
    }
    return r;
}

# 内外层都用跳转表（验证栈式分配没有被内层覆盖）
fn t_nested_table() -> i64 {
    let r: i64 = 0;
    switch (2) {
        case 0: r = 1;
        case 1: r = 2;
        case 2:
            switch (3) {
                case 0: r = r + 10;
                case 1: r = r + 20;
                case 2: r = r + 30;
                case 3: r = r + 40;
                case 4: r = r + 50;
                default: r = r + 900;
            }
        case 3: r = 3;
        case 4: r = 4;
    }
    return r;
}

# ---- switch 作为最后一条语句，后面的代码仍要执行 ----
fn t_after() -> i64 {
    let r: i64 = 0;
    switch (1) {
        case 1: r = 5;
    }
    r = r * 3;
    return r;
}

# ---- 跳转表 + 表后的代码不被当成指令执行 ----
fn t_after_table() -> i64 {
    let r: i64 = 0;
    switch (2) {
        case 0: r = 1;
        case 1: r = 2;
        case 2: r = 3;
        case 3: r = 4;
        case 4: r = 5;
    }
    let z: i64 = r + 100;
    return z;
}

# ---- case 里可以有自己的 let ----
fn t_case_scope() -> i64 {
    let r: i64 = 0;
    switch (1) {
        case 1:
            let a: i64 = 7;
            r = a * 2;
        case 2:
            let a: i64 = 100;
            r = a;
    }
    return r;
}

# ---- switch 值可以是表达式 ----
fn t_expr() -> i64 {
    let k: i64 = 2;
    let r: i64 = 0;
    switch (k + 1) {
        case 0: r = 1;
        case 1: r = 2;
        case 2: r = 3;
        case 3: r = 4;
        case 4: r = 5;
    }
    return r;
}

# ---- 函数返回值直接作为 switch 值 ----
fn sv(x: i64) -> i64 { return x * 2; }

fn t_call() -> i64 {
    let r: i64 = 0;
    switch (sv(2)) {
        case 0: r = 1;
        case 1: r = 2;
        case 2: r = 3;
        case 3: r = 4;
        case 4: r = 5;
    }
    return r;
}

# ---- default 不是最后一项 ----
fn t_default_first() -> i64 {
    let r: i64 = 0;
    switch (0) {
        default: r = 111;
        case 1: r = 1;
        case 2: r = 2;
        case 3: r = 3;
        case 4: r = 4;
    }
    return r;
}

# ---- 只有 default ----
fn t_only_default() -> i64 {
    let r: i64 = 0;
    switch (5) {
        default: r = 222;
    }
    return r;
}

# ---- 没有 default，落到 end ----
fn t_no_default() -> i64 {
    let r: i64 = 7;
    switch (42) {
        case 1: r = 1;
        case 2: r = 2;
    }
    return r;
}

fn main() -> i64 {
    assert_eq("chain", t_chain(), 20);
    assert_eq("chain default", t_chain_default(), 777);
    assert_eq("sparse -> chain", t_sparse(), 4);
    assert_eq("jump table", t_table(), 103);
    assert_eq("table hole", t_hole(), 555);
    assert_eq("below min", t_below(), 888);
    assert_eq("above max", t_above(), 666);
    assert_eq("negative cases", t_neg(), 32);
    assert_eq("no fallthrough", t_no_fallthrough(), 1);
    assert_eq("fallthrough", t_fallthrough(), 111);
    assert_eq("empty case", t_empty_case(), 42);
    assert_eq("break out of switch", t_break(), 4);
    assert_eq("continue in switch", t_continue_in_switch(), 18);
    assert_eq("continue in for", t_continue_for(), 12);
    assert_eq("nested", t_nested(), 20);
    assert_eq("nested table", t_nested_table(), 40);
    assert_eq("stmt after switch", t_after(), 15);
    assert_eq("stmt after table", t_after_table(), 103);
    assert_eq("case scope", t_case_scope(), 14);
    assert_eq("switch on expr", t_expr(), 4);
    assert_eq("switch on call", t_call(), 5);
    assert_eq("default first", t_default_first(), 111);
    assert_eq("only default", t_only_default(), 222);
    assert_eq("no default", t_no_default(), 7);
    return test_done();
}
