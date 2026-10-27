import "io.mo";

# 极简测试框架
#   assert_eq(name, got, want) —— 不等则打印失败并返回 1
#   test_done()                —— 输出汇总并以 failures 为退出码

var t_run: i64 = 0;
var t_fail: i64 = 0;

fn assert_eq(name: i64, got: i64, want: i64) -> i64 {
    t_run = t_run + 1;
    if got == want {
        return 0;
    }
    t_fail = t_fail + 1;
    print("FAIL ");
    print(name);
    print(": got ");
    print_i64(got);
    print(", want ");
    print_i64(want);
    print_nl();
    return 1;
}

fn assert_true(name: i64, cond: i64) -> i64 {
    return assert_eq(name, cond, 1);
}

fn test_done() -> i64 {
    print("ran ");
    print_i64(t_run);
    print(", failed ");
    print_i64(t_fail);
    print_nl();
    return t_fail;
}

# --- f64 辅助（供测试用）---
# 把比较结果（0/1）转成 i64 —— 比较本身已经是 i64，这里只为可读性
fn to_i(b: i64) -> i64 {
    if b == 0 { return 0; }
    return 1;
}
# 把 f64 的位模式当整数取出来（f64 值在 rax 里就是位模式）
fn bits(v: f64) -> i64 { return fbits(v); }
