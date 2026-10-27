# 132 —— for 循环
#
# v1.134 引入了 for，但**从未被任何测试跑到**：三种最普通的写法
# （`for (let i: i64 = 0; i < 5; i++)`）全部报 syntax error。
# 本文件是它第一次被验证，并在验证过程中修掉两个真缺陷。
#
# 🔴 缺陷一：step 的代码位置。
#    for 展开为 `init; while (cond) { body; step; }`，**代码**必须
#    body 在前、step 在后；而 step 的**文本**在 body 之前。
#    第一版按文本顺序解析，于是 body 的位置上读到的是 step，
#    报 syntax error —— 看起来像用户把 body 写错了。
#
# 🔴 缺陷二（更隐蔽）：嵌套 for 会让位置跑飞。
#    第一版的修法是"跳过 step 文本 → 解析 body → set_pos 回退解析 step"。
#    单层和并列 for 都对，但**嵌套 for** 会坏：外层记下的回退位置被
#    内层 for 自己的 set_pos 覆盖，token 位置越过文件末尾，
#    报 syntax error 且行列号超出文件总行数（最难读的那种错）。
#    现布局见 compiler.mo 里 parse_for 的注释：靠多两条 jmp 换
#    "生成顺序 == 文本顺序"，完全不碰 token 位置，可任意嵌套。
#
# 判据全是**具体数值**，不是"能不能编译/会不会崩"：
#   - continue 若错误地跳到循环头（而不是 step），i 永不前进 → 死循环。
#     这里的和是 12 = 0+1+2+4+5，跳过 3 且**没有死循环**才拿得到。
#   - 嵌套 12 = 3×4，同时证明内外层各自独立推进。
import "assert.mo";

fn f(x: i64) -> i64 { return x * 10; }

# 基本求和
fn t_basic() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 5; i++) { s = s + i; }
    return s;
}

# continue 必须跳到 step。跳到循环头就死循环。
fn t_continue() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 6; i++) {
        if i == 3 { continue; }
        s = s + i;
    }
    return s;
}

# break 跳出
fn t_break() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 100; i++) {
        if i == 5 { break; }
        s = s + i;
    }
    return s;
}

# step 是表达式
fn t_step_expr() -> i64 {
    let n: i64 = 0;
    for (let i: i64 = 1; i < 100; i = f(i)) { n = n + 1; }
    return n;
}

# step 是复合赋值
fn t_step_compound() -> i64 {
    let n: i64 = 0;
    for (let i: i64 = 0; i < 10; i += 3) { n = n + 1; }
    return n;
}

# step 是 i--（倒序）
fn t_step_dec() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 5; i > 0; i--) { s = s + i; }
    return s;
}

# 空条件 for(;;) + break
fn t_forever() -> i64 {
    let n: i64 = 0;
    for (;;) {
        n = n + 1;
        if n == 7 { break; }
    }
    return n;
}

# 嵌套 for（v1.134 修的就是它）
fn t_nested() -> i64 {
    let n: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) {
        for (let j: i64 = 0; j < 4; j++) {
            n = n + 1;
        }
    }
    return n;
}

# 嵌套 for 中内层 continue：只跳内层的 step，外层照常推进
fn t_nested_continue() -> i64 {
    let n: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) {
        for (let j: i64 = 0; j < 4; j++) {
            if j == 1 { continue; }
            n = n + 1;
        }
    }
    return n;
}

# 嵌套 for 中内层 break：只跳出内层
fn t_nested_break() -> i64 {
    let n: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) {
        for (let j: i64 = 0; j < 4; j++) {
            if j == 2 { break; }
            n = n + 1;
        }
    }
    return n;
}

# 多个 for 各用循环变量 i（for 自带作用域）
fn t_same_name() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 2; i++) { s = s + 1; }
    for (let i: i64 = 0; i < 3; i++) { s = s + 1; }
    for (let i: i64 = 0; i < 4; i++) { s = s + 1; }
    return s;
}

# for 的循环变量遮蔽外层同名变量，且循环结束后外层值不受影响
fn t_shadow() -> i64 {
    let i: i64 = 100;
    let s: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) { s = s + i; }
    return i * 1000 + s;
}

# for 之后还有语句：验证解析没有多/少消费 token
fn t_after() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) { s = s + i; }
    for (let i: i64 = 0; i < 3; i++) { s = s + i; }
    s = s * 2;
    if s == 12 { return 1; }
    return 0;
}

# 循环体内声明的变量不出循环（body 比 for 深一层）
fn t_body_scope() -> i64 {
    let s: i64 = 0;
    for (let i: i64 = 0; i < 3; i++) {
        let k: i64 = i * 2;
        s = s + k;
    }
    return s;
}

fn main() -> i64 {
    assert_eq("basic", t_basic(), 10);
    assert_eq("continue jumps to step", t_continue(), 12);
    assert_eq("break", t_break(), 10);
    assert_eq("step expr", t_step_expr(), 2);
    assert_eq("step compound +=", t_step_compound(), 4);
    assert_eq("step dec", t_step_dec(), 15);
    assert_eq("for(;;) break", t_forever(), 7);
    assert_eq("nested for", t_nested(), 12);
    assert_eq("nested continue", t_nested_continue(), 9);
    assert_eq("nested break", t_nested_break(), 6);
    assert_eq("same loop var name", t_same_name(), 9);
    assert_eq("shadow outer i", t_shadow(), 100003);
    assert_eq("stmt after for", t_after(), 1);
    assert_eq("body scope", t_body_scope(), 6);
    return test_done();
}
