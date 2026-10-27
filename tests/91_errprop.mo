# `?` 错误传播：返回值 < 0 就带着它立即返回
import "io.mo";

fn deep(x: i64) -> i64 {
    if x < 0 { return 0 - 7; }
    return x * 3;
}

fn mid(x: i64) -> i64 {
    let v: i64 = deep(x)?;      # 错误在这里被传出去
    return v + 1;
}

fn top(x: i64) -> i64 {
    let v: i64 = mid(x)?;
    return v + 100;
}

# 多次使用：同一函数里可以有多个 ?
fn multi(x: i64) -> i64 {
    let a: i64 = deep(x)?;
    let b: i64 = deep(x + 1)?;
    return a + b;
}

# 有局部变量的路径（验证错误出口的栈恢复正确）
fn with_local(x: i64) -> i64 {
    let t: i64 = 999;
    let v: i64 = deep(x)?;
    return v + t;
}

# 错误路径上也要能正确返回（不是只有成功路径）
fn chk() -> i64 {
    if top(10) != 131 { return 1; }
    if top(0 - 1) != 0 - 7 { return 2; }
    if mid(0 - 5) != 0 - 7 { return 3; }
    if multi(2) != 15 { return 4; }
    if multi(0 - 1) != 0 - 7 { return 5; }
    if with_local(4) != 1011 { return 6; }
    if with_local(0 - 2) != 0 - 7 { return 7; }
    return 0;
}

fn main() -> i64 {
    print_i64(top(10));   print(" ");
    print_i64(top(0 - 1)); print(" ");
    print_i64(multi(2));  print("\n");
    return chk();
}
