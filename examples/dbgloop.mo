import "io.mo";

# 条件断点 / 观察点的测试程序。
#
# 行号是刻意的：本文件里的断点与测试脚本 tools/modcondtest.sh 里的
# 数字一一对应，改动行序会让那些断言全部失准。
#
# 循环体里不放 let —— 墨语言在循环里声明局部变量会每轮新占栈槽，
# 长循环会累积到溢出（1.100 在 mols.mo 上踩过）。

fn addv(a: i64, b: i64) -> i64 {
    let s: i64 = a + b;
    return s;
}

fn main() -> i64 {
    let i: i64 = 0;
    let sum: i64 = 0;
    let t: i64 = 0;
    while i < 10 {
        t = addv(i, 1);
        sum = sum + t;
        i = i + 1;
    }
    print_i64(sum);
    print_nl();
    return 0;
}
